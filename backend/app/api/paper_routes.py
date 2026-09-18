"""组卷路由：POST /api/paper/generate、POST /api/paper/export。"""
from __future__ import annotations

from typing import Optional
from urllib.parse import quote

from fastapi import APIRouter, Depends, HTTPException
from fastapi.responses import StreamingResponse
from sqlalchemy.orm import Session

from app.api.deps import current_user_id, get_optional_user
from app.api.deps import run_service
from app.db.models import User
from app.db.session import get_db
from app.schemas.paper import (
    PaperGenerateRequest,
    PaperGenerateResponse,
    PaperPdfRequest,
)
from app.services.export_service import build_pdf
from app.services.paper_service import generate

router = APIRouter(prefix="/paper", tags=["paper"])


@router.post(
    "/generate",
    response_model=PaperGenerateResponse,
    summary="AI 变式组卷（错题优先 + AI 补齐）",
)
def generate_paper(
    payload: PaperGenerateRequest,
    db: Session = Depends(get_db),
    current_user: User | None = Depends(get_optional_user),
) -> PaperGenerateResponse:
    paper = run_service(
        lambda: generate(payload, db=db, user_id=current_user_id(current_user))
    )
    return PaperGenerateResponse(paper=paper)


@router.post("/export", summary="把已生成的卷导出为 PDF（reportlab）")
def export_paper_pdf(payload: PaperPdfRequest) -> StreamingResponse:
    questions = payload.questions
    if not questions:
        raise HTTPException(status_code=400, detail="没有可导出的题目")
    mode = "with_answer" if payload.include_answers else "plain"
    try:
        data = build_pdf(
            questions,
            mode=mode,
        )
    except ValueError as exc:
        raise HTTPException(status_code=400, detail=str(exc)) from exc
    filename = f"{payload.title or 'AI组卷'}.pdf"
    return StreamingResponse(
        iter([data]),
        media_type="application/pdf",
        headers={
            "Content-Disposition": (
                'attachment; filename="paper.pdf"; '
                f"filename*=utf-8''{quote(filename)}"
            )
        },
    )
