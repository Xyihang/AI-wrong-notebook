# AI 错题本 Pro · AI Wrong Notebook Pro

[中文](#中文) | [English](#english)

> 拍照错题 → AI 结构化 → 自动入库 → 匹配历史同类题 → 艾宾浩斯复习 → 变式组卷。
> 一个为高中生做的「AI 错题闭环」App：Flutter 前端 + FastAPI 后端，支持安卓 / iOS。

![Flutter](https://img.shields.io/badge/Flutter-3.41-blue) ![FastAPI](https://img.shields.io/badge/Backend-FastAPI-009688) ![License](https://img.shields.io/badge/License-PolyForm%20Noncommercial-orange)

---

## 中文

### 它解决什么问题
刷题时错题散落在卷子、照片、聊天记录里，复习时找不到、也不想重抄。这个 App 把「拍一张照片」变成结构化错题（题干 / 答案 / 解析步骤 / 错因 / 知识点），并在之后自动用艾宾浩斯曲线安排复习、生成同类变式题。

### 功能特性
- **拍照录题**：相机/相册 → 自由裁剪 → 识别 → AI 解析（视觉模型直连，或本地 OCR + 文本模型）
- **结构化解析**：题干、标准答案、分步解析、错因、知识点、AI 标签
- **同类题匹配**：入库后自动检索历史同知识点错题，一键回看对比
- **复习闭环**：艾宾浩斯到期提醒、三键反馈（仍不会 / 模糊 / 已掌握）、复习记录
- **AI 变式组卷**：按范围生成一套小卷，可导出 PDF
- **学情看板**：累计/今日新增/掌握率、科目分布、学习连击与成就徽章
- **数据自主**：本地 SQLite 离线可用，支持导入/导出/清空；支持 JSON 备份
- **液态玻璃 UI**：按设备性能分档（高/中/低/关闭），顶栏与底部栏随滚动渐变模糊；支持浅色/深色与 6 套页面背景
- **动态后端**：App 启动时从配置仓库读取后端地址，换服务器无需重新打包
- **游客模式**：不登录也能用（使用自己的 AI Key），数据仅存本机

### 技术栈
| 层 | 技术 |
|---|---|
| 前端 | Flutter 3.41（Riverpod / GoRouter / Drift / Dio） |
| 后端 | Python 3.10+ / FastAPI / SQLAlchemy |
| 识别 | 视觉大模型（OpenAI 兼容，如 DeepSeek）+ 本地 OCR 兜底（RapidOCR） |
| 检索 | 知识点标签 + 文本向量相似度 |
| 存储 | 前端 Drift SQLite（离线）、后端 SQLite |
| 设计 | 自建 Design Token 体系（颜色/字阶/间距/圆角/阴影，双主题） |

### 快速开始
```bash
# 后端
cd backend
pip install -r requirements-slim.txt
cp .env.example .env      # 填入 LLM_API_KEY / LLM_BASE_URL
python -m uvicorn app.main:app --host 0.0.0.0 --port 8000

# 前端
cd frontend
flutter pub get
flutter run                # 或 flutter build apk --release
```

后端地址由配置仓库下发：`Xyihang/ai-wrong-backend-config` 的 `backend-config.json`
（读取顺序：Gitee API → GitHub API → Gitee raw → GitHub raw，失败回退本地缓存/打包默认值）。

### 目录结构
```
frontend/   Flutter 前端（lib/src/features/* 按功能分层）
backend/    FastAPI 后端（OCR / 检索 / 大模型 / 业务 四层解耦）
docs/       规格、计划、架构、部署、iOS 打包、设计规格
design/     UI 设计稿（HTML 样机）
```

### 文档
- 功能规格与接口契约：`docs/spec.md`
- 实施计划：`docs/plan.md`
- 液态玻璃设计规格：`docs/SPEC-LIQUID-GLASS.md`
- UI 美化规格：`docs/SPEC-UI-BEAUTIFY.md`
- 部署与打包：`docs/DEPLOY.md`、`docs/IOS-PACKAGING.md`

### 许可证
**PolyForm Noncommercial License 1.0.0**（见 [`LICENSE`](LICENSE)）：
- ✅ 允许个人学习、研究、实验、非营利机构使用、修改与再分发
- ❌ 禁止任何商业用途（收费产品/服务、企业内部商业化运营等）
- ⚠️ **修改版必须在程序界面显著注明原作者**：
  `Based on AI Wrong Notebook by Xyihang` + 本仓库链接
- 商业授权请联系作者

---

## English

### What it is
An AI-powered "wrong-answer notebook" for high-school students: shoot a photo, get a structured question (stem / answer / step-by-step solution / mistake reason / knowledge points), then review it on a spaced-repetition schedule and practice generated variants.

### Features
- **Capture** – camera/gallery, free crop, OCR, AI analysis (vision model direct, or local OCR + text model)
- **Structured analysis** – stem, answer, steps, mistake reason, knowledge points, AI tags
- **Similar-question matching** – finds your earlier questions on the same knowledge point
- **Review loop** – Ebbinghaus scheduling, three-way feedback (forgot / fuzzy / mastered), history
- **AI paper generator** – build a mini test paper from a scope, export to PDF
- **Learning dashboard** – totals, mastery rate, subject split, streak & badges
- **Local-first data** – offline SQLite, import/export/clear, JSON backup
- **Liquid-glass UI** – tiered by device capability (high/mid/low/off), scroll-reactive blurred bars, light & dark themes, 6 page backgrounds
- **Dynamic backend** – the app resolves its API base URL from a config repo at launch (no rebuild to switch servers)
- **Guest mode** – use your own API key without an account, data stays on device

### Tech stack
Flutter 3.41 (Riverpod / GoRouter / Drift / Dio) · FastAPI · SQLAlchemy · OpenAI-compatible vision LLM · RapidOCR fallback · Drift & SQLite storage · custom design-token system.

### Quick start
```bash
cd backend  && pip install -r requirements-slim.txt && cp .env.example .env             && python -m uvicorn app.main:app --host 0.0.0.0 --port 8000
cd frontend && flutter pub get && flutter run
```

### License
**PolyForm Noncommercial 1.0.0** – free for personal, educational and non-profit use; commercial use is prohibited.
**Modified versions must display, in the app UI**: `Based on AI Wrong Notebook by Xyihang`
together with the link to this repository. See [`LICENSE`](LICENSE) for the full text.

> Copyright (c) 2026 Xyihang. Non-commercial use only.
