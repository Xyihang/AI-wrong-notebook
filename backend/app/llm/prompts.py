"""
中文提示词构建器（LLM 结构化 / 分析 / 打标签）。

提示词设计参考 ai-wrong-notebook 的 prompt 质量与约束风格：
- 只输出 JSON、不输出解释性文字；
- 字段与 QuestionRecord 契约一一对应（docs/spec.md §7.1）；
- 数学公式使用 LaTeX（aligned/cases 环境，不用 \\newline）；
- 输出前自检字段一致性（借鉴 ai_analysis_service.dart 的自检约束）。

所有 prompt 均要求「严格 JSON」，配合 structure.parse_question_json 的
容错解析使用。
"""
from __future__ import annotations

import json
from typing import Any, Dict, List, Optional, Sequence

# QuestionRecord 契约字段清单（与 docs/spec.md §7.1 一致）
QUESTION_FIELDS = [
    "subject",
    "knowledge_points",
    "question_type",
    "difficulty",
    "stem",
    "options",
    "answer",
    "analysis",
    "mistake_reason",
    "study_advice",
    "mastery",
    "tags",
]

_JSON_SCHEMA_HINT = """返回的 JSON 必须严格包含以下字段（值类型见括号）：
- subject: 学科（字符串），如 "数学"、"英语"、"物理"
- knowledge_points: 知识点数组（字符串数组，可含层级，如 ["初中", "几何", "圆"]）
- question_type: 题型（字符串），如 "单选题"、"填空题"、"解答题"、"计算题"、"证明题"、"阅读理解"
- difficulty: 难度（字符串），只能取 "简单" / "中等" / "困难" 之一
- stem: 题干（字符串），数学公式请用 LaTeX，方程组用 aligned/cases 环境，不要使用 \\\\newline。
      若 OCR 含多道题目，请把【全部题目】完整、按题号顺序写入 stem，不要遗漏、不要只写第一道
- options: 选项数组（字符串数组）；无选项时为 []
- answer: 正确答案（字符串）。若多道题，请按题号列出每题答案，如 "1. A 2. C 3. B"
- analysis: 解题步骤与解析（字符串）。若多道题，请逐题写出解析，用题号分隔；务必填写，不要留空
- mistake_reason: 学生可能的错因（字符串）；无法判断时填空字符串
- study_advice: 针对此题的学习建议（字符串，如应掌握的知识点、易错提醒、复习建议）；无法判断时填空字符串
- mastery: 掌握程度（字符串），只能取 "未掌握" / "需巩固" / "已掌握" 之一，默认 "未掌握"
- tags: 标签数组（字符串数组，2~5 个简短标签）

输出要求：
1. **必须输出一个合法的、完整的 JSON 对象**；禁止输出 JSON 数组、禁止输出多个对象、
   禁止任何非 JSON 的文字/解释/前言/结尾，禁止截断；只输出一个 JSON 对象本身。
2. 输出前自检：answer 与 analysis 的结论必须一致；knowledge_points 与 stem 内容相关；
   多题时 stem 必须包含全部题目。
3. 即使内容很多，answer 和 analysis 也务必填写（多题时逐题/整体说明），不要留空；
   仅当确实完全无法判断时才用空字符串填充，且不要编造。"""


def system_prompt() -> str:
    """系统提示词：定义模型角色与输出契约。"""
    return (
        "你是一名资深的中小学学科教师和错题整理专家，擅长把 OCR 识别出的题目文本"
        "结构化、分析解答、提炼知识点与错因。\n"
        "你只输出严格 JSON，不输出任何其它文字。\n"
        + _JSON_SCHEMA_HINT
    )


def build_extraction_prompt(subject: str, ocr_text: str) -> str:
    """
    从 OCR 文本抽取并结构化错题。

    支持整页多道题：OCR 文本含多道题时**完整保留全部题目**（不丢题、不合并），
    stem 为该页完整题目文本；单题场景行为不变。

    :param subject: 学科（可为空，让模型推断）
    :param ocr_text: OCR 识别出的原始文本
    """
    subject_line = f"学科（用户提供）：{subject}" if subject and subject != "未知" else "学科（请根据内容推断）"
    return f"""{subject_line}

请把下面 OCR 识别出的题目文本整理为一条完整、规范的错题记录。

OCR 文本：
---
{ocr_text}
---

要求：
- 修正 OCR 明显的错别字与乱码，还原题目原意；
- 数学公式转为 LaTeX（aligned/cases 环境，不要用 \\\\newline）；
- 若 OCR 文本包含多道题目，**完整保留全部题目内容**：不要遗漏、不要合并、
  不要只取第一道；各题题号/序号（如 1. 2. 3. 或 一、二、三、）原样保留，
  逐题转录完整题干、条件与选项；
- 严格按下列 JSON 契约输出：
{_JSON_SCHEMA_HINT}"""


