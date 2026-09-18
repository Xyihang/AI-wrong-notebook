# 系统架构文档（ARCHITECTURE）

> 版本：v1.0　对应 `docs/spec.md`　维护：Agent-D（后端装配 + 架构）

## 1. 总体架构

前后端完全分离：**Flutter 跨端前端**（拍照 / 展示 / 交互）＋ **Python FastAPI 后端微服务**（OCR / 检索 / 大模型 / 业务四层解耦），通过 REST（Base URL `http://<host>:8000/api`）通信。

```
┌─────────────────────────────────────────────────────────────────────────┐
│                              Flutter 前端（跨端）                          │
│  ai-wrong-notebook 复用：路由(GoRouter)/状态(Riverpod)/拍照/裁剪/LaTeX渲染  │
│  ┌──────────────┐ ┌──────────────┐ ┌──────────────┐ ┌────────────────┐   │
│  │ 拍照/相册页    │ │ 分析加载页    │ │ 错题本列表/详情│ │ 同类题弹窗       │   │
│  └──────┬───────┘ └──────┬───────┘ └──────┬───────┘ └───────┬────────┘   │
│         │ 图片(裁剪后)     │                │                 │             │
└─────────┼────────────────┼────────────────┼─────────────────┼─────────────┘
          │                │                │                 │
          │ POST /ocr/     │ POST /questions│ GET /questions  │ POST /retrieval/
          │ recognize      │ /analyze       │ .../export/pdf  │ match
          ▼                ▼                ▼                 ▼
┌─────────────────────────────────────────────────────────────────────────┐
│                     FastAPI 后端（Python 3.10 + uvicorn）                  │
│  app/main.py（CORS / lifespan: init_db + 检索索引注入）                    │
│  app/api/ 路由层（ServiceError→HTTPException；get_db 注入；向量库同步）      │
│  ┌──────────────┐ ┌──────────────┐ ┌──────────────┐ ┌────────────────┐   │
│  │ ocr/ 流水线    │ │ retrieval/   │ │ llm/ 大模型层  │ │ services/ 业务层 │   │
│  │ preprocess→   │ │ embeddings→  │ │ client(OpenAI│ │ question/settings│  │
│  │ layout→切片→   │ │ vector_store │ │ 兼容)→structure│ │ /import/export  │   │
│  │ PaddleOCR→    │ │ →matcher     │ │ (JSON容错+    │ │                 │   │
│  │ texify        │ │ (标签+向量)    │ │  规则降级)     │ │                 │   │
│  └──────┬───────┘ └──────┬───────┘ └──────┬───────┘ └───────┬────────┘   │
│         │                │                │                 │             │
│         ▼                ▼                ▼                 ▼             │
│  ┌──────────────┐  ┌──────────────┐                 ┌────────────────┐   │
│  │ SQLite        │  │ ChromaDB      │                 │ 外部大模型 API   │   │
│  │ questions/    │  │ collection:   │                 │ DeepSeek/通义    │   │
│  │ knowledge_    │  │ questions     │                 │ (OpenAI兼容)     │   │
│  │ points/       │  │ (降级:内存索引) │                 │                │   │
│  │ question_tags │  └──────────────┘                 └────────────────┘   │
│  └──────────────┘                                                        │
└─────────────────────────────────────────────────────────────────────────┘
```

## 2. 分层职责

| 层 | 模块 | 职责 | 复用来源 |
|---|---|---|---|
| 路由层 | `app/api/*` | REST 装配、参数校验、ServiceError→HTTPException、get_db 注入、SQLite↔向量库同步 | 新开发 |
| 业务层 | `app/services/` | 题目 CRUD/筛选/批量操作、运行时设置、PDF 导出、试卷导入（骨架） | texts-claude-question-bank-system 的 `question_manager.py` 思路 |
| OCR 层 | `app/ocr/` | 图片预处理→版面切分→长图切片去重→PaddleOCR→texify 公式 | convosage-tools（bubble_ocr 分支）两步法工程架构 |
| 检索层 | `app/retrieval/` | 文本向量化（local 哈希/API）、ChromaDB 向量库、标签+向量双重匹配 | texts 的 `search_questions` 检索思路升级为双重检索 |
| 大模型层 | `app/llm/` | OpenAI 兼容客户端、提示词、JSON 结构化容错、规则降级 | ai-wrong-notebook 的 OpenAI 兼容 `ai_analysis_service` 思路 |
| 数据层 | `app/db/` + `app/schemas/` | SQLite ORM、建表/种子知识点、Pydantic 契约（QuestionRecord） | texts 的 `models.py` schema |

## 3. 核心模块说明

### 3.1 OCR 流水线（`app/ocr/`，复用 convosage-tools bubble_ocr）

```
image_bytes → preprocess(去噪/二值化/倾斜矫正/边缘裁剪)
            → layout.detect(水平/垂直投影版面切分题目区域, 预留 YOLO 接口)
            → slice_long_image(>2000px 长图重叠切片) + dedup_blocks(重叠去重)
            → paddle_engine.recognize(PP-OCRv5, ch+en, 检测阈值0.2/unclip 2.5/batch 6)
            → 按版面顺序合并 ocr_text + 平均 confidence
            → texify_engine(可选) → latex_text
```

