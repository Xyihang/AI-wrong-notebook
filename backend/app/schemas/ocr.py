"""
OCR 识别结果契约（POST /api/ocr/recognize 响应）。

由 Agent-B 的 ocr 流水线填充：preprocess -> layout -> 逐块识别 -> 合并。
"""
from __future__ import annotations

from typing import Any

from pydantic import BaseModel, Field


class OCRBlock(BaseModel):
    """单个文字块（含位置与置信度）。"""

    text: str = Field(default="", description="块内识别文本")
    confidence: float = Field(default=0.0, ge=0.0, le=1.0, description="置信度 0~1")
    box: list[float] = Field(
        default_factory=list,
        description="四边形顶点 [x1, y1, x2, y2, x3, y3, x4, y4]",
    )


class OCRResult(BaseModel):
    """OCR 流水线整体输出。"""

    ocr_text: str = Field(default="", description="合并后的全文（按版面顺序）")
    latex_text: str = Field(default="", description="公式识别 LaTeX（texify 缺失时为空）")
    blocks: list[OCRBlock] = Field(default_factory=list, description="逐块识别结果")
    confidence: float = Field(default=0.0, ge=0.0, le=1.0, description="整体置信度")

    # 兼容旧契约：blocks 也可能被序列化为裸 dict 列表
    model_config = {"arbitrary_types_allowed": False}

    def to_legacy_dict(self) -> dict[str, Any]:
        """输出为 spec §7 约定的 dict 形态（blocks 为裸 dict）。"""
        return {
            "ocr_text": self.ocr_text,
            "latex_text": self.latex_text,
            "blocks": [b.model_dump() for b in self.blocks],
            "confidence": self.confidence,
        }
