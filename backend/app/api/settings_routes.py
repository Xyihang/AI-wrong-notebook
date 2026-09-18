"""
运行时设置路由（GET/PUT /api/settings）。

读：settings_service.get()，api_key 默认掩码为 ******。
写：settings_service.update() 部分更新（llm_enabled / model / base_url / api_key），
未知键 -> 400。更新成功后重建 LLM 客户端，使新 Key / 模型免重启生效。

额度：GET /api/settings/vision-quota 返回当前用户（按账户，匿名按 IP）视觉识别剩余额度。
"""
from __future__ import annotations

from typing import Any, Dict

from fastapi import APIRouter, Depends, HTTPException, Query, Request

from app.api.deps import current_user_id, get_optional_user, sync_llm_client_from_settings
from app.core.vision_rate_limiter import (
    NO_KEY_LIMIT,
    VISION_DAILY_LIMIT,
    VISION_KEY_NO_MODE_LIMIT,
    get_client_ip,
    remaining_vision_slots,
)
from app.db.models import User
from app.services.settings_service import settings_service

router = APIRouter(prefix="/settings", tags=["settings"])


@router.get("", response_model=Dict[str, Any], summary="读取后端配置（api_key 掩码）")
def get_settings() -> Dict[str, Any]:
    return settings_service.get()


@router.put("", response_model=Dict[str, Any], summary="更新后端配置（模型 / Key 等）")
def update_settings(payload: Dict[str, Any]) -> Dict[str, Any]:
    try:
        updated = settings_service.update(payload)
    except ValueError as exc:
        raise HTTPException(status_code=400, detail=str(exc)) from exc
    sync_llm_client_from_settings()
    return updated


@router.get(
    "/vision-quota",
    response_model=Dict[str, Any],
    summary="查询当前用户视觉识别剩余额度（按账户，匿名按 IP）",
)
def get_vision_quota(
    request: Request,
    has_vision_key: bool = Query(default=False, description="该用户是否已配置 DeepSeek Key"),
    use_vision_mode: bool = Query(
        default=False, description="该用户是否启用视觉模式（有 Key 未启用时按每天 20 档）"
    ),
    current_user: User | None = Depends(get_optional_user),
) -> Dict[str, Any]:
    """返回视觉兜底剩余额度。按登录账户计（user_id），匿名按 IP。

    三档：
    - no_key（无 Key）：累计 10 次；
    - vision_key（有 Key + 视觉模式）：每天 50 次；
    - vision_key_no_mode（有 Key 未启用视觉模式）：每天 20 次，并提示开启视觉模式省额度。
    三档池子独立，切换档位不重置任何一方计数。
    """
    ip = get_client_ip(request)
    uid = current_user_id(current_user)
    if not has_vision_key:
        limit = NO_KEY_LIMIT
        remaining = remaining_vision_slots(ip, False, user_id=uid)
        return {
            "mode": "no_key",
            "limit": limit,
            "remaining": remaining,
            "used": limit - remaining,
            "reset": "total",
        }
    if use_vision_mode:
        limit = VISION_DAILY_LIMIT
        remaining = remaining_vision_slots(ip, True, user_id=uid, use_vision_mode=True)
        return {
            "mode": "vision_key",
            "limit": limit,
            "remaining": remaining,
            "used": limit - remaining,
            "reset": "daily",
        }
    limit = VISION_KEY_NO_MODE_LIMIT
    remaining = remaining_vision_slots(ip, True, user_id=uid, use_vision_mode=False)
    return {
        "mode": "vision_key_no_mode",
        "limit": limit,
        "remaining": remaining,
        "used": limit - remaining,
        "reset": "daily",
    }
