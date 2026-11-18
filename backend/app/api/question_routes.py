"""
题目路由（/api/questions/*）。

- POST   /api/questions/analyze   : 图片 OCR + AI 结构化（不入库）+ 同类题匹配
- POST   /api/questions           : 保存错题 -> {id}
- GET    /api/questions           : 列表 / 多维度筛选
- GET    /api/questions/{id}      : 详情（不存在 -> 404）
- PATCH  /api/questions/{id}      : 部分更新（编辑 / 打标 / 掌握程度）
- DELETE /api/questions           : 批量删除 -> {deleted}
- POST   /api/questions/batch-move: 批量移动知识点 -> {moved}

对外标识：QuestionRecord 的 id 为字符串 UUID（questions.uuid 列），
int 主键不对外暴露（Agent-A 约定）。

数据一致性：create / update / batch-move 后同步写入向量库；
delete 后同步从向量库清理（DATA_MODEL.md §4.2）。
"""
from __future__ import annotations

import base64
import os

from fastapi import APIRouter, Depends, File, Form, HTTPException, Query, Request, UploadFile
from sqlalchemy.orm import Session

from app.api.deps import (
    build_question_out,
    current_user_id,
    get_optional_user,
    remove_questions_from_vector,
    run_service,
    sync_question_to_vector,
    to_match_items,
)
from app.core.config import settings
from app.core.logging import get_logger
from app.core.vision_rate_limiter import (
    NO_KEY_LIMIT,
    VISION_DAILY_LIMIT,
    VISION_KEY_NO_MODE_LIMIT,
    get_client_ip,
    remaining_vision_slots,
    try_consume_vision_slot,
)
from app.db.models import User
from app.db.session import get_db
from app.llm import llm_service
from app.ocr import ocr_pipeline, paddle_engine, rapidocr_engine
from app.retrieval import retrieval_service
from app.schemas.question import (
    BatchDeleteRequest,
    BatchMoveRequest,
    QuestionAnalyzeTextRequest,
    QuestionCreate,
    QuestionListOut,
    QuestionOut,
    QuestionUpdate,
)
from app.services.question_service import question_service

logger = get_logger(__name__)

router = APIRouter(prefix="/questions", tags=["questions"])


def _guess_mime_type(filename: str) -> str:
    """根据上传文件名粗略推断图片 MIME，默认 image/jpeg。"""
    name = (filename or "").lower()
    if name.endswith(".png"):
        return "image/png"
    if name.endswith(".webp"):
        return "image/webp"
    if name.endswith(".gif"):
        return "image/gif"
    return "image/jpeg"


def _chinese_ratio(text: str) -> float:
    """返回文本中汉字字符占比（0~1）。用于判断 OCR 结果是否为「有效中文题目」。

    手写乱题 RapidOCR 常识别出一堆拉丁字母/数字/乱码（汉字占比很低），
    此时即使置信度不低，也应判定为低质量并走视觉模型兜底。
    """
    if not text:
        return 0.0
    chinese = sum(1 for ch in text if "\u4e00" <= ch <= "\u9fff")
    total = sum(1 for ch in text if not ch.isspace())
    if total == 0:
        return 0.0
    return chinese / total


# 识别结果不完整时最多重试几次
MAX_STRUCTURE_RETRY = 2


def _question_incomplete(qdict: dict) -> bool:
    """题干或其他核心信息任一为空 -> 识别不完整，需重新识别。

    用于多题场景：LLM 结构化失败时返回默认结构（只有 stem=原文），
    answer/analysis/knowledge_points 为空。这里任一核心字段为空即判定
    不完整，触发重新视觉识别 + 重试结构化。
    """
    stem = str(qdict.get("stem") or "").strip()
    answer = str(qdict.get("answer") or "").strip()
    analysis = str(qdict.get("analysis") or "").strip()
    kps = qdict.get("knowledge_points") or []
    return not stem or not answer or not analysis or not kps


