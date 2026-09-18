"""OCR pipeline package (Agent-B).

Reuses the engineering pattern of the convosage-tools bubble_ocr project
(PaddleOCR two-stage architecture: region detection -> region crop -> per-block
recognition) generalised into a universal exam-photo pipeline:

    preprocess -> layout(question regions) -> slice/dedup -> PaddleOCR -> texify

Public entry point (spec.md section 7.1 / plan.md Agent-B):

    from app.ocr import ocr_pipeline
    result = ocr_pipeline.recognize(image_bytes)
    # -> {"ocr_text": str, "latex_text": str, "blocks": list, "confidence": float}

Import safety: ``import app.ocr`` never imports paddleocr / texify / torch at
module top level. Those heavy engines are lazily initialised inside
``paddle_engine`` / ``texify_engine`` and gracefully report unavailability,
so the whole package imports and runs even when only numpy / cv2 / Pillow are
installed.
"""
from . import config as ocr_config  # availability flags + engine settings
from .pipeline import OcrPipeline, ocr_pipeline

__all__ = ["ocr_pipeline", "ocr_config", "OcrPipeline"]
__version__ = "0.1.0"
