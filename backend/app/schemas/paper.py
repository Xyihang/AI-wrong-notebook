"""AI 变式组卷 数据契约（Pydantic v2）。"""
from __future__ import annotations

from pydantic import BaseModel, Field


class PaperGenerateRequest(BaseModel):
    """组卷请求。subject 必填；count 默认 10。"""

    subject: str = Field(description="学科，如 数学")
    knowledge_points: list[str] = Field(
        default_factory=list, description="知识点范围（可多选；空则不限）"
    )
    difficulty: str | None = Field(
        default=None, description="难度偏好：简单/中等/困难；空则自动均衡"
    )
    count: int = Field(default=10, ge=1, le=30, description="题数（1~30）")


class PaperQuestion(BaseModel):
    """卷中一题。source: existing=来自本人错题 / ai=AI 变式补齐。"""

    stem: str = Field(default="", description="题干")
    options: list[str] = Field(default_factory=list, description="选项（无则空）")
    answer: str = Field(default="", description="答案")
    analysis: str = Field(default="", description="解析")
    difficulty: str = Field(default="中等", description="难度")
    knowledge_points: list[str] = Field(
        default_factory=list, description="知识点"
    )
    question_type: str = Field(default="", description="题型")
    source: str = Field(default="ai", description="existing=本人错题 / ai=AI 变式")
    source_question_id: str | None = Field(default=None, description="来源错题 id（existing 时）")


class PaperResult(BaseModel):
    """生成的整卷。"""

    title: str = Field(default="", description="卷名")
    subject: str = Field(default="", description="学科")
    questions: list[PaperQuestion] = Field(default_factory=list, description="题目列表（按难度排序）")


class PaperGenerateResponse(BaseModel):
    paper: PaperResult = Field(description="生成的卷")


class PaperPdfRequest(BaseModel):
    """把已生成的卷导出为 PDF 的请求。"""

    title: str = Field(default="AI 组卷", description="PDF 标题")
    include_answers: bool = Field(
        default=False, description="True=含答案解析 / False=纯题（题面）"
    )
    questions: list[PaperQuestion] = Field(
        default_factory=list, description="卷内题目（后端据此渲染）"
    )
