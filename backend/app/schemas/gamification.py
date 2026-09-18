"""游戏化（学习连击 & 成就徽章）数据契约（Pydantic v2）。"""
from __future__ import annotations

from datetime import datetime

from pydantic import BaseModel, Field


class AchievementOut(BaseModel):
    """单枚徽章（含解锁状态）。achievement_id 与前端 gamification.dart 的 id 一致。"""

    id: str = Field(description="徽章 id（first_record / streak_3 …）")
    name: str = Field(description="徽章名")
    icon: str = Field(description="emoji 图标")
    description: str = Field(description="解锁条件描述")
    unlocked_at: datetime | None = Field(
        default=None, description="非空表示已解锁（该时间点解锁）"
    )


class GamificationOut(BaseModel):
    """账号连击 & 徽章全量快照（服务端权威）。"""

    streak: int = Field(description="当前连击天数")
    active_today: bool = Field(description="今天是否有学习行为")
    achievements: list[AchievementOut] = Field(
        default_factory=list, description="全部徽章（含解锁状态）"
    )
    newly: list[str] = Field(
        default_factory=list,
        description="本次调用新解锁的徽章 id（用于客户端弹『恭喜』）",
    )
