"""
登录失败限流（core.login_rate_limiter）。

防暴力破解：同一「用户名」或「IP」连续密码错误达阈值后，锁定一段时间。
- 阈值：连续失败 MAX_FAILURES 次（默认 5）
- 锁定：LOCK_SECONDS 秒（默认 600 = 10 分钟）
- 存储：进程内内存字典（与 vision_rate_limiter 同一风格）。
  单进程 uvicorn 下有效；若将来改多 worker 需换共享存储（如 Redis）。

key 维度：
- user:{username}  : 防止针对单个账号的密码枚举
- ip:{ip}          : 防止单 IP 批量撞库
任一维度达阈值即整体锁定。
"""
from __future__ import annotations

import threading
import time
from typing import Dict, Tuple

MAX_FAILURES = 5
LOCK_SECONDS = 600  # 10 分钟

_lock = threading.Lock()
# key -> {"count": int, "locked_until": float}
_records: Dict[str, Dict[str, object]] = {}


def _prune() -> None:
    """清理已过期的记录，避免内存无限增长。"""
    now = time.time()
    expired = [k for k, v in _records.items() if (v.get("locked_until") or 0) < now and not v.get("count")]
    for k in expired:
        _records.pop(k, None)


def check_login_allowed(username: str, client_ip: str) -> Tuple[bool, int]:
    """
    检查登录是否允许。

    :return: (allowed, retry_after_seconds)。allowed=False 时 retry_after 为
             还需等待的秒数；allowed=True 时 retry_after=0。
    """
    now = time.time()
    with _lock:
        for key in (f"user:{username}", f"ip:{client_ip}"):
            rec = _records.get(key)
            if rec and (rec.get("locked_until") or 0) > now:
                return False, int(rec["locked_until"] - now)
    return True, 0


def record_login_failure(username: str, client_ip: str) -> None:
    """记录一次失败。连续失败达阈值时触发锁定。"""
    now = time.time()
    with _lock:
        _prune()
        for key in (f"user:{username}", f"ip:{client_ip}"):
            rec = _records.setdefault(key, {"count": 0, "locked_until": 0.0})
            rec["count"] = int(rec.get("count") or 0) + 1
            rec["locked_until"] = 0.0
            if rec["count"] >= MAX_FAILURES:
                rec["locked_until"] = now + LOCK_SECONDS
                rec["count"] = 0


def reset_login_failures(username: str, client_ip: str) -> None:
    """登录成功后清除失败记录。"""
    with _lock:
        for key in (f"user:{username}", f"ip:{client_ip}"):
            _records.pop(key, None)
