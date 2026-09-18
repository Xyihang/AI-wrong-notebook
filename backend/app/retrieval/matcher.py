"""
双重检索匹配器（Matcher）。

「标签精确匹配 + 文本向量余弦相似度」双通道（spec §4.2 F2 / §2.3 复用点）：
1. 标签匹配：新题 knowledge_points（缺失时退用 tags）与库内题目共享 >=1 个
   知识点即命中；
2. 向量匹配：经 VectorStore 计算文本余弦相似度；
3. 合并打分：combined = 标签加成（命中 tag/both 时）+ 向量相似度，
   按 combined 降序返回 top_n，每条含
   {"question": QuestionRecord dict, "similarity": float, "matched_by": "vector"|"tag"|"both"}。

题目索引来源（question_index_provider）由集成方注入，本模块不依赖 DB：
- 注入 callable：`() -> Iterable[dict]`（每项为 QuestionRecord dict）；
- 注入带 `list_questions()` 方法的对象（DB session adapter 适配器）；
- 未注入时退用 VectorStore.list_items()（基于 upsert 时写入的 metadata
  重建 QuestionRecord，字段缺省补齐）。

本模块 import 安全：不依赖 chromadb / DB / pydantic-settings。
"""
from __future__ import annotations

import logging
import re
from typing import Any, Callable, Dict, Iterable, List, Optional, Protocol, Sequence

logger = logging.getLogger(__name__)

# QuestionRecord 契约字段（docs/spec.md §7.1），用于缺省补齐
_QUESTION_FIELDS: List[str] = [
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
    "mastery",
    "tags",
    "image_path",
    "ocr_text",
    "latex_text",
    "created_at",
    "similar_matches",
]

_QUESTION_DEFAULTS: Dict[str, Any] = {
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
    "mastery": "未掌握",
    "tags": [],
    "image_path": "",
    "ocr_text": "",
    "latex_text": "",
    "created_at": "",
    "similar_matches": [],
}


class QuestionIndexProvider(Protocol):
    """题目索引提供者：返回可迭代的 QuestionRecord 字典。"""

    def __call__(self) -> Iterable[Dict[str, Any]]: ...


def _norm(s: Any) -> str:
    """知识点 / 标签归一化：去空白、统一小写（英文标签大小写不敏感）。"""
    return re.sub(r"\s+", "", str(s or "")).strip().lower()


def _kps_of(question: Dict[str, Any]) -> List[str]:
    """取题目的知识点列表；为空时退用 tags。"""
    kps = question.get("knowledge_points") or []
    if not kps:
        kps = question.get("tags") or []
    return [_norm(k) for k in kps if _norm(k)]


def _ensure_record(question: Dict[str, Any]) -> Dict[str, Any]:
    """保证返回的 question 字典具备 QuestionRecord 全部字段（缺省补齐）。"""
    record = dict(_QUESTION_DEFAULTS)
    for k, v in (question or {}).items():
        if k in record or k in _QUESTION_FIELDS:
            record[k] = v
    return record


def _user_allowed(record: Dict[str, Any], scope_user_id: int) -> bool:
    """数据归属过滤：当前用户可见「本人（user_id==scope）」+「共享（user_id==0）」。

    匿名（scope_user_id==0）只可见共享数据。
    """
    uid = int((record or {}).get("user_id") or 0)
    scope = int(scope_user_id or 0)
    if scope == 0:
        return uid == 0
    return uid == scope or uid == 0


def _user_filter(scope_user_id: int) -> Dict[str, Any]:
    """构造向量检索的 user_id 过滤条件（Chroma where / 内存索引通用）。"""
    scope = int(scope_user_id or 0)
    if scope == 0:
        return {"user_id": 0}
    return {"$or": [{"user_id": scope}, {"user_id": 0}]}


