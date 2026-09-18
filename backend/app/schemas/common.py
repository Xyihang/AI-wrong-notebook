"""通用响应模型。"""
from __future__ import annotations

from pydantic import BaseModel, Field


class HealthOut(BaseModel):
    """健康检查响应（GET /api/health）。"""

    status: str = Field(default="ok", description="服务状态")
    version: str = Field(default="0.1.0", description="后端版本号")
    db: str = Field(default="ok", description="数据库连通状态")
    llm_enabled: bool = Field(default=False, description="大模型功能是否启用")
