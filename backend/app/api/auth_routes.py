"""
认证路由（/api/auth/*）。

- POST /api/auth/register      注册 -> 用户信息
- POST /api/auth/login         登录 -> JWT + 用户信息
- GET  /api/auth/me            当前用户（需 Bearer token）
- POST /api/auth/change-password 修改密码（需 Bearer token）

鉴权：/me 与 /change-password 通过 Depends(get_current_user) 注入当前用户；
非法 / 缺失 token 返回 401。
"""
from __future__ import annotations

from fastapi import APIRouter, Depends, HTTPException, Request
from sqlalchemy.orm import Session

from app.api.deps import get_current_user, run_service
from app.core.captcha import generate_captcha, verify_captcha
from app.core.vision_rate_limiter import get_client_ip
from app.db.models import User
from app.db.session import get_db
from app.schemas.auth import (
    ChangePasswordIn,
    LoginIn,
    RegisterIn,
    TokenOut,
    UserOut,
)
from app.services.auth_service import _to_out, auth_service

router = APIRouter(prefix="/auth", tags=["auth"])


@router.get(
    "/captcha",
    response_model=dict,
    summary="获取算术验证码",
    description="返回一张含算术题的 PNG 图片（base64）与 captcha_id，注册时需提交答案。单次有效，5 分钟过期。",
)
def get_captcha() -> dict:
    return generate_captcha()


@router.post(
    "/register",
    response_model=UserOut,
    summary="用户注册",
    description="创建用户。需先获取验证码（GET /auth/captcha）并提交 captcha_id + captcha_answer。"
    "用户名唯一，密码以加盐哈希存储。重复用户名返回 409。",
)
def register(payload: RegisterIn, db: Session = Depends(get_db)) -> UserOut:
    # 人机验证：算术验证码，单次有效
    if not verify_captcha(payload.captcha_id, payload.captcha_answer):
        raise HTTPException(status_code=400, detail="验证码错误或已过期，请重新获取")
    return run_service(
        lambda: auth_service.register(
            payload.username, payload.password, payload.display_name, db=db
        )
    )


@router.post(
    "/login",
    response_model=TokenOut,
    summary="用户登录",
    description="校验用户名密码，成功返回 JWT（Authorization: Bearer <token>）与用户信息。"
    "连续失败达 5 次会锁定 10 分钟（按用户名/IP）。",
)
def login(payload: LoginIn, request: Request, db: Session = Depends(get_db)) -> TokenOut:
    return run_service(
        lambda: auth_service.login(
            payload.username,
            payload.password,
            db=db,
            client_ip=get_client_ip(request),
        )
    )


@router.get(
    "/me",
    response_model=UserOut,
    summary="当前用户",
    description="根据 Authorization Bearer token 返回当前登录用户信息。",
)
def me(current_user: User = Depends(get_current_user)) -> UserOut:
    return _to_out(current_user)


@router.post(
    "/change-password",
    response_model=dict,
    summary="修改密码",
    description="需登录。校验旧密码后更新新密码，返回 {ok: true}。",
)
def change_password(
    payload: ChangePasswordIn,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
) -> dict:
    run_service(
        lambda: auth_service.change_password(
            current_user, payload.old_password, payload.new_password, db=db
        )
    )
    return {"ok": True}
