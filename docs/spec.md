# 功能规格文档 — 跨端 AI 错题整理系统

> 版本：v1.0　状态：已评审　来源需求：`needs.md` + 三份开源源码实测分析

## 1. 概述

### 1.1 背景
学生整理错题成本高、同类错题难以主动关联。本项目以三份已下载开源项目为基础，打造一套「**拍照错题自动入库 + 新题自动匹配历史同类错题**」的跨端 AI 错题整理系统。

### 1.2 目标
- 拍照 → 本地 OCR → AI 结构化 → 一键入库 → 自动检索同类历史错题，形成学习闭环。
- 前后端完全分离：Flutter 跨端前端 + Python FastAPI 后端微服务。
- 最大化复用三份源码的工程结构、OCR 工程化模式、题库数据结构与检索算法。

### 1.3 范围（本系统交付物）
1. **Flutter 前端工程**（复用 ai-wrong-notebook，标注新增代码）。
2. **Python FastAPI 后端工程**（OCR/检索/大模型/业务四层解耦）。
3. 设计文档、部署文档、操作手册、后续优化建议。

---

## 2. 三份源码复用边界（经源码实测确认）

### 2.1 convosage-tools（bubble_ocr 分支）→ 后端 OCR 工程底座
| 复用点 | 实测来源文件 | 落地方式 |
|---|---|---|
| PaddleOCR 两步法（区域检测→区域裁剪→逐块识别）工程架构 | `tools/bubble_ocr_recognizer/bubble_ocr_fullimg_ocr.py` | `backend/app/ocr/` 重构为通用 OCR 流水线 |
| PaddleOCR 集成、参数调优（检测阈值 0.2、unclip 2.5、batch 6、lang ch/en） | `config.yaml` + `bubble_ocr_fullimg_ocr.py` | 参数收敛到 `backend/app/ocr/config.py` |
| 长图切片与重叠去重 | README「长文本/长图」工程化说明 | 新增 `slice.py` + `dedup.py` |
| OCR 返回格式多版本解析（list/dict 兼容） | `_parse_ocr_results()` | 保留到 `paddle_engine.py` |
| 图片预处理：去噪、二值化、倾斜矫正、边缘裁剪 | README 工程经验 | 新增 `preprocess.py` |
| **不复用**：微信气泡检测业务逻辑、气泡模型、聊天上层功能、前端 UI | — | 全部丢弃；题目区域检测改用版面分析+规则 |

### 2.2 ai-wrong-notebook → Flutter 前端主框架 + 交互流程
| 复用点 | 实测来源文件 | 落地方式 |
|---|---|---|
| 工程目录结构、依赖、多端编译配置 | `pubspec.yaml`、`lib/` | 整体复制到 `frontend/`，新增代码按 `lib/src/` 分层 |
| 路由体系（GoRouter）、状态管理（Riverpod）、主题 | `lib/src/app/` | 原样保留 |
| 原生能力封装：摄像头、相册、裁剪、文件存储 | `capture_service.dart`、`image_crop_screen.dart`、`image_storage_service.dart` | 原样保留 |
| 错题核心页面：拍照/列表/详情/分类/导出 | `features/capture|notebook|analysis|settings/` | 原样保留 |
| LaTeX 渲染 | `katex_math_view.dart`、`flutter_math_fork`、`assets/katex` | 原样保留 |
| 拍照→识别→打标签→入库→查看同类题 交互流程 | `question_analysis_pipeline.dart`、`analysis_loading_screen.dart` | 保留，OCR/分析替换为后端调用 |
| **替换**：外部 AI 视觉 OCR（当前 OcrService 已停用） | `ocr_service.dart` | 改为调用本地后端 OCR 服务 |
| **替换**：简单标签匹配 | — | 改为后端「标签+向量」双重检索 |
| **替换**：强绑定大模型 SDK | `ai_analysis_service.dart`（OpenAI 兼容，保留） | 保留 OpenAI 兼容思路，转由后端统一封装 |

### 2.3 texts-claude-question-bank-system → 题库数据结构与检索算法
| 复用点 | 实测来源文件 | 落地方式 |
|---|---|---|
| 题目结构化 Schema：科目/知识点/题型/难度/题干/答案/解析/错因 | `backend/database/models.py` | 收敛到后端 SQLite schema |
| 多层级知识点标签体系 | `Tag(question_tag_association)` | 收敛为 `knowledge_points` 层级 + `tags` |
| 相似度检索算法设计 | `question_manager.search_questions` | 升级为「标签匹配 + 向量相似度」双重检索 |
| 批量导入/导出/组卷逻辑 | `question_manager.batch_import_questions` | 保留到后端 `services/question_service.py` |
| **不复用**：Claude 强绑定 | `backend/ai/ai_providers.py` | 改为通用 OpenAI 兼容接口 |
| **不复用**：Flask Web 前端 | `frontend/` | 丢弃，能力整合进 Flutter 端 |

