"""Formula recognition to LaTeX via texify (optional heavy dependency).

texify (VikParuchuri) turns an image crop containing a math formula into its
LaTeX source. It pulls in torch + transformers, so it is *not* imported at
module top level: like ``paddle_engine``, this module lazily builds a module-
level singleton guarded by try/except. When texify (or torch) is missing,
``config.TEXIFY_AVAILABLE`` flips to False, a warning is logged and
:func:`recognize_formula` returns ``""`` — the pipeline then falls back to
pure OCR text (spec.md section 9: "texify 为可选项，缺省回退纯 PaddleOCR + 文本").
"""
from __future__ import annotations

import logging
from typing import Any, Optional

import numpy as np
from PIL import Image

from . import config

logger = logging.getLogger(__name__)

# ---------------------------------------------------------------------------
# lazy singleton
# ---------------------------------------------------------------------------

_model: Optional[Any] = None   # either a Texify instance or (fn, model, processor)
_model_ready: bool = False     # True once the init attempt has finished
_init_error: Optional[str] = None


def ensure_engine() -> bool:
    """Idempotently build the texify singleton. Never raises.

    Supports both the modern class API (``from texify import Texify``) and the
    legacy function API (``texify.inference.batch_inference``).
    """
    global _model, _model_ready, _init_error
    if _model_ready:
        return _model is not None
    _model_ready = True

    if not config.TEXIFY_AVAILABLE:
        _init_error = "disabled by config (OCR_TEXIFY_AVAILABLE=0)"
        logger.warning("texify disabled by config; latex_text will be empty")
        return False

    # modern API: class-based, weights loaded lazily inside Texify()
    try:
        from texify import Texify  # heavy: torch + transformers

        _model = Texify(batch_size=config.texify.batch_size)
        config.TEXIFY_AVAILABLE = True
        logger.info("texify engine initialised (class API)")
        return True
    except Exception as exc:
        logger.debug("texify class API unavailable (%s); trying legacy API", exc)

    # legacy API: batch_inference + explicit model/processor
    try:
        from texify.inference import batch_inference
        from texify.model.model import get_model
        from texify.model.processor import get_processor

        _model = (batch_inference, get_model(), get_processor())
        config.TEXIFY_AVAILABLE = True
        logger.info("texify engine initialised (legacy API)")
        return True
    except Exception as exc:
        config.TEXIFY_AVAILABLE = False
        _init_error = f"texify import failed: {exc}"
        logger.warning("texify unavailable (%s); latex_text will be empty", _init_error)
        return False


def is_available() -> bool:
    """True if texify is (or can become) available; triggers init."""
    return ensure_engine()


# ---------------------------------------------------------------------------
# recognition
# ---------------------------------------------------------------------------


def _to_pil_rgb(image: Any) -> Image.Image:
    """Normalise a BGR numpy array (cv2 convention) or PIL image to RGB PIL."""
    if isinstance(image, Image.Image):
        return image.convert("RGB")
    arr = np.asarray(image)
    if arr.ndim == 3 and arr.shape[2] == 3:
        # assume BGR (cv2 convention used across this package)
        arr = arr[:, :, ::-1]
    return Image.fromarray(arr).convert("RGB")


def recognize_formula(image: Any) -> str:
    """Recognise a formula image crop and return its LaTeX source ('' on failure)."""
    if not ensure_engine():
        logger.warning("recognize_formula() called while texify is unavailable -> ''")
        return ""
    try:
        pil = _to_pil_rgb(image)
        if isinstance(_model, tuple):  # legacy API
            batch_inference, model, processor = _model
            results = batch_inference([pil], model, processor)
        else:  # class API
            results = _model([pil])  # type: ignore[union-attr]
        if results:
            latex = str(results[0]).strip()
            return latex
    except Exception as exc:
        logger.warning("texify inference failed: %s", exc)
    return ""
