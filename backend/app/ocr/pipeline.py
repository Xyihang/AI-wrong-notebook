"""OCR pipeline orchestration.

Assembly order (spec.md F1 / plan.md Agent-B target):

    bytes -> PIL -> preprocess -> detect question regions
    -> (slice + dedup) -> per-region PaddleOCR -> merge text top-to-bottom
    -> texify (optional) -> {ocr_text, latex_text, blocks, confidence}

Graceful degradation
--------------------
- PaddleOCR missing / broken  -> ``ocr_text=""``, ``blocks=[]``,
  ``confidence=0.0``, warning logged; the response structure is still returned
  so the API layer can answer "未识别到文字".
- texify missing / broken     -> ``latex_text=""``, pipeline continues.
- Bad image bytes             -> ``ValueError`` raised (400 at the API layer).

Public entry point (see package __init__)::

    from app.ocr import ocr_pipeline
    ocr_pipeline.recognize(image_bytes)
"""
from __future__ import annotations

import io
import logging
from typing import Any, Dict, List

import numpy as np
from PIL import Image, ImageOps

from . import config
from . import paddle_engine, rapidocr_engine, texify_engine
from .layout import QuestionLayoutDetector
from .preprocess import PreprocessConfig, preprocess
from .slice_dedup import dedup_blocks, slice_long_image

logger = logging.getLogger(__name__)


def _recognize_text(crop: np.ndarray) -> List[Dict[str, Any]]:
    """文字识别：优先 RapidOCR（轻量、中文好），失败/不可用回退 PaddleOCR。"""
    if rapidocr_engine.is_available():
        try:
            blocks = rapidocr_engine.recognize(crop)
            if blocks:
                return blocks
        except Exception as exc:  # noqa: BLE001
            logger.warning("RapidOCR 识别失败，回退 PaddleOCR: %s", exc)
    return paddle_engine.recognize(crop)


