"""
运行时设置服务（内存态）。

管理 llm_enabled / model / base_url / api_key，初始值取自
app.core.config.settings（即 .env），进程重启后重置为默认值。
api_key 读取时默认掩码为 ******，防止泄露到前端。

线程安全：内部 RLock 保护读写。
"""
from __future__ import annotations

import threading
from copy import deepcopy
from typing import Any

from app.core.config import settings as default_settings
from app.core.logging import get_logger

logger = get_logger(__name__)

_MASK = "******"
_ALLOWED_KEYS = frozenset({"llm_enabled", "model", "base_url", "api_key"})


class SettingsService:
    """运行时配置读写。"""

    def __init__(self, defaults: dict[str, Any] | None = None):
        self._store: dict[str, Any] = defaults if defaults is not None else {
            "llm_enabled": default_settings.LLM_ENABLED,
            "model": default_settings.LLM_MODEL,
            "base_url": default_settings.LLM_BASE_URL,
            "api_key": default_settings.LLM_API_KEY,
        }
        self._lock = threading.RLock()

    # ------------------------------------------------------------------

    def get(self, mask_secret: bool = True) -> dict[str, Any]:
        """返回设置副本；api_key 默认掩码。"""
        with self._lock:
            data = deepcopy(self._store)
        if mask_secret and data.get("api_key"):
            data["api_key"] = _MASK
        return data

    def update(self, patch: dict[str, Any] | None) -> dict[str, Any]:
        """部分更新；未知键抛 ValueError。返回更新后的完整设置（掩码）。"""
        patch = patch or {}
        unknown = set(patch) - _ALLOWED_KEYS
        if unknown:
            raise ValueError(f"不支持的设置项: {sorted(unknown)}")

        with self._lock:
            if "llm_enabled" in patch:
                self._store["llm_enabled"] = self._coerce_bool(patch["llm_enabled"])
            if patch.get("model") is not None:
                self._store["model"] = str(patch["model"]).strip()
            if patch.get("base_url") is not None:
                self._store["base_url"] = str(patch["base_url"]).strip()
            if "api_key" in patch:
                v = patch["api_key"]
                if v != _MASK:  # 掩码回写视为未修改
                    self._store["api_key"] = str(v).strip()

        logger.info(
            "运行时设置已更新: %s",
            {k: (v if k != "api_key" else _MASK) for k, v in self._store.items()},
        )
        return self.get()

    def is_llm_enabled(self) -> bool:
        """LLM 是否真正可用（开关开启且已配置 Key）。"""
        with self._lock:
            return bool(self._store.get("llm_enabled")) and bool(
                self._store.get("api_key")
            )

    def get_llm_config(self) -> dict[str, Any]:
        """供 llm 层读取的完整配置（含明文 api_key，仅服务端内部使用）。"""
        with self._lock:
            return deepcopy(self._store)

    # ------------------------------------------------------------------

    @staticmethod
    def _coerce_bool(v: Any) -> bool:
        if isinstance(v, bool):
            return v
        return str(v).strip().lower() in ("1", "true", "yes", "on", "y")


# 模块级单例
settings_service = SettingsService()
