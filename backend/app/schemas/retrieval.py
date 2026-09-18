"""
同类题检索契约（POST /api/retrieval/match）。

匹配机制（见 docs/DATA_MODEL.md「ChromaDB 向量库」）：
- 标签精确匹配：知识点标签命中
- 向量相似度：ChromaDB 余弦相似度
matched_by 取值：vector | tag | both

环形引用说明：MatchItem.question 引用 QuestionOut，而 QuestionOut.similar_matches
又引用 MatchItem —— 二者互为前向引用。本模块在 MatchItem 定义完成后调用
QuestionOut.model_rebuild(_types_namespace=...) 一次性解析，保证任意 import 顺序安全。
"""
from __future__ import annotations

from pydantic import BaseModel, ConfigDict, Field

from app.schemas.question import QuestionOut


class MatchItem(BaseModel):
    """单条匹配结果。"""

    model_config = ConfigDict(defer_build=True)  # question 字段前向引用 QuestionOut

    question: QuestionOut = Field(description="匹配到的历史错题（QuestionRecord JSON）")
    similarity: float = Field(default=0.0, ge=0.0, le=1.0, description="相似度 0~1")
    matched_by: str = Field(
        default="vector",
        description="命中方式：vector（向量）/ tag（标签）/ both（双重）",
    )


class MatchRequest(BaseModel):
    """匹配请求。"""

    text: str = Field(description="待匹配文本（题干 / OCR 文本）")
    knowledge_points: list[str] = Field(
        default_factory=list, description="候选知识点列表，用于标签精确匹配"
    )
    top_n: int = Field(default=5, ge=1, le=50, description="返回条数")


class MatchResponse(BaseModel):
    """匹配响应。"""

    items: list[MatchItem] = Field(default_factory=list)


# ---------------------------------------------------------------------------
# 解析跨模块前向引用（question.QuestionOut <-> retrieval.MatchItem）
# ---------------------------------------------------------------------------
MatchItem.model_rebuild(_types_namespace={"QuestionOut": QuestionOut})
QuestionOut.model_rebuild(_types_namespace={"MatchItem": MatchItem})
