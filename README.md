# 跨端 AI 错题整理系统（AI Wrong Notebook Pro）

> 基于三份开源项目整合：`ai-wrong-notebook`（Flutter 前端主框架）+ `convosage-tools`（OCR 工程底座）+ `texts-claude-question-bank-system`（题库数据与检索算法）。

## 核心价值
**「拍照错题自动入库 + 新题自动匹配历史同类错题」** — 拍照 → 本地 OCR → AI 结构化 → 一键入库 → 自动弹出历史同类错题，形成学习闭环。

## 目录结构
```
docs/          # 规格(spec.md)、实施计划(plan.md)、架构、数据模型、部署文档
backend/       # Python FastAPI 后端（OCR / 检索 / 大模型 / 业务 四层解耦）
frontend/      # Flutter 跨端前端（复用 ai-wrong-notebook）
needs.md       # 原始需求
```

## 快速导航
- 功能规格与前后端接口契约：`docs/spec.md`
- 实施计划与模块分工：`docs/plan.md`
- 后端启动与 Docker 部署：`backend/README.md` 与 `docs/DEPLOY.md`
- Flutter 各平台打包指南：`docs/DEPLOY.md`
- 架构图与核心模块说明：`docs/ARCHITECTURE.md`

## 技术栈
| 层 | 技术 |
|---|---|
| 前端 | Flutter（Riverpod / GoRouter / Drift / Dio）|
| 后端 | Python 3.10+ / FastAPI / SQLAlchemy |
| OCR | PaddleOCR PP-OCRv5 + texify（公式→LaTeX），本地运行 |
| 向量检索 | ChromaDB（标签匹配 + 文本向量余弦 双重检索）|
| 大模型 | 通用 OpenAI 兼容接口（DeepSeek / 通义千问等）|
| 存储 | 后端 SQLite + ChromaDB；前端 Drift SQLite 离线缓存 |
| 部署 | Docker Compose 一键启动 |
