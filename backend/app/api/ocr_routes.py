"""
OCR 识别路由（POST /api/ocr/recognize）。

对齐 docs/spec.md §7 接口表：multipart 字段名 file -> OCRResult
{ocr_text, latex_text, blocks[], confidence}。

依赖降级：PaddleOCR / texify 未安装时 ocr_pipeline 内部优雅降级
（空 ocr_text / 空 latex_text），本路由仍返回结构化结果；
坏图片字节 -> ValueError -> 400。
"""
from __future__ import annotations

from fastapi import APIRouter, File, HTTPException, UploadFile

from app.api.deps import to_ocr_result
from app.ocr import ocr_pipeline
from app.schemas.ocr import OCRResult

router = APIRouter(prefix="/ocr", tags=["ocr"])


@router.post(
    "/recognize",
    response_model=OCRResult,
    summary="图片 OCR 识别（中文印刷体 + 公式 LaTeX）",
)
async def recognize(
    file: UploadFile = File(..., description="图片文件（multipart 字段名 file）"),
) -> OCRResult:
    data = await file.read()
    if not data:
        raise HTTPException(status_code=400, detail="上传文件为空")
    try:
        raw = ocr_pipeline.recognize(data)
    except ValueError as exc:
        raise HTTPException(status_code=400, detail=str(exc)) from exc
    return to_ocr_result(raw)
