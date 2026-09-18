"""
用户认证业务服务：注册 / 登录 / 当前用户 / 修改密码。

- 密码使用 pbkdf2 加盐哈希存储（core.security），绝不存明文。
- 登录签发 JWT（无状态，subject = 用户 uuid）。
- 用户名唯一校验 + 密码长度校验。
- 业务错误统一抛 ServiceError（core.errors），路由层转 HTTPException。
"""
from __future__ import annotations

import re
from datetime import datetime, timezone
from typing import Any

from sqlalchemy import select
from sqlalchemy.orm import Session

from app.core.config import settings
from app.core.errors import ServiceError
from app.core.login_rate_limiter import (
    check_login_allowed,
    record_login_failure,
    reset_login_failures,
)
from app.core.logging import get_logger
from app.core.security import create_access_token, hash_password, verify_password
from app.db.models import User
from app.db.session import SessionLocal
from app.schemas.auth import PASSWORD_MIN, PASSWORD_MAX, USERNAME_MAX

logger = get_logger(__name__)

# 用户名允许字符：中英文、数字、下划线、点、短横（1~64）
_USERNAME_RE = re.compile(r"^[\w.\-\u4e00-\u9fff]+$")


def _normalize_username(username: str) -> str:
    """去掉首尾空白，并做合法性校验。"""
    name = (username or "").strip()
    if not name:
        raise ServiceError("用户名不能为空")
    if len(name) > USERNAME_MAX:
        raise ServiceError(f"用户名长度不能超过 {USERNAME_MAX} 字符")
    if not _USERNAME_RE.match(name):
        raise ServiceError("用户名只能包含中英文、数字、下划线、点或短横")
    return name


def _validate_password(password: str) -> None:
    if not password:
        raise ServiceError("密码不能为空")
    if len(password) < PASSWORD_MIN:
        raise ServiceError(f"密码长度至少 {PASSWORD_MIN} 位")
    if len(password) > PASSWORD_MAX:
        raise ServiceError(f"密码长度不能超过 {PASSWORD_MAX} 字符")


def _to_out(user: User) -> dict[str, Any]:
    """User ORM -> 对外 dict（UserOut 兼容）。"""
    return {
        "id": user.uuid,
        "username": user.username,
        "display_name": user.display_name or "",
        "created_at": user.created_at,
    }


