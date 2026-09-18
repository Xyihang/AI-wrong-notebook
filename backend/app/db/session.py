"""
数据库引擎与 Session 管理。

- engine        : 基于 settings.DATABASE_URL 创建（SQLite 自动加 check_same_thread=False）
- SessionLocal  : sessionmaker 工厂
- get_db()      : FastAPI 依赖注入用生成器（请求结束自动关闭）

SQLite 下通过 connect 事件开启 PRAGMA foreign_keys=ON，保证级联删除生效。
"""
from __future__ import annotations

from sqlalchemy import create_engine, event
from sqlalchemy.orm import Session, sessionmaker

from app.core.config import settings
from app.db.models import Base

_IS_SQLITE = settings.DATABASE_URL.startswith("sqlite")

engine = create_engine(
    settings.DATABASE_URL,
    echo=settings.DEBUG,
    future=True,
    connect_args={"check_same_thread": False} if _IS_SQLITE else {},
)

if _IS_SQLITE:

    @event.listens_for(engine, "connect")
    def _enable_sqlite_foreign_keys(dbapi_connection, _connection_record) -> None:  # noqa: ANN001
        cursor = dbapi_connection.cursor()
        cursor.execute("PRAGMA foreign_keys=ON")
        cursor.close()


SessionLocal = sessionmaker(
    bind=engine,
    class_=Session,
    autoflush=False,
    expire_on_commit=False,
)


def get_db():
    """FastAPI 依赖：每个请求一个 Session，请求结束自动关闭。"""
    db: Session = SessionLocal()
    try:
        yield db
    finally:
        db.close()