---

## 3. 用户故事
- 作为学生，我希望拍照错题后系统自动识别并入库，以便无需手动录入。
- 作为学生，我希望新错题自动弹出历史同类错题，以便举一反三、集中攻克薄弱点。
- 作为学生，我希望按科目/知识点/掌握程度筛选与管理错题，以便针对性复习。
- 作为老师/学生，我希望按知识点导出 PDF 或巩固练习卷，以便线下复习。

---

## 4. 功能需求

### 4.1 功能清单
| 功能模块 | 优先级 | 描述 |
|---|---|---|
| 拍照错题一键自动入库 | P0 | 相机/相册 → 端侧裁剪矫正 → 后端 OCR → AI 结构化 → 入库 |
| 同类题自动匹配 | P0 | OCR 完成后后端自动检索 TopN 同类错题并弹窗 |
| 错题本管理 | P1 | 多维度筛选、编辑、打标、掌握程度、批量删除/移动 |
| 数学公式识别与渲染 | P1 | 后端 texify→LaTeX，前端 flutter_math_fork/katex 渲染 |
| 导出与分享 | P1 | PDF 纯题/带解析两版，按知识点生成巩固练习卷 |
| 试卷批量导入 | P2 | 整页试卷图片自动切分多题批量入库 |
| 同步能力 | P2 | 本地 SQLite，预留多设备同步接口 |

### 4.2 详细规格

#### F1 拍照一键入库（P0）
- **输入**：设备图片（相机/相册），可选端侧裁剪。
- **处理**：
  1. 端侧基础裁剪/旋转矫正 → 上传后端。
  2. 后端 OCR 流水线：预处理 → 版面切分题目区域 → 逐块识别（PaddleOCR PP-OCRv5）→ 长图切片去重 → texify 公式识别 → 合并结构化文本。
  3. 大模型层提取：科目、知识点、题型、难度、题干、答案、解析、错因，输出 JSON。
- **输出**：`QuestionRecord` 完整结构化数据 + 原图/OCR 文本/标签，端侧缓存支持离线查看。
- **异常处理**：OCR 空结果→报「未识别到文字」；LLM 不可用→降级仅存 OCR 文本。

#### F2 同类题自动匹配（P0，核心亮点）
- **处理**：入库前/后调用 `/api/retrieval/match`，用「知识点标签精确匹配 + 文本向量余弦相似度（ChromaDB）」双重机制，返回 TopN。
- **输出**：按相似度排序的历史错题，含原题缩略图、错因、订正答案、收录时间。
- **交互**：Flutter 自动弹窗展示；可一键跳转该知识点全部历史错题。

#### F3 错题本管理（P1）
- 多维度筛选：科目、知识点、时间、掌握程度（已掌握/未掌握/需巩固）。
- 编辑题目信息、改标签、标记掌握程度；批量删除、批量移动知识点。

#### F4 公式识别与渲染（P1）
- 后端 texify 识别数学公式输出 LaTeX；前端 `flutter_math_fork` + katex webview 渲染。

#### F5 导出与分享（P1）
- PDF 导出两模式：纯题目版 / 带答案解析版；按知识点筛选生成巩固练习卷。

#### F6 试卷批量导入（P2）
- 上传整页试卷图 → 版面切分自动拆多题 → 批量入库。

#### F7 同步（P2）
- 本地 SQLite 单设备；`SyncService` 预留扩展接口。

---

## 5. 非功能需求
- **性能**：单题 OCR+分析目标 < 15s；检索 TopN < 1s。
- **本地优先**：OCR、检索、存储全部本地运行；仅大模型结构化可配置外部 API。
- **中文适配**：中文试卷、中文手写、国内教材知识点体系。
- **跨端一致**：Flutter Android/iOS/Windows/macOS 交互一致。
- **可扩展**：预留替换 OCR 引擎、接入本地大模型、扩展科目题型的接口。
- **配置化**：模型、Key、BaseURL 通过 `.env`/后端 `/api/settings` 配置。

---

## 6. 数据规格

### 6.1 后端 SQLite 核心表（借鉴 texts `models.py` + 错题本字段）
```text
questions
  id, subject, knowledge_points(JSON 多级), question_type, difficulty,
  stem(题干), options(JSON), answer, analysis, mistake_reason,
  source, status, mastery(未掌握/已掌握/需巩固),
  image_path, ocr_text, latex_text, tags(JSON),
  created_at, updated_at, sync_version

knowledge_points  多层级知识点标签体系（texts Tag 思想）
  id, name, parent_id, subject

question_tags     question_id × knowledge_point_id  多对多
```

