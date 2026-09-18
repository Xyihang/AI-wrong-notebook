"""Long-image slicing and OCR-block de-duplication.

Slicing
-------
Very tall images (long phone screenshots, tall exam pages) exceed the input
size the recognizer handles best. :func:`slice_long_image` splits them into
overlapping vertical chunks; overlapping the cuts guarantees text lines that
straddle a boundary are seen whole in at least one chunk.

De-duplication
--------------
Overlapping chunks (and PaddleOCR's own unclip expansion) make the same text
line appear in two blocks. :func:`dedup_blocks` merges blocks whose bounding
boxes overlap significantly — either because they are the same line detected
twice (identical/near-identical text) or because two adjacent lines touch.
Merging unions the bbox, orders the texts in reading order and averages the
confidence, so downstream text assembly stays clean.
"""
from __future__ import annotations

import logging
from typing import Dict, List, Sequence, Tuple

import numpy as np

logger = logging.getLogger(__name__)

# canonical block shape used across the package
Block = Dict[str, object]  # {"text": str, "confidence": float, "bbox": [x1,y1,x2,y2]}


# ---------------------------------------------------------------------------
# slicing
# ---------------------------------------------------------------------------


def slice_long_image(
    image: np.ndarray,
    max_height: int,
    overlap_ratio: float = 0.15,
    min_overlap: int = 64,
) -> List[Tuple[np.ndarray, int]]:
    """Split a tall image into chunks no taller than ``max_height``.

    Returns ``[(chunk, y_offset), ...]`` where ``y_offset`` is the chunk's top
    edge in the original image, so callers can translate detected boxes back
    into absolute coordinates. Chunks overlap by ``overlap`` pixels
    (``max(overlap_ratio * max_height, min_overlap)``, capped below
    ``max_height``). Images already short enough are returned as one chunk.
    """
    h = image.shape[0]
    if h <= max_height:
        return [(image, 0)]

    overlap = max(min_overlap, int(max_height * overlap_ratio))
    overlap = min(overlap, max_height - 1)  # keep step >= 1
    step = max_height - overlap
    if step < 1:
        step = 1

    slices: List[Tuple[np.ndarray, int]] = []
    y = 0
    while y < h:
        y2 = min(y + max_height, h)
        slices.append((image[y:y2], y))
        if y2 >= h:
            break
        y += step
    return slices


# ---------------------------------------------------------------------------
# de-duplication
# ---------------------------------------------------------------------------


def _bbox_of(block: Block) -> List[int]:
    bbox = block.get("bbox") or [0, 0, 0, 0]
    return [int(v) for v in bbox[:4]]


def _area(box: Sequence[int]) -> int:
    x1, y1, x2, y2 = box
    return max(0, x2 - x1) * max(0, y2 - y1)


def _intersection(a: Sequence[int], b: Sequence[int]) -> Tuple[int, int, int, int]:
    return (
        max(a[0], b[0]), max(a[1], b[1]),
        min(a[2], b[2]), min(a[3], b[3]),
    )


def _overlaps(a: Sequence[int], b: Sequence[int], *, iou_threshold: float = 0.25,
              area_ratio_threshold: float = 0.6) -> bool:
    """True when two boxes overlap enough to be merged.

    Matches if the IoU exceeds ``iou_threshold`` OR the intersection covers
    more than ``area_ratio_threshold`` of the *smaller* box (catches a small
    box fully nested inside a bigger one — the typical duplicate-line case).
    """
    ix1, iy1, ix2, iy2 = _intersection(a, b)
    inter = max(0, ix2 - ix1) * max(0, iy2 - iy1)
    if inter <= 0:
        return False
    area_a, area_b = _area(a), _area(b)
    if area_a <= 0 or area_b <= 0:
        return False
    iou = inter / float(area_a + area_b - inter)
    smaller = min(area_a, area_b)
    return iou > iou_threshold or (inter / float(smaller)) > area_ratio_threshold