def build_analysis_prompt(question_text: str, subject: str = "") -> str:
    """
    对一道题做解答与错因分析。

    :param question_text: 题干（含选项）
    :param subject: 学科（可为空）
    """
    subject_line = f"学科：{subject}" if subject and subject != "未知" else "学科：请根据内容推断"
    return f"""{subject_line}

请解答下面这道题，并给出解析与可能的错因。

题目：
---
{question_text}
---

要求：
- 分步推导，答案与解析结论必须一致；
- 数学公式用 LaTeX（aligned/cases 环境，不要用 \\\\newline）；
- 严格按下列 JSON 契约输出：
{_JSON_SCHEMA_HINT}"""


def build_tagging_prompt(
    question_text: str,
    subject: str = "",
    existing_knowledge_points: Optional[Sequence[str]] = None,
    existing_tags: Optional[Sequence[str]] = None,
) -> str:
    """
    为题目生成知识点与标签。

    :param question_text: 题干
    :param subject: 学科（可为空）
    :param existing_knowledge_points: 已有知识点（尽量沿用并扩展）
    :param existing_tags: 已有标签
    """
    subject_line = f"学科：{subject}" if subject and subject != "未知" else "学科：请根据内容推断"
    kp_hint = ""
    if existing_knowledge_points:
        kp_hint = f"\n已有知识点（请优先沿用，可补充层级）：{json.dumps(list(existing_knowledge_points), ensure_ascii=False)}"
    tag_hint = ""
    if existing_tags:
        tag_hint = f"\n已有标签（请优先沿用，可补充）：{json.dumps(list(existing_tags), ensure_ascii=False)}"
    return f"""{subject_line}

请为下面这道题提炼知识点层级与标签。{kp_hint}{tag_hint}

题目：
---
{question_text}
---

要求：
- knowledge_points 为知识点路径数组（如 ["初中", "几何", "圆"]），2~4 条；
- tags 为 2~5 个简短标签；
- 只输出一个 JSON 对象：{{"subject": "...", "knowledge_points": [...], "tags": [...]}}，
  不要输出任何其它文字。"""


def build_merge_prompt(
    llm_question: Dict[str, Any],
    ocr_text: str,
    subject: str = "",
) -> str:
    """
    将 LLM 结构化结果与 OCR 原文对照，修正 / 补齐字段（可选增强）。

    :param llm_question: 上一轮 LLM 输出的 QuestionRecord 字典
    :param ocr_text: OCR 原文
    :param subject: 学科（可为空）
    """
    return f"""你是一位严谨的校对员。下面是一道题的 OCR 原文与一份机器抽取结果，
请对照 OCR 原文修正抽取结果中的错误（题干缺字、答案与题目不符等），
信息不足的字段填空字符串 / 空数组，不要编造。

OCR 原文：
---
{ocr_text}
---

抽取结果：
{json.dumps(llm_question, ensure_ascii=False)}

只输出修正后的 JSON 对象，严格包含以下字段：
{_JSON_SCHEMA_HINT}"""


def build_variant_prompt(
    subject: str,
    knowledge_points: Sequence[str],
    difficulty: str = "中等",
    seed_stem: str = "",
    number: int = 1,
) -> str:
    """
    生成一道与给定知识点同型的**变式题**（AI 组卷/举一反三用，脱离具体原题也可出）。

    :param subject: 学科（如 数学）
    :param knowledge_points: 知识点路径（如 ["初中","函数","一次函数"]）
    :param difficulty: 难度：简单 / 中等 / 困难
    :param seed_stem: 可选的原题题干——有则围绕该题类型换数字/条件/问法做变式；
                      空则仅按知识点出该知识点的典型题。
    :param number: 该变式在卷中的题号（仅用于提示，不写入输出）
    """
    seed_hint = ""
    if seed_stem and seed_stem.strip():
        seed_hint = (
            "请参考下面这道原题的类型与考点，做一道**同知识点、但数字/条件/问法不同**的变式题，"
            "不要照抄原题、不要让两题只是换了个数字（题干表述也尽量不同）：\n"
            f"---\n{seed_stem}\n---\n"
        )
    else:
        seed_hint = "请出一道该知识点下**典型且有代表性**的题目（不要超纲、条件要自洽）。"
    return f"""你是一名资深的中小学教师，正在出题。

学科：{subject}
知识点：{json.dumps(list(knowledge_points), ensure_ascii=False)}
难度：{difficulty}
题号（卷内第 {number} 题，仅供定位，不要写进输出）

{seed_hint}

请为卷中的这一题生成一道完整的题目，题目必须：
- 与知识点紧密相关、难度与指定难度一致；
- 题干清晰完整、条件自洽、可独立求解，不自相矛盾；
- options：选择题才填选项数组，否则为 []；
- answer 与 analysis 结论一致（analysis 写清关键步骤）；
- 数学公式用 LaTeX（aligned/cases 环境，不要用 \\\\newline）。

严格只输出一个 JSON 对象，字段：
- subject（字符串）
- knowledge_points（数组）
- question_type（字符串，如 单选题/填空题/解答题/计算题/证明题）
- difficulty（只能 "简单"/"中等"/"困难"）
- stem（题干）
- options（数组，无则 []）
- answer（答案）
- analysis（解析）

禁止输出 JSON 数组以外的结构、禁止任何解释性文字、禁止截断。"""
