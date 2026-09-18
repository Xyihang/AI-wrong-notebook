"""
数据库初始化：建表 + 种子知识点树。

- init_db()              : 幂等。建表（若不存在）+ 种子知识点（若为空）。
- seed_knowledge_points(): 仅补种缺失节点，可重复调用。
- reset_db()             : 危险操作，drop 全部表后重建（仅测试/开发用）。

默认种子（中文教材知识点树，根节点 name == subject）：
    数学 -> 代数 / 几何 / 圆 / 函数 / 概率
    语文 -> 古诗文 / 现代文阅读 / 写作 / 文言文
    英语 -> 词汇 / 语法 / 阅读理解 / 写作
    物理 -> 力学 / 电学 / 光学 / 热学
    化学 -> 无机化学 / 有机化学 / 化学实验 / 化学计算
"""
from __future__ import annotations

import sqlalchemy as sa
from sqlalchemy import inspect, select
from sqlalchemy.orm import Session

from app.core.config import settings
from app.core.logging import get_logger
from app.db.models import Base, KnowledgePoint
from app.db.session import SessionLocal, engine

logger = get_logger(__name__)

DEFAULT_KNOWLEDGE_TREE: dict[str, list[str]] = {
    "数学": ["代数", "几何", "圆", "函数", "概率"],
    "语文": ["古诗文", "现代文阅读", "写作", "文言文"],
    "英语": ["词汇", "语法", "阅读理解", "写作"],
    "物理": ["力学", "电学", "光学", "热学"],
    "化学": ["无机化学", "有机化学", "化学实验", "化学计算"],
}


def init_db() -> None:
    """建表（不存在时）+ 轻量迁移 + 种子知识点。幂等，可安全多次调用。"""
    settings.ensure_dirs()
    _run_lightweight_migrations()
    Base.metadata.create_all(bind=engine)
    with SessionLocal() as db:
        created = seed_knowledge_points(db)
        if created:
            logger.info("知识点种子：新增 %d 个节点", created)


def _run_lightweight_migrations() -> None:
    """
    针对已存在旧库的轻量增量迁移（不引入 Alembic）。

    仅做「给已有表补列」这类安全的 ALTER TABLE ADD COLUMN，
    并用 inspect 判断列是否已存在，保证幂等、不破坏已有数据。
    """
    inspector = inspect(engine)
    table_names = set(inspector.get_table_names())

    # 历史单用户库的 questions 表没有 user_id 列 -> 补列（默认 0=匿名/共享）+ 索引
    if "questions" in table_names:
        cols = {c["name"] for c in inspector.get_columns("questions")}
        if "user_id" not in cols:
            logger.info("迁移：questions 表新增 user_id 列（默认 0，历史数据归共享）")
            with engine.begin() as conn:
                conn.execute(
                    sa.text(
                        "ALTER TABLE questions ADD COLUMN user_id INTEGER NOT NULL DEFAULT 0"
                    )
                )
            # SQLite 的 ALTER 不会带索引，手动补
            try:
                with engine.begin() as conn:
                    conn.execute(
                        sa.text(
                            "CREATE INDEX IF NOT EXISTS ix_questions_user_id "
                            "ON questions (user_id)"
                        )
                    )
            except Exception as exc:  # noqa: BLE001 - 索引失败不影响主流程
                logger.warning("创建 user_id 索引失败: %s", exc)
        # 复习/连击字段（服务端推算连击与徽章）：幂等补列
        if "review_count" not in cols:
            logger.info("迁移：questions 表新增 review_count 列（默认 0）")
            with engine.begin() as conn:
                conn.execute(
                    sa.text(
                        "ALTER TABLE questions "
                        "ADD COLUMN review_count INTEGER NOT NULL DEFAULT 0"
                    )
                )
        if "last_reviewed_at" not in cols:
            logger.info("迁移：questions 表新增 last_reviewed_at 列")
            with engine.begin() as conn:
                conn.execute(
                    sa.text("ALTER TABLE questions ADD COLUMN last_reviewed_at DATETIME")
                )
        # 客户端完整记录 JSON（无损同步用），幂等补列
        if "client_json" not in cols:
            logger.info("迁移：questions 表新增 client_json 列")
            with engine.begin() as conn:
                conn.execute(
                    sa.text("ALTER TABLE questions ADD COLUMN client_json TEXT")
                )


def seed_knowledge_points(
    db: Session, tree: dict[str, list[str]] | None = None
) -> int:
    """
    按 tree 补种知识点。已存在的节点跳过（按 name+subject 唯一约束判断）。

    :return: 本次新增节点数
    """
    tree = tree or DEFAULT_KNOWLEDGE_TREE
    created = 0
    for subject, child_names in tree.items():
        # 根节点（name == subject, parent_id 为空）
        root = db.scalar(
            select(KnowledgePoint).where(
                KnowledgePoint.name == subject,
                KnowledgePoint.subject == subject,
                KnowledgePoint.parent_id.is_(None),
            )
        )
        if root is None:
            root = KnowledgePoint(name=subject, subject=subject, parent_id=None)
            db.add(root)
            db.flush()
            created += 1

        for child_name in child_names:
            exists = db.scalar(
                select(KnowledgePoint).where(
                    KnowledgePoint.name == child_name,
                    KnowledgePoint.subject == subject,
                )
            )
            if exists is None:
                db.add(
                    KnowledgePoint(
                        name=child_name, subject=subject, parent_id=root.id
                    )
                )
                created += 1

    db.commit()
    return created


def reset_db(drop_all: bool = True) -> None:
    """危险：清空并重建所有表（仅测试 / 开发用）。"""
    if drop_all:
        Base.metadata.drop_all(bind=engine)
    init_db()
