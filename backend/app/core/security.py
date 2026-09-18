"""
安全工具（core.security）：密码哈希 + JWT。

刻意只用 Python 标准库（hashlib / hmac / secrets / base64 / json / time），
不引入 PyJWT / bcrypt 等第三方依赖 —— 避免云服务器上额外的安装与兼容风险。

- hash_password / verify_password : pbkdf2_hmac(sha256) 加盐哈希
- create_access_token / decode_access_token : HS256 JWT（无状态）
"""
from __future__ import annotations

import base64
import hashlib
import hmac
import json
import secrets
import time
from pathlib import Path
from typing import Any

from app.core.config import BASE_DIR, settings

# pbkdf2 迭代次数：客户端轻量仍足够安全（OWASP 建议 ≥600k 可选，这里取 260k 平衡速度）
_PBKDF2_ITERATIONS = 260_000
_ALG_SEPARATOR = "$"
# JWT 版本标记，便于将来算法升级
_JWT_VERSION = "1"


# ---------------------------------------------------------------------------
# JWT 签名密钥
# ---------------------------------------------------------------------------
def _get_jwt_secret() -> str:
    """获取 JWT 签名密钥。

    - 若 .env 配置了 JWT_SECRET，则使用之；
    - 否则首次运行自动生成强随机密钥并持久化到 data/.jwt_secret，
      保证重启后已签发 token 仍可校验（跨进程稳定）。
    """
    if settings.JWT_SECRET.strip():
        return settings.JWT_SECRET.strip()
    secret_file = Path(settings.UPLOAD_DIR).parent / ".jwt_secret"
    try:
        if secret_file.exists():
            val = secret_file.read_text(encoding="utf-8").strip()
            if val:
                return val
        val = secrets.token_urlsafe(48)
        secret_file.parent.mkdir(parents=True, exist_ok=True)
        secret_file.write_text(val, encoding="utf-8")
        return val
    except OSError:  # 无法落盘时降级为进程内随机（重启后旧 token 失效）
        return secrets.token_urlsafe(48)


def _b64url_encode(data: bytes) -> str:
    return base64.urlsafe_b64encode(data).rstrip(b"=").decode("ascii")


def _b64url_decode(data: str) -> bytes:
    padding = "=" * (-len(data) % 4)
    return base64.urlsafe_b64decode(data + padding)


# ---------------------------------------------------------------------------
# 密码哈希
# ---------------------------------------------------------------------------
def hash_password(password: str) -> str:
    """对明文密码做 pbkdf2 加盐哈希。

    存储格式：pbkdf2_sha256$1$迭代次数$salt_base64$hash_base64
    """
    salt = secrets.token_bytes(16)
    digest = hashlib.pbkdf2_hmac(
        "sha256", password.encode("utf-8"), salt, _PBKDF2_ITERATIONS
    )
    return _ALG_SEPARATOR.join(
        [
            "pbkdf2_sha256",
            _JWT_VERSION,
            str(_PBKDF2_ITERATIONS),
            _b64url_encode(salt),
            _b64url_encode(digest),
        ]
    )


def verify_password(password: str, hashed: str) -> bool:
    """校验明文密码与哈希是否匹配。哈希格式非法时安全返回 False。"""
    try:
        parts = hashed.split(_ALG_SEPARATOR)
        if len(parts) != 5 or parts[0] != "pbkdf2_sha256":
            return False
        _version, iterations_s, salt_b64, digest_b64 = parts[1:]
        iterations = int(iterations_s)
        salt = _b64url_decode(salt_b64)
        expected = _b64url_decode(digest_b64)
        actual = hashlib.pbkdf2_hmac(
            "sha256", password.encode("utf-8"), salt, iterations
        )
        return hmac.compare_digest(actual, expected)
    except (ValueError, TypeError):
        return False


# ---------------------------------------------------------------------------
# JWT（HS256）
# ---------------------------------------------------------------------------
def create_access_token(subject: str, expires_days: int | None = None) -> str:
    """签发 JWT。subject 为用户 uuid（对外标识）。

    payload: {"sub": uuid, "iat": 签发时间戳, "exp": 过期时间戳, "ver": 版本}
    """
    now = int(time.time())
    exp_days = expires_days if expires_days is not None else settings.JWT_EXPIRE_DAYS
    header = {"alg": "HS256", "typ": "JWT"}
    payload: dict[str, Any] = {
        "sub": subject,
        "iat": now,
        "exp": now + int(exp_days) * 86400,
        "ver": _JWT_VERSION,
    }
    secret = _get_jwt_secret()
    signing_input = ".".join(
        [_b64url_encode(json.dumps(header).encode("utf-8")),
         _b64url_encode(json.dumps(payload).encode("utf-8"))]
    )
    signature = hmac.new(secret.encode("utf-8"), signing_input.encode("utf-8"), hashlib.sha256).digest()
    return signing_input + "." + _b64url_encode(signature)


class InvalidTokenError(Exception):
    """token 非法 / 过期 / 篡改。"""


def decode_access_token(token: str) -> dict[str, Any]:
    """校验并解析 JWT。失败抛 InvalidTokenError。"""
    try:
        header_b64, payload_b64, sig_b64 = token.split(".")
        secret = _get_jwt_secret()
        signing_input = f"{header_b64}.{payload_b64}"
        expected = hmac.new(
            secret.encode("utf-8"), signing_input.encode("utf-8"), hashlib.sha256
        ).digest()
        if not hmac.compare_digest(expected, _b64url_decode(sig_b64)):
            raise InvalidTokenError("签名校验失败")
        header = json.loads(_b64url_decode(header_b64))
        payload = json.loads(_b64url_decode(payload_b64))
        if header.get("alg") != "HS256":
            raise InvalidTokenError("不支持的签名算法")
        if payload.get("ver") != _JWT_VERSION:
            raise InvalidTokenError("token 版本不兼容")
        exp = int(payload.get("exp", 0))
        if exp and exp < int(time.time()):
            raise InvalidTokenError("token 已过期")
        return payload
    except (ValueError, IndexError, json.JSONDecodeError, UnicodeDecodeError) as exc:
        raise InvalidTokenError("token 格式非法") from exc
