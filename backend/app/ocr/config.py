"""OCR engine configuration.

Tuning mirrors the production-proven settings of the convosage-tools bubble_ocr
project (``config.yaml`` + ``bubble_ocr_fullimg_ocr.py``):

    PaddleOCR PP-OCRv5, lang ["ch","en"],
    use_textline_orientation True,
    text_det_thresh 0.2,          # lower det threshold -> more candidate regions
    text_det_box_thresh 0.2,      # lower box confidence threshold (default 0.5)
    text_det_unclip_ratio 2.5,    # expand det boxes (default 2.0) -> catch edge text
    text_recognition_batch_size 6

Every value can be overridden through environment variables (loaded from
``os.environ`` at import time, so ``.env`` values already exported by the app
startup — e.g. ``python-dotenv`` — take effect; otherwise the convosage
defaults are used).

Availability flags
------------------
``PADDLE_AVAILABLE`` / ``TEXIFY_AVAILABLE`` express *intended* availability and
are initialised from the environment (optimistic by default). The engine
modules (``paddle_engine`` / ``texify_engine``) flip them to the *real* value
after their one-time lazy init attempt, so ``import app.ocr`` never crashes
even when paddleocr / texify / torch are not installed. Consumers that need a
definitive answer should call ``ensure_engine()`` on the engine module first.
"""
from __future__ import annotations

import os
from dataclasses import dataclass, field
from typing import List

# ---------------------------------------------------------------------------
# env helpers
# ---------------------------------------------------------------------------


def _env_bool(name: str, default: bool) -> bool:
    raw = os.getenv(name)
    if raw is None:
        return default
    return raw.strip().lower() in {"1", "true", "yes", "on"}


def _env_int(name: str, default: int) -> int:
    raw = os.getenv(name)
    if raw is None:
        return default
    try:
        return int(raw.strip())
    except (TypeError, ValueError):
        return default


def _env_float(name: str, default: float) -> float:
    raw = os.getenv(name)
    if raw is None:
        return default
    try:
        return float(raw.strip())
    except (TypeError, ValueError):
        return default


def _env_list(name: str, default: List[str]) -> List[str]:
    raw = os.getenv(name)
    if raw is None:
        return list(default)
    items = [part.strip() for part in raw.split(",") if part.strip()]
    return items or list(default)


# ---------------------------------------------------------------------------
# PaddleOCR (PP-OCRv5) engine settings
# ---------------------------------------------------------------------------


@dataclass(frozen=True)
class PaddleSettings:
    """PaddleOCR construction parameters (mirrors convosage config.yaml)."""

    #: PP-OCR major version used for tuning notes / model selection.
    version: int = _env_int("OCR_PADDLE_VERSION", 5)
    #: Recognition languages.
    lang: List[str] = field(default_factory=lambda: _env_list("OCR_LANG", ["ch", "en"]))
    #: Enable the text-line orientation classifier (rotated text support).
    use_textline_orientation: bool = _env_bool("OCR_USE_TEXTLINE_ORIENTATION", True)
    #: Detection threshold — lower keeps more candidate text regions.
    text_det_thresh: float = _env_float("OCR_DET_THRESH", 0.2)
    #: Box confidence threshold — lower keeps weaker boxes.
    text_det_box_thresh: float = _env_float("OCR_DET_BOX_THRESH", 0.2)
    #: Unclip ratio — expands detected boxes to avoid clipping edge characters.
    text_det_unclip_ratio: float = _env_float("OCR_DET_UNCLIP_RATIO", 2.5)
    #: Recognition batch size.
    text_recognition_batch_size: int = _env_int("OCR_REC_BATCH_SIZE", 6)

    def as_kwargs(self) -> dict:
        """Keyword arguments for ``PaddleOCR(...)`` (PP-OCRv5 / paddleocr>=2.7)."""
        return {
            "use_textline_orientation": self.use_textline_orientation,
            "lang": list(self.lang),
            "text_det_thresh": self.text_det_thresh,
            "text_det_box_thresh": self.text_det_box_thresh,
            "text_det_unclip_ratio": self.text_det_unclip_ratio,
            "text_recognition_batch_size": self.text_recognition_batch_size,
        }


# ---------------------------------------------------------------------------
# Pipeline / preprocessing settings
# ---------------------------------------------------------------------------


@dataclass(frozen=True)
class PipelineSettings:
    """Behavioural knobs for the OCR pipeline orchestration."""

    #: Long-image slicing: a region taller than this (px) is split into
    #: overlapping chunks before recognition (see slice_dedup.slice_long_image).
    max_slice_height: int = _env_int("OCR_MAX_SLICE_HEIGHT", 2000)
    #: Downscale cap applied by preprocessing (PP-OCR det works best <= 4096).
    max_image_dim: int = _env_int("OCR_MAX_IMAGE_DIM", 4096)


# ---------------------------------------------------------------------------
# texify (formula -> LaTeX)
# ---------------------------------------------------------------------------


@dataclass(frozen=True)
class TexifySettings:
    """texify engine settings (optional heavy dependency)."""

    #: Batch size for texify inference (one formula image at a time here).
    batch_size: int = _env_int("OCR_TEXIFY_BATCH_SIZE", 1)


# ---------------------------------------------------------------------------
# Runtime availability flags
# ---------------------------------------------------------------------------

#: True when PaddleOCR is (intended to be / actually) available.
#: Initial value is an env hint (default: optimistic). ``paddle_engine``
#: corrects it to the real value after its one-time lazy init attempt.
PADDLE_AVAILABLE: bool = _env_bool("OCR_PADDLE_AVAILABLE", True)

#: True when texify is (intended to be / actually) available.
#: Corrected by ``texify_engine`` after its one-time lazy init attempt.
TEXIFY_AVAILABLE: bool = _env_bool("OCR_TEXIFY_AVAILABLE", True)

# ---------------------------------------------------------------------------
# module-level singletons
# ---------------------------------------------------------------------------

paddle = PaddleSettings()
pipeline = PipelineSettings()
texify = TexifySettings()


def reset_availability() -> None:
    """Re-read the env hints (mainly for tests)."""
    global PADDLE_AVAILABLE, TEXIFY_AVAILABLE
    PADDLE_AVAILABLE = _env_bool("OCR_PADDLE_AVAILABLE", True)
    TEXIFY_AVAILABLE = _env_bool("OCR_TEXIFY_AVAILABLE", True)
