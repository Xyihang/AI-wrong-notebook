"""
日志配置。

- setup_logging() 幂等：重复调用只重置 handler，不会叠加重复输出。
- 统一输出到 stdout，格式含时间 / 级别 / 模块 / 行号。
- get_logger(name) 便捷获取子 logger。

用法：
    from app.core.logging import get_logger
    logger = get_logger(__name__)
    logger.info("hello")
"""
from __future__ import annotations

import logging
import sys

from app.core.config import settings

_LOGGING_CONFIGURED = False

_FORMAT = "%(asctime)s | %(levelname)-7s | %(name)s:%(lineno)d | %(message)s"
_DATE_FORMAT = "%Y-%m-%d %H:%M:%S"


def setup_logging(level: str | None = None, force: bool = False) -> logging.Logger:
    """
    配置根 logger 与 uvicorn 相关 logger。

    :param level: 日志级别字符串（DEBUG/INFO/WARNING/ERROR），默认取 settings.LOG_LEVEL
    :param force: 即使已配置也重新应用（便于测试）
    """
    global _LOGGING_CONFIGURED
    if _LOGGING_CONFIGURED and not force:
        return logging.getLogger()

    level = (level or settings.LOG_LEVEL or "INFO").upper()
    handler = logging.StreamHandler(sys.stdout)
    handler.setFormatter(logging.Formatter(_FORMAT, datefmt=_DATE_FORMAT))

    root = logging.getLogger()
    root.setLevel(getattr(logging, level, logging.INFO))
    root.handlers[:] = [handler]

    # uvicorn 的 logger 独立管理，避免重复打印
    for name in ("uvicorn", "uvicorn.error", "uvicorn.access"):
        lg = logging.getLogger(name)
        lg.handlers[:] = [handler]
        lg.propagate = False
        lg.setLevel(getattr(logging, level, logging.INFO))

    logging.getLogger("sqlalchemy.engine").setLevel(
        logging.DEBUG if settings.DEBUG else logging.WARNING
    )

    _LOGGING_CONFIGURED = True
    return root


def get_logger(name: str) -> logging.Logger:
    """获取命名 logger（父 logger 已由 setup_logging 配置）。"""
    return logging.getLogger(name)


# 模块导入即完成一次配置，保证任何模块 import 后即可使用日志
setup_logging()
