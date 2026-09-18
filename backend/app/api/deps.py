"""
API 层共享工具（deps）。

供各路由模块复用的编排胶水：
- run_service()                : 执行业务调用，ServiceError -> HTTPException
- to_ocr_result()              : ocr_pipeline 输出 -> OCRResult（bbox -> box）
- build_question_out()         : 结构化 dict -> QuestionOut（补临时 uuid / created_at）
- to_match_items()             : retrieval 层裸 dict 结果 -> list[MatchItem]
- sync_question_to_vector()    : 题目 create/update 后同步向量库（幂等 upsert）
- remove_questions_from_vector(): 批量删除时同步清理向量库
- wire_retrieval_index_provider(): 启动时把 SQLite 题目注入检索层标签通道
- sync_llm_client_from_settings(): 运行时设置变更后重建 LLM 客户端（免重启生效）
"""
from __future__ import annotations

import uuid as uuid_lib
from datetime import datetime, timezone
from typing import Any, Callable, Dict, Iterable, List, TypeVar

from fastapi import Depends, HTTPException
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer
from sqlalchemy import select
from sqlalchemy.orm import Session

from app.core.logging import get_logger
from app.core.security import InvalidTokenError, decode_access_token
from app.db.models import Question, User
from app.db.session import SessionLocal, get_db
from app.retrieval import retrieval_service
from app.schemas.ocr import OCRBlock, OCRResult
from app.schemas.question import QuestionOut
from app.schemas.retrieval import MatchItem
from app.services.question_service import ServiceError, question_service
from app.services.settings_service import settings_service

logger = get_logger(__name__)

T = TypeVar("T")

# Bearer token 解析器（auto_error=False：缺 header 时返回 None 而非直接 401，
# 便于 get_optional_user 对匿名/旧客户端做向后兼容）
_bearer_scheme = HTTPBearer(auto_error=False)


# ---------------------------------------------------------------------------
# ServiceError -> HTTPException
# ---------------------------------------------------------------------------
def run_service(fn: Callable[[], T]) -> T:
    """
    执行一次业务调用；ServiceError 统一转为
    HTTPException(status_code=e.status_code, detail=e.message)。
    """
    try:
        return fn()
    except ServiceError as exc:
        raise HTTPException(status_code=exc.status_code, detail=exc.message) from exc


# ---------------------------------------------------------------------------
# 认证依赖（用户登录）
# ---------------------------------------------------------------------------
def get_optional_user(
    credentials: HTTPAuthorizationCredentials | None = Depends(_bearer_scheme),
    db: Session = Depends(get_db),
) -> User | None:
    """
    可选鉴权：Bearer token 有效 -> 返回 User；缺失 / 非法 / 过期 -> 返回 None。

    用于「向后兼容」的场景：匿名 / 旧客户端（尚未接入登录）仍可访问，
    但数据按 user_id=0（共享）过滤；已登录用户按其 user_id 隔离。
    """
    if credentials is None:
        return None
    try:
        payload = decode_access_token(credentials.credentials)
    except InvalidTokenError:
        return None
    sub = payload.get("sub")
    if not sub:
        return None
    return db.scalar(select(User).where(User.uuid == sub))


def get_current_user(
    credentials: HTTPAuthorizationCredentials | None = Depends(_bearer_scheme),
    db: Session = Depends(get_db),
) -> User:
    """强制鉴权：token 缺失 / 非法 / 过期时抛 401。"""
    user = get_optional_user(credentials, db)
    if user is None:
        raise HTTPException(status_code=401, detail="未认证或登录已过期")
    return user


def current_user_id(user: User | None) -> int:
    """把当前用户（或 None）映射为归属 user_id（匿名 -> 0）。"""
    return user.id if user is not None else 0


# ---------------------------------------------------------------------------
# OCR 结果归一化
# ---------------------------------------------------------------------------
def to_ocr_result(raw: Dict[str, Any]) -> OCRResult:
    """
    把 ocr_pipeline.recognize() 的输出规范为 OCRResult 契约。

    流水线 blocks 使用 "bbox"（[x1,y1,x2,y2]），OCRBlock 契约为 "box"
    （[x1,y1,x2,y2,x3,y3,x4,y4]）；二者兼容取 bbox，缺失时回退 box / 空。
    """
    blocks: List[OCRBlock] = []
    for b in raw.get("blocks") or []:
        box = b.get("box") or b.get("bbox") or []
        blocks.append(
            OCRBlock(
                text=str(b.get("text", "") or ""),
                confidence=float(b.get("confidence", 0.0) or 0.0),
                box=[float(x) for x in box],
            )
        )
    return OCRResult(
        ocr_text=str(raw.get("ocr_text", "") or ""),
        latex_text=str(raw.get("latex_text", "") or ""),
        blocks=blocks,
        confidence=float(raw.get("confidence", 0.0) or 0.0),
    )


