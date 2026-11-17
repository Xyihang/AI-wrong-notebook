"""
大模型层（Agent-C）。

对外暴露 `llm_service` 单例（LLMService 门面），统一编排：
- LLMClient  : OpenAI 兼容客户端（DeepSeek / 通义等）
- prompts    : 中文提示词构建（结构化 / 分析 / 打标签）
- structure  : JSON 稳健解析 + OCR 兜底 + 纯规则降级分析

典型用法：
    from app.llm import llm_service

    if llm_service.available():
        question = llm_service.analyze_question(subject="数学", ocr_text="...")
    else:
        question = llm_service.rule_analyze("...")   # 或直接 rule_based_analyze
"""
from __future__ import annotations

import logging
from typing import Any, Dict, List, Optional, Sequence

logger = logging.getLogger(__name__)

from app.llm.client import LLMClient, LLMError, LLMUnavailableError  # noqa: E402
from app.llm.prompts import (  # noqa: E402
    build_analysis_prompt,
    build_extraction_prompt,
    build_merge_prompt,
    build_tagging_prompt,
    system_prompt,
)
from app.llm.structure import (  # noqa: E402
    merge_ocr_fallback,
    normalize_question,
    parse_question_json,
    rule_based_analyze,
)

__all__ = [
    "llm_service",
    "LLMService",
    "LLMClient",
    "LLMError",
    "LLMUnavailableError",
    "system_prompt",
    "build_extraction_prompt",
    "build_analysis_prompt",
    "build_tagging_prompt",
    "build_merge_prompt",
    "parse_question_json",
    "merge_ocr_fallback",
    "normalize_question",
    "rule_based_analyze",
]


class LLMService:
    """大模型服务门面：客户端 + 提示词 + 结构化解析 + 降级路径。"""

    def __init__(self, client: Optional[LLMClient] = None) -> None:
        self.client = client or LLMClient()

    # ------------------------------------------------------------------ #
    # 可用性
    # ------------------------------------------------------------------ #
    def available(self) -> bool:
        return self.client.available()

    # ------------------------------------------------------------------ #
    # 底层对话
    # ------------------------------------------------------------------ #
    def chat(
        self,
        system: str,
        user: str,
        max_tokens: Optional[int] = None,
        temperature: float = 0.2,
    ) -> str:
        """底层对话：默认使用 LLM_MAX_TOKENS；空内容时兜底到最大输出上限重试一次。"""
        from app.core.config import settings

        tokens = max_tokens or settings.LLM_MAX_TOKENS
        raw = self.client.chat(system, user, max_tokens=tokens, temperature=temperature)
        if not (raw or "").strip() and tokens < settings.LLM_MAX_TOKENS_FALLBACK:
            logger.warning(
                "LLM 返回空内容，使用最大输出上限重试: %s",
                settings.LLM_MAX_TOKENS_FALLBACK,
            )
            raw = self.client.chat(
                system,
                user,
                max_tokens=settings.LLM_MAX_TOKENS_FALLBACK,
                temperature=temperature,
            )
        return raw

    # ------------------------------------------------------------------ #
    # 高层编排
    # ------------------------------------------------------------------ #
    def analyze_question(
        self,
        ocr_text: str,
        subject: str = "",
        max_tokens: Optional[int] = None,
    ) -> Dict[str, Any]:
        """
        完整分析：OCR 文本 -> 结构化 QuestionRecord。

        LLM 可用：抽取 prompt -> chat -> 稳健 JSON 解析 -> 与 OCR 合并补齐。
        LLM 不可用 / 调用失败：自动降级为 rule_based_analyze（仅存 OCR 文本）。
        """
        if not self.available():
            logger.info("LLM 不可用，降级为纯规则分析（仅存 OCR 文本）")
            return rule_based_analyze(ocr_text)
        try:
            raw = self.chat(
                system_prompt(),
                build_extraction_prompt(subject=subject, ocr_text=ocr_text),
                max_tokens=max_tokens,
            )
            question = parse_question_json(raw)
            return merge_ocr_fallback(question, ocr_text)
        except LLMError as exc:
            logger.warning("LLM 分析失败，降级为纯规则分析: %s", exc)
            return rule_based_analyze(ocr_text)
        except Exception as exc:  # noqa: BLE001 - 任何异常都走降级路径
            logger.exception("LLM 分析异常，降级为纯规则分析: %s", exc)
            return rule_based_analyze(ocr_text)

    def analyze_given_question(
        self,
        question_text: str,
        subject: str = "",
        max_tokens: Optional[int] = None,
    ) -> Dict[str, Any]:
        """对已确定的题干做解答分析（不依赖 OCR 降级）。"""
        if not self.available():
            raise LLMUnavailableError("LLM 未启用或未配置")
        raw = self.chat(
            system_prompt(),
            build_analysis_prompt(question_text=question_text, subject=subject),
            max_tokens=max_tokens,
        )
        return parse_question_json(raw)

    def tag_question(
        self,
        question_text: str,
        subject: str = "",
        existing_knowledge_points: Optional[Sequence[str]] = None,
        existing_tags: Optional[Sequence[str]] = None,
    ) -> Dict[str, Any]:
        """为题目生成知识点与标签（返回 {"subject","knowledge_points","tags"}）。"""
        if not self.available():
            raise LLMUnavailableError("LLM 未启用或未配置")
        raw = self.client.chat(
            system_prompt(),
            build_tagging_prompt(
                question_text=question_text,
                subject=subject,
                existing_knowledge_points=existing_knowledge_points,
                existing_tags=existing_tags,
            ),
            max_tokens=800,
        )
        data = parse_question_json(raw)
        return {
            "subject": data.get("subject", subject),
            "knowledge_points": data.get("knowledge_points", []),
            "tags": data.get("tags", []),
        }

    def rule_analyze(self, ocr_text: str) -> Dict[str, Any]:
        """纯规则降级分析（同 rule_based_analyze）。"""
        return rule_based_analyze(ocr_text)

    def recognize_image(
        self,
        image_b64: str,
        mime_type: str = "image/jpeg",
        prompt: str = "",
        max_tokens: int = 1500,
    ) -> str:
        """
        用多模态视觉模型直接读图，返回识别的题目文本。

        供 PaddleOCR 不可用时的读图兜底（需配置视觉模型，如
        deepseek-v4-flash-vision-exp）。失败抛 LLMUnavailableError / LLMError，
        由调用方决定是否降级。
        """
        return self.client.recognize_image(
            image_b64=image_b64,
            mime_type=mime_type,
            prompt=prompt,
            max_tokens=max_tokens,
        )


# 模块级单例
llm_service = LLMService()
