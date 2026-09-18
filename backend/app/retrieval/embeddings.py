"""
文本向量化服务（EmbeddingService）。

两种模式（由环境变量 EMBEDDING_MODE 控制，默认 local）：
- local : 确定性本地嵌入。字符/词条哈希（hashing trick）投影到固定维度向量，
          完全离线、零依赖、无模型下载，跨进程结果一致（用 hashlib.md5，
          不用 Python 内置 hash()，因为其每次进程启动加盐）。
- api   : OpenAI 兼容嵌入接口。POST {base}/embeddings（如 DeepSeek / 通义 /
          OpenAI），配置 EMBEDDING_BASE_URL / EMBEDDING_API_KEY / EMBEDDING_MODEL；
          未配置或调用失败时自动降级回 local 模式。

本模块 import 安全：不依赖 chromadb / openai / pydantic-settings。
"""
from __future__ import annotations

import hashlib
import logging
import math
import os
import re
import threading
from collections import Counter
from typing import List, Optional, Sequence

logger = logging.getLogger(__name__)

# 优先使用 app.core.config.settings（读取 backend/.env），缺失时退回 os.environ。
try:  # pragma: no cover - 取决于其它 Agent 的 core 是否就绪
    from app.core.config import settings as _app_settings

    _HAS_APP_SETTINGS = True
except Exception:  # noqa: BLE001 - pydantic-settings 未安装等
    _HAS_APP_SETTINGS = False

_CJK_RE = re.compile(r"[\u4e00-\u9fff]")
_WORD_RE = re.compile(r"[a-zA-Z0-9]+")


def _env(name: str, default: str = "") -> str:
    """读环境变量；settings 可用时优先走 settings（其已读 .env）。"""
    if _HAS_APP_SETTINGS and hasattr(_app_settings, name):
        value = getattr(_app_settings, name)
        if value is not None:
            return str(value)
    return os.getenv(name, default)


def _tokens(text: str) -> List[str]:
    """中文题目文本 -> 词条列表：ASCII 单词 + 中文字符 + 相邻中文字符二元组。"""
    if not text:
        return []
    text = text.lower()
    tokens: List[str] = []
    tokens.extend(_WORD_RE.findall(text))
    cjk = _CJK_RE.findall(text)
    tokens.extend(cjk)
    for i in range(len(cjk) - 1):
        tokens.append(cjk[i] + cjk[i + 1])
    if not tokens:  # 纯符号等极端情况
        tokens = [text[:64]]
    return tokens


def _hash_index(token: str, dim: int) -> tuple[int, float]:
    """确定性哈希：md5 前 8 字节 -> 桶下标，第 9 字节奇偶 -> 符号（有符号哈希）。"""
    digest = hashlib.md5(token.encode("utf-8")).digest()
    idx = int.from_bytes(digest[:8], "big") % dim
    sign = 1.0 if digest[8] % 2 == 0 else -1.0
    return idx, sign


class EmbeddingService:
    """
    文本 -> 固定维度稠密向量。

    local 模式：TF 风格有符号哈希（每词条计数累加），L2 归一化。
    api 模式：OpenAI 兼容 /embeddings 接口，失败自动回退 local。
    """

    def __init__(
        self,
        mode: Optional[str] = None,
        dimension: Optional[int] = None,
        base_url: Optional[str] = None,
        api_key: Optional[str] = None,
        model: Optional[str] = None,
        timeout: float = 30.0,
    ) -> None:
        self._mode = (mode or _env("EMBEDDING_MODE", "local") or "local").strip().lower()
        try:
            self._dimension = int(dimension or _env("EMBEDDING_DIM", "256"))
        except (TypeError, ValueError):
            self._dimension = 256
        if self._dimension <= 0:
            self._dimension = 256

        self._base_url = (base_url or _env("EMBEDDING_BASE_URL") or _env("LLM_BASE_URL", "")).rstrip("/")
        self._api_key = api_key or _env("EMBEDDING_API_KEY") or _env("LLM_API_KEY", "")
        self._model = model or _env("EMBEDDING_MODEL", "text-embedding-3-small")
        self._timeout = float(timeout)

        self._lock = threading.RLock()
        self._api_configured = bool(self._base_url and self._api_key)

    # ------------------------------------------------------------------ #
    # 公开 API
    # ------------------------------------------------------------------ #
    @property
    def mode(self) -> str:
        """当前模式：local | api。"""
        return self._mode

    @property
    def dimension(self) -> int:
        """向量维度（local 模式下由 EMBEDDING_DIM 决定）。"""
        return self._dimension

    @property
    def api_configured(self) -> bool:
        """api 模式所需的 base_url / api_key 是否齐备。"""
        return self._api_configured

    def embed(self, texts: Sequence[str]) -> List[List[float]]:
        """
        批量嵌入。

        :param texts: 文本列表
        :return: 每个文本对应的向量（与输入顺序一致）
        """
        items = [t if t is not None else "" for t in texts]
        if self._mode == "api" and self._api_configured:
            try:
                return self._embed_api(items)
            except Exception as exc:  # noqa: BLE001 - 外部服务失败必须降级
                logger.warning("API 嵌入失败(%s)，降级为 local 嵌入", exc)
        return [self._embed_local(t) for t in items]

    def embed_one(self, text: str) -> List[float]:
        """单个文本嵌入（便捷方法）。"""
        return self.embed([text])[0]

    # ------------------------------------------------------------------ #
    # local 实现（确定性离线哈希）
    # ------------------------------------------------------------------ #
    def _embed_local(self, text: str) -> List[float]:
        vec = [0.0] * self._dimension
        for token, count in Counter(_tokens(text)).items():
            idx, sign = _hash_index(token, self._dimension)
            vec[idx] += sign * count
        return self._normalize(vec)

    # ------------------------------------------------------------------ #
    # api 实现（OpenAI 兼容）
    # ------------------------------------------------------------------ #
    def _embed_api(self, texts: Sequence[str]) -> List[List[float]]:
        import requests  # 延迟导入，保持模块级 import 安全

        url = f"{self._base_url}/embeddings"
        payload = {"model": self._model, "input": list(texts)}
        headers = {"Authorization": f"Bearer {self._api_key}"}
        last_exc: Optional[Exception] = None
        for attempt in (1, 2):  # 失败重试一次
            try:
                resp = requests.post(url, json=payload, headers=headers, timeout=self._timeout)
                resp.raise_for_status()
                data = resp.json()
                ordered = sorted(data.get("data", []), key=lambda e: e.get("index", 0))
                vectors = [e.get("embedding", []) for e in ordered]
                if len(vectors) != len(texts):
                    raise ValueError(f"嵌入数量不匹配: {len(vectors)} != {len(texts)}")
                return [self._normalize(list(map(float, v))) if v else [0.0] * self._dimension for v in vectors]
            except Exception as exc:  # noqa: BLE001
                last_exc = exc
                logger.warning("API 嵌入第 %d 次尝试失败: %s", attempt, exc)
        raise RuntimeError(f"嵌入接口调用失败: {last_exc}")

    # ------------------------------------------------------------------ #
    # 工具
    # ------------------------------------------------------------------ #
    @staticmethod
    def _normalize(vec: List[float]) -> List[float]:
        norm = math.sqrt(sum(v * v for v in vec))
        if norm == 0.0:
            return vec
        inv = 1.0 / norm
        return [v * inv for v in vec]
