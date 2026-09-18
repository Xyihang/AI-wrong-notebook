"""
题目业务服务：CRUD / 多维度筛选 / 批量删除 / 批量移动知识点。

设计要点：
- 对外标识是字符串 UUID（questions.uuid 列），int 主键不对外暴露。
- 所有方法接受可选的 Session（FastAPI 注入 get_db()），未传入时自建并关闭。
- 业务错误抛出 ServiceError（ValueError 子类），message 可直接作为
  API 错误体 {"detail": message}；Agent-D 在路由层捕获并转为 HTTPException。
- 知识点同步：题目上的 knowledge_points（JSON 路径列表）会同步 upsert 到
  knowledge_points 表并通过 question_tags 关联，保证树与关联一致。
- 向量入库（ChromaDB）由 Agent-C 的 retrieval 层负责，本服务不写向量库。

借鉴 texts-claude-question-bank-system 的 question_manager.py 的
create/search/batch_import 思路，改造为 SQLAlchemy 2.0 + 本系统契约。
"""
from __future__ import annotations

import uuid as uuid_lib
from datetime import datetime, timezone
from typing import Any, Iterable

from sqlalchemy import func, or_, select
from sqlalchemy.orm import Session

from app.core.errors import ServiceError
from app.core.logging import get_logger
from app.db.models import KnowledgePoint, Question
from app.db.session import SessionLocal
from app.schemas.question import (
    MASTERY_LEVELS,
    DIFFICULTY_LEVELS,
    QuestionCreate,
    QuestionListOut,
    QuestionOut,
    QuestionUpdate,
)

logger = get_logger(__name__)


