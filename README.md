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
- 后端启动与部署（含当前线上服务器）：`backend/README.md` 与 `docs/DEPLOY.md`
- Flutter 各平台打包指南：`docs/DEPLOY.md`
- iOS 打包教程（含签名/ATS 配置）：`docs/IOS-PACKAGING.md`
- 架构图与核心模块说明：`docs/ARCHITECTURE.md`

## 后端地址（无需重新打包即可更换）
App 启动时会从配置仓库读取最新后端地址：
`https://github.com/Xyihang/ai-wrong-backend-config` 的 `backend-config.json`
（失败时使用本地缓存或打包默认值）。

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

## 许可证 / License
本项目采用 **PolyForm Noncommercial License 1.0.0**（详见 [`LICENSE`](LICENSE)）：

- ✅ **允许非商业用途**：个人学习、研究、实验、业余项目，以及学校、公益/公立科研等非营利机构的使用、修改与再分发。
- ❌ **禁止任何商业用途**：不得用于营利性产品或服务、对外收费、企业内部商业化运营、以本软件提供付费服务等。
- ⚠️ 再分发须随附本许可证全文并保留版权声明。
- 如需商业授权，请联系作者另行取得书面许可。

> Copyright (c) 2026 Xyihang. All rights reserved (non-commercial use only).
