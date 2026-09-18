"""Image preprocessing utilities for the OCR pipeline.

Adapted from the engineering experience documented in the convosage-tools
bubble_ocr README: noise removal, adaptive binarization, skew correction,
border trimming and size handling before a text recognizer sees the image.

Input accepted: ``numpy.ndarray`` (cv2 BGR or grayscale), ``PIL.Image`` or
``bytes`` (encoded image file content). Internal convention is the OpenCV
one — BGR ``uint8`` arrays.

Public API
----------
``preprocess(image, ...) -> np.ndarray`` — full chain:

    to_array -> grayscale -> denoise -> adaptive binarize
    -> skew correct -> polarity normalize -> trim borders -> resize

Every step can be switched off individually and tuned through ``PreprocessConfig``.
"""
from __future__ import annotations

import io
import logging
from dataclasses import dataclass
from typing import Union

import cv2
import numpy as np
from PIL import Image, ImageOps

logger = logging.getLogger(__name__)

ImageLike = Union[np.ndarray, Image.Image, bytes]


@dataclass
class PreprocessConfig:
    """Tunable knobs for :func:`preprocess` (code-level; pass a custom instance)."""

    denoise: bool = True
    denoise_method: str = "bilateral"  # "bilateral" | "median"
    denoise_d: int = 5                 # bilateral diameter
    denoise_sigma_color: float = 50.0
    denoise_sigma_space: float = 50.0
    denoise_ksize: int = 5             # median kernel size

    binarize: bool = True
    adaptive_block_size: int = 31      # must be odd
    adaptive_c: float = 15.0

    correct_skew: bool = True
    skew_method: str = "minarea"       # "minarea" | "hough"
    skew_min_angle: float = 0.5        # degrees; smaller angles are ignored

    normalize_polarity: bool = True    # ensure dark text on light background

    trim_borders: bool = True
    trim_margin: int = 8               # px margin kept around the content

    resize: bool = True
    max_dim: int = 4096                # downscale cap (PP det input limit)
    upscale_small: bool = False        # upscale tiny images (text too small)
    min_side: int = 320                # used only when upscale_small


DEFAULT_CONFIG = PreprocessConfig()


# ---------------------------------------------------------------------------
# input conversion
# ---------------------------------------------------------------------------


def to_array(image: ImageLike) -> np.ndarray:
    """Normalise any accepted input to a BGR ``uint8`` numpy array."""
    if isinstance(image, np.ndarray):
        arr = image
        if arr.dtype != np.uint8:
            arr = np.clip(arr, 0, 255).astype(np.uint8)
        if arr.ndim == 3 and arr.shape[2] == 4:  # drop alpha (RGBA -> BGR)
            arr = cv2.cvtColor(arr, cv2.COLOR_RGBA2BGR)
        return arr
    if isinstance(image, bytes):
        return _pil_to_bgr(Image.open(io.BytesIO(image)))
    if isinstance(image, Image.Image):
        return _pil_to_bgr(image)
    raise TypeError(f"unsupported image type: {type(image)!r}")


def _pil_to_bgr(pil_image: Image.Image) -> np.ndarray:
    # Respect EXIF orientation (phone photos) before conversion.
    img = ImageOps.exif_transpose(pil_image) or pil_image
    if img.mode not in ("RGB", "L"):
        img = img.convert("RGB")
    rgb = np.asarray(img)
    return cv2.cvtColor(rgb, cv2.COLOR_RGB2BGR) if rgb.ndim == 3 else rgb


# ---------------------------------------------------------------------------
# individual steps
# ---------------------------------------------------------------------------


def grayscale(image: np.ndarray) -> np.ndarray:
    """Convert to single-channel 8-bit gray."""
    if image.ndim == 2:
        return image
    return cv2.cvtColor(image, cv2.COLOR_BGR2GRAY)


