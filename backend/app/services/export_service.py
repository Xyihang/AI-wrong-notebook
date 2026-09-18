"""
PDF 导出服务（reportlab）—— 美观版。

- build_pdf(questions, mode="plain"|"with_answer")
    纯题版：题干 + 选项；带答案解析版：额外含【答案】与【解析】（浅色框）。
- build_worksheet(questions)
    巩固练习卷：题干后预留答题空行，不含答案。

排版要点：
- 顶部主题色标题带 + 细分隔线；
- 每题带编号圆角徽标（indigo），紧随「题型 · 难度」；灰色小字标注来源（本人错题/AI 变式）与知识点；
- 选项自动 A/B/C…；
- 答案以浅绿底、解析以浅灰底浅框呈现，视觉分区清晰；
- 每页页脚页码。

中文渲染：reportlab 内置 UnicodeCIDFont("STSong-Light")，无需随包字体。
"""
from __future__ import annotations

import io
from typing import Any, Callable, Iterable, List
from xml.sax.saxutils import escape

try:  # 防御性导入
    from reportlab.lib import colors
    from reportlab.lib.enums import TA_CENTER, TA_LEFT
    from reportlab.lib.pagesizes import A4
    from reportlab.lib.styles import ParagraphStyle, getSampleStyleSheet
    from reportlab.lib.units import mm
    from reportlab.pdfbase import pdfmetrics
    from reportlab.pdfbase.cidfonts import UnicodeCIDFont
    from reportlab.platypus import (
        HRFlowable,
        Paragraph,
        SimpleDocTemplate,
        Spacer,
        Table,
        TableStyle,
    )

    _REPORTLAB_AVAILABLE = True
except ImportError:  # pragma: no cover
    _REPORTLAB_AVAILABLE = False

from app.core.logging import get_logger

logger = get_logger(__name__)

_CJK_FONT = "STSong-Light"
_ANSWER_LINE = "答：＿＿＿＿＿＿＿＿＿＿＿＿＿＿＿＿＿＿＿＿＿＿＿＿＿＿＿＿"

# 主题色
_PRIMARY = colors.HexColor("#4F46E5")      # indigo
_PRIMARY_DARK = colors.HexColor("#3730A3")
_ACCENT = colors.HexColor("#F59E0B")        # amber
_TEXT = colors.HexColor("#1F2937")
_MUTED = colors.HexColor("#6B7280")
_ANSWER_BG = colors.HexColor("#F0FDF4")
_ANSWER_BORDER = colors.HexColor("#BBF7D0")
_ANALYSIS_BG = colors.HexColor("#F8FAFC")
_ANALYSIS_BORDER = colors.HexColor("#E2E8F0")
_RULE = colors.HexColor("#E5E7EB")


def _ensure_reportlab() -> None:
    if not _REPORTLAB_AVAILABLE:
        raise RuntimeError(
            "reportlab 未安装，无法导出 PDF。请先执行: pip install reportlab"
        )
    if _CJK_FONT not in pdfmetrics.getRegisteredFontNames():
        pdfmetrics.registerFont(UnicodeCIDFont(_CJK_FONT))


def _as_dict(q: Any) -> dict[str, Any]:
    if isinstance(q, dict):
        return q
    if hasattr(q, "model_dump"):
        return q.model_dump()
    if hasattr(q, "__dict__"):
        return vars(q)
    return {}


def _text(q: dict[str, Any], key: str, default: str = "") -> str:
    v = q.get(key, default)
    if isinstance(v, (list, tuple)):
        v = " ".join(str(x) for x in v)
    if v is None:
        return default
    return str(v).strip()


def _esc(text: str) -> str:
    return escape(text) if text else ""


def _num(value: Any, fallback: int = 0) -> int:
    try:
        return int(value)
    except (TypeError, ValueError):
        return fallback


def _source_label(q: dict[str, Any]) -> str:
    source = (q.get("source") or "").strip()
    if source == "existing":
        return "本人错题"
    if source == "ai":
        return "AI 变式"
    return ""


