"""
检索层（Agent-C）。

对外暴露 `retrieval_service` 单例（RetrievalService 门面），统一编排：
- EmbeddingService : 文本向量化（local 哈希 / api）
- VectorStore      : ChromaDB 向量库（缺省降级内存索引）
- Matcher          : 标签 + 向量 双重检索

典型用法：
    from app.retrieval import retrieval_service

    # 集成方（Agent-A/D）在启动时注入题目索引来源（可选，不注入则用向量库 metadata 重建）
    retrieval_service.set_question_index_provider(lambda: session.query(...))

    # 入库时同步写入向量库
    retrieval_service.upsert_question(question)

    # 同类题匹配
    items = retrieval_service.match(new_question, top_n=5)
    # -> [{"question": {...}, "similarity": 0.9, "matched_by": "both"}, ...]
"""
from __future__ import annotations

import logging
from typing import Any, Dict, List, Optional, Sequence

logger = logging.getLogger(__name__)

from app.retrieval.embeddings import EmbeddingService  # noqa: E402
from app.retrieval.matcher import Matcher, QuestionIndexProvider  # noqa: E402
from app.retrieval.vector_store import VectorStore, compose_embedding_text  # noqa: E402

__all__ = [
    "retrieval_service",
    "RetrievalService",
    "EmbeddingService",
    "VectorStore",
    "Matcher",
    "QuestionIndexProvider",
    "compose_embedding_text",
]


class RetrievalService:
    """检索服务门面：向量库写入 + 双重检索匹配。"""

    def __init__(
        self,
        embedding_service: Optional[EmbeddingService] = None,
        vector_store: Optional[VectorStore] = None,
        matcher: Optional[Matcher] = None,
    ) -> None:
        self.embeddings = embedding_service or EmbeddingService()
        self.vector_store = vector_store or VectorStore(embedding_service=self.embeddings)
        self.matcher = matcher or Matcher(
            vector_store=self.vector_store,
            embedding_service=self.embeddings,
        )

    # ------------------------------------------------------------------ #
    # 配置
    # ------------------------------------------------------------------ #
    def set_question_index_provider(self, provider: Any) -> None:
        """
        注入题目索引来源（供标签通道枚举库内题目）。

        :param provider: callable `() -> Iterable[dict]`，或带
            `list_questions()` 方法的 DB session adapter。
        """
        self.matcher.set_question_index_provider(provider)

    @property
    def vector_available(self) -> bool:
        """ChromaDB 是否可用（False 时走内存余弦索引）。"""
        return self.vector_store.available

    # ------------------------------------------------------------------ #
    # 写入
    # ------------------------------------------------------------------ #
    def upsert_question(self, question: Dict[str, Any]) -> None:
        """将一条 QuestionRecord 写入向量库（幂等 upsert）。"""
        self.vector_store.upsert_questions([question])

    def upsert_questions(self, questions: Sequence[Dict[str, Any]]) -> None:
        """批量写入 QuestionRecord 列表。"""
        self.vector_store.upsert_questions(questions)

    # ------------------------------------------------------------------ #
    # 检索
    # ------------------------------------------------------------------ #
    def match(
        self,
        new_question: Dict[str, Any],
        top_n: int = 5,
        scope_user_id: int = 0,
    ) -> List[Dict[str, Any]]:
        """
        双重检索：标签精确匹配 + 向量余弦相似度。

        :param new_question: 新题 QuestionRecord 字典
        :param top_n: 返回条数
        :param scope_user_id: 数据隔离范围。匿名 0 = 仅共享；登录用户 = 本人 + 共享。
        :return: 按相似度降序的 [{"question": {...}, "similarity": float,
                  "matched_by": "vector"|"tag"|"both"}, ...]
        """
        return self.matcher.match(new_question, top_n=top_n, scope_user_id=scope_user_id)

    def query(self, text: str, top_n: int = 5, filter_meta: Optional[Dict[str, Any]] = None) -> List[Dict[str, Any]]:
        """纯向量相似度检索（不叠加标签加成）。"""
        return self.vector_store.query(text, top_n=top_n, filter_meta=filter_meta)

    def delete(self, ids: Sequence[str]) -> None:
        """从向量库删除题目。"""
        self.vector_store.delete(ids)

    def get_collection_count(self) -> int:
        """向量库当前题目数。"""
        return self.vector_store.get_collection_count()


# 模块级单例
retrieval_service = RetrievalService()
