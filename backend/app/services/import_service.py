"""
整页试卷批量导入服务（骨架）。

真实流程（由 Agent-D 集成时接线，或后续迭代实现）：
    试卷图片 -> ocr 版面切分（layout.py 检测题目区域）
             -> 逐题裁剪 OCR + texify 公式识别
             -> llm 结构化（structure.py）
             -> 组装 list[QuestionCreate]

本模块当前仅提供契约方法 import_paper()，未接线时抛 NotImplementedError，
保证其它模块可正常 import（不会因重型依赖缺失而失败）。
"""
from __future__ import annotations

from typing import Any

from app.core.logging import get_logger
from app.schemas.question import QuestionCreate

logger = get_logger(__name__)


class ImportService:
    """试卷批量导入入口。"""

    def import_paper(
        self,
        image_bytes: bytes,
        subject: str | None = None,
        filename: str | None = None,
        **kwargs: Any,
    ) -> list[QuestionCreate]:
        """
        解析整页试卷图片为结构化题目列表。

        :param image_bytes: 试卷图片原始字节
        :param subject:     可选，指定科目（缺省由 LLM 推断）
        :param filename:    可选，来源文件名（写入 Question.source）
        :raises NotImplementedError: 尚未接线真实切分流程
        """
        raise NotImplementedError(
            "import_paper 尚未接线：需要 ocr 版面切分 + llm 结构化后返回 "
            "list[QuestionCreate]（由 Agent-D 集成阶段实现）"
        )

    def import_paper_batch(
        self, papers: list[bytes], subject: str | None = None
    ) -> list[QuestionCreate]:
        """批量导入多张试卷（同样为骨架）。"""
        result: list[QuestionCreate] = []
        for i, image_bytes in enumerate(papers, start=1):
            result.extend(self.import_paper(image_bytes, subject=subject))
        return result


# 模块级单例
import_service = ImportService()
