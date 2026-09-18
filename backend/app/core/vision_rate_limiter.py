"""
视觉兜底限流器（按账户 + 双档位独立池 + SQLite 持久化）。

后端用「自带 Key」做视觉大模型读图兜底时，按用户是否配置了 DeepSeek Key
采用不同限流档位，防止白嫖后端视觉识别资源：

- **有 Key 用户且启用视觉模式**（has_vision_key=true, use_vision_mode=true）：
  每天最多 VISION_DAILY_LIMIT 次（默认 50）。
- **有 Key 用户但未启用视觉模式**（has_vision_key=true, use_vision_mode=false）：
  每天最多 VISION_KEY_NO_MODE_LIMIT 次（默认 20）——提醒用户开启视觉模式可省额度。
- **无 Key 用户**（has_vision_key=false）：累计（非每日）最多 NO_KEY_LIMIT 次（默认 10）。

计数维度（P0-3：按账户算）：
- **登录用户**：按 user_id 计（f"user:{user_id}"），换设备 / 换 IP 不丢额度；
- **匿名 / 旧客户端**：按 IP 计（f"ip:{ip}"），兼容历史行为。

三个档位池子完全独立：切换档位（改 Key / 改视觉模式）不重置任何一方的计数（P0-2）。

持久化：计数写入 SQLite（data/vision_quota.db，可用 VISION_QUOTA_DB 覆盖），
后端重启不清零。写入失败仅告警，不影响识别主流程。
"""
from __future__ import annotations

import os
import sqlite3
import threading
from datetime import date
from pathlib import Path
from typing import Dict, Tuple

from app.core.logging import get_logger

try:  # pragma: no cover - 取决于运行环境
    from app.core.config import settings as _app_settings

    _HAS_APP_SETTINGS = True
except Exception:  # noqa: BLE001
    _HAS_APP_SETTINGS = False

logger = get_logger(__name__)

# 有 Key 用户且启用视觉模式：每天最多视觉兜底次数
VISION_DAILY_LIMIT = int(os.getenv("VISION_DAILY_LIMIT", "50"))
# 有 Key 用户但未启用视觉模式：每天最多视觉兜底次数（略低于全量）
VISION_KEY_NO_MODE_LIMIT = int(os.getenv("VISION_KEY_NO_MODE_LIMIT", "20"))
# 无 Key 用户：累计最大视觉兜底次数（总共，非每天）
NO_KEY_LIMIT = int(os.getenv("NO_KEY_LIMIT", "10"))

_POOL_DAILY = "daily"
_POOL_DAILY_NOMODE = "daily_nomode"
_POOL_TOTAL = "total"

_lock = threading.Lock()
# 有 Key + 视觉模式：{counter_key: (date_iso, count)}
_daily_counter: Dict[str, Tuple[str, int]] = {}
# 有 Key + 未启用视觉模式：{counter_key: (date_iso, count)}
_daily_nomode_counter: Dict[str, Tuple[str, int]] = {}
# 无 Key 用户：{counter_key: count}（累计，不按天）
_total_counter: Dict[str, int] = {}
_loaded = False


def _db_path() -> str:
    """持久化数据库路径：默认 backend/data/vision_quota.db，可用 VISION_QUOTA_DB 覆盖。"""
    env = os.getenv("VISION_QUOTA_DB", "").strip()
    if env:
        return env
    if _HAS_APP_SETTINGS:
        try:
            base = Path(_app_settings.UPLOAD_DIR).parent  # backend/data
            return str(base / "vision_quota.db")
        except Exception:  # noqa: BLE001
            pass
    return "./data/vision_quota.db"


def _get_conn() -> sqlite3.Connection:
    conn = sqlite3.connect(_db_path(), timeout=5)
    conn.execute(
        "CREATE TABLE IF NOT EXISTS vision_quota ("
        " counter_key TEXT NOT NULL,"
        " pool TEXT NOT NULL,"
        " date_iso TEXT NOT NULL DEFAULT '',"
        " count INTEGER NOT NULL DEFAULT 0,"
        " PRIMARY KEY (counter_key, pool))"
    )
    return conn


def _load_from_db() -> None:
    """启动后首次访问时，把 SQLite 中的计数加载进内存（惰性，仅一次）。"""
    global _loaded
    with _lock:
        if _loaded:
            return
        _loaded = True
    try:
        conn = _get_conn()
        try:
            rows = conn.execute("SELECT counter_key, pool, date_iso, count FROM vision_quota").fetchall()
            with _lock:
                for key, pool, date_iso, count in rows:
                    if pool == _POOL_DAILY:
                        _daily_counter[key] = (date_iso, int(count))
                    elif pool == _POOL_DAILY_NOMODE:
                        _daily_nomode_counter[key] = (date_iso, int(count))
                    elif pool == _POOL_TOTAL:
                        _total_counter[key] = int(count)
        finally:
            conn.close()
        logger.info("视觉额度计数已从 %s 加载（daily=%d nomode=%d total=%d）",
                    _db_path(), len(_daily_counter), len(_daily_nomode_counter), len(_total_counter))
    except Exception as exc:  # noqa: BLE001 - 加载失败则从空计数开始
        logger.warning("视觉额度计数加载失败（以空计数继续）: %s", exc)


