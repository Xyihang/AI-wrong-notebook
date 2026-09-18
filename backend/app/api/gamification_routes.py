"""
游戏化接口：GET /api/gamification —— 账号连击 & 成就徽章（服务端权威，按账号）。

- 连击：由该账号已同步错题的 created_at / last_reviewed_at 的「活跃日期」推算，
  规则与前端 gamification.dart 一致（今天或昨天活跃才延续、断层归 0）。
- 徽章：条件由账号错题统计判定；已解锁持久化到 user_achievements，解锁不回退。
  每次 GET 会重算并把「新满足且未落库」的徽章落库、写入 newly（幂等，不重复弹）。
"""
from __future__ import annotations

from datetime import date, datetime, timezone, timedelta
from typing import Any

from fastapi import APIRouter, Depends
from sqlalchemy import select
from sqlalchemy.orm import Session

from app.api.deps import get_current_user
from app.db.models import Question, User, UserAchievement
from app.db.session import get_db
from app.schemas.gamification import AchievementOut, GamificationOut
from app.core.logging import get_logger

logger = get_logger(__name__)

router = APIRouter(prefix="/gamification", tags=["gamification"])

# ---------------------------------------------------------------------------
# 徽章目录（与前端 gamification.dart 对齐；server 仅能派生文字可同步字段）
# ---------------------------------------------------------------------------

# id: (name, icon, description, predicate)
_ACHIEVEMENTS: list[tuple[str, str, str, str, Any]] = [
    ("first_record", "首次记录", "🎉", "记录第一道错题", lambda s: s["question_count"] >= 1),
    ("collector_10", "收藏家 · 10 题", "📚", "错题本累计 10 道错题", lambda s: s["question_count"] >= 10),
    ("collector_50", "收藏家 · 50 题", "🗂️", "错题本累计 50 道错题", lambda s: s["question_count"] >= 50),
    ("collector_100", "收藏家 · 100 题", "🏛️", "错题本累计 100 道错题", lambda s: s["question_count"] >= 100),
    ("streak_3", "燃起小火苗", "🔥", "学习连击达到 3 天", lambda s: s["streak"] >= 3),
    ("streak_7", "一鼓作气", "⚡", "学习连击达到 7 天", lambda s: s["streak"] >= 7),
    ("streak_21", "坚持之王", "🏆", "学习连击达到 21 天", lambda s: s["streak"] >= 21),
    ("subject_master", "单科通", "✍️", "任意一科掌握 10 道错题",
     lambda s: any(c >= 10 for c in s["mastered_by_subject"].values())),
    ("night_owl", "深夜学者", "🌙", "曾在 0–5 点学习", lambda s: s["night_study"]),
    ("review_20", "巩固达人", "🎯", "累计复习 20 次", lambda s: s["total_reviews"] >= 20),
    # 举一反三依赖端侧变式练习（不同步图片/练习结构），服务端暂按未满足处理；
    # 若后续练习数据上云再启用：lambda s: s["any_exercise"]
]


# ---------------------------------------------------------------------------
# 日期/连击工具（与前端 dayKeyOf / computeStreak 对齐）
# ---------------------------------------------------------------------------
def _as_utc(dt: datetime | None) -> datetime | None:
    if dt is None:
        return None
    if dt.tzinfo is None:
        return dt.replace(tzinfo=timezone.utc)
    return dt.astimezone(timezone.utc)


def _date_of(dt: datetime | None) -> date | None:
    utc = _as_utc(dt)
    return utc.date() if utc is not None else None


def _compute_streak(active_dates: set[date], today: date) -> tuple[int, bool]:
    """返回 (streak, active_today)。今天活跃则续；今天没学但昨天活跃则沿用昨天连击。"""
    active_today = today in active_dates
    cursor = today
    if not active_today:
        if (today - timedelta(days=1)) not in active_dates:
            return 0, False
        cursor = today - timedelta(days=1)
    streak = 0
    while cursor in active_dates:
        streak += 1
        cursor -= timedelta(days=1)
    return streak, active_today


# ---------------------------------------------------------------------------
# 业务实现
# ---------------------------------------------------------------------------
def _compute_and_unlock(db: Session, user: User) -> GamificationOut:
    uid = user.id
    # 该账号所有 active 错题（status=active ≈ 端侧 ready）
    questions = db.scalars(
        select(Question).where(Question.user_id == uid, Question.status == "active")
    ).all()

    # 活跃日期 = created_at 与 last_reviewed_at 的日期并集
    active_dates: set[date] = set()
    mastered_by_subject: dict[str, int] = {}
    total_reviews = 0
    night_study = False
    for q in questions:
        for dt in (q.created_at, q.last_reviewed_at):
            d = _date_of(dt)
            if d:
                active_dates.add(d)
            if dt and 0 <= dt.hour < 5:
                night_study = True
        total_reviews += int(q.review_count or 0)
        if q.mastery == "已掌握":
            mastered_by_subject[q.subject or ""] = (
                mastered_by_subject.get(q.subject or "", 0) + 1
            )

    today = datetime.now(timezone.utc).date()
    streak, active_today = _compute_streak(active_dates, today)

    stats = {
        "question_count": len(questions),
        "mastered_by_subject": mastered_by_subject,
        "total_reviews": total_reviews,
        "streak": streak,
        "night_study": night_study,
        "any_exercise": False,
    }

    # 已持久化解锁
    unlocked_rows = db.scalars(
        select(UserAchievement).where(UserAchievement.user_id == uid)
    ).all()
    unlocked_by_id: dict[str, datetime] = {
        r.achievement_id: r.unlocked_at for r in unlocked_rows
    }

    # 本次新解锁：条件满足且未落库 -> 落库 + 进 newly
    newly: list[str] = []
    for aid, name, icon, desc, pred in _ACHIEVEMENTS:
        if aid not in unlocked_by_id and pred(stats):
            row = UserAchievement(
                user_id=uid, achievement_id=aid, unlocked_at=datetime.now(timezone.utc)
            )
            db.add(row)
            unlocked_by_id[aid] = row.unlocked_at
            newly.append(aid)
    if newly:
        try:
            db.commit()
        except Exception:  # noqa: BLE001 - 落库失败不阻断返回
            db.rollback()
            logger.warning("gamification 解锁落库失败 user=%s newly=%s", uid, newly)

    achievements = [
        AchievementOut(
            id=aid,
            name=name,
            icon=icon,
            description=desc,
            unlocked_at=unlocked_by_id.get(aid),
        )
        for aid, name, icon, desc, _pred in _ACHIEVEMENTS
    ]

    return GamificationOut(
        streak=streak, active_today=active_today,
        achievements=achievements, newly=newly,
    )


@router.get("", response_model=GamificationOut, summary="账号连击 & 成就徽章")
def get_gamification(
    user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
) -> GamificationOut:
    return _compute_and_unlock(db, user)
