"""
应用配置（pydantic-settings）。

从环境变量 / backend/.env 读取，所有相对路径统一解析为
backend/ 目录下的绝对路径，避免从任意 CWD 启动时路径错乱。

用法：
    from app.core.config import settings
    settings.DATABASE_URL
"""
from __future__ import annotations

from functools import lru_cache
from pathlib import Path

from pydantic import field_validator
from pydantic_settings import BaseSettings, SettingsConfigDict

# backend/ 目录（app/core/config.py -> backend/app/core/ -> backend/）
BASE_DIR = Path(__file__).resolve().parents[2]


class Settings(BaseSettings):
    """全局配置。字段名与 .env 中全大写变量一一对应（大小写不敏感）。"""

    model_config = SettingsConfigDict(
        env_file=str(BASE_DIR / ".env"),
        env_file_encoding="utf-8",
        extra="ignore",
        case_sensitive=False,
    )

    # --- 应用 ---
    APP_NAME: str = "AI-Wrong Backend"
    VERSION: str = "0.1.0"
    DEBUG: bool = False
    LOG_LEVEL: str = "INFO"

    # --- 数据库 ---
    DATABASE_URL: str = "sqlite:///./data/wrongbook.db"

    # --- 向量库 / 嵌入 ---
    CHROMA_DIR: str = "./data/chroma"
    EMBEDDING_MODE: str = "local"  # local | api

    # --- 大模型（OpenAI 兼容）---
    LLM_BASE_URL: str = "https://api.deepseek.com/v1"
    LLM_API_KEY: str = ""
    LLM_MODEL: str = "deepseek-chat"
    LLM_ENABLED: bool = False
    # 多模态视觉模型（用于未装 PaddleOCR 时的图片读图兜底）
    VISION_MODEL: str = ""
    VISION_MAX_TOKENS: int = 1500
    # 大模型输出上限（DeepSeek deepseek-flash / deepseek-v4-pro 官方最大 384K）。
    # 基础值取官方最大的一半，空内容时兜底到 LLM_MAX_TOKENS_FALLBACK。
    # 注意：max_tokens 只是上限，按实际生成 token 计费。
    LLM_MAX_TOKENS: int = 192000
    LLM_MAX_TOKENS_FALLBACK: int = 384000

    # --- 认证（JWT）---
    # JWT 签名密钥。留空时首次启动自动生成并持久化到 data/.jwt_secret，
    # 保证重启后已签发的 token 仍有效。生产建议在 .env 显式配置强随机值。
    JWT_SECRET: str = ""
    # token 有效期（天）
    JWT_EXPIRE_DAYS: int = 7
    # 签名算法（仅支持 HS256）
    TOKEN_ALG: str = "HS256"

    # --- 注册开关（内测控制）---
    # 是否开放新用户注册。false = 锁定注册（内测只允许预置/已存在账户登录）。
    REGISTER_ENABLED: bool = False
    # 预置账户：逗号分隔的 "username:password"，如 "u1:p1,u2:p2"。
    # 启动时自动创建（已存在则重置密码），用于内测固定账户。
    DEFAULT_ACCOUNTS: str = ""

    # --- 文件 ---
    UPLOAD_DIR: str = "./data/uploads"

    # --- 服务 ---
    HOST: str = "0.0.0.0"
    BACKEND_PORT: int = 8000
    # 逗号分隔的 CORS 白名单，* 表示全部
    CORS_ORIGINS: str = "*"

    # ----------------------------------------------------------
    # 路径归一化：相对路径统一转为 BASE_DIR 下的绝对路径
    # ----------------------------------------------------------

    @field_validator("DATABASE_URL", mode="after")
    @classmethod
    def _normalize_database_url(cls, v: str) -> str:
        if not v.startswith("sqlite:///"):
            return v  # 其它方言（如 postgres）原样保留
        rest = v[len("sqlite:///"):]
        if rest.startswith("/") or rest.startswith(":"):
            return v  # 绝对路径（sqlite:////abs/path）或内存库（:memory:）原样保留
        p = Path(rest).expanduser()
        if not p.is_absolute():
            p = BASE_DIR / p
        p.parent.mkdir(parents=True, exist_ok=True)
        return f"sqlite:///{p.as_posix()}"

    @field_validator("CHROMA_DIR", "UPLOAD_DIR", mode="after")
    @classmethod
    def _normalize_dir(cls, v: str) -> str:
        if not v:
            return v
        p = Path(v).expanduser()
        if not p.is_absolute():
            p = BASE_DIR / p
        return p.as_posix()

    @property
    def cors_origin_list(self) -> list[str]:
        """解析逗号分隔的 CORS 白名单。"""
        return [o.strip() for o in self.CORS_ORIGINS.split(",") if o.strip()]

    def ensure_dirs(self) -> None:
        """确保数据目录存在（数据库目录 / 向量库 / 上传目录）。"""
        for d in (Path(self.UPLOAD_DIR), Path(self.CHROMA_DIR)):
            d.mkdir(parents=True, exist_ok=True)


@lru_cache
def get_settings() -> Settings:
    """获取全局 Settings 单例。"""
    return Settings()


# 模块级单例，其它模块直接 import
settings = get_settings()
