"""
Pydantic v2 数据契约层。

与 Flutter 端共享的 QuestionRecord JSON 结构见 question.QuestionOut。
模块划分：
- common.py     : 通用响应模型（HealthOut 等）
- question.py   : 题目 CRUD / 批量操作 / 列表 / 知识点契约
- ocr.py        : OCR 识别结果契约
- retrieval.py  : 同类题匹配契约
"""
from app.schemas.common import HealthOut
from app.schemas.question import (
    BatchDeleteRequest,
    BatchMoveRequest,
    KnowledgePointOut,
    QuestionCreate,
    QuestionListOut,
    QuestionOut,
    QuestionUpdate,
)
from app.schemas.retrieval import MatchItem, MatchRequest, MatchResponse
from app.schemas.ocr import OCRResult

__all__ = [
    # common
    "HealthOut",
    # question
    "QuestionCreate",
    "QuestionUpdate",
    "QuestionOut",
    "QuestionListOut",
    "BatchDeleteRequest",
    "BatchMoveRequest",
    "KnowledgePointOut",
    # ocr
    "OCRResult",
    # retrieval
    "MatchItem",
    "MatchRequest",
    "MatchResponse",
]
