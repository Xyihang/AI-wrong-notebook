"""PaddleOCR (PP-OCRv5) engine wrapper.

Adapted from ``convosage-tools-bubble_ocr/.../bubble_ocr_fullimg_ocr.py``:

- lazy module-level singleton — the heavy ``paddleocr`` import and model
  download only happen on the first ``recognize`` / ``ensure_engine`` call;
- graceful unavailability — if paddleocr is not installed or the model fails
  to build, ``config.PADDLE_AVAILABLE`` flips to False, a warning is logged
  and ``recognize`` returns an empty list (the pipeline degrades to
  structure-only output);
- robust multi-version result parsing (``_parse_ocr_results``), covering the
  formats documented in the bubble_ocr README:

    * PP-OCRv5 / paddleocr 3.x: dict with ``boxes`` / ``texts`` / ``scores``
    * paddleocr 2.6-2.9: list[dict] or dict with ``rec_texts`` / ``rec_scores``
      / ``rec_polys`` (and ``det_boxes`` variants)
    * paddleocr <= 2.5: legacy nested list ``[[poly, (text, score)], ...]``
      (possibly wrapped in a per-page list)

Fallback note
-------------
A pytesseract-free, pure-cv2 contour fallback (``contour_text_regions``) can
locate text *regions* without any deep-learning dependency, but it cannot read
text. When PaddleOCR is missing, ``recognize`` therefore returns ``[]`` with a
log warning rather than fabricating garbage — the caller decides how to react
(e.g. report "未识别到文字").
"""
from __future__ import annotations

import logging
from typing import Any, Dict, List, Optional, Sequence

import cv2
import numpy as np

from . import config

logger = logging.getLogger(__name__)

# ---------------------------------------------------------------------------
# lazy singleton
# ---------------------------------------------------------------------------

_engine: Optional[Any] = None      # the PaddleOCR instance (any version)
_engine_ready: bool = False        # True once the init attempt has finished
_init_error: Optional[str] = None  # last init failure, for diagnostics


def ensure_engine() -> bool:
    """Idempotently initialise the PaddleOCR singleton.

    Returns True when recognition is possible. Never raises: any failure is
    logged and recorded in ``config.PADDLE_AVAILABLE`` / ``_init_error``.
    """
    global _engine, _engine_ready, _init_error
    if _engine_ready:
        return _engine is not None
    _engine_ready = True

    if not config.PADDLE_AVAILABLE:
        _init_error = "disabled by config (OCR_PADDLE_AVAILABLE=0)"
        logger.warning("PaddleOCR disabled by config; OCR will return empty results")
        return False

    try:
        from paddleocr import PaddleOCR  # heavy import, kept out of module top
    except Exception as exc:  # ImportError / broken install
        config.PADDLE_AVAILABLE = False
        _init_error = f"paddleocr import failed: {exc}"
        logger.warning("PaddleOCR unavailable (%s); OCR will return empty results", _init_error)
        return False

    try:
        _engine = PaddleOCR(**config.paddle.as_kwargs())
        config.PADDLE_AVAILABLE = True
        logger.info("PaddleOCR engine initialised (PP-OCRv%d, lang=%s)",
                    config.paddle.version, list(config.paddle.lang))
        return True
    except TypeError as exc:
        # Parameter names differ across PaddleOCR versions (README warns about
        # this). Retry with the minimal cross-version parameter set.
        logger.warning("PaddleOCR init failed with full params (%s); retrying with minimal params", exc)
        try:
            _engine = PaddleOCR(
                use_textline_orientation=config.paddle.use_textline_orientation,
                lang=list(config.paddle.lang),
            )
            config.PADDLE_AVAILABLE = True
            logger.info("PaddleOCR engine initialised (minimal params, lang=%s)",
                        list(config.paddle.lang))
            return True
        except Exception as retry_exc:
            config.PADDLE_AVAILABLE = False
            _init_error = f"PaddleOCR init failed: {retry_exc}"
            logger.warning("PaddleOCR initialisation failed: %s", retry_exc)
            return False
    except Exception as exc:
        config.PADDLE_AVAILABLE = False
        _init_error = f"PaddleOCR init failed: {exc}"
        logger.warning("PaddleOCR initialisation failed: %s", exc)
        return False


def is_available() -> bool:
    """True if PaddleOCR is (or can become) available; triggers init."""
    return ensure_engine()


# ---------------------------------------------------------------------------
# recognition
# ---------------------------------------------------------------------------


def recognize(image: np.ndarray) -> List[Dict[str, Any]]:
    """Recognise text in a BGR/grayscale numpy image.

    Returns blocks ``[{"text": str, "confidence": float, "bbox": [x1,y1,x2,y2]}]``
    or ``[]`` when PaddleOCR is unavailable / recognition fails.
    """
    if not ensure_engine():
        logger.warning("recognize() called while PaddleOCR is unavailable -> []")
        return []

    # PaddleOCR 3.x uses predict(); older versions use ocr(). Try both.
    results: Any = None
    try:
        results = _engine.predict(image)  # type: ignore[union-attr]
    except Exception:
        try:
            results = _engine.ocr(image)  # type: ignore[union-attr]  # legacy
        except Exception as exc:
            logger.error("PaddleOCR recognition failed: %s", exc)
            return []
    return _parse_ocr_results(results)


# ---------------------------------------------------------------------------
# multi-version result parsing (adapted from bubble_ocr_fullimg_ocr.py)
# ---------------------------------------------------------------------------