def _make_styles() -> dict[str, ParagraphStyle]:
    base = getSampleStyleSheet()
    return {
        # 标题带（白字 on indigo）
        "title": ParagraphStyle(
            "CJKTitle", parent=base["Normal"], fontName=_CJK_FONT,
            fontSize=19, leading=24, alignment=TA_CENTER,
            textColor=colors.white,
            backColor=_PRIMARY, borderPadding=(6, 0, 6, 0),
            spaceBefore=0, spaceAfter=0,
        ),
        "subtitle": ParagraphStyle(
            "CJKSubtitle", parent=base["Normal"], fontName=_CJK_FONT,
            fontSize=9.5, alignment=TA_CENTER,
            textColor=_MUTED, spaceBefore=2 * mm, spaceAfter=2 * mm,
        ),
        # 题干 / 正文
        "body": ParagraphStyle(
            "CJKBody", parent=base["Normal"], fontName=_CJK_FONT,
            fontSize=11, leading=17, textColor=_TEXT,
            spaceBefore=2 * mm, spaceAfter=1 * mm,
        ),
        "option": ParagraphStyle(
            "CJKOption", parent=base["Normal"], fontName=_CJK_FONT,
            fontSize=11, leading=16, textColor=_TEXT,
            leftIndent=10 * mm, spaceAfter=0.5 * mm,
        ),
        # 头部元信息小字
        "meta": ParagraphStyle(
            "CJKMeta", parent=base["Normal"], fontName=_CJK_FONT,
            fontSize=8.5, leading=11, textColor=_MUTED,
            spaceBefore=0.5 * mm,
        ),
        # 答案框（浅绿）
        "answer": ParagraphStyle(
            "CJKAnswer", parent=base["Normal"], fontName=_CJK_FONT,
            fontSize=10.5, leading=16, textColor=colors.HexColor("#14532D"),
            backColor=_ANSWER_BG, borderColor=_ANSWER_BORDER,
            borderWidth=0.8, borderPadding=(5, 6, 5, 6),
            spaceBefore=2 * mm,
        ),
        # 解析框（浅灰）
        "analysis": ParagraphStyle(
            "CJKAnalysis", parent=base["Normal"], fontName=_CJK_FONT,
            fontSize=10, leading=15, textColor=colors.HexColor("#334155"),
            backColor=_ANALYSIS_BG, borderColor=_ANALYSIS_BORDER,
            borderWidth=0.6, borderPadding=(5, 6, 5, 6),
            spaceBefore=2 * mm,
        ),
        # 题号徽标数字（白）
        "badge": ParagraphStyle(
            "CJKBadge", parent=base["Normal"], fontName="Helvetica-Bold",
            fontSize=12, alignment=TA_CENTER, textColor=colors.white,
            leading=12,
        ),
        # 题型·难度（题号右侧，加粗）
        "qhead": ParagraphStyle(
            "CJKQHead", parent=base["Normal"], fontName=_CJK_FONT,
            fontSize=12, leading=15, textColor=_TEXT,
        ),
        # worksheet 答题行
        "answerline": ParagraphStyle(
            "CJKAnswerLine", parent=base["Normal"], fontName=_CJK_FONT,
            fontSize=11, textColor=_TEXT, spaceBefore=4 * mm,
        ),
    }


def _qhead_label(q: dict[str, Any]) -> str:
    parts = []
    t = _text(q, "question_type")
    if t:
        parts.append(t)
    d = _text(q, "difficulty")
    if d:
        parts.append(d)
    return " · ".join(parts) or "题目"


def _meta_label(q: dict[str, Any]) -> str:
    meta = []
    subj = _text(q, "subject")
    if subj:
        meta.append(subj)
    kps = [str(k) for k in (q.get("knowledge_points") or []) if str(k).strip()]
    if kps:
        meta.append(" / ".join(kps[:4]))
    src = _source_label(q)
    if src:
        # 来源用色块文字区分
        color = "#C2410C" if src == "本人错题" else "#4F46E5"
        meta.append(f'<font color="{color}">{_esc(src)}</font>')
    return "　·　".join(meta)


def _question_block(
    q: dict[str, Any],
    idx: int,
    styles: dict[str, ParagraphStyle],
    with_answer: bool,
    worksheet: bool,
):
    """一道题的完整 platypus 流：编号徽标行 + 题干 + 选项 + （答案/解析框）。"""
    items = []
    # 编号徽标 + 题型·难度 放在一个两列 Table（左侧小方块填色）
    badge = Paragraph(_esc(str(idx)), styles["badge"])
    head = Paragraph(f"<b>{_esc(_qhead_label(q))}</b>", styles["qhead"])
    meta = Paragraph(_meta_label(q), styles["meta"])
    header = Table(
        [[badge, [head, meta]]],
        colWidths=[7 * mm, None],
    )
    header.setStyle(TableStyle([
        ("VALIGN", (0, 0), (0, 0), "MIDDLE"),
        ("VALIGN", (1, 0), (1, 0), "TOP"),
        ("BACKGROUND", (0, 0), (0, 0), _PRIMARY),
        ("LEFTPADDING", (0, 0), (0, 0), 0),
        ("RIGHTPADDING", (0, 0), (0, 0), 0),
        ("TOPPADDING", (0, 0), (0, 0), 2 * mm),
        ("BOTTOMPADDING", (0, 0), (0, 0), 2 * mm),
        ("TOPPADDING", (1, 0), (1, 0), 0),
        ("LEFTPADDING", (1, 0), (1, 0), 3 * mm),
        ("TOPPADDING", (0, 0), (1, 0), 0),
    ]))
    items.append(header)
    items.append(Spacer(1, 2 * mm))

    # 题干
    stem = _text(q, "stem") or "（无题干）"
    items.append(Paragraph(_esc(stem), styles["body"]))

    # 选项
    options = q.get("options") or []
    for opt_idx, opt in enumerate(options, start=1):
        letter = chr(64 + opt_idx)
        items.append(
            Paragraph(_esc(f"{letter}. {str(opt)}"), styles["option"])
        )

    if worksheet:
        items.append(Paragraph(_esc(_ANSWER_LINE), styles["answerline"]))
        items.append(Spacer(1, 9 * mm))
    elif with_answer:
        if _text(q, "answer"):
            items.append(
                Paragraph(
                    f'<b>【答案】</b>{_esc(_text(q, "answer"))}',
                    styles["answer"],
                )
            )
        if _text(q, "analysis"):
            items.append(
                Paragraph(
                    f'<b>【解析】</b>{_esc(_text(q, "analysis"))}',
                    styles["analysis"],
                )
            )
        if _text(q, "mistake_reason"):
            items.append(
                Paragraph(
                    f'<font color="#B91C1C"><b>【错因】</b></font>'
                    f'{_esc(_text(q, "mistake_reason"))}',
                    styles["analysis"],
                )
            )
    return items


