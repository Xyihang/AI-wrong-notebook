"""
同类题检索路由（POST /api/retrieval/match）。

对齐 docs/spec.md §7：{text, knowledge_points, top_n} ->
{items: [{question: QuestionRecord, similarity, matched_by: vector|tag|both}]}。

检索实现（Agent-C 的 retrieval_service）：
- 标签精确匹配：knowledge_points 与库内题目共享 >=1 个知识点
- 向量余弦相似度：ChromaDB（缺省降级内存索引）
- 双重命中 -> matched_by="both"
"""
from __future__ import annotations

from fastapi import APIRouter, Depends

from app.api.deps import current_user_id, get_optional_user, to_match_items
from app.db.models import User
from app.retrieval import retrieval_service
from app.schemas.retrieval import MatchRequest, MatchResponse

router = APIRouter(prefix="/retrieval", tags=["retrieval"])


@router.post("/match", response_model=MatchResponse, summary="同类题匹配（标签 + 向量双重检索）")
def match(
    payload: MatchRequest,
    current_user: User | None = Depends(get_optional_user),
) -> MatchResponse:
    # 以请求文本构造「新题」QuestionRecord 骨架，交给双重检索
    new_question = {
        "id": "",  # 空 id 保证库内题目不会被排除
        "stem": payload.text,
        "knowledge_points": list(payload.knowledge_points),
        "tags": list(payload.knowledge_points),
        "question_type": "",
    }
    raw = retrieval_service.match(
        new_question,
        top_n=payload.top_n,
        scope_user_id=current_user_id(current_user),
    )
    return MatchResponse(items=to_match_items(raw))