def denoise(image: np.ndarray, cfg: PreprocessConfig = DEFAULT_CONFIG) -> np.ndarray:
    """Remove sensor / scan noise while preserving text edges."""
    if cfg.denoise_method == "median":
        k = int(cfg.denoise_ksize)
        if k % 2 == 0:
            k += 1
        return cv2.medianBlur(image, k)
    # bilateral filter keeps edges sharp (good for text)
    return cv2.bilateralFilter(
        image,
        d=int(cfg.denoise_d),
        sigmaColor=cfg.denoise_sigma_color,
        sigmaSpace=cfg.denoise_sigma_space,
    )


def adaptive_binarize(image: np.ndarray, cfg: PreprocessConfig = DEFAULT_CONFIG) -> np.ndarray:
    """Adaptive (Gaussian) binarization — robust to uneven illumination."""
    if image.ndim != 2:
        image = grayscale(image)
    block = int(cfg.adaptive_block_size)
    if block % 2 == 0:
        block += 1
    block = max(3, block)
    return cv2.adaptiveThreshold(
        image,
        255,
        cv2.ADAPTIVE_THRESH_GAUSSIAN_C,
        cv2.THRESH_BINARY,
        block,
        cfg.adaptive_c,
    )


def _find_contours(binary: np.ndarray, min_area: int = 8):
    """Contours on an inverted binary image (text pixels = 255)."""
    inv = cv2.bitwise_not(binary)
    contours, _ = cv2.findContours(inv, cv2.RETR_LIST, cv2.CHAIN_APPROX_SIMPLE)
    return [c for c in contours if cv2.contourArea(c) >= min_area]


def _rotate(image: np.ndarray, angle_deg: float, border_value: int = 255) -> np.ndarray:
    h, w = image.shape[:2]
    center = (w / 2.0, h / 2.0)
    matrix = cv2.getRotationMatrix2D(center, angle_deg, 1.0)
    return cv2.warpAffine(
        image, matrix, (w, h), flags=cv2.INTER_CUBIC, borderMode=cv2.BORDER_CONSTANT,
        borderValue=border_value,
    )