def _to_bbox(box: Any) -> Optional[List[int]]:
    """Convert a polygon/rect of any shape to ``[x1, y1, x2, y2]``."""
    try:
        pts = np.asarray(box, dtype=np.float32)
    except (TypeError, ValueError):
        return None
    if pts.ndim == 1:
        if pts.size == 4:  # already [x1, y1, x2, y2]
            x1, y1, x2, y2 = pts
            return [int(round(x1)), int(round(y1)), int(round(x2)), int(round(y2))]
        if pts.size == 8:  # flattened quad
            pts = pts.reshape(4, 2)
        else:
            return None
    if pts.ndim == 2 and pts.shape[1] == 2:
        xs, ys = pts[:, 0], pts[:, 1]
        return [int(round(float(xs.min()))), int(round(float(ys.min()))),
                int(round(float(xs.max()))), int(round(float(ys.max())))]
    if pts.ndim == 2 and pts.shape[1] == 4:  # batch of rects — take first row
        x1, y1, x2, y2 = pts[0]
        return [int(round(x1)), int(round(y1)), int(round(x2)), int(round(y2))]
    return None


def _append_block(texts: Sequence[Any], scores: Sequence[Any], polys: Sequence[Any],
                  out: List[Dict[str, Any]]) -> None:
    """Zip aligned texts/scores/polys into canonical blocks (see reference)."""
    for text, score, poly in zip(texts, scores, polys):
        text = str(text).strip()
        if not text:
            continue
        try:
            confidence = float(score)
        except (TypeError, ValueError):
            confidence = 0.0
        bbox = _to_bbox(poly)
        if bbox is None:
            continue
        out.append({"text": text, "confidence": confidence, "bbox": bbox})


def _parse_ocr_results(ocr_results: Any) -> List[Dict[str, Any]]:
    """Parse any PaddleOCR result shape into canonical blocks."""
    blocks: List[Dict[str, Any]] = []
    if not ocr_results:
        return blocks

    # --- dict format (PP-OCRv5 / 3.x): {"boxes": [...], "texts": [...], "scores": [...]}
    if isinstance(ocr_results, dict):
        boxes = ocr_results.get("boxes")
        texts = ocr_results.get("texts")
        scores = ocr_results.get("scores")
        if boxes is not None and texts is not None and scores is not None:
            _append_block(texts, scores, boxes, blocks)
            if blocks:
                return blocks
        # --- dict format (2.6-2.9): rec_texts / rec_scores / rec_polys
        rec_texts = ocr_results.get("rec_texts")
        rec_scores = ocr_results.get("rec_scores")
        rec_polys = ocr_results.get("rec_polys") or ocr_results.get("det_boxes")
        if rec_texts is not None and rec_scores is not None and rec_polys is not None:
            _append_block(rec_texts, rec_scores, rec_polys, blocks)
            if blocks:
                return blocks
        # --- nested result key (e.g. {"result": [...]}) -> recurse
        if "result" in ocr_results:
            return _parse_ocr_results(ocr_results["result"])
        return blocks

    # --- list of page-dicts (predict() on 2.6-2.9 / 3.x single image)
    if isinstance(ocr_results, list) and ocr_results and isinstance(ocr_results[0], dict):
        for page in ocr_results:
            blocks.extend(_parse_ocr_results(page))
        return blocks

    # --- legacy nested list: [[poly, (text, score)], ...]
    # PaddleOCR <=2.5 predict() returns a page-wrapped list of pages:
    #     [ [ [poly1, ("文本", 0.99)], [poly2, ...] ], ... ]
    # while some callers hand us the flat item list directly. Both shapes are
    # accepted: a page is a list whose first element is itself a legacy item.
    if isinstance(ocr_results, list):
        items: Any = ocr_results
        if (ocr_results and isinstance(ocr_results[0], list) and ocr_results[0]
                and _is_legacy_item(ocr_results[0][0])):
            items = ocr_results[0]  # unwrap the page level
        for item in items:
            if not _is_legacy_item(item):
                continue
            poly, rec = item[0], item[1]
            text = str(rec[0]).strip()
            if not text:
                continue
            try:
                confidence = float(rec[1])
            except (TypeError, ValueError):
                confidence = 0.0
            bbox = _to_bbox(poly)
            if bbox is None:
                continue
            blocks.append({"text": text, "confidence": confidence, "bbox": bbox})
    return blocks


def _is_legacy_item(x: Any) -> bool:
    """True when ``x`` is a legacy OCR item ``[poly, (text, score)]``.

    The second element must be a 2-sequence whose first element is a *string*
    (the recognised text); a polygon's second point (also a 2-sequence of
    numbers) therefore does not match.
    """
    return (
        isinstance(x, (list, tuple)) and len(x) >= 2
        and isinstance(x[1], (list, tuple)) and len(x[1]) >= 2
        and isinstance(x[1][0], str)
    )


# ---------------------------------------------------------------------------
# pytesseract-free cv2 fallback (region detection only — cannot read text)
# ---------------------------------------------------------------------------


def contour_text_regions(image: np.ndarray,
                         min_area: int = 40,
                         min_height: int = 8) -> List[List[int]]:
    """Pure-cv2 contour-based text *region* detection.

    NOTE: this fallback locates likely-text boxes but cannot transcribe them
    without a recognizer (no pytesseract anywhere in this codebase). It exists
    so a caller can at least know *where* text sits when PaddleOCR is absent;
    :func:`recognize` intentionally returns ``[]`` in that case instead of
    emitting empty-text blocks.
    """
    from .preprocess import adaptive_binarize, grayscale

    gray = grayscale(image)
    binary = adaptive_binarize(gray)
    inv = cv2.bitwise_not(binary)
    contours, _ = cv2.findContours(inv, cv2.RETR_EXTERNAL, cv2.CHAIN_APPROX_SIMPLE)
    regions: List[List[int]] = []
    for c in contours:
        x, y, w, h = cv2.boundingRect(c)
        if w * h < min_area or h < min_height:
            continue
        regions.append([x, y, x + w, y + h])
    return regions
