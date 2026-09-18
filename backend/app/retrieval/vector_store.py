"""
向量库封装（ChromaDB 优先，纯 Python 内存索引兜底）。

- 持久化目录：环境变量 CHROMA_DIR（默认 ./chroma_data，settings 可用时取
  settings.CHROMA_DIR）。
- Collection 名称：questions。
- 嵌入：优先使用本包的 EmbeddingService（local 哈希嵌入，离线可用），
  通过自定义 EmbeddingFunction 交给 ChromaDB，避免 ChromaDB 默认的
  ONNX/MiniLM 模型下载。

降级策略：
- chromadb 未安装 / 初始化失败 -> available=False，upsert 维护内存索引，
  query 退化为纯 Python 余弦扫描，接口签名保持一致。
- 内存索引与 ChromaDB 同步维护（写入时双写），因此查询结果一致。

本模块 import 安全：chromadb 延迟导入，缺失不影响模块加载。
"""
from __future__ import annotations

import json
import logging
import math
import os
import threading
from typing import Any, Dict, Iterable, List, Optional, Sequence, Tuple

logger = logging.getLogger(__name__)

try:  # pragma: no cover - 取决于其它 Agent 的 core 是否就绪
    from app.core.config import settings as _app_settings

    _HAS_APP_SETTINGS = True
except Exception:  # noqa: BLE001
    _HAS_APP_SETTINGS = False


def _chroma_dir() -> str:
    if _HAS_APP_SETTINGS:
        return str(_app_settings.CHROMA_DIR)
    return os.getenv("CHROMA_DIR", "./chroma_data")


def compose_embedding_text(
    stem: str = "",
    knowledge_points: Optional[Sequence[str]] = None,
    question_type: str = "",
) -> str:
    """按 spec §6.2 拼接待嵌入文本：stem + 知识点 + 题型。"""
    parts = [stem or ""]
    if knowledge_points:
        parts.append(" ".join(str(k) for k in knowledge_points if str(k).strip()))
    if question_type:
        parts.append(str(question_type))
    return " ".join(p for p in parts if p.strip())


def _normalize_metadata(metadata: Optional[Dict[str, Any]]) -> Optional[Dict[str, Any]]:
    """ChromaDB metadata 只接受 str/int/float/bool（部分版本支持 list），
    列表/字典值统一 JSON 序列化；None 值删除。"""
    if not metadata:
        return None
    out: Dict[str, Any] = {}
    for k, v in metadata.items():
        if v is None:
            continue
        if isinstance(v, (str, int, float, bool)):
            out[str(k)] = v
        else:
            out[str(k)] = json.dumps(v, ensure_ascii=False)
    return out or None


def _normalize_where(filter_meta: Optional[Dict[str, Any]]) -> Optional[Dict[str, Any]]:
    """把 filter_meta 规整为 ChromaDB where 可接受的等值条件。

    列表/字典值与 _normalize_metadata 保持一致的 JSON 序列化语义。
    支持 $or（任一子条件命中）——用于 user_id = 当前用户 OR user_id = 0。
    """
    if not filter_meta:
        return None
    out: Dict[str, Any] = {}
    for k, v in filter_meta.items():
        if k == "$or" and isinstance(v, list):
            out["$or"] = [_normalize_where(c) or {} for c in v]
            continue
        if v is None:
            continue
        if isinstance(v, (str, int, float, bool)):
            out[str(k)] = v
        else:
            out[str(k)] = json.dumps(v, ensure_ascii=False)
    return out or None


def _metadata_matches(metadata: Optional[Dict[str, Any]], filter_meta: Optional[Dict[str, Any]]) -> bool:
    """内存索引的 metadata 过滤（与 ChromaDB where 等值语义一致，含序列化比较）。

    支持 $or；user_id 缺失时视为共享（0），兼容历史未带 user_id 的数据。
    """
    if not filter_meta:
        return True
    meta = metadata or {}
    # $or：任一子条件匹配即通过（用于 user_id = 当前用户 OR user_id = 0）
    if isinstance(filter_meta.get("$or"), list):
        return any(_metadata_matches(meta, c) for c in filter_meta["$or"])
    for k, v in filter_meta.items():
        sk = str(k)
        if sk == "$or":
            continue
        if sk == "user_id":
            # 历史数据未存 user_id -> 视为共享（0）
            stored = meta.get("user_id", 0)
            if str(stored) != str(v):
                return False
            continue
        if sk not in meta:
            return False
        stored = meta[sk]
        if isinstance(v, (list, dict, tuple)):
            if json.dumps(v, ensure_ascii=False) != json.dumps(stored, ensure_ascii=False) and str(v) != str(stored):
                return False
        elif str(stored) != str(v):
            return False
    return True


