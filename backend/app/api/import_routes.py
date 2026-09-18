"""
整页试卷批量导入路由（POST /api/import/paper）。

当前 import_service.import_paper 为骨架（P2 功能），调用即抛
NotImplementedError -> 501，detail「整页试卷切分功能开发中」。
后续实现切分流程后无需改动路由层。
"""
from __future__ import annotations

from fastapi import APIRouter, File, Form, HTTPException, UploadFile

from app.services.import_service import import_service

router = APIRouter(prefix="/import", tags=["import"])


@router.post("/paper", summary="整页试卷批量导入（开发中）")
async def import_paper(
    file: UploadFile = File(..., description="试卷图片（multipart 字段名 file）"),
    subject: str = Form(default="", description="科目（可选）"),
) -> dict:
    data = await file.read()
    if not data:
        raise HTTPException(status_code=400, detail="上传文件为空")
    try:
        items = import_service.import_paper(
            data, subject=subject or None, filename=file.filename
        )
    except NotImplementedError as exc:
        raise HTTPException(
            status_code=501, detail="整页试卷切分功能开发中"
        ) from exc
    return {"message": "敬请期待", "items": [i.model_dump() for i in items]}