### 6.2 ChromaDB 向量库
- Collection：`questions`；embedding 文本 = `stem + 知识点 + 题型`。
- Metadata：`question_id, subject, knowledge_points, tags, created_at, image_path`。
- 主键对齐 SQLite `id`。

### 6.3 Flutter 端缓存
复用 ai-wrong-notebook 的 Drift SQLite（`QuestionRecords` 表）+ 原图文件存储；同步远端结构映射。

---

## 7. 接口规格（前后端契约，各并行 Agent 遵循）

Base URL：`http://<host>:8000/api`

| 方法 | 路径 | 说明 | 请求/响应要点 |
|---|---|---|---|
| POST | `/ocr/recognize` | 上传图片→结构化 OCR | multipart `file` → `{ocr_text, latex_text, blocks[], confidence}` |
| POST | `/questions/analyze` | OCR+AI 结构化 | multipart `file`+`subject?` → `QuestionRecord JSON` |
| POST | `/questions` | 保存错题 | QuestionRecord JSON → `{id}` |
| GET | `/questions` | 列表/筛选 | query `subject/kp/type/mastery/keyword/page` |
| GET | `/questions/{id}` | 详情 | — |
| PUT/PATCH | `/questions/{id}` | 编辑/打标/掌握程度 | 部分字段 |
| DELETE | `/questions` | 批量删除 | body `{ids:[]}` |
| POST | `/questions/batch-move` | 批量移动知识点 | body `{ids:[], knowledge_point}` |
| POST | `/retrieval/match` | 同类题匹配（标签+向量） | `{text, knowledge_points, top_n}` → `{items:[{question, similarity, matched_by}]}` |
| GET | `/knowledge-points` | 知识点树 | → 层级树 |
| POST | `/import/paper` | 整页试卷批量导入 | multipart `file` → 切分结果 |
| GET | `/export/pdf` | 导出 PDF | query `mode=plain|with_answer` + 筛选 |
| GET | `/export/worksheet` | 巩固练习卷 | query 知识点筛选 |
| GET/PUT | `/settings` | 后端配置（模型/Key） | — |
| GET | `/health` | 健康检查 | → `{status}` |

统一错误格式：`{"detail": "<msg>"}`，HTTP 4xx/5xx。

### 7.1 QuestionRecord JSON（前后端共享）
```json
{
  "id": "uuid",
  "subject": "数学",
  "knowledge_points": ["初中", "几何", "圆"],
  "question_type": "解答题",
  "difficulty": "中等",
  "stem": "题干文本",
  "options": [],
  "answer": "答案",
  "analysis": "解析",
  "mistake_reason": "错因",
  "mastery": "未掌握",
  "tags": ["圆"],
  "image_path": "url/path",
  "ocr_text": "OCR原文",
  "latex_text": "LaTeX",
  "created_at": "ISO8601",
  "similar_matches": [{"question": {...}, "similarity": 0.9, "matched_by": "vector|tag|both"}]
}
```

---

## 8. 验收标准
- [ ] 后端服务可 `uvicorn` 启动，`/health` 返回 200；`/docs`(OpenAPI) 可用。
- [ ] `/ocr/recognize` 对中文印刷体图片返回非空 `ocr_text`。
- [ ] `/questions/analyze` 返回完整 QuestionRecord 结构（LLM 配置后）。
- [ ] `/retrieval/match` 在库中命中相似题并返回 `matched_by`。
- [ ] 错题 CRUD、筛选、批量删除/移动接口通过。
- [ ] `/export/pdf` 生成含题目/答案解析的 PDF。
- [ ] Flutter 工程可 `flutter pub get` + 结构完整，OCR/分析/检索接入后端。
- [ ] Docker Compose 一键启动后端。

---

## 9. 风险与依赖
- PaddleOCR / texify / torch / chromadb 依赖较重，Docker 镜像大；提供 CPU 可运行版本。
- texify 为可选项，缺省回退纯 PaddleOCR + 文本。
- LLM Key 需用户自行配置（DeepSeek/通义等 OpenAI 兼容）。
- 原 Flutter 工程含较多私有业务（如一致性复核），保留但标记复用边界，避免过度重构。

## 10. 明确不做（Won't Have）
- 微信聊天气泡识别。
- 题库独立后台 UI（能力并入 Flutter）。
- 首次接入即强制多端云同步（仅预留接口）。
- 预训练题目检测 YOLO 模型（第一期用版面规则，预留微调接口）。