def _skew_angle_minarea(binary: np.ndarray) -> float:
    """Estimate skew from the dominant text component orientation (minAreaRect)."""
    contours = _find_contours(binary, min_area=max(8, binary.shape[0] // 400))
    if not contours:
        return 0.0
    pts = np.vstack([c.reshape(-1, 2) for c in contours])
    if len(pts) < 4:
        return 0.0
    try:
        rect = cv2.minAreaRect(pts)
    except cv2.error:  # pragma: no cover - degenerate geometry
        return 0.0
    angle = rect[2]
    # Normalise: minAreaRect returns angle in [-90, 0]; convert to [-45, 45].
    if angle > 45:
        angle -= 90
    elif angle < -45:
        angle += 90
    return float(angle)


def _skew_angle_hough(binary: np.ndarray) -> float:
    """Estimate skew from the median angle of long Hough lines."""
    edges = cv2.Canny(binary, 50, 150, apertureSize=3)
    lines = cv2.HoughLinesP(
        edges, 1, np.pi / 180.0, threshold=80,
        minLineLength=max(40, binary.shape[1] // 8), maxLineGap=20,
    )
    if lines is None or len(lines) == 0:
        return 0.0
    angles = []
    for line in lines[:, 0]:
        x1, y1, x2, y2 = line
        dx, dy = x2 - x1, y2 - y1
        if abs(dx) < 1e-6:
            continue
        angle = float(np.degrees(np.arctan2(dy, dx)))
        if angle > 45:
            angle -= 90
        elif angle < -45:
            angle += 90
        angles.append(angle)
    if not angles:
        return 0.0
    return float(np.median(angles))


def correct_skew(image: np.ndarray, cfg: PreprocessConfig = DEFAULT_CONFIG) -> np.ndarray:
    """Rotate the image so text lines are horizontal.

    ``minarea`` (default): global text-orientation via minAreaRect of all text
    contours — robust for dense text. ``hough``: median angle of long lines.

    Sign convention (verified empirically): minAreaRect/Hough report the angle
    the text is *already tilted by*; applying ``getRotationMatrix2D`` with that
    same angle cancels the tilt, so the rotation argument is ``+angle``.
    """
    if image.ndim != 2:
        image = grayscale(image)
    angle = (
        _skew_angle_hough(image) if cfg.skew_method == "hough"
        else _skew_angle_minarea(image)
    )
    if abs(angle) < cfg.skew_min_angle:
        return image
    logger.debug("skew correction: rotating by %.2f deg", angle)
    return _rotate(image, angle)


def normalize_polarity(image: np.ndarray, cfg: PreprocessConfig = DEFAULT_CONFIG) -> np.ndarray:
    """Ensure dark text on a light background (the common OCR assumption).

    A mostly-dark image (e.g. dark-mode screenshot, negative scan) is inverted.
    """
    if not cfg.normalize_polarity:
        return image
    gray = grayscale(image)
    dark_fraction = float(np.mean(gray < 127))
    if dark_fraction > 0.5:
        return cv2.bitwise_not(image)
    return image


def trim_borders(image: np.ndarray, cfg: PreprocessConfig = DEFAULT_CONFIG) -> np.ndarray:
    """Crop uniform border rows/columns around the actual content.

    Works on any image; foreground is decided via an Otsu threshold when the
    input is not already binary.
    """
    if image.ndim == 2:
        gray = image
    else:
        gray = grayscale(image)
    if len(np.unique(gray)) > 2:
        _, gray = cv2.threshold(gray, 0, 255, cv2.THRESH_BINARY + cv2.THRESH_OTSU)
    # Foreground = dark pixels (dark text on light background after polarity normalize).
    dark = gray < 127
    if not dark.any():
        return image
    ys, xs = np.where(dark)
    y1, y2 = int(ys.min()), int(ys.max())
    x1, x2 = int(xs.min()), int(xs.max())
    m = int(cfg.trim_margin)
    y1, y2 = max(0, y1 - m), min(image.shape[0], y2 + m + 1)
    x1, x2 = max(0, x1 - m), min(image.shape[1], x2 + m + 1)
    return image[y1:y2, x1:x2]


def resize_image(image: np.ndarray, cfg: PreprocessConfig = DEFAULT_CONFIG) -> np.ndarray:
    """Resize handling: downscale oversized images, optionally upscale tiny ones."""
    if not cfg.resize:
        return image
    h, w = image.shape[:2]
    scale = 1.0
    if max(h, w) > cfg.max_dim:
        scale = cfg.max_dim / float(max(h, w))
    elif cfg.upscale_small and min(h, w) < cfg.min_side:
        scale = cfg.min_side / float(min(h, w))
    if abs(scale - 1.0) < 1e-6:
        return image
    new_w, new_h = int(round(w * scale)), int(round(h * scale))
    interp = cv2.INTER_AREA if scale < 1.0 else cv2.INTER_CUBIC
    return cv2.resize(image, (new_w, new_h), interpolation=interp)


# ---------------------------------------------------------------------------
# full chain
# ---------------------------------------------------------------------------


def preprocess(image: ImageLike, cfg: PreprocessConfig = DEFAULT_CONFIG) -> np.ndarray:
    """Full preprocessing chain -> BGR/gray ``uint8`` array ready for OCR.

    Steps (each gated by ``cfg``):

        1. normalise input to a BGR array      (``to_array``)
        2. grayscale                            (``grayscale``)
        3. denoise                              (``denoise``)
        4. adaptive binarization                (``adaptive_binarize``)
        5. skew correction                      (``correct_skew``)
        6. polarity normalization (dark->light) (``normalize_polarity``)
        7. border trimming                      (``trim_borders``)
        8. resize handling                      (``resize_image``)
    """
    arr = to_array(image)
    out = grayscale(arr)
    if cfg.denoise:
        out = denoise(out, cfg)
    if cfg.binarize:
        out = adaptive_binarize(out, cfg)
    if cfg.correct_skew:
        out = correct_skew(out, cfg)
    out = normalize_polarity(out, cfg)
    if cfg.trim_borders:
        out = trim_borders(out, cfg)
    if cfg.resize:
        out = resize_image(out, cfg)
    return out
