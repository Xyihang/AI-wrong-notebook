"""
LLM 输出的结构化解析与容错（structure）。

- parse_question_json(raw) : 从模型原始输出中稳健提取 JSON（去 ```json 围栏、
  定位首个 {...}、失败回退默认值），并补齐 QuestionRecord 全部字段。
- merge_ocr_fallback(dict, ocr_text) : LLM 不可用 / 缺字段时，用 OCR 原文
  填充 stem 等字段。
- rule_based_analyze(ocr_text) : 纯规则兜底分析（无 LLM 时的降级路径，
  满足 spec F1 异常处理：LLM 不可用 -> 仅存 OCR 文本）。
"""
from __future__ import annotations

import json
import logging
import re
from typing import Any, Dict, List, Optional

logger = logging.getLogger(__name__)

# QuestionRecord 契约字段与默认值（docs/spec.md §7.1）
QUESTION_FIELDS: List[str] = [
    "id",
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
    "image_path",
    "ocr_text",
    "latex_text",
    "created_at",
    "similar_matches",
]

QUESTION_DEFAULTS: Dict[str, Any] = {
    "id": "",
    "subject": "",
    "knowledge_points": [],
    "question_type": "",
    "difficulty": "中等",
    "stem": "",
    "options": [],
    "answer": "",
    "analysis": "",
    "mistake_reason": "",
    "study_advice": "",
    "mastery": "未掌握",
    "tags": [],
    "image_path": "",
    "ocr_text": "",
    "latex_text": "",
    "created_at": "",
    "similar_matches": [],
}

_LIST_FIELDS = {"knowledge_points", "options", "tags", "similar_matches"}
_VALID_DIFFICULTY = {"简单", "中等", "困难"}
_VALID_MASTERY = {"未掌握", "已掌握", "需巩固"}


def _clean_response(raw: str) -> str:
    """去掉 ```json 围栏，返回最内层的候选 JSON 文本。"""
    text = (raw or "").strip()
    if not text:
        return ""
    # 去掉 ```json ... ``` 围栏
    fenced = re.search(r"```(?:json)?\s*([\s\S]*?)```", text)
    if fenced:
        return fenced.group(1).strip()
    return text


def _extract_first_object(text: str) -> Optional[str]:
    """定位第一个平衡的 {...} 块（忽略字符串内的花括号）。"""
    start = text.find("{")
    if start == -1:
        return None
    depth = 0
    in_str = False
    escape = False
    for i in range(start, len(text)):
        ch = text[i]
        if in_str:
            if escape:
                escape = False
            elif ch == "\\":
                escape = True
            elif ch == '"':
                in_str = False
            continue
        if ch == '"':
            in_str = True
        elif ch == "{":
            depth += 1
        elif ch == "}":
            depth -= 1
            if depth == 0:
                return text[start : i + 1]
    return None


def _coerce_value(key: str, value: Any) -> Any:
    """按字段契约规整类型。"""
    if key in _LIST_FIELDS:
        if value is None:
            return []
        if isinstance(value, str):
            # 尝试解析 JSON 字符串数组（模型偶发把数组序列化成了字符串）
            try:
                parsed = json.loads(value)
                if isinstance(parsed, list):
                    value = parsed
                else:
                    return [value]
            except (json.JSONDecodeError, TypeError):
                return [value]
        if isinstance(value, (list, tuple)):
            return [str(v) for v in value]
        return []
    if value is None:
        return QUESTION_DEFAULTS.get(key, "")
    return value


def normalize_question(data: Dict[str, Any]) -> Dict[str, Any]:
    """把任意解析结果规整为完整 QuestionRecord 字典。"""
    out: Dict[str, Any] = dict(QUESTION_DEFAULTS)
    for key in QUESTION_FIELDS:
        if key in data and data[key] is not None:
            out[key] = _coerce_value(key, data[key])
    # 枚举值校验
    if out.get("difficulty") not in _VALID_DIFFICULTY:
        out["difficulty"] = "中等"
    if out.get("mastery") not in _VALID_MASTERY:
        out["mastery"] = "未掌握"
    # 字符串字段转 str
    for key, value in list(out.items()):
        if key not in _LIST_FIELDS:
            out[key] = str(value if value is not None else "")
    return out


def _repair_truncated(text: str) -> str:
    """若文本以 { 开头但未闭合，补全右花括号（处理 LLM 输出被截断）。"""
    s = text.strip()
    if not s.startswith("{"):
        return text
    depth = 0
    in_str = False
    escape = False
    for ch in s:
        if in_str:
            if escape:
                escape = False
            elif ch == "\\":
                escape = True
            elif ch == '"':
                in_str = False
            continue
        if ch == '"':
            in_str = True
        elif ch == "{":
            depth += 1
        elif ch == "}":
            depth -= 1
    if depth > 0:
        return s + "}" * depth
    return s


def _candidate_objects(text: str) -> List[str]:
    """
    收集所有可能的 JSON 对象文本候选（按优先级）：
    - 整体就是一个对象 / 数组（数组则逐个取其中对象）；
    - 第一个平衡 {...} 块；
    - 截断补全后的对象。
    """
    cands: List[str] = []
    stripped = text.strip()
    if not stripped:
        return cands

    if stripped.startswith("{"):
        cands.append(stripped)
    elif stripped.startswith("["):
        # 整体是数组：成功则逐个取对象；失败则提取其中对象
        try:
            arr = json.loads(stripped)
            if isinstance(arr, list):
                for item in arr:
                    if isinstance(item, dict):
                        cands.append(json.dumps(item, ensure_ascii=False))
        except (json.JSONDecodeError, TypeError):
            pass
        for obj in _extract_all_objects(stripped):
            cands.append(obj)

    obj = _extract_first_object(stripped)
    if obj:
        cands.append(obj)

    repaired = _repair_truncated(stripped)
    if repaired and repaired != stripped:
        cands.append(repaired)
    return cands