@router.post(
    "/analyze",
    response_model=QuestionOut,
    summary="图片 OCR + AI 结构化（不入库，附带同类题匹配）",
)
async def analyze(
    request: Request,
    file: UploadFile = File(..., description="错题图片（multipart 字段名 file）"),
    subject: str = Form(default="", description="科目（可选，如：数学）"),
    has_vision_key: bool = Form(
        default=False, description="该用户是否已配置 DeepSeek Key（用于选择限流档位）"
    ),
    use_vision_mode: bool = Form(
        default=False,
        description="该用户是否启用视觉模式（配了 Key 但未启用时额度降为每天 20）",
    ),
    current_user: User | None = Depends(get_optional_user),
) -> QuestionOut:
    data = await file.read()
    if not data:
        raise HTTPException(status_code=400, detail="上传文件为空")

    # 1) 本地 OCR（优先 RapidOCR，回退 PaddleOCR）。不可用时尝试视觉模型读图兜底。
    ocr_text = ""
    latex_text = ""
    ocr_confidence = 0.0
    ocr_engine_available = rapidocr_engine.is_available() or paddle_engine.is_available()
    if ocr_engine_available:
        try:
            ocr = ocr_pipeline.recognize(data)
            ocr_text = ocr.get("ocr_text") or ""
            latex_text = ocr.get("latex_text") or ""
            ocr_confidence = float(ocr.get("confidence") or 0.0)
        except ValueError as exc:
            raise HTTPException(status_code=400, detail=str(exc)) from exc
    else:
        logger.info("本地 OCR（RapidOCR/PaddleOCR）均不可用，检查是否可用视觉大模型读图兜底")

    # 识别质量判断：满足任一条件即认为 RapidOCR 结果不可靠，走视觉大模型读图兜底。
    # 1) ocr_text 为空
    # 2) 平均置信度 < 阈值（实测乱码题置信度约 0.716，正常印刷体约 0.95）
    # 3) 中文字符占比 < 阈值（手写乱题常识别出大量拉丁/乱码，汉字占比低）
    ocr_confidence_threshold = float(os.getenv("OCR_CONFIDENCE_THRESHOLD", "0.85"))
    ocr_chinese_ratio_threshold = float(os.getenv("OCR_CHINESE_RATIO_THRESHOLD", "0.6"))

    chinese_ratio = _chinese_ratio(ocr_text)
    ocr_quality_poor = (
        (not ocr_text.strip())
        or ocr_confidence < ocr_confidence_threshold
        or chinese_ratio < ocr_chinese_ratio_threshold
    )
    logger.info(
        "OCR 质量判断: len=%d 置信度=%.3f 中文占比=%.3f -> 质量差=%s",
        len(ocr_text.strip()), ocr_confidence, chinese_ratio, ocr_quality_poor,
    )

    # 视觉兜底 + 结构化（含完整性重试，最多 MAX_STRUCTURE_RETRY 次）。
    # 多题场景：LLM 结构化可能失败返回「默认结构」（只有题干、缺答案/解析/知识点），
    # 这里校验完整性，任一核心字段为空则重新视觉识别 + 重试结构化。
    attempt = 0
    qdict: dict = {}
    vision_charged = False   # 本次请求是否已扣过视觉额度（重试不再重复扣）
    ocr_from_vision = False  # 当前 ocr_text 是否来自视觉识别
    while True:
        # 1) 需要走视觉兜底：仅「首次 OCR 质量差」或「当前没有可用的 OCR 文本」。
        #    已有视觉 OCR 文本时，完整性重试只重新做结构化，不再重新读图/扣额度
        #    （修复「一张图被扣多次额度」的问题）。
        need_vision = (
            (ocr_quality_poor or attempt > 0)
            and (not ocr_text.strip() or not ocr_from_vision)
        )
        vision_allowed = True
        if need_vision:
            vision_used = False
            client_ip = get_client_ip(request)
            # 额度按账户计：登录用户按 user_id，匿名按 IP
            uid = current_user_id(current_user)
            vision_available = llm_service.available()
            # 限流三档：有Key+视觉模式每天50 / 有Key未开视觉模式每天20 / 无Key累计10。
            # 注意：**只有真正走视觉兜底（视觉模型可用且还有额度）时才扣减额度**；
            # 纯本地 OCR（质量良好）或视觉模型不可用一律不扣。
            if vision_available:
                if vision_charged:
                    # 同一次请求内已计费：重试直接复用，不再扣额度
                    vision_allowed = True
                else:
                    vision_allowed = try_consume_vision_slot(
                        client_ip, has_vision_key, user_id=uid,
                        use_vision_mode=use_vision_mode,
                    )
                    if vision_allowed:
                        vision_charged = True
                if not vision_allowed:
                    logger.info(
                        "IP %s 用户(has_key=%s vision_mode=%s user_id=%s) 视觉兜底已达上限，跳过视觉兜底，回退标准模式",
                        client_ip, has_vision_key, use_vision_mode, uid,
                    )
                else:
                    try:
                        mime = _guess_mime_type(file.filename or "")
                        image_b64 = base64.b64encode(data).decode("ascii")
                        ocr_text = llm_service.recognize_image(
                            image_b64=image_b64,
                            mime_type=mime,
                            max_tokens=settings.LLM_MAX_TOKENS,
                        )
                        ocr_text = (ocr_text or "").strip()
                        if ocr_text:
                            vision_used = True
                            ocr_from_vision = True
                            logger.info(
                                "视觉大模型读图兜底成功（IP %s has_key=%s vision_mode=%s user_id=%s 剩余 %d 次）",
                                client_ip, has_vision_key, use_vision_mode, uid,
                                remaining_vision_slots(
                                    client_ip, has_vision_key, user_id=uid,
                                    use_vision_mode=use_vision_mode,
                                ),
                            )
                    except Exception as exc:  # noqa: BLE001 - 兜底失败则继续降级
                        logger.warning("视觉大模型读图兜底失败: %s", exc)

            if not ocr_text.strip():
                detail = "未识别到文字，请更换图片或重试"
                if vision_available and not vision_allowed:
                    if not has_vision_key:
                        limit = NO_KEY_LIMIT
                        prefix = "累计 "
                    elif use_vision_mode:
                        limit = VISION_DAILY_LIMIT
                        prefix = "每账户每天 "
                    else:
                        limit = VISION_KEY_NO_MODE_LIMIT
                        prefix = "每账户每天 "
                    detail = (
                        f"视觉识别兜底次数已达上限（{prefix}{limit} 次）。"
                        f"DS 视觉识别已回退到基础 OCR，重新填写 Key 或开启视觉模式即可继续使用。"
                    )
                elif not vision_used:
                    detail += "（本地 OCR 与视觉模型均不可用，请安装 paddleocr 或配置视觉大模型）"
                raise HTTPException(status_code=400, detail=detail)

        # 2) LLM 可用 -> 抽取结构化；不可用 / 失败 -> 纯规则降级（仅存 OCR 文本）
        if llm_service.available():
            # 多题/长文本时用更大输出上限，避免 LLM 输出 JSON 被截断导致不完整
            structure_max_tokens = settings.LLM_MAX_TOKENS
            qdict = llm_service.analyze_question(
                ocr_text=ocr_text,
                subject=subject,
                max_tokens=structure_max_tokens,
                extra_instruction=(
                    "特别注意：上一轮结构化结果缺少答案/解析/知识点中的部分字段。"
                    "请务必基于 OCR 文本补全这些字段，并只输出完整合法的 JSON。"
                    if attempt > 0
                    else ""
                ),
            )
        else:
            qdict = llm_service.rule_analyze(ocr_text)

        qdict["ocr_text"] = ocr_text
        qdict["latex_text"] = latex_text or qdict.get("latex_text") or ""
        if subject and not qdict.get("subject"):
            qdict["subject"] = subject

        # 3) 完整性检查：题干/答案/解析/知识点任一为空 -> 重新视觉识别重试。
        #    纯规则降级（LLM 不可用）只存文本，属预期行为，不做完整性重试。
        if not llm_service.available() or not _question_incomplete(qdict):
            break
        if attempt >= MAX_STRUCTURE_RETRY:
            logger.warning(
                "识别结果不完整，重试 %d 次仍失败（OCR len=%d）",
                attempt, len(ocr_text),
            )
            raise HTTPException(
                status_code=422,
                detail="识别结果不完整（题干/答案/解析/知识点缺失），已自动重试仍失败。"
                       "请更换更清晰的图片，或开启视觉模式使用你的 Key 直连后重试。",
            )
        attempt += 1
        logger.warning(
            "识别结果不完整（第 %d 次重试），重新视觉识别后重试结构化", attempt
        )

    question = build_question_out(qdict)

    # 同类题自动匹配（标签 + 向量双重检索），挂到 similar_matches
    # 按当前用户隔离：登录用户只匹配本人 + 共享数据；匿名只匹配共享数据。
    try:
        matches = retrieval_service.match(
            qdict, top_n=5, scope_user_id=current_user_id(current_user)
        )
        question.similar_matches = to_match_items(matches)
    except Exception as exc:  # noqa: BLE001 - 检索失败不影响结构化结果返回
        logger.warning("同类题匹配失败: %s", exc)

    return question


