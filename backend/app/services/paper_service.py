"""AI 变式组卷：选材（本人错题）+ AI 变式补齐 + 编排（返回整卷）。"""
from __future__ import annotations

from datetime import datetime, timezone
from typing import Any, Dict, List, Optional

from sqlalchemy import select
from sqlalchemy.orm import Session

from app.core.errors import ServiceError
from app.core.logging import get_logger
from app.db.models import Question
from app.schemas.paper import PaperGenerateRequest, PaperQuestion, PaperResult
from app.services.variant_service import generate_one

logger = get_logger(__name__)

# Subject.name -> 中文标签（用于 DB 匹配 + 给模型的学科名）
_SUBJECT_LABEL = {
    "math": "数学", "chinese": "语文", "english": "英语", "physics": "物理",
    "chemistry": "化学", "biology": "生物", "history": "历史",
    "geography": "地理", "politics": "政治", "science": "科学",
    "unknown": "", "custom": "自定义",
}
_BALANCE_DIFFICULTY = ["简单", "中等", "困难"]


def _subject_label(subject: str) -> str:
    s = (subject or "").strip()
    if not s:
        return ""
    return _SUBJECT_LABEL.get(s.lower(), s)


def _normalize_subject(s: str) -> str:
    """把 DB 存储的 subject 与请求 subject 都规整为中文标签以便比较。"""
    v = (s or "").strip()
    if v in _SUBJECT_LABEL.values():
        return v
    return _SUBJECT_LABEL.get(v.lower(), v)


def _kp_overlap(qkps: List[str], want: List[str]) -> bool:
    if not want:
        return True
    qset = {str(x) for x in (qkps or [])}
    return any(str(w) in qset or any(str(w) in qv for qv in qset) for w in want)


def fetch_candidates(
    db: Session, user_id: int, subject: str,
    knowledge_points: List[str], difficulty: Optional[str],
) -> List[Question]:
    """取当前用户（含共享 user_id=0）active 错题，按薄弱程度排序。"""
    q_subject = _normalize_subject(subject)
    rows = db.scalars(
        select(Question).where(
            Question.status == "active",
            Question.user_id.in_([int(user_id), 0]),
        )
    ).all()
    out = []
    for q in rows:
        if _normalize_subject(q.subject or "") != q_subject:
            continue
        if difficulty and (q.difficulty or "中等") != difficulty:
            continue
        if not _kp_overlap(q.knowledge_points or [], knowledge_points):
            continue
        out.append(q)
    # 薄弱优先：未掌握 -> 需巩固 -> 已掌握；同级按复习次数少/更早排前面
    rank = {"未掌握": 0, "需巩固": 1, "已掌握": 2, "": 1}
    out.sort(key=lambda q: (rank.get(q.mastery, 1), -(q.review_count or 0)))
    return out


def _to_paper_question(q: Question, source: str, source_id: Optional[str]) -> PaperQuestion:
    difficulty = q.difficulty or "中等"
    return PaperQuestion(
        stem=q.stem or "",
        options=list(q.options or []),
        answer=q.answer or "",
        analysis=q.analysis or "",
        difficulty=difficulty,
        knowledge_points=list(q.knowledge_points or []),
        question_type=q.question_type or "",
        source=source,
        source_question_id=source_id,
    )


def generate(
    request: PaperGenerateRequest,
    db: Session,
    user_id: int = 0,
) -> PaperResult:
    count = max(1, min(int(request.count or 10), 30))
    subject_label = _subject_label(request.subject) or "未知"
    candidates = fetch_candidates(
        db, user_id, request.subject,
        list(request.knowledge_points or []), request.difficulty,
    )

    questions: List[PaperQuestion] = []
    # 1) 优先用本人错题（取 up to count）
    for q in candidates:
        if len(questions) >= count:
            break
        questions.append(_to_paper_question(q, "existing", q.uuid))

    # 2) AI 变式补齐
    need = count - len(questions)
    failed = 0
    for i in range(need):
        idx = i + 1
        diffs = ([request.difficulty] if request.difficulty
                 else _BALANCE_DIFFICULTY)
        diff = diffs[i % len(diffs)]
        # 种子：优先从已有该知识点的原题取题干，让变式有据可依
        seed = ""
        for q in candidates:
            if q.stem:
                seed = q.stem
                break
        try:
            v = generate_one(
                subject=subject_label,
                knowledge_points=list(request.knowledge_points or []),
                difficulty=diff,
                seed_stem=seed,
                number=idx,
            )
            if not (v.get("stem") or "").strip():
                failed += 1
                continue
            questions.append(PaperQuestion(
                stem=v["stem"],
                options=v.get("options") or [],
                answer=v.get("answer") or "",
                analysis=v.get("analysis") or "",
                difficulty=v.get("difficulty") or diff,
                knowledge_points=v.get("knowledge_points")
                or list(request.knowledge_points or []),
                question_type=v.get("question_type") or "",
                source="ai",
            ))
        except Exception as exc:  # noqa: BLE001 - 单题失败继续，保证部分成功返回
            failed += 1
            logger.warning("组卷变式第 %d 题失败: %s", idx, exc)

    # 编排：先按 source（原题在前）？按难度简单->困难 更好看。这里先 difficulty 排序，再同难度保持稳定
    order = {"简单": 0, "中等": 1, "困难": 2, "": 1}
    questions.sort(key=lambda qq: (order.get(qq.difficulty, 1)))

    if not questions:
        raise ServiceError(
            "该条件下没有可用错题，且 AI 变式生成失败（请确认已配置可用模型 Key 后重试）",
            status_code=400,
        )

    ts = datetime.now(timezone.utc).strftime("%Y-%m-%d %H:%M")
    title = f"{subject_label} · AI 变式组卷（{ts}）"
    if failed:
        logger.info("组卷完成 %d 题，其中 %d 题 AI 生成失败（已跳过）", len(questions), failed)
    return PaperResult(
        title=title, subject=request.subject,
        questions=questions,
    )