def _save(key: str, pool: str, date_iso: str, count: int) -> None:
    """把单条计数写回 SQLite（INSERT OR REPLACE）。写失败仅告警。"""
    try:
        conn = _get_conn()
        try:
            conn.execute(
                "INSERT OR REPLACE INTO vision_quota (counter_key, pool, date_iso, count)"
                " VALUES (?, ?, ?, ?)",
                (key, pool, date_iso, int(count)),
            )
            conn.commit()
        finally:
            conn.close()
    except Exception as exc:  # noqa: BLE001 - 持久化失败不影响识别
        logger.warning("视觉额度计数持久化失败(%s/%s): %s", key, pool, exc)


def get_client_ip(request) -> str:
    """从 FastAPI Request 提取客户端 IP（优先 X-Forwarded-For）。"""
    try:
        forwarded = request.headers.get("x-forwarded-for", "")
        if forwarded:
            return forwarded.split(",")[0].strip()
    except Exception:  # noqa: BLE001
        pass
    try:
        if request.client is not None:
            return request.client.host or "unknown"
    except Exception:  # noqa: BLE001
        pass
    return "unknown"


def _counter_key(client_ip: str, user_id: int) -> str:
    """
    计数键：登录用户按 user_id（跨设备/跨 IP 共享）；
    匿名/未登录按 IP（兼容旧客户端）。
    """
    uid = int(user_id or 0)
    if uid > 0:
        return f"user:{uid}"
    return f"ip:{client_ip or 'unknown'}"


def try_consume_vision_slot(
    client_ip: str,
    has_vision_key: bool,
    user_id: int = 0,
    use_vision_mode: bool = False,
) -> bool:
    """
    尝试消耗一个视觉兜底名额。

    :param client_ip: 客户端 IP（匿名时作为计数键）
    :param has_vision_key: 该用户是否已配置 DeepSeek Key（选择档位）
    :param user_id: 登录用户 id（>0 时按账户计，覆盖 IP 维度）
    :param use_vision_mode: 是否启用视觉模式（配了 Key 但未启用时降为每天 20）
    :return: True 允许（已计数）；False 超限拒绝。
    """
    _load_from_db()
    key = _counter_key(client_ip, user_id)
    if not has_vision_key:
        return _try_consume_total(key)
    if use_vision_mode:
        return _try_consume_daily(key, VISION_DAILY_LIMIT, _POOL_DAILY, _daily_counter)
    return _try_consume_daily(key, VISION_KEY_NO_MODE_LIMIT, _POOL_DAILY_NOMODE, _daily_nomode_counter)


def _try_consume_daily(
    key: str,
    limit: int,
    pool: str,
    counter: Dict[str, Tuple[str, int]],
) -> bool:
    """每日限额（limit 由档位决定）。"""
    today = date.today().isoformat()
    with _lock:
        rec = counter.get(key)
        if rec is None or rec[0] != today:
            counter[key] = (today, 1)
            _save(key, pool, today, 1)
            return True
        _date, count = rec
        if count >= limit:
            logger.info(
                "%s 今日视觉兜底已达上限 %d 次，拒绝后续兜底",
                key, limit,
            )
            return False
        new_count = count + 1
        counter[key] = (today, new_count)
        _save(key, pool, today, new_count)
        return True


def _try_consume_total(key: str) -> bool:
    """无 Key 用户：累计限 NO_KEY_LIMIT 次（计数持久化）。"""
    with _lock:
        count = _total_counter.get(key, 0)
        if count >= NO_KEY_LIMIT:
            logger.info(
                "%s 无 Key 用户视觉兜底已达累计上限 %d 次，拒绝后续兜底",
                key, NO_KEY_LIMIT,
            )
            return False
        new_count = count + 1
        _total_counter[key] = new_count
        _save(key, _POOL_TOTAL, "", new_count)
        return True


def remaining_vision_slots(
    client_ip: str,
    has_vision_key: bool,
    user_id: int = 0,
    use_vision_mode: bool = False,
) -> int:
    """返回该用户剩余视觉兜底次数（按账户 / 匿名按 IP）。"""
    _load_from_db()
    key = _counter_key(client_ip, user_id)
    if not has_vision_key:
        with _lock:
            count = _total_counter.get(key, 0)
            return max(0, NO_KEY_LIMIT - count)
    limit = VISION_DAILY_LIMIT if use_vision_mode else VISION_KEY_NO_MODE_LIMIT
    counter = _daily_counter if use_vision_mode else _daily_nomode_counter
    today = date.today().isoformat()
    with _lock:
        rec = counter.get(key)
        if rec is None or rec[0] != today:
            return limit
        return max(0, limit - rec[1])


def reset_counter() -> None:
    """清空计数（测试用）：内存 + SQLite。"""
    global _loaded
    with _lock:
        _daily_counter.clear()
        _daily_nomode_counter.clear()
        _total_counter.clear()
        _loaded = True
    try:
        conn = _get_conn()
        try:
            conn.execute("DELETE FROM vision_quota")
            conn.commit()
        finally:
            conn.close()
    except Exception as exc:  # noqa: BLE001
        logger.warning("清空视觉额度计数失败: %s", exc)
