"""
SQLAlchemy 2.0 ORM 模型 —— SQLite schema。

表结构（详细说明见 docs/DATA_MODEL.md）：
- questions           错题主表（int 自增主键 + uuid 对外标识）
- knowledge_points    多层级知识点树（name, subject 唯一）
- question_tags       题目 × 知识点 多对多关联表

JSON 列（knowledge_points / options / tags）使用自定义 JSONText 类型：
以 TEXT 存储且 ensure_ascii=False，使中文内容在 SQLite 中可直接 LIKE 过滤。
"""
from __future__ import annotations

import json
import uuid as uuid_lib
from datetime import datetime, timezone
from typing import Any

from sqlalchemy import (
    Column,
    DateTime,
    ForeignKey,
    Integer,
    String,
    Table,
    Text,
    UniqueConstraint,
)
from sqlalchemy.orm import DeclarativeBase, Mapped, mapped_column, relationship
from sqlalchemy.types import TypeDecorator


def utc_now() -> datetime:
    """UTC 当前时间（带时区）。"""
    return datetime.now(timezone.utc)


def new_uuid() -> str:
    """生成对外题目标识（QuestionRecord 的 id 字段）。"""
    return str(uuid_lib.uuid4())


class JSONText(TypeDecorator):
    """
    以 TEXT 存储 JSON 的列类型。

    - 绑定参数：dict/list -> json.dumps(ensure_ascii=False)
    - 读取结果：TEXT -> json.loads
    - ensure_ascii=False 保证中文以明文落库，支持 SQL LIKE 中文过滤
      （如 Question.knowledge_points.like('%"几何"%')）。
    """

    impl = Text
    cache_ok = True

    def process_bind_param(self, value: Any, dialect: Any) -> Any:
        if value is None:
            return None
        if isinstance(value, str):
            try:
                value = json.loads(value)
            except (TypeError, ValueError):
                return value
        return json.dumps(value, ensure_ascii=False)

    def process_literal_param(self, value: Any, dialect: Any) -> str:
        return json.dumps(value, ensure_ascii=False)

    def process_result_value(self, value: Any, dialect: Any) -> Any:
        if value is None:
            return None
        if isinstance(value, str):
            try:
                return json.loads(value)
            except (TypeError, ValueError):
                return value
        return value


class Base(DeclarativeBase):
    """所有 ORM 模型的基类。"""


# ---------------------------------------------------------------------------
# 题目 × 知识点 多对多关联表
# ---------------------------------------------------------------------------
question_tag_association = Table(
    "question_tags",
    Base.metadata,
    # 使用题目 int 主键关联（uuid 仅作为对外标识）
    Column("question_id", ForeignKey("questions.id", ondelete="CASCADE"), primary_key=True),
    Column(
        "knowledge_point_id",
        ForeignKey("knowledge_points.id", ondelete="CASCADE"),
        primary_key=True,
    ),
)


class Question(Base):
    """错题主表。"""

    __tablename__ = "questions"

    # --- 标识 ---
    id: Mapped[int] = mapped_column(Integer, primary_key=True, autoincrement=True)
    # 对外暴露的 UUID（QuestionRecord JSON 的 id 字段）
    uuid: Mapped[str] = mapped_column(
        String(36), unique=True, index=True, nullable=False, default=new_uuid
    )

    # --- 分类字段 ---
    subject: Mapped[str] = mapped_column(String(50), default="", index=True)
    knowledge_points: Mapped[list] = mapped_column(JSONText, default=list)
    question_type: Mapped[str] = mapped_column(String(50), default="")
    difficulty: Mapped[str] = mapped_column(String(20), default="中等")
    tags: Mapped[list] = mapped_column(JSONText, default=list)

    # --- 归属 ---
    # 用户 int 主键。默认 0 = 匿名 / 历史单用户数据（所有用户可见）；
    # 多用户注册登录后，各自错题归各自 user_id（数据隔离）。
    user_id: Mapped[int] = mapped_column(Integer, default=0, index=True, nullable=False)

    # --- 内容字段 ---
    stem: Mapped[str] = mapped_column(Text, default="", nullable=False)
    options: Mapped[list] = mapped_column(JSONText, default=list)
    answer: Mapped[str] = mapped_column(Text, default="")
    analysis: Mapped[str] = mapped_column(Text, default="")
    mistake_reason: Mapped[str] = mapped_column(Text, default="")
    image_path: Mapped[str] = mapped_column(String(500), default="")
    ocr_text: Mapped[str] = mapped_column(Text, default="")
    latex_text: Mapped[str] = mapped_column(Text, default="")

    # --- 状态 / 同步 ---
    source: Mapped[str | None] = mapped_column(String(255), nullable=True)
    status: Mapped[str] = mapped_column(String(20), default="active", index=True)
    mastery: Mapped[str] = mapped_column(String(20), default="未掌握", index=True)
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), default=utc_now, nullable=False
    )
    updated_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), default=utc_now, onupdate=utc_now, nullable=False
    )
    sync_version: Mapped[int] = mapped_column(Integer, default=0, nullable=False)

    # --- 复习 / 连击状态（服务端按账号推算连击与徽章用）---
    review_count: Mapped[int] = mapped_column(Integer, default=0, nullable=False)
    last_reviewed_at: Mapped[datetime | None] = mapped_column(
        DateTime(timezone=True), nullable=True
    )
    # 客户端完整记录 JSON（手机 Drift QuestionRecord.toJson 原样），用于无损回拉/
    # 换设备恢复；索引列仍由字段映射填充。空 = 非同步场景（如 analyze 后直接落库）。
    client_json: Mapped[str | None] = mapped_column(Text, nullable=True)

    # --- 关联 ---
    # 注意：与 JSON 列 knowledge_points 区分，关系属性命名为 knowledge_points_rel
    knowledge_points_rel: Mapped[list[KnowledgePoint]] = relationship(
        secondary=question_tag_association,
        back_populates="questions",
        order_by="KnowledgePoint.id",
    )

    def __repr__(self) -> str:  # pragma: no cover - 仅调试
        return f"<Question id={self.id} uuid={self.uuid} subject={self.subject!r}>"