class QuestionService:
    """错题数据访问与业务逻辑。"""

    def __init__(self, session_factory=SessionLocal):
        self._session_factory = session_factory

    # ------------------------------------------------------------------
    # 内部工具
    # ------------------------------------------------------------------

    def _session(self, db: Session | None) -> Session:
        return db if db is not None else self._session_factory()

    @staticmethod
    def _close(db: Session, own: bool) -> None:
        if own:
            db.close()

    @staticmethod
    def _ownership(user_id: int):
        """
        数据归属过滤子句。

        多用户模式下，每个用户只能看到/操作自己的错题（user_id == 当前用户）；
        同时兼容历史单用户数据（user_id == 0 的共享题，所有用户可见）。
        匿名访问（user_id=0）时只可见共享数据。
        """
        return or_(Question.user_id == int(user_id), Question.user_id == 0)

    @staticmethod
    def _get_by_uuid(db: Session, q_uuid: str, user_id: int = 0) -> Question:
        q = db.scalar(
            select(Question).where(
                Question.uuid == q_uuid, QuestionService._ownership(user_id)
            )
        )
        if q is None:
            raise ServiceError(f"题目不存在: {q_uuid}", status_code=404)
        return q

    @staticmethod
    def _validate_enums(data: dict[str, Any]) -> None:
        mastery = data.get("mastery")
        if mastery is not None and mastery not in MASTERY_LEVELS:
            raise ServiceError(
                f"mastery 取值非法: {mastery!r}（可选: {'/'.join(MASTERY_LEVELS)}）"
            )
        difficulty = data.get("difficulty")
        if difficulty is not None and difficulty not in DIFFICULTY_LEVELS:
            raise ServiceError(
                f"difficulty 取值非法: {difficulty!r}（可选: {'/'.join(DIFFICULTY_LEVELS)}）"
            )

    def _sync_knowledge_points(
        self, db: Session, question: Question, names: Iterable[str]
    ) -> None:
        """
        将题目 knowledge_points（如 ["初中","几何","圆"]）同步到
        knowledge_points 表（get-or-create，按 name+subject 唯一）并刷新关联。

        新出现的知识点以 parent_id=None 建为顶层节点（树由 init_db 种子提供，
        业务上允许自由扩展）。关联集合整体替换。
        """
        subject = question.subject.strip() or "未分类"
        links: list[KnowledgePoint] = []
        seen: set[str] = set()
        for raw in names or []:
            name = str(raw).strip()
            if not name or name in seen:
                continue
            seen.add(name)
            kp = db.scalar(
                select(KnowledgePoint).where(
                    KnowledgePoint.name == name,
                    KnowledgePoint.subject == subject,
                )
            )
            if kp is None:
                kp = KnowledgePoint(name=name, subject=subject, parent_id=None)
                db.add(kp)
                db.flush()
            links.append(kp)
        question.knowledge_points_rel = links

    # ------------------------------------------------------------------
    # ORM -> QuestionOut
    # ------------------------------------------------------------------

    @staticmethod
    def to_out(q: Question, similar_matches: list | None = None) -> QuestionOut:
        """ORM Question -> QuestionRecord JSON（id 取 uuid，int 主键不暴露）。"""
        return QuestionOut(
            id=q.uuid,
            subject=q.subject or "",
            knowledge_points=list(q.knowledge_points or []),
            question_type=q.question_type or "",
            difficulty=q.difficulty or "中等",
            stem=q.stem or "",
            options=list(q.options or []),
            answer=q.answer or "",
            analysis=q.analysis or "",
            mistake_reason=q.mistake_reason or "",
            mastery=q.mastery or "未掌握",
            tags=list(q.tags or []),
            image_path=q.image_path or "",
            ocr_text=q.ocr_text or "",
            latex_text=q.latex_text or "",
            created_at=q.created_at,
            updated_at=q.updated_at,
            review_count=int(q.review_count or 0),
            last_reviewed_at=q.last_reviewed_at,
            client_json=q.client_json,
            source=q.source,
            status=q.status or "active",
            similar_matches=list(similar_matches or []),
        )

    # ------------------------------------------------------------------
    # CRUD
    # ------------------------------------------------------------------

    def create(
        self,
        payload: QuestionCreate | dict[str, Any],
        db: Session | None = None,
        user_id: int = 0,
    ) -> QuestionOut:
        """
        创建 / 幂等 upsert 题目。

        客户端同步时可传入自己的 uuid（payload.id）与 created_at / updated_at /
        review_count / last_reviewed_at：
        - 已存在同 uuid 且属于该用户 -> 更新为「本人所有并带新时间戳」，返回既有记录；
        - 否则新建（uuid 用客户端 id 或服务端生成）。

        无客户端 id 时保持原语义：服务端生成 uuid、sync_version=0。
        stem 与 ocr_text 允许为空（LLM 降级为纯 OCR 入库），但二者不能同时为空。
        """
        data = (
            payload.model_dump()
            if isinstance(payload, QuestionCreate)
            else QuestionCreate.model_validate(payload).model_dump()
        )
        if not data.get("stem", "").strip() and not data.get("ocr_text", "").strip():
            raise ServiceError("题干(stem)与 OCR 文本不能同时为空")
        self._validate_enums(data)

        own = db is None
        db = self._session(db)
        try:
            now = datetime.now(timezone.utc)

            def _coerce(dt) -> datetime | None:
                if isinstance(dt, datetime):
                    return dt
                if dt:
                    try:
                        return datetime.fromisoformat(str(dt))
                    except ValueError:
                        return None
                return None

            client_id = str(data.get("id") or "").strip() or None
            # 幂等 upsert：客户端 id 已存在且属该用户 -> 更新并返回
            if client_id:
                existing = db.scalar(
                    select(Question).where(
                        Question.uuid == client_id,
                        QuestionService._ownership(user_id),
                    )
                )
                if existing is not None:
                    for key in (
                        "subject", "knowledge_points", "question_type", "difficulty",
                        "stem", "options", "answer", "analysis", "mistake_reason",
                        "mastery", "tags", "image_path", "ocr_text", "latex_text",
                    ):
                        setattr(existing, key, data.get(key) or type(getattr(existing, key))())
                    if "knowledge_points" in data:
                        self._sync_knowledge_points(db, existing, data["knowledge_points"])
                    rc = data.get("review_count")
                    if rc is not None:
                        existing.review_count = int(rc)
                    lr = _coerce(data.get("last_reviewed_at"))
                    if lr is not None:
                        existing.last_reviewed_at = lr
                    if data.get("client_json") is not None:
                        existing.client_json = str(data["client_json"])
                    upd = _coerce(data.get("updated_at"))
                    existing.updated_at = upd or now
                    existing.user_id = int(user_id)
                    existing.sync_version = (existing.sync_version or 0) + 1
                    db.commit()
                    db.refresh(existing)
                    logger.info("upsert 更新题目 uuid=%s sync_version=%d",
                                existing.uuid, existing.sync_version)
                    return self.to_out(existing)

            created = _coerce(data.get("created_at")) or now
            updated = _coerce(data.get("updated_at")) or created
            q = Question(
                uuid=client_id or str(uuid_lib.uuid4()),
                user_id=int(user_id),
                subject=data.get("subject") or "",
                knowledge_points=data.get("knowledge_points") or [],
                question_type=data.get("question_type") or "",
                difficulty=data.get("difficulty") or "中等",
                stem=data.get("stem") or "",
                options=data.get("options") or [],
                answer=data.get("answer") or "",
                analysis=data.get("analysis") or "",
                mistake_reason=data.get("mistake_reason") or "",
                source=None,
                status="active",
                mastery=data.get("mastery") or "未掌握",
                image_path=data.get("image_path") or "",
                ocr_text=data.get("ocr_text") or "",
                latex_text=data.get("latex_text") or "",
                tags=data.get("tags") or [],
                review_count=int(data.get("review_count") or 0),
                last_reviewed_at=_coerce(data.get("last_reviewed_at")),
                client_json=data.get("client_json"),
                created_at=created,
                updated_at=updated,
                sync_version=0,
            )
            db.add(q)
            db.flush()
            self._sync_knowledge_points(db, q, data.get("knowledge_points") or [])
            db.commit()
            db.refresh(q)
            logger.info("创建题目 uuid=%s subject=%s", q.uuid, q.subject)
            return self.to_out(q)
        except ServiceError:
            db.rollback()
            raise
        except Exception as exc:  # noqa: BLE001 - 统一转为业务错误
            db.rollback()
            logger.exception("创建题目失败")
            raise ServiceError(f"创建题目失败: {exc}", status_code=500) from exc
        finally:
            self._close(db, own)

    def get(self, q_uuid: str, db: Session | None = None, user_id: int = 0) -> QuestionOut:
        """按 UUID 获取题目详情。不存在或非本人时抛 ServiceError(404)。"""
        own = db is None
        db = self._session(db)
        try:
            return self.to_out(self._get_by_uuid(db, q_uuid, user_id))
        finally:
            self._close(db, own)

    def list(
        self,
        subject: str | None = None,
        knowledge_point: str | None = None,
        question_type: str | None = None,
        mastery: str | None = None,
        keyword: str | None = None,
        page: int = 1,
        page_size: int = 20,
        status: str = "active",
        db: Session | None = None,
        user_id: int = 0,
    ) -> QuestionListOut:
        """
        多维度筛选 + 分页。

        - knowledge_point : 精确匹配 JSON 数组元素（like '%"几何"%'）
        - keyword         : 模糊匹配 stem / answer / analysis / ocr_text
        """
        own = db is None
        db = self._session(db)
        try:
            page = max(int(page or 1), 1)
            page_size = min(max(int(page_size or 20), 1), 200)

            conds = []
            if status:
                conds.append(Question.status == status)
            # 多用户数据隔离：本人 + 历史共享数据（user_id == 0）
            conds.append(QuestionService._ownership(user_id))
            if subject:
                conds.append(Question.subject == subject)
            if question_type:
                conds.append(Question.question_type == question_type)
            if mastery:
                conds.append(Question.mastery == mastery)
            if knowledge_point:
                kp = str(knowledge_point).strip()
                if kp:
                    conds.append(Question.knowledge_points.like(f'%"{kp}"%'))
            if keyword:
                kw = str(keyword).strip()
                if kw:
                    like = f"%{kw}%"
                    conds.append(
                        or_(
                            Question.stem.like(like),
                            Question.answer.like(like),
                            Question.analysis.like(like),
                            Question.ocr_text.like(like),
                        )
                    )

            stmt = select(Question)
            count_stmt = select(func.count(Question.id))
            for c in conds:
                stmt = stmt.where(c)
                count_stmt = count_stmt.where(c)

            total = db.scalar(count_stmt) or 0
            rows = db.scalars(
                stmt.order_by(Question.created_at.desc(), Question.id.desc())
                .offset((page - 1) * page_size)
                .limit(page_size)
            ).all()
            return QuestionListOut(
                page=page,
                total=total,
                items=[self.to_out(r) for r in rows],
            )
        finally:
            self._close(db, own)

    def update(
        self,
        q_uuid: str,
        payload: QuestionUpdate | dict[str, Any],
        db: Session | None = None,
        user_id: int = 0,
    ) -> QuestionOut:
        """
        部分更新：仅应用请求中显式提交的字段（exclude_unset），
        并递增 sync_version、刷新 updated_at。
        """
        data = (
            payload.model_dump(exclude_unset=True)
            if isinstance(payload, QuestionUpdate)
            else QuestionUpdate.model_validate(payload).model_dump(exclude_unset=True)
        )
        self._validate_enums(data)

        own = db is None
        db = self._session(db)
        try:
            q = self._get_by_uuid(db, q_uuid, user_id)
            for key, value in data.items():
                if key in ("id", "uuid", "created_at"):
                    continue
                if hasattr(q, key):
                    setattr(q, key, value)
            if "knowledge_points" in data:
                self._sync_knowledge_points(db, q, data["knowledge_points"])
            q.sync_version = (q.sync_version or 0) + 1
            # 客户端同步时携带自己的 updated_at；未携带则用服务器当前时间
            if "updated_at" not in data:
                q.updated_at = datetime.now(timezone.utc)
            db.commit()
            db.refresh(q)
            logger.info("更新题目 uuid=%s sync_version=%d", q.uuid, q.sync_version)
            return self.to_out(q)
        except ServiceError:
            db.rollback()
            raise
        except Exception as exc:  # noqa: BLE001
            db.rollback()
            logger.exception("更新题目失败 uuid=%s", q_uuid)
            raise ServiceError(f"更新题目失败: {exc}", status_code=500) from exc
        finally:
            self._close(db, own)

    def delete(self, ids: list[str], db: Session | None = None, user_id: int = 0) -> int:
        """
        批量删除（软删倾向：直接物理删除 + 级联清关联）。

        仅删除当前用户（或共享 user_id=0）的题目，不越权操作他人数据。
        :return: 实际删除条数；不存在的 id 记 warning，不报错。
        """
        ids = [str(i).strip() for i in (ids or []) if str(i).strip()]
        if not ids:
            return 0

        own = db is None
        db = self._session(db)
        try:
            rows = db.scalars(
                select(Question).where(
                    Question.uuid.in_(ids), QuestionService._ownership(user_id)
                )
            ).all()
            found = {r.uuid for r in rows}
            missing = [i for i in ids if i not in found]
            for r in rows:
                db.delete(r)
            db.commit()
            if missing:
                logger.warning("批量删除：%d 个 id 不存在: %s", len(missing), missing)
            logger.info("批量删除 %d 题（请求 %d 个）", len(rows), len(ids))
            return len(rows)
        except Exception as exc:  # noqa: BLE001
            db.rollback()
            logger.exception("批量删除失败")
            raise ServiceError(f"批量删除失败: {exc}", status_code=500) from exc
        finally:
            self._close(db, own)

    def batch_move(
        self,
        ids: list[str],
        knowledge_point: str,
        db: Session | None = None,
        user_id: int = 0,
    ) -> int:
        """
        批量移动知识点：将题目的 knowledge_points 整体替换为 [knowledge_point]，
        并同步关联表；tags 中追加该知识点（去重）。

        仅处理当前用户（或共享 user_id=0）的题目。
        :return: 实际处理的题目数。
        """
        kp = (knowledge_point or "").strip()
        if not kp:
            raise ServiceError("目标知识点不能为空")
        ids = [str(i).strip() for i in (ids or []) if str(i).strip()]
        if not ids:
            return 0

        own = db is None
        db = self._session(db)
        try:
            rows = db.scalars(
                select(Question).where(
                    Question.uuid.in_(ids), QuestionService._ownership(user_id)
                )
            ).all()
            found = {r.uuid for r in rows}
            missing = [i for i in ids if i not in found]
            now = datetime.now(timezone.utc)
            for r in rows:
                r.knowledge_points = [kp]
                tags = list(r.tags or [])
                if kp not in tags:
                    tags.append(kp)
                r.tags = tags
                self._sync_knowledge_points(db, r, [kp])
                r.sync_version = (r.sync_version or 0) + 1
                r.updated_at = now
            db.commit()
            if missing:
                logger.warning("批量移动：%d 个 id 不存在: %s", len(missing), missing)
            logger.info("批量移动 %d 题 -> 知识点 %s", len(rows), kp)
            return len(rows)
        except ServiceError:
            db.rollback()
            raise
        except Exception as exc:  # noqa: BLE001
            db.rollback()
            logger.exception("批量移动失败")
            raise ServiceError(f"批量移动失败: {exc}", status_code=500) from exc
        finally:
            self._close(db, own)


# 模块级单例，路由层可直接复用（也可自行实例化）
question_service = QuestionService()
