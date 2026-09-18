"""
OpenAI 兼容大模型客户端（LLMClient）。

配置（环境变量 / backend/.env，settings 可用时优先）：
- LLM_BASE_URL : 兼容接口基址，如 https://api.deepseek.com/v1
- LLM_API_KEY  : API Key
- LLM_MODEL    : 模型名，如 deepseek-chat
- LLM_ENABLED  : 是否启用（未配置 Key 时应为 false）

实现：
- POST {base}/chat/completions，system + user 双消息；
- 用 requests（OpenAI 兼容接口），openai 库存在时亦可选用；
- 失败自动重试一次；
- 未启用 / 无 Key / 无 base_url -> available() 返回 False，
  chat() 抛 LLMUnavailableError，调用方降级（见 structure.rule_based_analyze）。

本模块 import 安全：openai 库延迟导入，requests 为轻量依赖。
"""
from __future__ import annotations

import json
import logging
import os
from typing import Any, Dict, List, Optional

logger = logging.getLogger(__name__)

try:  # pragma: no cover - 取决于其它 Agent 的 core 是否就绪
    from app.core.config import settings as _app_settings

    _HAS_APP_SETTINGS = True
except Exception:  # noqa: BLE001
    _HAS_APP_SETTINGS = False


class LLMError(Exception):
    """大模型调用通用错误。"""


class LLMUnavailableError(LLMError):
    """大模型未启用 / 未配置，无法调用。"""


def _get_setting(name: str, default: str = "") -> str:
    if _HAS_APP_SETTINGS and hasattr(_app_settings, name):
        value = getattr(_app_settings, name)
        if value is not None:
            return str(value)
    return os.getenv(name, default)


