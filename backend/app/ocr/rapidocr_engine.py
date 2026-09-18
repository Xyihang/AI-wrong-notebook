"""
RapidOCR 引擎（基于 onnxruntime，轻量、中文效果好）。

替代重量级 PaddlePaddle：用 RapidOCR（PP-OCR 模型的 ONNX 版）做端侧/后端
文字识别，适合内存有限的服务器（如 CVM 1.9G）与低配环境。

- 依赖：pip install rapidocr_onnxruntime（自动内置中文模型，首次使用下载）
- 特性：中文印刷体/手写效果好、依赖轻、无需 PaddlePaddle、跨平台
- 优雅降级：rapidocr 未安装 / 加载失败时 available=False，调用方回退视觉大模型
"""
from __future__ import annotations

import logging
from typing import Any, Dict, List, Optional

logger = logging.getLogger(__name__)

_engine: Optional[Any] = None
_engine_ready: bool = False
_init_error: Optional[str] = None

#: 运行期真实可用性（懒加载后由 ensure_engine 校正）
AVAILABLE: bool = True


def _load_engine() -> Any:
    """延迟导入并初始化 RapidOCR 单例。"""
    try:
        from rapidocr_onnxruntime import RapidOCR  # 延迟导入
    except Exception as exc:  # noqa: BLE001
        raise RuntimeError(f"rapidocr_onnxruntime 导入失败: {exc}") from exc
    # RapidOCR() 首次会加载内置中文检测 + 识别模型（自动下载，之后缓存到本地）
    return RapidOCR()


def ensure_engine() -> bool:
    """幂等初始化 RapidOCR。失败时置 AVAILABLE=False 并记录原因。"""
    global _engine, _engine_ready, _init_error, AVAILABLE
    if _engine_ready:
        return _engine is not None
    _engine_ready = True
    try:
        _engine = _load_engine()
        AVAILABLE = True
        logger.info("RapidOCR 引擎就绪（onnxruntime，中文模型）")
        return True
    except Exception as exc:  # noqa: BLE001
        AVAILABLE = False
        _init_error = str(exc)
        logger.warning("RapidOCR 初始化失败（%s）; OCR 将回退视觉大模型", _init_error)
        return False


def is_available() -> bool:
    """触发懒加载并返回 RapidOCR 是否可用。"""
    return ensure_engine()


def recognize(image: Any) -> List[Dict[str, Any]]:
    """
    识别一张图（numpy 数组 / PIL / 路径）。

    :return: blocks = [{"text", "confidence", "bbox": [x1,y1,x2,y2]}, ...]
    """
    if not ensure_engine():
        return []
    try:
        # RapidOCR 输入：numpy 数组（BGR/RGB 均可）或图片路径或 bytes
        result = _engine(image)
        return _parse_result(result)
    except Exception as exc:  # noqa: BLE001 - 识别失败返回空，不阻断主流程
        logger.warning("RapidOCR 识别失败: %s", exc)
        return []


def _parse_result(result: Any) -> List[Dict[str, Any]]:
    """
    解析 RapidOCR 返回。

    不同版本返回格式：
    - 新版（1.4.x）：engine(img) 返回 `(result, elapse)`，result 为条目列表，
      每条为 `[box, text, score]`（box 为 4 点四边形 [[x,y],...]）。
    - 旧版：返回 `(boxes, texts, scores)` 3 元组。
    本函数同时兼容两种格式。
    """
    if not result:
        return []

    # 新版：result 是 (result, elapse) 2 元组，取 result[0]
    if isinstance(result, (list, tuple)) and len(result) == 2:
        items = result[0]
        # items 形如 [[box, text, score], ...]
        if isinstance(items, (list, tuple)) and items and isinstance(
            items[0], (list, tuple)
        ):
            blocks: List[Dict[str, Any]] = []
            for entry in items:
                if not isinstance(entry, (list, tuple)) or len(entry) < 3:
                    continue
                box, text, score = entry[0], entry[1], entry[2]
                block = _box_text_score_to_block(box, text, score)
                if block:
                    blocks.append(block)
            return blocks
        # 兜底：直接递归解析 items
        return _parse_result(items)

    # 旧版：(boxes, texts, scores) 3 元组
    if isinstance(result, (list, tuple)) and len(result) >= 3:
        boxes, texts, scores = result[0], result[1], result[2]
        blocks = []
        if boxes is None or texts is None:
            return []
        for box, text, score in zip(boxes, texts, scores):
            block = _box_text_score_to_block(box, text, score)
            if block:
                blocks.append(block)
        return blocks

    return []


def _box_text_score_to_block(box: Any, text: Any, score: Any) -> Optional[Dict[str, Any]]:
    """把一个条目 (box, text, score) 转成统一 block。"""
    try:
        # box: 4 点 [[x,y],...] 或扁平 list，取外接矩形
        pts = list(box)
        xs = []
        ys = []
        for p in pts:
            if isinstance(p, (list, tuple)) and len(p) >= 2:
                xs.append(float(p[0]))
                ys.append(float(p[1]))
            elif isinstance(p, (int, float)):
                # 扁平坐标，按 x,y,x,y 交替推断（此处仅防御）
                pass
        if not xs or not ys:
            return None
        text_str = str(text).strip()
        if not text_str:
            return None
        return {
            "text": text_str,
            "confidence": float(score),
            "bbox": [int(min(xs)), int(min(ys)), int(max(xs)), int(max(ys))],
        }
    except Exception as exc:  # noqa: BLE001
        logger.debug("跳过异常文本块: %s", exc)
        return None
