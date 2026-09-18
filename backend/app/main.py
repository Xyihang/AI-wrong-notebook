"""
FastAPI 应用入口（uvicorn app.main:app）。

装配内容：
- title / version 取自 app.core.config.settings（.env 可覆盖）
- CORS 中间件：allow_origins = settings.cors_origin_list（默认 *），全方法 / 全头
- lifespan：settings.ensure_dirs() -> init_db()（建表 + 种子知识点）
             -> wire_retrieval_index_provider()（检索层标签通道注入 SQLite 索引）
- 挂载 /api 路由（见 app.api.router），不挂载其它静态资源

启动：uvicorn app.main:app --host 0.0.0.0 --port 8000
"""
from __future__ import annotations

from contextlib import asynccontextmanager

from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware

from app.api.deps import wire_retrieval_index_provider
from app.api.router import api_router
from app.core.config import settings
from app.core.logging import get_logger
from app.db.init_db import init_db
from app.db.session import SessionLocal
from app.services.auth_service import auth_service

logger = get_logger(__name__)


@asynccontextmanager
async def lifespan(app: FastAPI):
    settings.ensure_dirs()
    init_db()
    wire_retrieval_index_provider()
    # 预置账户（内测固定账号，见 settings.DEFAULT_ACCOUNTS）
    try:
        with SessionLocal() as db:
            auth_service.ensure_default_accounts(db)
    except Exception as exc:  # noqa: BLE001 - 预置账户失败不影响启动
        logger.warning("预置账户处理失败: %s", exc)
    logger.info(
        "%s v%s 启动完成（LLM_ENABLED=%s EMBEDDING_MODE=%s REGISTER_ENABLED=%s）",
        settings.APP_NAME, settings.VERSION,
        settings.LLM_ENABLED, settings.EMBEDDING_MODE,
        settings.REGISTER_ENABLED,
    )
    yield


app = FastAPI(
    title=settings.APP_NAME,
    version=settings.VERSION,
    description="跨端 AI 错题整理系统后端：OCR 流水线 + 标签/向量双重检索 + 大模型结构化 + 错题业务",
    lifespan=lifespan,
)

app.add_middleware(
    CORSMiddleware,
    allow_origins=settings.cors_origin_list,
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

app.include_router(api_router)


if __name__ == "__main__":  # pragma: no cover - 便捷本地启动
    import uvicorn

    uvicorn.run(
        "app.main:app",
        host=settings.HOST,
        port=settings.BACKEND_PORT,
        reload=settings.DEBUG,
    )