class LLMClient:
    """OpenAI 兼容 chat completions 客户端。"""

    def __init__(
        self,
        base_url: Optional[str] = None,
        api_key: Optional[str] = None,
        model: Optional[str] = None,
        enabled: Optional[bool] = None,
        timeout: float = 60.0,
        use_openai_lib: bool = False,
    ) -> None:
        self.base_url = (base_url or _get_setting("LLM_BASE_URL", "https://api.deepseek.com/v1")).rstrip("/")
        self.api_key = api_key or _get_setting("LLM_API_KEY", "")
        self.model = model or _get_setting("LLM_MODEL", "deepseek-chat")
        if enabled is None:
            enabled_val = _get_setting("LLM_ENABLED", "false")
            self.enabled = str(enabled_val).strip().lower() in ("1", "true", "yes", "on")
        else:
            self.enabled = bool(enabled)
        self.timeout = float(timeout)
        self.use_openai_lib = use_openai_lib

    # ------------------------------------------------------------------ #
    # 可用性
    # ------------------------------------------------------------------ #
    def available(self) -> bool:
        """是否可用：启用 且 有 Key 且 有 base_url。"""
        return bool(self.enabled and self.api_key and self.base_url)

    # ------------------------------------------------------------------ #
    # 对话
    # ------------------------------------------------------------------ #
    def chat(
        self,
        system: str,
        user: str,
        max_tokens: int = 1500,
        temperature: float = 0.2,
    ) -> str:
        """
        发起一次 chat 对话，返回模型回复文本。

        :param system: 系统提示词
        :param user: 用户输入
        :param max_tokens: 最大生成 token 数
        :param temperature: 采样温度
        :raises LLMUnavailableError: 未启用 / 未配置
        :raises LLMError: 调用失败（已重试一次）
        """
        if not self.available():
            raise LLMUnavailableError("LLM 未启用或未配置（LLM_ENABLED/LLM_API_KEY/LLM_BASE_URL）")

        messages = [
            {"role": "system", "content": system},
            {"role": "user", "content": user},
        ]
        last_exc: Optional[Exception] = None
        for attempt in (1, 2):  # 失败重试一次
            try:
                if self.use_openai_lib:
                    return self._chat_openai(messages, max_tokens, temperature)
                return self._chat_requests(messages, max_tokens, temperature)
            except Exception as exc:  # noqa: BLE001 - 记录后重试
                last_exc = exc
                logger.warning("LLM 第 %d 次调用失败: %s", attempt, exc)
        raise LLMError(f"LLM 调用失败（已重试一次）: {last_exc}")

    def _chat_requests(self, messages: List[Dict[str, str]], max_tokens: int, temperature: float) -> str:
        import requests  # 延迟导入

        url = f"{self.base_url}/chat/completions"
        payload: Dict[str, Any] = {
            "model": self.model,
            "messages": messages,
            "max_tokens": max_tokens,
            "temperature": temperature,
        }
        headers = {
            "Authorization": f"Bearer {self.api_key}",
            "Content-Type": "application/json",
        }
        resp = requests.post(url, json=payload, headers=headers, timeout=self.timeout)
        resp.raise_for_status()
        data = resp.json()
        content = data["choices"][0]["message"]["content"]
        if content is None:
            content = ""
        return str(content).strip()

    def _chat_openai(self, messages: List[Dict[str, str]], max_tokens: int, temperature: float) -> str:
        import openai  # 延迟导入

        client = openai.OpenAI(api_key=self.api_key, base_url=self.base_url, timeout=self.timeout)
        resp = client.chat.completions.create(
            model=self.model,
            messages=messages,
            max_tokens=max_tokens,
            temperature=temperature,
        )
        content = resp.choices[0].message.content
        return str(content or "").strip()

    # ------------------------------------------------------------------ #
    # 视觉 / 图片理解（多模态模型，如 deepseek-v4-flash-vision-exp）
    # ------------------------------------------------------------------ #
    def recognize_image(
        self,
        image_b64: str,
        mime_type: str = "image/jpeg",
        prompt: str = "",
        max_tokens: int = 1500,
        temperature: float = 0.1,
    ) -> str:
        """
        把一张图片（base64）发给多模态模型，返回模型输出的文本。

        用于 PaddleOCR 未安装 / 无法识别时的读图兜底：让视觉大模型直接
        读取图片内容，识别题目文字并整理成题干文本。

        :param image_b64: 图片的 base64（不含 data: 前缀）
        :param mime_type: 图片 MIME，如 image/jpeg / image/png
        :param prompt: 附加指令（默认让模型转述图片中的题目内容）
        :raises LLMUnavailableError: 未启用 / 未配置
        :raises LLMError: 调用失败（已重试一次）
        """
        if not self.available():
            raise LLMUnavailableError("LLM 未启用或未配置（LLM_ENABLED/LLM_API_KEY/LLM_BASE_URL）")

        if not prompt:
            prompt = (
                "请仔细阅读这张图片中的题目（可能含数学公式），完整地转录出题目内容。"
                "保持原有结构，不要漏掉选项、条件和单位。只输出题目文本，不要额外解释。"
            )
        messages: List[Dict[str, Any]] = [
            {"role": "system", "content": "你是专业的图片 OCR 与题目转录助手。"},
            {
                "role": "user",
                "content": [
                    {"type": "text", "text": prompt},
                    {
                        "type": "image_url",
                        "image_url": {"url": f"data:{mime_type};base64,{image_b64}", "detail": "high"},
                    },
                ],
            },
        ]
        url = f"{self.base_url}/chat/completions"
        headers = {
            "Authorization": f"Bearer {self.api_key}",
            "Content-Type": "application/json",
        }
        payload: Dict[str, Any] = {
            "model": _get_setting("VISION_MODEL") or self.model,
            "messages": messages,
            "max_tokens": max_tokens,
            "temperature": temperature,
        }
        import requests  # 延迟导入

        last_exc: Optional[Exception] = None
        for _ in range(2):  # 失败重试一次
            try:
                resp = requests.post(url, json=payload, headers=headers, timeout=self.timeout)
                resp.raise_for_status()
                data = resp.json()
                content = data["choices"][0]["message"]["content"]
                return str(content or "").strip()
            except Exception as exc:  # noqa: BLE001 - 记录后重试
                last_exc = exc
                logger.warning("视觉模型调用失败: %s", exc)
        raise LLMError(f"视觉模型调用失败（已重试一次）: {last_exc}")

    # ------------------------------------------------------------------ #
    # JSON 便捷方法
    # ------------------------------------------------------------------ #
    def chat_json(
        self,
        system: str,
        user: str,
        max_tokens: int = 1500,
        temperature: float = 0.2,
    ) -> Dict[str, Any]:
        """发起对话并解析 JSON（内部用 structure.parse_question_json 兜底）。"""
        from app.llm.structure import parse_question_json

        raw = self.chat(system, user, max_tokens=max_tokens, temperature=temperature)
        return parse_question_json(raw)
