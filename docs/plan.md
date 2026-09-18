# 实施计划 — 跨端 AI 错题整理系统

> 来源：`spec.md` v1.0　策略：多 Agent 并行，按目录隔离避免冲突，契约先行（`docs/spec.md` §7 接口 + §7.1 QuestionRecord JSON）。

## 0. 交付目录布局

```
AI-wrong/
├── needs.md                     # 原始需求（只读）
├── docs/
│   ├── spec.md                  # 规格（本计划依据）
│   ├── plan.md                  # 本文件
│   ├── ARCHITECTURE.md          # 架构图 + 模块说明（Agent-D）
│   ├── DATA_MODEL.md            # 数据结构设计（Agent-A）
│   └── DEPLOY.md                # 部署+使用手册（Agent-D）
├── backend/                     # Python FastAPI 后端（新开发，复用三个项目模式）
│   ├── app/
│   │   ├── main.py              # 入口 + CORS + 路由挂载（Agent-D）
│   │   ├── core/{config.py,logging.py}
│   │   ├── schemas/{question.py,ocr.py,retrieval.py,common.py}
│   │   ├── ocr/                 # 复用 convosage 模式（Agent-B）
│   │   │   ├── config.py        # PaddleOCR 参数（检测阈值0.2/unclip2.5/batch6/lang ch,en）
│   │   │   ├── preprocess.py    # 去噪/二值化/倾斜矫正/边缘裁剪
│   │   │   ├── layout.py        # 题目区域检测（版面分析+规则，YOLO接口预留）
│   │   │   ├── slice_dedup.py   # 长图切片 + 重叠去重
│   │   │   ├── paddle_engine.py # PP-OCRv5 封装 + 多版本结果解析
│   │   │   ├── texify_engine.py # 公式→LaTeX（可缺省回退）
│   │   │   └── pipeline.py      # 编排：preprocess→layout→识别→合并
│   │   ├── retrieval/           # 检索层（Agent-C）
│   │   │   ├── vector_store.py  # ChromaDB
│   │   │   ├── embeddings.py    # 文本向量（默认 hash/Jieba 本地；可选 API）
│   │   │   └── matcher.py       # 标签+向量 双重检索
│   │   ├── llm/                 # 大模型层（Agent-C）
│   │   │   ├── client.py        # OpenAI 兼容客户端（DeepSeek/通义）
│   │   │   ├── prompts.py       # 题目提取/结构化/标签 prompt
│   │   │   └── structure.py     # JSON 结构化解析与容错
│   │   ├── db/
│   │   │   ├── models.py        # SQLite schema（借鉴 texts models.py）
│   │   │   ├── session.py       # SQLAlchemy session
│   │   │   └── init_db.py       # 建表/迁移/种子知识点
│   │   └── services/            # 业务层（Agent-A）
│   │       ├── capture_service.py  # OCR→LLM→入库→检索 编排
│   │       ├── question_service.py # CRUD/筛选/批量移动/删除（借鉴 texts question_manager）
│   │       ├── import_service.py   # 整页试卷切分批量导入
│   │       ├── export_service.py   # PDF 导出（reportlab）纯题/带解析/练习卷
│   │       └── settings_service.py # 后端配置
│   ├── requirements.txt
│   ├── .env.example
│   ├── Dockerfile
│   ├── docker-compose.yml
│   └── README.md
├── frontend/                    # Flutter（整体复制自 ai-wrong-notebook + 新增）
│   └── lib/src/
│       ├── data/remote/backend/backend_client.dart   # Dio 封装（Agent-E）
│       ├── data/services/ocr_service.dart            # 改为调后端（Agent-E）
│       ├── data/remote/ai/ai_analysis_service.dart   # 改为调后端（Agent-E）
│       └── features/similar/similar_question_popup.dart  # 同类题弹窗（Agent-F）
└── docs/（见上）
```

## 1. 阶段与 Agent 分工（并行）

> 契约已定（`spec.md`），各 Agent 只写自己负责的目录/文件，互不覆盖。集成由主 Agent 在阶段末统一接线。