- 入口：`ocr_pipeline.recognize(image_bytes) -> {ocr_text, latex_text, blocks, confidence}`
- 优雅降级：PaddleOCR/texify 缺失时流水线仍返回结构（空文本），**import app.ocr 永不因重型依赖崩溃**。

### 3.2 双重检索（`app/retrieval/`，标签 + 向量）

```
new_question ──┬─ 标签通道：knowledge_points 与库内题目交集 ≥1 → matched_by="tag"
               └─ 向量通道：compose_embedding_text(stem+知识点+题型) → 余弦相似度
                               → matched_by="vector"
               合并打分：combined = clamp(tag_bonus + vec_score) → 按 similarity 降序 top_n
               双命中 → matched_by="both"
```

- 向量库：ChromaDB（collection `questions`，cosine 空间）；缺失时降级为**纯 Python 内存余弦索引**，接口签名一致。
- 嵌入：默认 `local` 确定性哈希（离线、零依赖）；可配 `api` 模式走外部 embedding 接口。
- 索引来源：启动时（`wire_retrieval_index_provider`）把 SQLite active 题目注入标签通道，标签匹配不依赖向量库内容。

### 3.3 大模型结构化（`app/llm/`，OpenAI 兼容）

```
ocr_text ──► available()? ── 是 ──► extraction prompt ──► chat ──► parse_question_json(容错)
              │                                              │
              └── 否 / 失败 ───────────────────────────► rule_based_analyze(仅存 OCR 文本)
```

- `parse_question_json`：去 ```json 围栏 → 定位首个平衡 {...} → 字段规整（枚举校验/列表强转）。
- `merge_ocr_fallback`：LLM 缺字段时用 OCR 原文补齐 stem。
- 客户端：POST `{base}/chat/completions`，失败自动重试一次；DeepSeek / 通义等任意 OpenAI 兼容端点。

### 3.4 数据一致性约定

- **对外标识**：QuestionRecord `id` = `questions.uuid`（字符串 UUID）；int 主键仅内部使用。
- **SQLite ↔ 向量库同步**（路由层执行，`app/api/deps.py`）：
  - create / update / batch-move 后 → `retrieval_service.upsert_question(out.model_dump(mode="json"))`
  - delete 后 → `retrieval_service.delete(ids)`
  - 向量库失败仅告警，不影响主流程。

## 4. P0 主流程：拍照入库 + 同类题匹配

```
拍照/相册 ─► 端侧裁剪/矫正 ─► POST /api/questions/analyze (multipart file + subject?)
   │
   ├─ ocr_pipeline.recognize ──► ocr_text / latex_text / blocks
   ├─ llm_service.analyze_question ──► QuestionRecord dict（LLM 不可用→规则降级）
   ├─ 构造临时 QuestionOut（uuid + created_at）
   └─ retrieval_service.match(新题, top_n=5) ──► similar_matches 挂到响应
           │
           ▼
   前端预览结构化结果 + 弹出同类错题（缩略图/错因/订正答案/相似度）
           │
           ▼ 用户确认保存
POST /api/questions (QuestionCreate) ─► question_service.create ─► SQLite
                                        └─► retrieval_service.upsert_question（向量库同步）
           │
           ▼ 后续
GET /api/questions?...（筛选）/ PATCH（编辑/打标/掌握程度）/ DELETE（批量）
GET /api/export/pdf|worksheet（线下复习）/ POST /api/retrieval/match（随时手动检索）
```

## 5. 依赖与降级矩阵

| 组件 | 依赖 | 缺失时 |
|---|---|---|
| Web | fastapi / uvicorn / pydantic / pydantic-settings | 服务不可用（必需） |
| DB | SQLAlchemy | 服务不可用（必需） |
| 图像基础 | numpy / opencv-python-headless / Pillow | OCR 层不可用（必需） |
| 向量库 | chromadb | 降级内存余弦索引 |
| 中文字体 PDF | reportlab | 导出 500（提示安装） |
| 中文 OCR | paddlepaddle / paddleocr（可选） | OCR 返回空文本 |
| 公式 LaTeX | texify / torch（可选） | latex_text 为空 |
| 大模型 | requests + 外部 API Key（可选） | analyze 规则降级 |

## 6. 复用来源对照（spec §2）

| 来源项目 | 复用什么 | 落地位置 |
|---|---|---|
| convosage-tools（bubble_ocr 分支） | PaddleOCR 两步法架构、参数（阈值0.2/unclip2.5/batch6）、长图切片去重、多版本结果解析、预处理 | `backend/app/ocr/` |
| ai-wrong-notebook | Flutter 工程骨架、路由/状态管理、拍照/裁剪/存储、LaTeX 渲染、分析交互流程 | `frontend/` |
| texts-claude-question-bank-system | 题目 schema、知识点标签体系、批量导入/导出/检索算法 | `backend/app/db/models.py`、`app/services/question_service.py`、`app/retrieval/` |