def _build_document(
    questions: list[dict[str, Any]],
    title: str,
    subtitle: str,
    with_answer: bool,
    worksheet: bool,
) -> bytes:
    _ensure_reportlab()
    if not questions:
        raise ValueError("没有可导出的题目")

    buf = io.BytesIO()
    doc = SimpleDocTemplate(
        buf,
        pagesize=A4,
        leftMargin=18 * mm, rightMargin=18 * mm,
        topMargin=16 * mm, bottomMargin=18 * mm,
        title=title, author="AI-Wrong",
    )
    styles = _make_styles()

    def _footer(canvas: Any, _doc: Any) -> None:
        canvas.saveState()
        canvas.setStrokeColor(_RULE)
        canvas.setLineWidth(0.5)
        canvas.line(18 * mm, 14 * mm, A4[0] - 18 * mm, 14 * mm)
        canvas.setFont("Helvetica", 8.5)
        canvas.setFillColor(_MUTED)
        canvas.drawCentredString(A4[0] / 2, 10 * mm, f"- {canvas.getPageNumber()} -")
        canvas.restoreState()

    story: List[Any] = []

    # 顶部：标题色带
    title_p = Paragraph(_esc(title), styles["title"])
    title_tbl = Table([[title_p]], colWidths=[doc.width])
    title_tbl.setStyle(TableStyle([
        ("BACKGROUND", (0, 0), (0, 0), _PRIMARY),
        ("LEFTPADDING", (0, 0), (0, 0), 0),
        ("RIGHTPADDING", (0, 0), (0, 0), 0),
    ]))
    story.append(title_tbl)
    story.append(Spacer(1, 2 * mm))

    if subtitle:
        story.append(Paragraph(_esc(subtitle), styles["subtitle"]))
    # 主题色细线
    story.append(HRFlowable(width="100%", thickness=1.2,
                            color=_ACCENT, spaceBefore=2 * mm, spaceAfter=4 * mm))

    for idx, q in enumerate(questions, start=1):
        story.extend(_question_block(q, idx, styles, with_answer, worksheet))
        if idx < len(questions):
            story.append(Spacer(1, 6 * mm))
            story.append(HRFlowable(width="100%", thickness=0.4,
                                    color=_RULE, spaceBefore=0, spaceAfter=4 * mm))

    doc.build(story, onFirstPage=_footer, onLaterPages=_footer)
    return buf.getvalue()


def build_pdf(
    questions: Iterable[Any], mode: str = "plain"
) -> bytes:
    """
    导出 PDF 字节流。

    :param questions: QuestionOut / dict 列表
    :param mode:      "plain"（纯题）| "with_answer"（含答案解析）
    """
    mode = (mode or "plain").strip().lower()
    if mode not in ("plain", "with_answer"):
        raise ValueError(f"mode 取值非法: {mode!r}（可选: plain / with_answer）")

    qs = [_as_dict(q) for q in questions]
    return _build_document(
        qs,
        title="错题本",
        subtitle=f"共 {len(qs)} 题 · {'纯题版' if mode == 'plain' else '含答案解析版'}",
        with_answer=(mode == "with_answer"),
        worksheet=False,
    )


def build_worksheet(questions: Iterable[Any]) -> bytes:
    """导出巩固练习卷（题干后留答题空行，不含答案）。"""
    qs = [_as_dict(q) for q in questions]
    kp_names = []
    for q in qs:
        for k in q.get("knowledge_points") or []:
            if str(k).strip() and str(k) not in kp_names:
                kp_names.append(str(k))
    subtitle = (
        f"共 {len(qs)} 题 · 知识点：{'、'.join(kp_names[:8])}"
        if kp_names
        else f"共 {len(qs)} 题"
    )
    return _build_document(
        qs,
        title="巩固练习卷",
        subtitle=subtitle,
        with_answer=False,
        worksheet=True,
    )
