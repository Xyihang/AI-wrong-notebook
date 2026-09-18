"""
认证数据契约（Pydantic v2）。

- RegisterIn / LoginIn / ChangePasswordIn : 请求体
- UserOut  : 对外用户信息（id 为 uuid，不暴露 int 主键 / 密码哈希）
- TokenOut : 登录响应（JWT + 用户信息）
"""
from __future__ import annotations

from datetime import datetime

from pydantic import BaseModel, ConfigDict, Field

# 用户名 / 密码约束（前后端约定一致）
USERNAME_MIN = 1
USERNAME_MAX = 64
PASSWORD_MIN = 6
PASSWORD_MAX = 128
DISPLAY_NAME_MAX = 64


class RegisterIn(BaseModel):
    """注册请求。"""

    username: str = Field(
        min_length=USERNAME_MIN,
        max_length=USERNAME_MAX,
        description="登录用户名（唯一，1~64 字符）",
    )
    password: str = Field(
        min_length=PASSWORD_MIN,
        max_length=PASSWORD_MAX,
        description=f"密码（{PASSWORD_MIN}~{PASSWORD_MAX} 字符）",
    )
    display_name: str = Field(
        default="", max_length=DISPLAY_NAME_MAX, description="展示名（可选）"
    )
    captcha_id: str = Field(description="验证码 id（来自 GET /api/auth/captcha）")
    captcha_answer: str = Field(
        min_length=1, max_length=16, description="算术验证码答案（图片中的算式结果）"
    )


class LoginIn(BaseModel):
    """登录请求。"""

    username: str = Field(min_length=1, max_length=USERNAME_MAX)
    password: str = Field(min_length=1, max_length=PASSWORD_MAX)


class ChangePasswordIn(BaseModel):
    """修改密码请求（需登录）。"""

    old_password: str = Field(min_length=1, max_length=PASSWORD_MAX)
    new_password: str = Field(
        min_length=PASSWORD_MIN,
        max_length=PASSWORD_MAX,
        description=f"新密码（{PASSWORD_MIN}~{PASSWORD_MAX} 字符）",
    )


class UserOut(BaseModel):
    """对外用户信息。id 为字符串 UUID（users.uuid 列）。"""

    model_config = ConfigDict(from_attributes=True)

    id: str = Field(description="用户 UUID（字符串）")
    username: str = Field(description="登录用户名")
    display_name: str = Field(default="", description="展示名")
    created_at: datetime = Field(description="注册时间（ISO8601）")


class TokenOut(BaseModel):
    """登录成功响应：JWT + 用户信息。"""

    access_token: str = Field(description="JWT（请求头 Authorization: Bearer <token>）")
    token_type: str = Field(default="bearer")
    user: UserOut = Field(description="当前用户信息")
