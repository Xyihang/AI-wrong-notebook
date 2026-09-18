"""Question-area detection via layout analysis + heuristics.

The convosage project used a fine-tuned YOLO bubble detector because chat
screenshots contain lots of non-text distractors. Exam photos are simpler:
questions are separated by whitespace, so we segment the page with classic
projection profiles:

1. binarize and compute the **horizontal ink projection** (dark pixels / row);
2. contiguous inked rows form candidate bands, separated by whitespace gaps;
3. small gaps inside a question (e.g. between the stem and its options) are
   merged, and thin bands are dropped;
4. within each band, the **vertical ink projection** splits multi-column
   layouts (common on exam answer sheets);
5. bands are expanded by a margin and returned as ``[x1, y1, x2, y2]``.

A clearly marked extension point ``yolo_detector`` (None by default) lets a
fine-tuned YOLOv8 model replace/augment the heuristics later — see the
``# TODO YOLOv8 fine-tune hook`` block below. Nothing here calls a YOLO model;
when ``yolo_detector`` is None the pure-layout path runs.
"""
from __future__ import annotations

import logging
from dataclasses import dataclass
from typing import Callable, List, Optional

import cv2
import numpy as np

from .preprocess import grayscale

logger = logging.getLogger(__name__)

# A YOLO detector returns boxes as [x1, y1, x2, y2] (ints), optionally with conf.
YoloDetector = Callable[[np.ndarray], List[List[int]]]


# ---------------------------------------------------------------------------
# YOLO extension point
# ---------------------------------------------------------------------------

# TODO YOLOv8 fine-tune hook
# --------------------------
# ``yolo_detector`` is the plug point for a fine-tuned question-area detector
# (the same idea as convosage's bubble YOLO, but for exam questions). It is
# deliberately None in v1: the spec (section 10, Won't Have) defers the
# pre-trained question-detection model to a later phase, so the layout
# heuristics below are the default path.
#
# Interface contract:
#     yolo_detector(image: np.ndarray) -> List[List[int]]
#         * image : BGR/gray uint8 array (already preprocessed by the caller)
#         * return: list of [x1, y1, x2, y2] boxes (absolute coordinates)
#
# Example wiring with ultralytics once a model is available:
#
#     from ultralytics import YOLO
#     _model = YOLO("weights/question_det_yolov8n.pt")
#
#     def _yolo_detect(image: np.ndarray) -> List[List[int]]:
#         results = _model.predict(image, verbose=False, conf=0.35)[0]
#         boxes = []
#         for b in results.boxes:
#             x1, y1, x2, y2 = map(int, b.xyxy[0].tolist())
#             boxes.append([x1, y1, x2, y2])
#         return boxes
#
#     from app.ocr import layout
#     layout.yolo_detector = _yolo_detect
#
# When set, ``QuestionLayoutDetector.detect`` tries the model first and falls
# back to the heuristic segmentation if it returns nothing or raises.
yolo_detector: Optional[YoloDetector] = None


# ---------------------------------------------------------------------------
# detector
# ---------------------------------------------------------------------------


@dataclass
class LayoutConfig:
    """Heuristic thresholds (fractions of image height/width unless noted)."""

    #: Minimum whitespace gap (as a fraction of image height) that separates
    #: two question bands.
    min_gap_ratio: float = 0.012
    #: Gaps smaller than this (fraction of height) inside a question are merged.
    merge_gap_ratio: float = 0.006
    #: Minimum band height in pixels to be considered a question area.
    min_band_height: int = 24
    #: Minimum number of inked rows inside a band.
    min_ink_rows: int = 3
    #: Margin added around each detected region (fraction of image dims).
    margin_ratio: float = 0.008
    #: A vertical gap wider than this (fraction of width), sitting in the
    #: middle third of a band, splits the band into two columns.
    column_gap_ratio: float = 0.06


DEFAULT_CONFIG = LayoutConfig()


def _binarize_ink(image: np.ndarray) -> np.ndarray:
    """Return a binary map with ink pixels = 1, background = 0."""
    gray = grayscale(image)
    _, binary = cv2.threshold(gray, 0, 255, cv2.THRESH_BINARY_INV + cv2.THRESH_OTSU)
    return (binary > 0).astype(np.uint8)


