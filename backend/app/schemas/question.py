"""
题目数据契约（Pydantic v2）。

QuestionOut 严格对齐 docs/spec.md §7.1 的 QuestionRecord JSON（与 Flutter 共享）：
    id / subject / knowledge_points / question_type / difficulty / stem /
    options / answer / analysis / mistake_reason / mastery / tags /
    image_path / ocr_text / latex_text / created_at / similar_matches

注意：
- id 是字符串 UUID（对应 questions 表的 uuid 列，int 主键不对外暴露）。
- similar_matches 与 retrieval.MatchItem 互为引用（跨模块环形引用），
  通过 defer_build + model_rebuild(_types_namespace=...) 在 retrieval.py 中解析，
  两个模块以任意顺序 import 均安全。
"""
from __future__ import annotations

from datetime import datetime
from typing import TYPE_CHECKING

from pydantic import BaseModel, ConfigDict, Field

if TYPE_CHECKING:  # 仅类型检查时导入，避免运行时环形依赖
    from app.schemas.retrieval import MatchItem  # noqa: F401

# ---------------------------------------------------------------------------
# 通用约束常量（与 DB schema / Flutter 端一致）
# ---------------------------------------------------------------------------
MASTERY_LEVELS = ("未掌握", "已掌握", "需巩固")
DIFFICULTY_LEVELS = ("简单", "中等", "困难")
QUESTION_STATUSES = ("active", "archived", "deleted")


class QuestionBase(BaseModel):
    """题目公共字段（创建 / 更新 / 输出共用）。"""

    subject: str = Field(default="", description="科目，如：数学")
    knowledge_points: list[str] = Field(
        default_factory=list,
        description="知识点路径列表，如 [\"初中\", \"几何\", \"圆\"]",
    )
    question_type: str = Field(default="", description="题型，如：解答题 / 单选题")
    difficulty: str = Field(default="中等", description="难度：简单 / 中等 / 困难")
    stem: str = Field(default="", description="题干文本")
    options: list[str] = Field(default_factory=list, description="选项列表（选择题）")
    answer: str = Field(default="", description="答案 / 订正答案")
    analysis: str = Field(default="", description="解析")
    mistake_reason: str = Field(default="", description="错因")
    study_advice: str = Field(default="", description="学习建议（应掌握知识点、易错提醒、复习建议）")
    mastery: str = Field(default="未掌握", description="掌握程度：未掌握 / 已掌握 / 需巩固")
    tags: list[str] = Field(default_factory=list, description="标签列表")
    image_path: str = Field(default="", description="原图路径 / URL")
    ocr_text: str = Field(default="", description="OCR 识别原文")
    latex_text: str = Field(default="", description="LaTeX 公式文本（texify 产出）")


class QuestionCreate(QuestionBase):
    """
    创建题目请求。

    id / created_at / updated_at 可选：客户端同步错题时可传入自己的
    uuid 与时间戳，服务端按 id 幂等 upsert（已存在同 uuid 且属于该用户则更新）。
    缺省时服务端生成 uuid 与当前时间。
    review_count / last_reviewed_at 用于客户端推送复习状态（服务端据此算连击）。
    """

    id: str | None = Field(default=None, description="客户端题目标识（uuid，可选）")
    created_at: datetime | None = Field(default=None, description="客户端创建时间（可选）")
    updated_at: datetime | None = Field(default=None, description="客户端最后修改时间（可选）")
    review_count: int | None = Field(default=None, description="累计复习次数（可选）")
    last_reviewed_at: datetime | None = Field(default=None, description="上次复习时间（可选）")
    client_json: str | None = Field(
        default=None, description="客户端完整记录 JSON（无损同步，可选）"
    )


class QuestionUpdate(BaseModel):
    """
    部分更新请求：所有字段可选，仅提交的字段会被更新。
    通过 model_fields_set 区分「未提交」与「显式置空」。
    """

    subject: str | None = None
    knowledge_points: list[str] | None = None
    question_type: str | None = None
    difficulty: str | None = None
    stem: str | None = None
    options: list[str] | None = None
    answer: str | None = None
    analysis: str | None = None
    mistake_reason: str | None = None
    mastery: str | None = None
    tags: list[str] | None = None
    image_path: str | None = None
    ocr_text: str | None = None
    latex_text: str | None = None
    source: str | None = None
    status: str | None = None
    updated_at: datetime | None = None
    review_count: int | None = None
    last_reviewed_at: datetime | None = None


class QuestionOut(QuestionBase):
    """
    题目输出模型 —— 即 QuestionRecord JSON 契约。

    字段 id 为字符串 UUID（questions.uuid 列）。
    similar_matches 默认空列表；由检索服务填充。
    """

    model_config = ConfigDict(
        from_attributes=True,
        defer_build=True,  # similar_matches 引用 retrieval.MatchItem，延后构建
    )

    id: str = Field(description="题目 UUID（字符串）")
    created_at: datetime = Field(description="创建时间（ISO8601）")
    updated_at: datetime | None = Field(default=None, description="最后更新时间（ISO8601）")
    review_count: int = Field(default=0, description="累计复习次数")
    last_reviewed_at: datetime | None = Field(
        default=None, description="上次复习时间（ISO8601，未复习为空）"
    )
    client_json: str | None = Field(
        default=None, description="客户端完整记录 JSON（无损同步；非同步场景为空）"
    )
    source: str | None = Field(default=None, description="来源（文件名等）")
    status: str = Field(default="active", description="状态：active / archived / deleted")
    similar_matches: list["MatchItem"] = Field(
        default_factory=list,
        description="同类题匹配结果（由 /api/retrieval/match 填充）",
    )


class QuestionListOut(BaseModel):
    """分页列表响应。"""

    page: int = Field(description="当前页码（从 1 开始）")
    total: int = Field(description="符合条件的总条数")
    items: list[QuestionOut] = Field(default_factory=list, description="本页题目列表")


class BatchDeleteRequest(BaseModel):
    """批量删除请求。"""

    ids: list[str] = Field(description="题目 UUID 列表")


class BatchMoveRequest(BaseModel):
    """批量移动知识点请求。"""

    ids: list[str] = Field(description="题目 UUID 列表")
    knowledge_point: str = Field(description="目标知识点名称（替换原知识点）")


class KnowledgePointOut(BaseModel):
    """知识点树节点（层级结构）。"""

    id: int
    name: str
    subject: str
    parent_id: int | None = None
    children: list["KnowledgePointOut"] = Field(default_factory=list)


class QuestionAnalyzeTextRequest(BaseModel):
    """端侧 OCR 文字结构化请求（供本地 ML Kit OCR 后调用，不再上传图片）。"""

    ocr_text: str = Field(default="", description="端侧 OCR 识别出的题目文字")
    subject: str = Field(default="", description="科目（可选，如：数学）")