class Matcher:
    """
    标签 + 向量 双重检索。

    :param vector_store: VectorStore 实例
    :param embedding_service: EmbeddingService 实例（用于拼查询文本）
    :param question_index_provider: 题目索引来源（见模块 docstring）
    :param tag_bonus: 首个共享知识点的得分加成
    :param tag_bonus_step: 每多共享一个知识点的额外加成
    :param tag_bonus_cap: 标签加成上限
    :param vector_margin: 向量通道多取的比例（合并前留出候选余量）
    """

    def __init__(
        self,
        vector_store=None,
        embedding_service=None,
        question_index_provider: Optional[Any] = None,
        tag_bonus: float = 0.25,
        tag_bonus_step: float = 0.05,
        tag_bonus_cap: float = 0.4,
        vector_margin: float = 3.0,
    ) -> None:
        if vector_store is None:
            from app.retrieval.vector_store import VectorStore

            vector_store = VectorStore()
        if embedding_service is None:
            from app.retrieval.embeddings import EmbeddingService

            embedding_service = EmbeddingService()
        self._vector_store = vector_store
        self._embedding_service = embedding_service
        self._provider = question_index_provider
        self._tag_bonus = float(tag_bonus)
        self._tag_bonus_step = float(tag_bonus_step)
        self._tag_bonus_cap = float(tag_bonus_cap)
        self._vector_margin = max(1.0, float(vector_margin))

    # ------------------------------------------------------------------ #
    # 索引来源
    # ------------------------------------------------------------------ #
    @property
    def question_index_provider(self) -> Any:
        return self._provider

    def set_question_index_provider(self, provider: Any) -> None:
        """注入 / 替换题目索引来源（集成方在应用启动时调用）。"""
        self._provider = provider

    def _iter_questions(self) -> Iterable[Dict[str, Any]]:
        """枚举库内全部题目（优先 provider，缺省退用 vector_store 内存索引）。"""
        if self._provider is not None:
            if callable(self._provider):
                yield from self._provider() or []
                return
            list_fn = getattr(self._provider, "list_questions", None)
            if callable(list_fn):
                yield from list_fn() or []
                return
            logger.warning("question_index_provider 无法调用（无 __call__ 且无 list_questions），退用向量库索引")
        # 缺省：由 vector_store 的 metadata 重建
        for item in self._vector_store.list_items():
            meta = dict(item.get("metadata") or {})
            meta.setdefault("id", item.get("id", ""))
            yield meta

    # ------------------------------------------------------------------ #
    # 核心匹配
    # ------------------------------------------------------------------ #
    def match(
        self,
        new_question: Dict[str, Any],
        top_n: int = 5,
        scope_user_id: int = 0,
    ) -> List[Dict[str, Any]]:
        """
        双通道检索。

        :param new_question: 新题 QuestionRecord 字典（至少含 stem /
                             knowledge_points / tags / question_type）
        :param top_n: 返回条数
        :param scope_user_id: 数据隔离范围。匿名传 0（仅匹配共享数据）；
                              已登录用户传其 user_id（匹配本人 + 共享数据）。
        :return: [{"question": {...}, "similarity": float, "matched_by": str}, ...]
                 按 similarity 降序
        """
        top_n = max(1, int(top_n))
        if not new_question:
            return []

        new_id = str(new_question.get("id") or "")
        query_text = self._build_query_text(new_question)
        new_kps = set(_kps_of(new_question))

        # --- 通道 1：标签匹配（共享 >=1 知识点，且归属当前用户/共享）---
        tag_hits: Dict[str, Dict[str, Any]] = {}  # id -> {"question", "shared"}
        for existing in self._iter_questions():
            eid = str(existing.get("id") or "")
            if not eid or eid == new_id:
                continue
            if not _user_allowed(existing, scope_user_id):
                continue
            shared = new_kps & set(_kps_of(existing))
            if shared:
                tag_hits[eid] = {"question": existing, "shared": len(shared)}

        # --- 通道 2：向量匹配（余弦相似度，按 user_id 隔离）---
        vector_hits: Dict[str, float] = {}
        if query_text.strip():
            vec_top = max(top_n * int(self._vector_margin), top_n)
            for hit in self._vector_store.query(
                query_text, top_n=vec_top, filter_meta=_user_filter(scope_user_id)
            ):
                hid = str(hit.get("id") or "")
                if hid and hid != new_id:
                    vector_hits[hid] = float(hit.get("score", 0.0))

        # --- 合并打分 ---
        merged: Dict[str, Dict[str, Any]] = {}
        for eid in set(tag_hits) | set(vector_hits):
            tag_info = tag_hits.get(eid)
            vec_score = vector_hits.get(eid, 0.0)
            tag_bonus = 0.0
            if tag_info:
                shared = tag_info["shared"]
                tag_bonus = min(
                    self._tag_bonus + (shared - 1) * self._tag_bonus_step,
                    self._tag_bonus_cap,
                )
            if tag_info and vec_score > 0:
                matched_by = "both"
            elif tag_info:
                matched_by = "tag"
            else:
                matched_by = "vector"
            combined = min(1.0, tag_bonus + vec_score)  # 钳制到 [0,1]，便于前端展示
            question = tag_info["question"] if tag_info else None
            if question is None:
                # vector-only 命中：从向量库 metadata 重建
                question = self._question_from_store(eid)
            merged[eid] = {
                "question": _ensure_record(question),
                "similarity": round(combined, 4),
                "matched_by": matched_by,
            }

        results = sorted(
            merged.values(),
            key=lambda r: (-r["similarity"], str(r["question"].get("id", ""))),
        )
        return results[:top_n]

    # ------------------------------------------------------------------ #
    # 工具
    # ------------------------------------------------------------------ #
    def _build_query_text(self, question: Dict[str, Any]) -> str:
        from app.retrieval.vector_store import compose_embedding_text

        return compose_embedding_text(
            stem=str(question.get("stem", "")),
            knowledge_points=question.get("knowledge_points") or question.get("tags") or [],
            question_type=str(question.get("question_type", "")),
        )

    def _question_from_store(self, question_id: str) -> Dict[str, Any]:
        for item in self._vector_store.list_items():
            if str(item.get("id", "")) == str(question_id):
                meta = dict(item.get("metadata") or {})
                meta.setdefault("id", question_id)
                return meta
        return {"id": question_id}
