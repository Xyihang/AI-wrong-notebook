"""
AI-Wrong 后端应用包。

分层结构（与 docs/plan.md 对齐）：
- core      : 配置 / 日志等基础设施
- schemas   : Pydantic v2 数据契约（与 Flutter 共享的 QuestionRecord JSON）
- db        : SQLAlchemy 2.0 ORM / session / 初始化
- services  : 业务层（题目 CRUD、设置、导入、导出）
- ocr       : OCR 流水线（由 Agent-B 维护）
- retrieval : 向量检索（由 Agent-C 维护）
- llm       : 大模型层（由 Agent-C 维护）
"""

__version__ = "0.1.0"
