"""
API 路由聚合（app.api.router）。

统一挂载到 /api 前缀（spec §7 Base URL: http://<host>:8000/api），
并在此定义系统级 GET /api/health。
"""
from __future__ import annotations

from fastapi import APIRouter, Depends
from sqlalchemy import text
from sqlalchemy.orm import Session

from app.api import (
    auth_routes,
    export_routes,
    gamification_routes,
    import_routes,
    knowledge_routes,
    ocr_routes,
    paper_routes,
    question_routes,
    retrieval_routes,
    settings_routes,
)
from app.core.config import settings
from app.db.session import get_db
from app.schemas.common import HealthOut
from app.services.settings_service import settings_service

api_router = APIRouter(prefix="/api")


@api_router.get("/health", response_model=HealthOut, tags=["system"], summary="健康检查")
def health(db: Session = Depends(get_db)) -> HealthOut:
    db_ok = True
    try:
        db.execute(text("SELECT 1"))
    except Exception:  # noqa: BLE001 - 数据库不可用时降级报告
        db_ok = False
    return HealthOut(
        status="ok" if db_ok else "degraded",
        version=settings.VERSION,
        db="ok" if db_ok else "error",
        llm_enabled=settings_service.is_llm_enabled(),
    )


# 子路由（各自带 prefix / tags）
api_router.include_router(auth_routes.router)
api_router.include_router(gamification_routes.router)
api_router.include_router(paper_routes.router)
api_router.include_router(ocr_routes.router)
api_router.include_router(question_routes.router)
api_router.include_router(retrieval_routes.router)
api_router.include_router(knowledge_routes.router)
api_router.include_router(import_routes.router)
api_router.include_router(export_routes.router)
api_router.include_router(settings_routes.router)
