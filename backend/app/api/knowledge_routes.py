"""
知识点树路由（GET /api/knowledge-points）。

返回多层级树：根节点（parent_id 为空，name == subject）-> 子节点。
种子树由 app/db/init_db.py 在启动时幂等补种。
"""
from __future__ import annotations

from fastapi import APIRouter, Depends
from sqlalchemy import select
from sqlalchemy.orm import Session

from app.db.models import KnowledgePoint
from app.db.session import get_db
from app.schemas.question import KnowledgePointOut

router = APIRouter(prefix="/knowledge-points", tags=["knowledge-points"])


@router.get("", response_model=list[KnowledgePointOut], summary="知识点树（多层级）")
def list_knowledge_points(
    db: Session = Depends(get_db),
) -> list[KnowledgePointOut]:
    rows = db.scalars(select(KnowledgePoint).order_by(KnowledgePoint.id)).all()
    nodes: dict[int, KnowledgePointOut] = {}
    by_parent: dict[int | None, list[KnowledgePointOut]] = {}
    for kp in rows:
        node = KnowledgePointOut(
            id=kp.id, name=kp.name, subject=kp.subject, parent_id=kp.parent_id
        )
        nodes[kp.id] = node
        by_parent.setdefault(kp.parent_id, []).append(node)
    for node in nodes.values():
        node.children = by_parent.get(node.id, [])
    return by_parent.get(None, [])