def _join_cluster_texts(items: Sequence[Block]) -> str:
    """Join the texts of a merged cluster in reading order (top-to-bottom,
    left-to-right), inserting a space only when a horizontal gap suggests
    separate words (keeps CJK text unbroken)."""
    if not items:
        return ""
    heights = [(_bbox_of(b)[3] - _bbox_of(b)[1]) for b in items]
    med_h = float(np.median(heights)) if heights else 16.0

    ordered = sorted(
        items,
        key=lambda b: ((_bbox_of(b)[1] + _bbox_of(b)[3]) / 2.0,
                       (_bbox_of(b)[0] + _bbox_of(b)[2]) / 2.0),
    )
    parts: List[str] = []
    prev_x2: float = -1e9
    prev_yc: float = -1e9
    for b in ordered:
        x1, y1, x2, y2 = _bbox_of(b)
        text = str(b.get("text", "")).strip()
        if not text:
            continue
        yc = (y1 + y2) / 2.0
        if parts:
            # new line?
            if abs(yc - prev_yc) > 0.6 * med_h:
                parts.append("\n")
            elif (x1 - prev_x2) > 0.25 * med_h:  # word gap on the same line
                parts.append(" ")
        parts.append(text)
        prev_x2 = x2
        prev_yc = yc
    return "".join(parts)


def dedup_blocks(
    blocks: Sequence[Block],
    *,
    iou_threshold: float = 0.25,
    area_ratio_threshold: float = 0.6,
) -> List[Block]:
    """Merge OCR text blocks whose bounding boxes overlap.

    Greedy union-find style merge, stable for the moderate block counts the
    pipeline produces. Blocks with empty text are dropped. Each cluster keeps
    its member blocks so texts can be joined in true reading order at the end.
    The output keeps the canonical ``{"text", "confidence", "bbox"}`` shape.
    """
    live = [dict(b) for b in blocks if str(b.get("text", "")).strip()]
    if not live:
        return []
    # sort by top edge so overlaps are discovered near each other
    live.sort(key=lambda b: (_bbox_of(b)[1], _bbox_of(b)[0]))

    # clusters: list of member lists; cluster bbox = union of members
    clusters: List[List[Block]] = []
    cluster_boxes: List[List[int]] = []
    for block in live:
        box = _bbox_of(block)
        target: int = -1
        for idx, cbox in enumerate(cluster_boxes):
            if _overlaps(box, cbox, iou_threshold=iou_threshold,
                         area_ratio_threshold=area_ratio_threshold):
                target = idx
                break
        if target >= 0:
            clusters[target].append(block)
            cluster_boxes[target] = _union_box(cluster_boxes[target], box)
        else:
            clusters.append([block])
            cluster_boxes.append(list(box))

    # merge clusters that started overlapping after growth
    changed = True
    while changed:
        changed = False
        for i in range(len(clusters)):
            for j in range(i + 1, len(clusters)):
                if _overlaps(cluster_boxes[i], cluster_boxes[j],
                             iou_threshold=iou_threshold,
                             area_ratio_threshold=area_ratio_threshold):
                    clusters[i].extend(clusters[j])
                    cluster_boxes[i] = _union_box(cluster_boxes[i], cluster_boxes[j])
                    del clusters[j]
                    del cluster_boxes[j]
                    changed = True
                    break
            if changed:
                break

    result: List[Block] = []
    for members, box in zip(clusters, cluster_boxes):
        result.append(_finalize_cluster(members, box))
    result.sort(key=lambda b: (_bbox_of(b)[1], _bbox_of(b)[0]))
    return result


def _union_box(a: Sequence[int], b: Sequence[int]) -> List[int]:
    return [
        min(a[0], b[0]), min(a[1], b[1]),
        max(a[2], b[2]), max(a[3], b[3]),
    ]


def _finalize_cluster(members: Sequence[Block], box: Sequence[int]) -> Block:
    """Collapse a cluster: union bbox, reading-order text, area-weighted confidence.

    Members with identical text (the same line detected twice across
    overlapping slices) are collapsed to the highest-confidence copy so the
    text is not doubled.
    """
    collapsed: List[Block] = []
    best_by_text: Dict[str, Block] = {}
    for m in members:
        text = str(m.get("text", "")).strip()
        if not text:
            continue
        prev = best_by_text.get(text)
        if prev is None or float(m.get("confidence", 0.0) or 0.0) > float(prev.get("confidence", 0.0) or 0.0):
            best_by_text[text] = m
    collapsed = list(best_by_text.values())
    if not collapsed:
        collapsed = [m for m in members if str(m.get("text", "")).strip()]

    total_area = sum(max(1, _area(_bbox_of(m))) for m in collapsed)
    weighted = sum(float(m.get("confidence", 0.0) or 0.0) * max(1, _area(_bbox_of(m)))
                   for m in collapsed) / total_area
    return {
        "text": _join_cluster_texts(collapsed),
        "confidence": weighted,
        "bbox": [int(v) for v in box],
    }