@router.post(
    "/analyze-text",
    response_model=QuestionOut,
    summary="端侧OCR文字 -> AI 结构化（不入库，附带同类题匹配）",
)
def analyze_text(
    payload: QuestionAnalyzeTextRequest,
    current_user: User | None = Depends(get_optional_user),
) -> QuestionOut:
    """接收端侧 OCR 识别出的文字，走结构化 + 同类题匹配（不再上传图片）。"""
    ocr_text = (payload.ocr_text or "").strip()
    if not ocr_text:
        raise HTTPException(status_code=400, detail="识别文字为空")

    # 结构化（LLM 可用 -> AI；否则 -> 纯规则降级）
    if llm_service.available():
        qdict = llm_service.analyze_question(ocr_text=ocr_text, subject=payload.subject)
    else:
        qdict = llm_service.rule_analyze(ocr_text)

    qdict["ocr_text"] = ocr_text
    if payload.subject and not qdict.get("subject"):
        qdict["subject"] = payload.subject

    question = build_question_out(qdict)

    # 同类题自动匹配（按当前用户隔离）
    try:
        matches = retrieval_service.match(
            qdict, top_n=5, scope_user_id=current_user_id(current_user)
        )
        question.similar_matches = to_match_items(matches)
    except Exception as exc:  # noqa: BLE001 - 检索失败不影响结构化结果返回
        logger.warning("同类题匹配失败: %s", exc)

    return question


