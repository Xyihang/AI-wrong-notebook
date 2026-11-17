"""AI 变式题生成（组卷补齐用，脱离具体原题也能按知识点出题）。"""
from __future__ import annotations

from typing import Any, Dict, List, Optional

from app.llm import llm_service
from app.llm.prompts import build_variant_prompt, system_prompt
from app.llm.structure import parse_question_json
from app.core.logging import get_logger

logger = get_logger(__name__)


def generate_one(
    subject: str,
    knowledge_points: List[str],
    difficulty: str = "中等",
    seed_stem: str = "",
    number: int = 1,
    max_tokens: Optional[int] = None,
) -> Dict[str, Any]:
    """
    生成一道变式题（返回规范化字段 dict：subject/knowledge_points/question_type/
    difficulty/stem/options/answer/analysis）。失败抛异常由调用方兜底。
    max_tokens 默认取 settings.LLM_MAX_TOKENS（DeepSeek 官方上限的一半），
    空内容由 llm_service.chat 兜底到最大上限。
    """
    if not llm_service.available():
        raise RuntimeError("LLM 未启用，无法生成变式题")
    raw = llm_service.chat(
        system_prompt(),
        build_variant_prompt(
            subject=subject,
            knowledge_points=knowledge_points or [],
            difficulty=difficulty,
            seed_stem=seed_stem,
            number=number,
        ),
        max_tokens=max_tokens,
    )
    data = parse_question_json(raw)
    return normalize_variant(data, subject=subject, difficulty=difficulty)


def normalize_variant(
    data: Dict[str, Any],
    subject: str = "",
    difficulty: str = "中等",
) -> Dict[str, Any]:
    """把 parse 出的 QuestionRecord dict 规整为组卷需要的题字段。"""
    return {
        "subject": str(data.get("subject") or subject or ""),
        "knowledge_points": list(data.get("knowledge_points") or []),
        "question_type": str(data.get("question_type") or ""),
        "difficulty": str(data.get("difficulty") or difficulty or "中等"),
        "stem": str(data.get("stem") or ""),
        "options": list(data.get("options") or []),
        "answer": str(data.get("answer") or ""),
        "analysis": str(data.get("analysis") or ""),
    }
