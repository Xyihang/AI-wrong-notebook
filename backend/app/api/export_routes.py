"""
PDF 导出路由（GET /api/export/pdf | /worksheet）。

- GET /api/export/pdf?mode=plain|with_answer&subject=&knowledge_point=&ids=
    ids 为逗号分隔的题目 UUID，提供时忽略其它筛选（导出指定题目）。
- GET /api/export/worksheet?subject=&knowledge_point=
    巩固练习卷：题干后预留答题空行，不含答案。

导出实现（Agent-A 的 export_service）：reportlab + 内置 STSong-Light 中文字体。
无题可导 -> 400。
"""
from __future__ import annotations

from typing import Optional
from urllib.parse import quote

from fastapi import APIRouter, Depends, HTTPException, Query
from fastapi.responses import StreamingResponse
from sqlalchemy import select
from sqlalchemy.orm import Session

from app.api.deps import run_service
from app.db.models import Question
from app.db.session import get_db
from app.services.export_service import build_pdf, build_worksheet
from app.services.question_service import question_service

router = APIRouter(prefix="/export", tags=["export"])


def _content_disposition(filename: str) -> str:
    """RFC 5987：中文文件名用 filename* 编码，同时保留 ASCII 兜底名。"""
    return f"attachment; filename=\"export.pdf\"; filename*=utf-8''{quote(filename)}"


def _pdf_response(data: bytes, filename: str) -> StreamingResponse:
    return StreamingResponse(
        iter([data]),
        media_type="application/pdf",
        headers={"Content-Disposition": _content_disposition(filename)},
    )


def _load_questions(
    subject: Optional[str],
    knowledge_point: Optional[str],
    ids: Optional[str],
    db: Session,
):
    """ids 优先（逗号分隔 UUID）；否则按筛选条件取前 200 条。"""
    if ids:
        id_list = [i.strip() for i in ids.split(",") if i.strip()]
        if not id_list:
            raise HTTPException(status_code=400, detail="ids 参数为空")
        rows = db.scalars(select(Question).where(Question.uuid.in_(id_list))).all()
        return [question_service.to_out(r) for r in rows]
    result = run_service(
        lambda: question_service.list(
            subject=subject,
            knowledge_point=knowledge_point,
            page=1,
            page_size=200,
            db=db,
        )
    )
    return result.items


@router.get("/pdf", summary="导出错题 PDF（纯题 / 带答案解析）")
def export_pdf(
    mode: str = Query(default="plain", pattern="^(plain|with_answer)$", description="plain=纯题 | with_answer=含答案解析"),
    subject: Optional[str] = Query(default=None, description="科目筛选"),
    knowledge_point: Optional[str] = Query(default=None, description="知识点筛选"),
    ids: Optional[str] = Query(default=None, description="逗号分隔的题目 UUID（提供时忽略其它筛选）"),
    db: Session = Depends(get_db),
) -> StreamingResponse:
    questions = _load_questions(subject, knowledge_point, ids, db)
    try:
        data = build_pdf(questions, mode=mode)
    except ValueError as exc:
        raise HTTPException(status_code=400, detail=str(exc)) from exc
    return _pdf_response(data, "错题导出.pdf")


@router.get("/worksheet", summary="导出巩固练习卷 PDF（不含答案）")
def export_worksheet(
    subject: Optional[str] = Query(default=None, description="科目筛选"),
    knowledge_point: Optional[str] = Query(default=None, description="知识点筛选"),
    db: Session = Depends(get_db),
) -> StreamingResponse:
    questions = _load_questions(subject, knowledge_point, None, db)
    try:
        data = build_worksheet(questions)
    except ValueError as exc:
        raise HTTPException(status_code=400, detail=str(exc)) from exc
    return _pdf_response(data, "巩固练习卷.pdf")