@router.post("", response_model=dict, summary="保存错题")
def create(
    payload: QuestionCreate,
    db: Session = Depends(get_db),
    current_user: User | None = Depends(get_optional_user),
) -> dict:
    uid = current_user_id(current_user)
    out = run_service(lambda: question_service.create(payload, db=db, user_id=uid))
    sync_question_to_vector(out, user_id=uid)
    return {"id": out.id}


@router.get("", response_model=QuestionListOut, summary="错题列表 / 多维度筛选")
def list_questions(
    subject: str | None = Query(default=None, description="科目精确筛选"),
    knowledge_point: str | None = Query(default=None, description="知识点（JSON 数组元素精确匹配）"),
    question_type: str | None = Query(default=None, description="题型精确筛选"),
    mastery: str | None = Query(default=None, description="掌握程度：未掌握 / 已掌握 / 需巩固"),
    keyword: str | None = Query(default=None, description="关键词（匹配 题干/答案/解析/OCR 原文）"),
    page: int = Query(default=1, ge=1, description="页码（从 1 开始）"),
    page_size: int = Query(default=20, ge=1, le=200, description="每页条数（上限 200）"),
    db: Session = Depends(get_db),
    current_user: User | None = Depends(get_optional_user),
) -> QuestionListOut:
    return run_service(
        lambda: question_service.list(
            subject=subject,
            knowledge_point=knowledge_point,
            question_type=question_type,
            mastery=mastery,
            keyword=keyword,
            page=page,
            page_size=page_size,
            db=db,
            user_id=current_user_id(current_user),
        )
    )


@router.get("/{question_id}", response_model=QuestionOut, summary="题目详情（按 UUID）")
def get_question(
    question_id: str,
    db: Session = Depends(get_db),
    current_user: User | None = Depends(get_optional_user),
) -> QuestionOut:
    return run_service(
        lambda: question_service.get(question_id, db=db, user_id=current_user_id(current_user))
    )


@router.patch("/{question_id}", response_model=QuestionOut, summary="部分更新题目（编辑 / 打标 / 掌握程度）")
def update_question(
    question_id: str,
    payload: QuestionUpdate,
    db: Session = Depends(get_db),
    current_user: User | None = Depends(get_optional_user),
) -> QuestionOut:
    out = run_service(
        lambda: question_service.update(
            question_id, payload, db=db, user_id=current_user_id(current_user)
        )
    )
    sync_question_to_vector(out, user_id=current_user_id(current_user))
    return out


@router.delete("", response_model=dict, summary="批量删除题目")
def delete_questions(
    payload: BatchDeleteRequest,
    db: Session = Depends(get_db),
    current_user: User | None = Depends(get_optional_user),
) -> dict:
    deleted = run_service(
        lambda: question_service.delete(
            payload.ids, db=db, user_id=current_user_id(current_user)
        )
    )
    remove_questions_from_vector(payload.ids)
    return {"deleted": deleted}


@router.post("/batch-move", response_model=dict, summary="批量移动知识点")
def batch_move(
    payload: BatchMoveRequest,
    db: Session = Depends(get_db),
    current_user: User | None = Depends(get_optional_user),
) -> dict:
    moved = run_service(
        lambda: question_service.batch_move(
            payload.ids,
            payload.knowledge_point,
            db=db,
            user_id=current_user_id(current_user),
        )
    )
    # 移动后知识点变化，同步刷新向量库元数据（未找到的 id 跳过）
    for qid in payload.ids:
        try:
            sync_question_to_vector(
                question_service.get(qid, db=db),
                user_id=current_user_id(current_user),
            )
        except Exception:  # noqa: BLE001 - 单个失败不影响整体
            continue
    return {"moved": moved}
