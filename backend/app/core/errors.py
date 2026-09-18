"""
业务错误定义（core.errors）。

ServiceError 是各业务服务（question_service / auth_service 等）统一抛出的
业务异常：message 为面向用户的描述，status_code 供路由层映射 HTTP 状态码。
继承 ValueError，以便既有 except ValueError 逻辑兜底。
"""
from __future__ import annotations


class ServiceError(ValueError):
    """
    业务错误。

    - message     : 面向用户的错误描述（路由层直接作为 {"detail": message}）
    - status_code : 建议的 HTTP 状态码（默认 400）
    """

    def __init__(self, message: str, status_code: int = 400):
        super().__init__(message)
        self.message = message
        self.status_code = status_code