def _extract_all_objects(text: str) -> List[str]:
    """提取文本中的所有顶层平衡 {...} 块（用于数组/多对象场景）。"""
    out: List[str] = []
    i = 0
    while i < len(text):
        start = text.find("{", i)
        if start == -1:
            break
        depth = 0
        in_str = False
        escape = False
        j = start
        while j < len(text):
            ch = text[j]
            if in_str:
                if escape:
                    escape = False
                elif ch == "\\":
                    escape = True
                elif ch == '"':
                    in_str = False
            else:
                if ch == '"':
                    in_str = True
                elif ch == "{":
                    depth += 1
                elif ch == "}":
                    depth -= 1
                    if depth == 0:
                        out.append(text[start : j + 1])
                        i = j + 1
                        break
            j += 1
        else:
            break
    return out


def parse_question_json(raw: str) -> Dict[str, Any]:
    """
    从模型原始输出稳健提取 QuestionRecord JSON。

    容错策略（逐级回退）：
    1. 整体对象 / 整体数组（数组取字段最全的对象）；
    2. 第一个平衡 {...} 块；
    3. 截断补全后的对象；
    4. 全部失败 -> 默认结构（stem 置为原文，便于人工查看）。
    """
    cleaned = _clean_response(raw)
    if not cleaned:
        logger.warning("LLM 输出为空，返回默认结构")
        out = dict(QUESTION_DEFAULTS)
        out["stem"] = raw or ""
        return out

    best: Optional[Dict[str, Any]] = None
    best_score = -1
    for cand in _candidate_objects(cleaned):
        try:
            data = json.loads(cand)
            if not isinstance(data, dict):
                continue
            normalized = normalize_question(data)
            # 选字段最完整（stem/answer/analysis/知识点）的候选
            score = _completeness_score(normalized)
            if score > best_score:
                best_score = score
                best = normalized
        except (json.JSONDecodeError, TypeError):
            continue

    if best is not None:
        _log_completeness(best)
        return best

    logger.warning("LLM 输出无法解析为 JSON，返回默认结构: %.200s", cleaned)
    out = dict(QUESTION_DEFAULTS)
    out["stem"] = cleaned or raw or ""
    return out


def _completeness_score(d: Dict[str, Any]) -> int:
    """按核心字段完整度打分，用于在多个候选对象中选最优。"""
    score = 0
    if str(d.get("stem") or "").strip():
        score += 3
    if str(d.get("answer") or "").strip():
        score += 2
    if str(d.get("analysis") or "").strip():
        score += 2
    if d.get("knowledge_points"):
        score += 2
    if str(d.get("subject") or "").strip():
        score += 1
    return score


def _log_completeness(d: Dict[str, Any]) -> None:
    """记录结构化结果的核心字段完整度（便于观测多题/解析不完整问题）。"""
    stem = bool(str(d.get("stem") or "").strip())
    answer = bool(str(d.get("answer") or "").strip())
    analysis = bool(str(d.get("analysis") or "").strip())
    kps = bool(d.get("knowledge_points"))
    if not (stem and answer and analysis and kps):
        logger.warning(
            "结构化字段不完整: stem=%s answer=%s analysis=%s knowledge_points=%s",
            stem, answer, analysis, kps,
        )


def merge_ocr_fallback(question_dict: Dict[str, Any], ocr_text: str) -> Dict[str, Any]:
    """
    LLM 不可用 / 缺字段时，用 OCR 原文补齐。

    - stem 为空 -> 用 ocr_text；
    - question_type / difficulty / mastery 空 -> 默认值；
    - ocr_text 始终保留。
    """
    data = normalize_question(question_dict or {})
    ocr = str(ocr_text or "")
    if not data.get("stem"):
        data["stem"] = ocr
    if not data.get("ocr_text"):
        data["ocr_text"] = ocr
    return data


def rule_based_analyze(ocr_text: str) -> Dict[str, Any]:
    """
    纯规则兜底分析（LLM 不可用时的降级入库）。

    按任务约定填充：stem=ocr_text, question_type='未知', difficulty='中等',
    mastery='未掌握', knowledge_points=[], tags=[]。
    附加轻量启发式：从 OCR 文本猜测题型（选择题 / 填空题等），猜不出则 '未知'。
    """
    text = str(ocr_text or "").strip()
    out = dict(QUESTION_DEFAULTS)
    out["stem"] = text
    out["ocr_text"] = text
    out["question_type"] = _guess_question_type(text)
    out["difficulty"] = "中等"
    out["mastery"] = "未掌握"
    out["knowledge_points"] = []
    out["tags"] = []
    return out


def _guess_question_type(text: str) -> str:
    """基于文本模式的轻量题型猜测（尽力而为，猜不出返回 '未知'）。"""
    if not text:
        return "未知"
    # 选项特征：A. / B. / C. / D. 或 A、B、C、D（出现 >=2 个不同标记）
    option_markers = set(re.findall(r"\b[A-DＡ-Ｄ]\s*[.．、)]", text))
    if len(option_markers) >= 2:
        return "单选题"
    if re.search(r"填空", text):
        return "填空题"
    if re.search(r"判断[题对错]", text):
        return "判断题"
    if re.search(r"计算", text):
        return "计算题"
    if re.search(r"证明", text):
        return "证明题"
    if re.search(r"(?:阅读|完形)", text):
        return "阅读理解"
    return "未知"