class OcrPipeline:
    """High-level OCR pipeline (module-level singleton ``ocr_pipeline``)."""

    def __init__(
        self,
        detector: QuestionLayoutDetector = QuestionLayoutDetector(),
        max_slice_height: int = 2000,
    ) -> None:
        self.detector = detector
        self.max_slice_height = int(config.pipeline.max_slice_height or max_slice_height)

    # ------------------------------------------------------------------
    # public
    # ------------------------------------------------------------------

    def recognize(self, image_bytes: bytes) -> Dict[str, Any]:
        """Full OCR on encoded image bytes.

        Returns ``{"ocr_text": str, "latex_text": str, "blocks": list,
        "confidence": float}``. Blocks are ``{"text", "confidence", "bbox"}``
        with absolute pixel coordinates.
        """
        pil_image = self._load(image_bytes)

        # OCR path: full preprocessing (binarized) for text recognition.
        ocr_image = preprocess(pil_image)
        regions = self.detector.detect(ocr_image)

        blocks: List[Dict[str, Any]] = []
        if regions:
            for x1, y1, x2, y2 in regions:
                crop = ocr_image[y1:y2, x1:x2]
                blocks.extend(self._recognize_region(crop, x_offset=x1, y_offset=y1))
        else:
            # No separable regions (single question page): recognise the whole image.
            logger.info("no question regions found; recognising the full page")
            blocks = self._recognize_region(ocr_image, 0, 0)

        blocks = dedup_blocks(blocks)
        ocr_text = self._merge_text(blocks)
        confidence = self._average_confidence(blocks)

        # texify path: run on a *non-binarized* preprocessed copy (binarization
        # destroys the stroke structure texify needs) when the engine is up.
        latex_text = ""
        if texify_engine.ensure_engine():
            try:
                soft_image = preprocess(pil_image, PreprocessConfig(binarize=False))
                latex_text = texify_engine.recognize_formula(soft_image)
            except Exception as exc:  # texify must never break the pipeline
                logger.warning("texify step failed (%s); latex_text left empty", exc)
                latex_text = ""

        if not blocks and not latex_text:
            logger.warning("OCR pipeline returned empty results for the given image")

        return {
            "ocr_text": ocr_text,
            "latex_text": latex_text,
            "blocks": blocks,
            "confidence": round(confidence, 4),
        }

    # ------------------------------------------------------------------
    # internals
    # ------------------------------------------------------------------

    @staticmethod
    def _load(image_bytes: bytes) -> Image.Image:
        """Decode + EXIF-orient encoded bytes into a PIL image."""
        if isinstance(image_bytes, str):
            image_bytes = image_bytes.encode("latin-1")  # pragma: no cover - safety
        try:
            pil = Image.open(io.BytesIO(image_bytes))
            pil.load()
        except Exception as exc:
            raise ValueError(f"无法解析图片数据: {exc}") from exc
        return ImageOps.exif_transpose(pil) or pil

    def _recognize_region(
        self,
        crop: np.ndarray,
        x_offset: int = 0,
        y_offset: int = 0,
    ) -> List[Dict[str, Any]]:
        """Recognise one region crop; long crops are sliced with overlap and
        every block's bbox is translated back to image-absolute coordinates."""
        blocks: List[Dict[str, Any]] = []
        if crop.shape[0] > self.max_slice_height:
            logger.debug("slicing region of height %d into chunks", crop.shape[0])
            for chunk, offset_y in slice_long_image(crop, self.max_slice_height):
                for b in _recognize_text(chunk):
                    b = dict(b)
                    bx = b["bbox"]
                    b["bbox"] = [
                        bx[0] + x_offset, bx[1] + y_offset + offset_y,
                        bx[2] + x_offset, bx[3] + y_offset + offset_y,
                    ]
                    blocks.append(b)
        else:
            for b in _recognize_text(crop):
                b = dict(b)
                bx = b["bbox"]
                b["bbox"] = [
                    bx[0] + x_offset, bx[1] + y_offset,
                    bx[2] + x_offset, bx[3] + y_offset,
                ]
                blocks.append(b)
        return blocks

    @staticmethod
    def _merge_text(blocks: List[Dict[str, Any]]) -> str:
        """Assemble ``ocr_text``: top-to-bottom ordering by y (reading order).

        Blocks are grouped into text lines by vertical proximity; within a line
        they are ordered left-to-right and joined with a space only when a
        horizontal gap suggests separate words (CJK stays unbroken). Lines are
        separated by newlines.
        """
        if not blocks:
            return ""
        heights = [b["bbox"][3] - b["bbox"][1] for b in blocks]
        med_h = float(np.median(heights)) if heights else 16.0
        line_tol = max(2.0, 0.6 * med_h)

        ordered = sorted(
            blocks,
            key=lambda b: ((b["bbox"][1] + b["bbox"][3]) / 2.0,
                           (b["bbox"][0] + b["bbox"][2]) / 2.0),
        )
        lines: List[List[Dict[str, Any]]] = []
        current: List[Dict[str, Any]] = []
        prev_yc: float = -1e9
        for b in ordered:
            yc = (b["bbox"][1] + b["bbox"][3]) / 2.0
            if current and (yc - prev_yc) > line_tol:
                lines.append(current)
                current = []
            current.append(b)
            prev_yc = yc
        if current:
            lines.append(current)

        out_lines: List[str] = []
        for line in lines:
            parts: List[str] = []
            prev_x2: float = -1e9
            for b in line:  # already x-ordered within the line
                text = str(b.get("text", "")).strip()
                if not text:
                    continue
                if parts and (b["bbox"][0] - prev_x2) > 0.25 * med_h:
                    parts.append(" ")
                parts.append(text)
                prev_x2 = b["bbox"][2]
            out_lines.append("".join(parts))
        return "\n".join(out_lines)

    @staticmethod
    def _average_confidence(blocks: List[Dict[str, Any]]) -> float:
        """Mean block confidence (0.0 when there are no blocks)."""
        if not blocks:
            return 0.0
        return float(np.mean([float(b.get("confidence", 0.0) or 0.0) for b in blocks]))


# Module-level singleton exported by app.ocr.
ocr_pipeline = OcrPipeline()