class AuthService:
    """认证业务逻辑。方法与 question_service 一样接受可选 Session。"""

    def __init__(self, session_factory=SessionLocal):
        self._session_factory = session_factory

    def _session(self, db: Session | None) -> Session:
        return db if db is not None else self._session_factory()

    @staticmethod
    def _close(db: Session, own: bool) -> None:
        if own:
            db.close()

    # ------------------------------------------------------------------
    # 注册
    # ------------------------------------------------------------------
    def register(
        self,
        username: str,
        password: str,
        display_name: str = "",
        db: Session | None = None,
    ) -> dict[str, Any]:
        """创建用户。用户名重复 / 密码太弱时抛 ServiceError。"""
        # 注册开关：内测锁定（REGISTER_ENABLED=false）时拒绝新注册
        if not settings.REGISTER_ENABLED:
            raise ServiceError(
                "当前为内测阶段，暂不开放注册。如有需要请联系管理员开通账号。",
                status_code=403,
            )
        name = _normalize_username(username)
        _validate_password(password)

        own = db is None
        db = self._session(db)
        try:
            exists = db.scalar(select(User).where(User.username == name))
            if exists is not None:
                raise ServiceError(f"用户名 {name!r} 已被注册", status_code=409)

            now = datetime.now(timezone.utc)
            user = User(
                username=name,
                password_hash=hash_password(password),
                display_name=(display_name or "").strip()[:64],
                created_at=now,
                updated_at=now,
                sync_version=0,
            )
            db.add(user)
            db.commit()
            db.refresh(user)
            logger.info("注册新用户 username=%s uuid=%s", user.username, user.uuid)
            return _to_out(user)
        except ServiceError:
            db.rollback()
            raise
        except Exception as exc:  # noqa: BLE001
            db.rollback()
            logger.exception("注册失败")
            raise ServiceError(f"注册失败: {exc}", status_code=500) from exc
        finally:
            self._close(db, own)

    # ------------------------------------------------------------------
    # 登录
    # ------------------------------------------------------------------
    def login(
        self,
        username: str,
        password: str,
        db: Session | None = None,
        client_ip: str = "",
    ) -> dict[str, Any]:
        """校验凭据并签发 JWT。

        凭据错误统一返回 401（不泄露用户是否存在）；连续失败达阈值触发
        IP/用户名锁定，锁定期间返回 429。成功后清除失败记录。
        """
        name = (username or "").strip()
        if not name or not password:
            raise ServiceError("用户名或密码不能为空", status_code=401)

        # 限流：锁定期间拒绝
        allowed, retry_after = check_login_allowed(name, client_ip or "")
        if not allowed:
            raise ServiceError(
                f"尝试次数过多，请 {retry_after} 秒后再试", status_code=429
            )

        own = db is None
        db = self._session(db)
        try:
            user = db.scalar(select(User).where(User.username == name))
            if user is None or not verify_password(password, user.password_hash):
                record_login_failure(name, client_ip or "")
                logger.warning("登录失败：用户名或密码错误 (%s)", name)
                raise ServiceError("用户名或密码错误", status_code=401)
            reset_login_failures(name, client_ip or "")
            token = create_access_token(subject=user.uuid)
            logger.info("登录成功 username=%s uuid=%s", user.username, user.uuid)
            return {"access_token": token, "token_type": "bearer", "user": _to_out(user)}
        except ServiceError:
            raise
        except Exception as exc:  # noqa: BLE001
            logger.exception("登录失败")
            raise ServiceError(f"登录失败: {exc}", status_code=500) from exc
        finally:
            self._close(db, own)

    # ------------------------------------------------------------------
    # 按 uuid 取用户（/api/auth/me）
    # ------------------------------------------------------------------
    def get_user_by_uuid(
        self, uuid: str, db: Session | None = None
    ) -> User:
        """按对外 uuid 取用户。不存在抛 404。"""
        own = db is None
        db = self._session(db)
        try:
            user = db.scalar(select(User).where(User.uuid == uuid))
            if user is None:
                raise ServiceError("用户不存在或已注销", status_code=404)
            return user
        finally:
            self._close(db, own)

    # ------------------------------------------------------------------
    # 修改密码
    # ------------------------------------------------------------------
    def change_password(
        self,
        user: User,
        old_password: str,
        new_password: str,
        db: Session | None = None,
    ) -> None:
        """校验旧密码后更新新密码。旧密码错误返回 401。"""
        _validate_password(new_password)
        if not verify_password(old_password, user.password_hash):
            raise ServiceError("旧密码不正确", status_code=401)
        if old_password == new_password:
            raise ServiceError("新密码不能与旧密码相同")

        own = db is None
        db = self._session(db)
        try:
            user.password_hash = hash_password(new_password)
            user.updated_at = datetime.now(timezone.utc)
            user.sync_version = (user.sync_version or 0) + 1
            db.commit()
            logger.info("用户 %s 已修改密码", user.username)
        except Exception as exc:  # noqa: BLE001
            db.rollback()
            logger.exception("修改密码失败")
            raise ServiceError(f"修改密码失败: {exc}", status_code=500) from exc
        finally:
            self._close(db, own)


    # ------------------------------------------------------------------
    # 预置账户（内测固定账号）
    # ------------------------------------------------------------------
    def ensure_default_accounts(self, db: Session | None = None) -> int:
        """
        按 settings.DEFAULT_ACCOUNTS（如 "u1:p1,u2:p2"）确保账户存在。

        - 不存在 -> 创建；
        - 已存在 -> 重置密码为配置值（保证内测固定账号密码可控）。
        返回本次新增 + 重置的账户数。启动时（lifespan）调用一次。
        """
        raw = (settings.DEFAULT_ACCOUNTS or "").strip()
        if not raw:
            return 0
        pairs = [p for p in raw.split(",") if p.strip()]
        own = db is None
        db = self._session(db)
        count = 0
        try:
            for pair in pairs:
                if ":" not in pair:
                    logger.warning("DEFAULT_ACCOUNTS 项缺少 ':'，跳过: %s", pair)
                    continue
                name, password = pair.split(":", 1)
                name = (name or "").strip()
                if not name or not password:
                    continue
                now = datetime.now(timezone.utc)
                user = db.scalar(select(User).where(User.username == name))
                if user is None:
                    user = User(
                        username=name,
                        password_hash=hash_password(password),
                        display_name=name,
                        created_at=now,
                        updated_at=now,
                        sync_version=0,
                    )
                    db.add(user)
                    logger.info("预置账户已创建: %s", name)
                else:
                    user.password_hash = hash_password(password)
                    user.updated_at = now
                    user.sync_version = (user.sync_version or 0) + 1
                    logger.info("预置账户已重置密码: %s", name)
                count += 1
            db.commit()
            return count
        except Exception as exc:  # noqa: BLE001
            db.rollback()
            logger.exception("预置账户处理失败")
            raise ServiceError(f"预置账户处理失败: {exc}", status_code=500) from exc
        finally:
            self._close(db, own)


# 模块级单例，路由层直接复用
auth_service = AuthService()