def _cosine(a: Sequence[float], b: Sequence[float]) -> float:
    """余弦相似度（纯 Python 实现，向量可不等长按较短截断）。"""
    n = min(len(a), len(b))
    if n == 0:
        return 0.0
    dot = 0.0
    na = 0.0
    nb = 0.0
    for i in range(n):
        x = a[i]
        y = b[i]
        dot += x * y
        na += x * x
        nb += y * y
    if na == 0.0 or nb == 0.0:
        return 0.0
    return dot / (math.sqrt(na) * math.sqrt(nb))


class _ChromaEmbeddingFunction:
    """把 EmbeddingService 适配为 ChromaDB EmbeddingFunction。"""

    def __init__(self, embedding_service) -> None:
        self._service = embedding_service

    def __call__(self, input: Sequence[str]) -> List[List[float]]:
        return self._service.embed(list(input))

    def name(self) -> str:
        return f"ai-wrong-{self._service.mode}-{self._service.dimension}"


class VectorStore:
    """
    ChromaDB 向量库封装（collection: questions）。

    方法在 ChromaDB 可用时走 Chroma，否则走内存余弦扫描；两种路径
    签名与返回结构一致，调用方无需感知后端差异。
    """

    def __init__(
        self,
        embedding_service=None,
        chroma_dir: Optional[str] = None,
        collection_name: str = "questions",
    ) -> None:
        if embedding_service is None:
            from app.retrieval.embeddings import EmbeddingService

            embedding_service = EmbeddingService()
        self._embedding_service = embedding_service
        self._chroma_dir = chroma_dir or _chroma_dir()
        self._collection_name = collection_name

        self._client = None
        self._collection = None
        self._available: Optional[bool] = None  # None=未探测

        # 内存索引：question_id -> {"text","metadata","vector"}
        self._index: Dict[str, Dict[str, Any]] = {}
        self._lock = threading.RLock()

    # ------------------------------------------------------------------ #
    # 可用性 / 初始化
    # ------------------------------------------------------------------ #
    @property
    def available(self) -> bool:
        """ChromaDB 是否可用（惰性探测，失败后不再重试）。"""
        if self._available is None:
            self._available = self._ensure_chroma()
        return self._available

    def _ensure_chroma(self) -> bool:
        try:
            import chromadb  # 延迟导入

            self._client = chromadb.PersistentClient(path=self._chroma_dir)
            self._collection = self._client.get_or_create_collection(
                name=self._collection_name,
                embedding_function=_ChromaEmbeddingFunction(self._embedding_service),
                metadata={"hnsw:space": "cosine"},
            )
            # 启动时把 Chroma 中已有条目回填进内存索引（幂等：同名覆盖）
            existing = self._collection.get(include=["metadatas", "documents"])
            for qid, meta, doc in zip(existing.get("ids", []), existing.get("metadatas", []), existing.get("documents", [])):
                text = doc or ""
                vec = self._embedding_service.embed_one(text)
                self._index[str(qid)] = {"text": text, "metadata": meta or {}, "vector": vec}
            logger.info("ChromaDB 可用: dir=%s collection=%s items=%d", self._chroma_dir, self._collection_name, len(existing.get("ids", [])))
            return True
        except Exception as exc:  # noqa: BLE001 - 任何初始化失败都降级
            logger.warning("ChromaDB 不可用，降级为内存向量索引: %s", exc)
            self._client = None
            self._collection = None
            return False

    # ------------------------------------------------------------------ #
    # 写入
    # ------------------------------------------------------------------ #
    def upsert_question(
        self,
        question_id: str,
        text: Optional[str] = None,
        metadata: Optional[Dict[str, Any]] = None,
    ) -> None:
        """
        写入 / 更新单题。

        :param question_id: 题目 UUID（与 SQLite 主键对齐）
        :param text: 嵌入文本；为空时按 metadata 中的 stem/knowledge_points/
                     question_type 组合（spec §6.2）
        :param metadata: 元数据（subject/knowledge_points/tags/created_at/...）
        """
        metadata = dict(metadata or {})
        if not text:
            text = compose_embedding_text(
                stem=str(metadata.get("stem", "")),
                knowledge_points=metadata.get("knowledge_points") or [],
                question_type=str(metadata.get("question_type", "")),
            )
        text = text or str(question_id)
        vector = self._embedding_service.embed_one(text)

        with self._lock:
            self._index[str(question_id)] = {"text": text, "metadata": metadata, "vector": vector}
            if self.available:
                try:
                    self._collection.upsert(
                        ids=[str(question_id)],
                        documents=[text],
                        metadatas=[_normalize_metadata(metadata)],
                    )
                except Exception as exc:  # noqa: BLE001 - 双写失败仅告警
                    logger.warning("ChromaDB upsert 失败(question=%s): %s", question_id, exc)

    def upsert_questions(self, items: Sequence[Any]) -> None:
        """
        批量写入。

        :param items: 每项为
            - {"id":..., "text":..., "metadata":...} 或
            - QuestionRecord 字典（含 id/stem/knowledge_points/question_type 等）
        """
        for item in items:
            if not isinstance(item, dict):
                continue
            qid = item.get("id")
            if not qid:
                continue
            if "text" in item or "metadata" in item:
                self.upsert_question(
                    str(qid),
                    text=item.get("text"),
                    metadata=item.get("metadata") or {},
                )
            else:  # QuestionRecord 字典
                self.upsert_question(
                    str(qid),
                    text=compose_embedding_text(
                        stem=str(item.get("stem", "")),
                        knowledge_points=item.get("knowledge_points") or [],
                        question_type=str(item.get("question_type", "")),
                    ),
                    metadata=item,
                )

    # ------------------------------------------------------------------ #
    # 查询
    # ------------------------------------------------------------------ #
    def query(
        self,
        text: str,
        top_n: int = 5,
        filter_meta: Optional[Dict[str, Any]] = None,
    ) -> List[Dict[str, Any]]:
        """
        相似度检索。

        :param text: 查询文本（内部会嵌入）
        :param top_n: 返回条数
        :param filter_meta: 等值过滤（如 {"subject": "数学"}）
        :return: [{"id": str, "score": float(0~1)}, ...] 按 score 降序
        """
        top_n = max(1, int(top_n))
        if self.available:
            try:
                return self._query_chroma(text, top_n, filter_meta)
            except Exception as exc:  # noqa: BLE001 - Chroma 运行时失败降级内存
                logger.warning("ChromaDB 查询失败，降级内存索引: %s", exc)
        return self._query_memory(text, top_n, filter_meta)

    def _query_chroma(self, text: str, top_n: int, filter_meta: Optional[Dict[str, Any]]) -> List[Dict[str, Any]]:
        n_results = min(top_n, max(1, self.get_collection_count()))
        result = self._collection.query(
            query_texts=[text],
            n_results=n_results,
            where=_normalize_where(filter_meta),
            include=["distances", "metadatas"],
        )
        ids = result.get("ids", [[]])[0] if result.get("ids") else []
        distances = result.get("distances", [[]])[0] if result.get("distances") else []
        hits: List[Dict[str, Any]] = []
        for qid, dist in zip(ids, distances):
            sim = 1.0 - float(dist)  # cosine distance -> similarity
            hits.append({"id": str(qid), "score": max(0.0, min(1.0, sim))})
        hits.sort(key=lambda h: h["score"], reverse=True)
        return hits[:top_n]

    def _query_memory(self, text: str, top_n: int, filter_meta: Optional[Dict[str, Any]]) -> List[Dict[str, Any]]:
        query_vec = self._embedding_service.embed_one(text)
        scored: List[Dict[str, Any]] = []
        with self._lock:
            for qid, entry in self._index.items():
                if not _metadata_matches(entry.get("metadata"), filter_meta):
                    continue
                score = _cosine(query_vec, entry.get("vector") or [])
                scored.append({"id": qid, "score": max(0.0, min(1.0, score))})
        scored.sort(key=lambda h: h["score"], reverse=True)
        return scored[:top_n]

    # ------------------------------------------------------------------ #
    # 删除 / 统计 / 枚举
    # ------------------------------------------------------------------ #
    def delete(self, ids: Sequence[str]) -> None:
        """按题目 ID 删除（幂等）。"""
        id_list = [str(i) for i in ids]
        with self._lock:
            for qid in id_list:
                self._index.pop(qid, None)
            if self.available:
                try:
                    self._collection.delete(ids=id_list)
                except Exception as exc:  # noqa: BLE001
                    logger.warning("ChromaDB delete 失败: %s", exc)

    def get_collection_count(self) -> int:
        """当前集合中的题目数量。"""
        if self.available:
            try:
                return int(self._collection.count())
            except Exception:  # noqa: BLE001
                pass
        return len(self._index)

    def list_items(self) -> List[Dict[str, Any]]:
        """
        枚举全部条目（供 Matcher 构建标签索引 / 集成方自建索引）。

        :return: [{"id": str, "metadata": {...}, "text": str}, ...]
        """
        with self._lock:
            return [
                {"id": qid, "metadata": dict(entry.get("metadata") or {}), "text": entry.get("text", "")}
                for qid, entry in self._index.items()
            ]