### 阶段 A：后端数据与业务骨架（Agent-A）
- 建 `backend/` 骨架、`requirements.txt`、`.env.example`。
- `db/models.py`（SQLite Schema：questions/knowledge_points/question_tags）、`session.py`、`init_db.py`（含中文知识点种子）。
- `schemas/*.py` Pydantic 模型（严格对齐 §7.1 QuestionRecord JSON）。
- `services/question_service.py`（CRUD/筛选/批量移动/删除）、`settings_service.py`、`import_service.py`、`export_service.py` 的接口与骨架。
- 产出 `docs/DATA_MODEL.md`。

### 阶段 B：OCR 流水线模块（Agent-B）
- `ocr/config.py`（复用 convosage 参数）、`preprocess.py`、`layout.py`、`slice_dedup.py`、`paddle_engine.py`（PP-OCRv5 + 多版本解析）、`texify_engine.py`（可缺省）、`pipeline.py`。
- 目标：`ocr_pipeline.recognize(image_bytes) -> {ocr_text, latex_text, blocks, confidence}`。
- 依赖缺失时优雅降级（PaddleOCR 未装→报可用性提示；texify 未装→回退纯 OCR）。

### 阶段 C：检索与大模型层（Agent-C）
- `retrieval/vector_store.py`（ChromaDB）、`embeddings.py`、`matcher.py`（标签精确匹配 + 向量余弦，返回 `matched_by`）。
- `llm/client.py`（OpenAI 兼容，支持 DeepSeek/通义，读 `.env`/设置）、`prompts.py`、`structure.py`（JSON 结构化 + 容错）。

### 阶段 D：后端装配 + 架构文档（Agent-D）
- `main.py`（FastAPI 入口、CORS、`/api/*` 路由挂载、`/health`、`/docs`）。
- `api/` 各路由调用 A/B/C 的服务层装配成 REST（对齐 §7 接口表）。
- `Dockerfile` + `docker-compose.yml` + `backend/README.md`。
- 产出 `docs/ARCHITECTURE.md`、`docs/DEPLOY.md`。

### 阶段 E：Flutter 后端接入（Agent-E）
- 新增 `backend_client.dart`（Dio，读后端 BaseURL 配置）。
- 改 `ocr_service.dart`：调用 `POST /ocr/recognize`。
- 改 `ai_analysis_service.dart`：调用 `POST /questions/analyze`、`POST /retrieval/match`。
- 保持 ai-wrong-notebook 结构/路由/状态管理不变，仅替换数据来源。

### 阶段 F：Flutter 新组件（Agent-F）
- `similar_question_popup.dart`：展示 TopN 同类错题（缩略图/错因/订正答案/时间/相似度）。
- 在分析结果页接线弹窗；新增「查看该知识点全部错题」跳转路由。
- 复用 `katex_math_view.dart` 渲染 LaTeX。

## 2. 依赖顺序
1. Agent-A 先落 `db/models.py` 与 `schemas/`（B/C/D 依赖其字段名与 JSON 结构）→ 其余并行。
2. Agent-D 在 A/B/C 完成核心接口后统一装配 `main.py` 与路由。
3. Agent-E/F 基于 §7 契约与后端并行，不阻塞。

## 3. 集成与验证（主 Agent）
- `python -m compileall backend` 语法检查。
- 启动 `uvicorn` 验证 `/health`、`/docs`、错题 CRUD。
- PaddleOCR/texify 是否可装取决于本机，缺省走降级路径，验证代码可 import。
- Flutter：`flutter pub get` 验证依赖可解析（本机可能无 Flutter SDK，则以结构/代码正确性为准并标注）。

## 4. 里程碑
- M1：spec + plan 完成（本文件）。
- M2：后端四层可运行（A/B/C/D）。
- M3：Flutter 接入 + 新组件（E/F）。
- M4：文档齐全 + 集成验证通过。

## 5. 风险与回退
- 后端依赖重：Docker 化 + CPU 兼容；PaddleOCR 缺失走降级。
- 本机无 Flutter SDK：前端以可编译结构 + 契约正确性为准。
- LLM 无 Key：analyze 降级为纯 OCR 文本入库。