class QuestionLayoutDetector:
    """Segments a (preprocessed) page image into question areas.

    Usage::

        detector = QuestionLayoutDetector()
        regions = detector.detect(image)   # list of [x1, y1, x2, y2]
    """

    def __init__(
        self,
        cfg: LayoutConfig = DEFAULT_CONFIG,
        yolo_detector: Optional[YoloDetector] = None,
    ) -> None:
        self.cfg = cfg
        #: Extension point — see the module-level ``yolo_detector`` docs.
        self.yolo_detector = yolo_detector

    # -- public ----------------------------------------------------------

    def detect(self, image: np.ndarray) -> List[List[int]]:
        """Detect question regions -> list of ``[x1, y1, x2, y2]`` (absolute).

        Uses ``self.yolo_detector`` if set, else the module-level
        ``layout.yolo_detector`` plug (read lazily so runtime assignment works),
        else the layout heuristics.
        """
        yolo = self.yolo_detector or yolo_detector  # module-level plug
        if yolo is not None:
            regions = self._detect_with_yolo(image, yolo)
            if regions:
                return regions
            logger.warning("yolo_detector returned no regions; falling back to layout heuristics")
        return self._detect_heuristic(image)

    # -- yolo path -------------------------------------------------------

    def _detect_with_yolo(self, image: np.ndarray, yolo: YoloDetector) -> List[List[int]]:
        """Run the plugged YOLO detector; sanitise its output."""
        try:
            raw = yolo(image)
        except Exception as exc:  # never let a broken model break the pipeline
            logger.warning("yolo_detector failed (%s); falling back to heuristics", exc)
            return []
        boxes: List[List[int]] = []
        h, w = image.shape[:2]
        for b in raw or []:
            try:
                x1, y1, x2, y2 = (int(v) for v in b[:4])
            except (TypeError, ValueError):
                continue
            x1, y1 = max(0, x1), max(0, y1)
            x2, y2 = min(w, x2), min(h, y2)
            if x2 > x1 and y2 > y1:
                boxes.append([x1, y1, x2, y2])
        return boxes

    # -- heuristic path --------------------------------------------------

    def _detect_heuristic(self, image: np.ndarray) -> List[List[int]]:
        """Whitespace / projection-profile based question segmentation."""
        h, w = image.shape[:2]
        if h < 10 or w < 10:
            return []
        ink = _binarize_ink(image)
        row_ink = ink.sum(axis=1)  # dark pixels per row

        bands = self._segment_rows(row_ink, h)
        regions: List[List[int]] = []
        for y1, y2 in bands:
            col_ink = ink[y1:y2].sum(axis=0)
            for x1, x2 in self._segment_columns(col_ink, w):
                regions.append([x1, y1, x2, y2])

        regions = self._apply_margin(regions, h, w)
        return self._dedupe(regions)

    def _segment_rows(self, row_ink: np.ndarray, height: int) -> List[List[int]]:
        """Split inked rows into bands (question areas) separated by whitespace.

        Two-stage, font-size agnostic:

        1. every contiguous ink run is a candidate band (a text line);
        2. adjacent bands whose separating gap is smaller than ~1.5 median line
           heights are merged — such gaps are interior whitespace (between the
           stem and its options), while larger gaps separate questions.
        """
        h = row_ink.shape[0]
        inked = row_ink > 0
        min_gap = max(2, int(self.cfg.min_gap_ratio * height))
        merge_gap = max(1, int(self.cfg.merge_gap_ratio * height))

        # 1. contiguous ink runs = candidate bands
        runs: List[List[int]] = []
        i = 0
        while i < h:
            if inked[i]:
                j = i
                while j < h and inked[j]:
                    j += 1
                runs.append([i, j])
                i = j
            else:
                i += 1
        if not runs:
            return []

        # reference line height = median run height
        line_h = float(np.median([r[1] - r[0] for r in runs]))
        interior_gap = max(min_gap, merge_gap, 1.5 * line_h)

        # 2. merge adjacent runs separated by interior whitespace
        merged: List[List[int]] = [list(runs[0])]
        for y1, y2 in runs[1:]:
            gap = y1 - merged[-1][1]
            if gap <= interior_gap:
                merged[-1][1] = y2
            else:
                merged.append([y1, y2])

        return [b for b in merged if self._band_qualifies(row_ink, b[0], b[1], height)]

    def _band_qualifies(self, row_ink: np.ndarray, y1: int, y2: int, height: int) -> bool:
        if y2 - y1 < self.cfg.min_band_height:
            return False
        ink_rows = int((row_ink[y1:y2] > 0).sum())
        return ink_rows >= self.cfg.min_ink_rows

    def _segment_columns(self, col_ink: np.ndarray, width: int) -> List[List[int]]:
        """Within a band, find the inked x-extent(s), splitting two-column layouts."""
        w = col_ink.shape[0]
        inked = col_ink > 0
        if not inked.any():
            return []

        # column gap detection: a wide empty vertical stripe in the middle third
        mid_start, mid_end = w // 3, 2 * w // 3
        col_gap = max(4, int(self.cfg.column_gap_ratio * width))
        gap_x: Optional[int] = None
        i = mid_start
        while i < mid_end:
            if not inked[i]:
                j = i
                while j < mid_end and not inked[j]:
                    j += 1
                if j - i >= col_gap:
                    gap_x = (i + j) // 2
                    break
                i = j
            else:
                i += 1

        if gap_x is None:
            xs = np.where(inked)[0]
            return [[int(xs.min()), int(xs.max()) + 1]]
        # two columns: clamp extents to the gap
        left = np.where(inked[:gap_x])[0]
        right = np.where(inked[gap_x + 1:])[0]
        boxes: List[List[int]] = []
        if left.size:
            boxes.append([int(left.min()), int(left.max()) + 1])
        if right.size:
            boxes.append([int(right.min()) + gap_x + 1, int(right.max()) + gap_x + 2])
        return boxes or [[0, w]]

    def _apply_margin(self, regions: List[List[int]], h: int, w: int) -> List[List[int]]:
        m_x = max(1, int(self.cfg.margin_ratio * w))
        m_y = max(1, int(self.cfg.margin_ratio * h))
        out: List[List[int]] = []
        for x1, y1, x2, y2 in regions:
            out.append([
                max(0, x1 - m_x), max(0, y1 - m_y),
                min(w, x2 + m_x), min(h, y2 + m_y),
            ])
        return out

    @staticmethod
    def _dedupe(regions: List[List[int]]) -> List[List[int]]:
        """Drop near-identical boxes (same band, same column split)."""
        seen = set()
        out: List[List[int]] = []
        for x1, y1, x2, y2 in regions:
            key = (x1, y1, x2, y2)
            if key in seen:
                continue
            seen.add(key)
            out.append([x1, y1, x2, y2])
        return out


# ---------------------------------------------------------------------------
# module-level convenience
# ---------------------------------------------------------------------------

_default_detector = QuestionLayoutDetector()


def detect_question_regions(image: np.ndarray) -> List[List[int]]:
    """Detect question areas on a preprocessed page image.

    Uses the module-level ``yolo_detector`` if one has been plugged in, else
    the layout heuristics. Returns ``[x1, y1, x2, y2]`` boxes (absolute px).
    """
    return _default_detector.detect(image)