# ---------------------------------------------------------------------------
# QuestionRecord 归一化
# ---------------------------------------------------------------------------
def _coerce_datetime(value: Any) -> datetime:
    """QuestionRecord.created_at 兼容值（datetime / ISO 字符串 / 空）-> datetime。"""
    if isinstance(value, datetime):
        return value
    if value:
        text = str(value).strip()
        try:
            if text.endswith("Z"):
                text = text[:-1] + "+00:00"
            return datetime.fromisoformat(text)
        except ValueError:
            logger.warning("无法解析 created_at=%r，回退为当前时间", value)
    return datetime.now(timezone.utc)


def build_question_out(qdict: Dict[str, Any]) -> QuestionOut:
    """
    从结构化 dict（llm_service.analyze_question / rule_analyze 输出）构建
    QuestionOut。analyze 场景不入库，id 生成临时 uuid、created_at 缺省取当前时间。
    """
    data = dict(qdict or {})
    data.setdefault("id", str(uuid_lib.uuid4()))
    data["created_at"] = _coerce_datetime(data.get("created_at"))
    return QuestionOut.model_validate(data)


def to_match_items(raw_items: Iterable[Dict[str, Any]]) -> List[MatchItem]:
    """
    把 retrieval_service.match() 返回的裸 dict 列表
    [{"question": {...}, "similarity": float, "matched_by": str}]
    规范为 list[MatchItem]（question 嵌套 QuestionOut）。
    """
    items: List[MatchItem] = []
    for raw in raw_items or []:
        qdict = dict(raw.get("question") or {})
        qdict.setdefault("id", "")
        qdict["created_at"] = _coerce_datetime(qdict.get("created_at"))
        items.append(
            MatchItem(
                question=QuestionOut.model_validate(qdict),
                similarity=float(raw.get("similarity", 0.0) or 0.0),
                matched_by=str(raw.get("matched_by", "vector") or "vector"),
            )
        )
    return items


# ---------------------------------------------------------------------------
# SQLite <-> 向量库 同步（DATA_MODEL.md §4.2）
# ---------------------------------------------------------------------------
def sync_question_to_vector(question_out: QuestionOut, user_id: int = 0) -> None:
    """题目 create / update 后同步写入向量库（幂等 upsert，失败仅告警）。

    在向量库 metadata 中写入 user_id，供检索时按用户隔离。
    """
    try:
        d = question_out.model_dump(mode="json")
        d["user_id"] = int(user_id or 0)
        retrieval_service.upsert_question(d)
    except Exception as exc:  # noqa: BLE001 - 向量库失败不影响主流程
        logger.warning("向量库 upsert 失败(id=%s): %s", question_out.id, exc)


def remove_questions_from_vector(ids: List[str]) -> None:
    """批量删除题目时同步清理向量库（幂等，失败仅告警）。"""
    try:
        retrieval_service.delete(ids)
    except Exception as exc:  # noqa: BLE001
        logger.warning("向量库删除失败: %s", exc)


def wire_retrieval_index_provider() -> None:
    """
    把 SQLite 中的 active 题目注入检索层作为标签通道索引来源，
    使「标签精确匹配」不依赖向量库内容（matcher 文档：由集成方注入）。
    应用启动（lifespan）时调用一次。

    同时把全部题目重新同步进向量库（metadata 携带 user_id）：
    历史数据（此前未存 user_id）在启动时补齐归属，保证检索按用户隔离正确生效。
    """

    def _provider() -> Iterable[Dict[str, Any]]:
        with SessionLocal() as db:
            rows = db.scalars(
                select(Question).where(Question.status == "active")
            ).all()
            for r in rows:
                qdict = question_service.to_out(r).model_dump(mode="json")
                qdict["user_id"] = r.user_id or 0
                yield qdict

    retrieval_service.set_question_index_provider(_provider)
    logger.info("检索层题目索引来源已注入（SQLite -> QuestionRecord dict）")

    # 启动同步：确保向量库 metadata 全部携带 user_id（含历史数据）
    try:
        questions = list(_provider())
        if questions:
            retrieval_service.upsert_questions(questions)
            logger.info("向量库启动同步 %d 题（已补 user_id）", len(questions))
    except Exception as exc:  # noqa: BLE001 - 同步失败不影响启动
        logger.warning("向量库启动同步失败: %s", exc)


# ---------------------------------------------------------------------------
# 运行时设置 -> LLM 客户端同步
# ---------------------------------------------------------------------------
def sync_llm_client_from_settings() -> None:
    """
    PUT /api/settings 更新运行时配置后重建 LLM 客户端，
    使 GUI 修改 Key / 模型后无需重启进程即生效。
    """
    try:
        from app.llm import llm_service
        from app.llm.client import LLMClient

        cfg = settings_service.get_llm_config()
        llm_service.client = LLMClient(
            base_url=cfg.get("base_url") or "",
            api_key=cfg.get("api_key") or "",
            model=cfg.get("model") or "",
            enabled=bool(cfg.get("llm_enabled")),
        )
        logger.info("LLM 客户端已按运行时设置重建（model=%s enabled=%s）",
                    cfg.get("model"), cfg.get("llm_enabled"))
    except Exception as exc:  # noqa: BLE001 - 同步失败不阻断设置保存
        logger.warning("同步 LLM 客户端失败: %s", exc)
