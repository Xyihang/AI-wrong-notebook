# AI-Wrong 后端（FastAPI）

跨端 AI 错题整理系统的后端服务：**拍照错题自动入库 + 新题自动匹配历史同类错题**。

技术栈：FastAPI + SQLAlchemy 2.0（SQLite）+ ChromaDB（向量库）+ PaddleOCR/texify（OCR）+ OpenAI 兼容大模型（结构化）。

## 快速开始（本地开发）

```bash
cd backend

# 1. 创建虚拟环境并安装核心依赖（Python 3.10+）
python -m venv .venv
# Windows:
.venv\Scripts\activate
# macOS / Linux:
source .venv/bin/activate
pip install -r requirements.txt

# 2. 配置环境变量
cp .env.example .env
# 编辑 .env：填写 LLM_API_KEY / LLM_BASE_URL / LLM_MODEL，并把 LLM_ENABLED 置为 true

# 3. 启动服务（--reload 便于开发）
uvicorn app.main:app --host 0.0.0.0 --port 8000 --reload
```

打开 http://localhost:8000/docs 查看交互式 API 文档；健康检查：http://localhost:8000/api/health

## 接口一览

Base URL：`http://<host>:8000/api`（完整契约见 `docs/spec.md` §7）

| 方法 | 路径 | 说明 |
|---|---|---|
| POST | `/ocr/recognize` | 图片 OCR（multipart `file`）→ `{ocr_text, latex_text, blocks, confidence}` |
| POST | `/questions/analyze` | OCR + AI 结构化（multipart `file` + 可选 `subject`）→ QuestionRecord + `similar_matches` |
| POST | `/questions` | 保存错题 → `{id}` |
| GET | `/questions` | 列表 / 筛选（subject / knowledge_point / question_type / mastery / keyword / page / page_size） |
| GET | `/questions/{id}` | 详情（UUID） |
| PATCH | `/questions/{id}` | 部分更新（编辑 / 打标 / 掌握程度） |
| DELETE | `/questions` | 批量删除（body `{ids: []}`） |
| POST | `/questions/batch-move` | 批量移动知识点（body `{ids, knowledge_point}`） |
| POST | `/retrieval/match` | 同类题匹配（标签 + 向量）→ `{items: [{question, similarity, matched_by}]}` |
| GET | `/knowledge-points` | 知识点树（多层级） |
| POST | `/import/paper` | 整页试卷批量导入（P2，当前返回 501） |
| GET | `/export/pdf` | 导出 PDF（mode=plain\|with_answer，可按 subject / knowledge_point / ids 筛选） |
| GET | `/export/worksheet` | 巩固练习卷 PDF（不含答案） |
| GET/PUT | `/settings` | 后端配置（LLM Key / 模型等，api_key 掩码显示） |
| GET | `/health` | 健康检查 |

## 优雅降级（重要）

核心依赖缺失时服务**仍可启动**，能力逐级降级，不会崩：

| 缺什么 | 行为 |
|---|---|
| `paddleocr` / `torch` | `/ocr/recognize` 返回空结构（`ocr_text: ""`）；`/questions/analyze` 报 400「未识别到文字」 |
| `texify` | `latex_text` 恒为空，其余正常 |
| `chromadb` | 向量库降级为纯 Python 内存余弦索引（重启后索引清空，功能可用） |
| LLM（无 Key / 未启用） | `analyze` 降级为纯规则分析，仅存 OCR 原文入库 |

重装依赖后无需改代码，重启进程即恢复完整能力。可选重型依赖安装方法见 `requirements.txt` 末尾注释。

## Docker Compose

```bash
cd backend
cp .env.example .env      # compose 需要 .env 存在
docker compose up -d --build
# 访问 http://localhost:8000/docs
```

数据持久化在 `backend/data/`（SQLite `wrongbook.db` + ChromaDB 目录），删除该目录即重置数据。

详细部署与使用手册见 [`docs/DEPLOY.md`](../docs/DEPLOY.md)，架构说明见 [`docs/ARCHITECTURE.md`](../docs/ARCHITECTURE.md)。