class KnowledgePoint(Base):
    """知识点树节点（多层级，parent_id 自引用）。"""

    __tablename__ = "knowledge_points"
    __table_args__ = (
        UniqueConstraint("name", "subject", name="uq_knowledge_point_name_subject"),
    )

    id: Mapped[int] = mapped_column(Integer, primary_key=True, autoincrement=True)
    name: Mapped[str] = mapped_column(String(100), nullable=False)
    parent_id: Mapped[int | None] = mapped_column(
        ForeignKey("knowledge_points.id", ondelete="SET NULL"), nullable=True
    )
    subject: Mapped[str] = mapped_column(String(50), default="", nullable=False)
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), default=utc_now, nullable=False
    )

    # 自引用层级
    parent: Mapped[KnowledgePoint | None] = relationship(
        remote_side=[id], back_populates="children"
    )
    children: Mapped[list[KnowledgePoint]] = relationship(
        back_populates="parent", order_by="KnowledgePoint.id"
    )
    questions: Mapped[list[Question]] = relationship(
        secondary=question_tag_association, back_populates="knowledge_points_rel"
    )

    def __repr__(self) -> str:  # pragma: no cover - 仅调试
        return f"<KnowledgePoint id={self.id} name={self.name!r} subject={self.subject!r}>"


class User(Base):
    """用户表（注册 / 登录 / JWT 认证）。"""

    __tablename__ = "users"

    id: Mapped[int] = mapped_column(Integer, primary_key=True, autoincrement=True)
    # 对外用户标识（JWT subject / /api/auth/me 返回的 id）
    uuid: Mapped[str] = mapped_column(
        String(36), unique=True, index=True, nullable=False, default=new_uuid
    )
    # 登录名，唯一
    username: Mapped[str] = mapped_column(
        String(64), unique=True, index=True, nullable=False
    )
    # 加盐哈希（pbkdf2_sha256），绝不存明文
    password_hash: Mapped[str] = mapped_column(String(255), nullable=False)
    display_name: Mapped[str] = mapped_column(String(64), default="")
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), default=utc_now, nullable=False
    )
    updated_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), default=utc_now, onupdate=utc_now, nullable=False
    )
    sync_version: Mapped[int] = mapped_column(Integer, default=0, nullable=False)

    def __repr__(self) -> str:  # pragma: no cover - 仅调试
        return f"<User id={self.id} username={self.username!r}>"


class UserAchievement(Base):
    """用户已解锁的成就徽章（按账号持久化，解锁不回退）。

    一条记录 = 某用户在某时刻解锁了某徽章 id。
    徽章 id 字符串与前端 gamification.dart 的 Achievement.id 一致。
    """

    __tablename__ = "user_achievements"
    __table_args__ = (
        UniqueConstraint("user_id", "achievement_id", name="uq_user_achievement"),
    )

    id: Mapped[int] = mapped_column(Integer, primary_key=True, autoincrement=True)
    # 归属用户（users.id）。0 = 匿名/共享（一般不会用到）。
    user_id: Mapped[int] = mapped_column(Integer, index=True, nullable=False)
    # 徽章 id，如 first_record / streak_3（与前端一致）。
    achievement_id: Mapped[str] = mapped_column(String(64), nullable=False)
    unlocked_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), default=utc_now, nullable=False
    )

    def __repr__(self) -> str:  # pragma: no cover - 仅调试
        return f"<UserAchievement user={self.user_id} {self.achievement_id!r}>"
