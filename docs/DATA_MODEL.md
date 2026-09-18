# 数据结构设计文档（DATA_MODEL）

> 版本：v1.0　对应 `docs/spec.md` §6 数据规格　维护：Agent-A（数据与业务层）

## 1. 总览

- **主存储**：SQLite（SQLAlchemy 2.0 ORM），库文件默认 `backend/data/wrongbook.db`（`DATABASE_URL` 可配置）。
- **向量存储**：ChromaDB 持久化目录 `backend/data/chroma`，collection 名 `questions`。
- **对外标识**：题目对外 JSON 的 `id` 为**字符串 UUID**（存于 `questions.uuid` 列）；`questions.id` 为 int 自增主键，仅内部使用，不对外暴露。
- **JSON 列**：`knowledge_points` / `options` / `tags` 使用自定义 `JSONText` 类型（TEXT 落库 + `ensure_ascii=False`），支持中文 LIKE 过滤。

---

## 2. SQLite 表结构

### 2.1 `questions` — 错题主表

| 列名 | 类型 | 约束/默认 | 说明 |
|---|---|---|---|
| `id` | INTEGER | PK, AUTOINCREMENT | 内部主键（不对外） |
| `uuid` | VARCHAR(36) | UNIQUE, NOT NULL, INDEX | 对外题目标识（QuestionRecord `id`） |
| `subject` | VARCHAR(50) | DEFAULT '' | 科目，如「数学」 |
| `knowledge_points` | TEXT(JSON) | DEFAULT `[]` | 知识点路径列表，见 §3.1 |
| `question_type` | VARCHAR(50) | DEFAULT '' | 题型：单选题/解答题/… |
| `difficulty` | VARCHAR(20) | DEFAULT '中等' | 简单 / 中等 / 困难 |
| `stem` | TEXT | NOT NULL, DEFAULT '' | 题干 |
| `options` | TEXT(JSON) | DEFAULT `[]` | 选项列表（选择题） |
| `answer` | TEXT | DEFAULT '' | 答案/订正答案 |
| `analysis` | TEXT | DEFAULT '' | 解析 |
| `mistake_reason` | TEXT | DEFAULT '' | 错因 |
| `source` | VARCHAR(255) | NULL | 来源（文件名/拍照等） |
| `status` | VARCHAR(20) | DEFAULT 'active', INDEX | active / archived / deleted |
| `mastery` | VARCHAR(20) | DEFAULT '未掌握', INDEX | 未掌握 / 已掌握 / 需巩固 |
| `image_path` | VARCHAR(500) | DEFAULT '' | 原图路径/URL |
| `ocr_text` | TEXT | DEFAULT '' | OCR 识别原文 |
| `latex_text` | TEXT | DEFAULT '' | texify 公式 LaTeX |
| `tags` | TEXT(JSON) | DEFAULT `[]` | 标签列表 |
| `created_at` | DATETIME(tz) | DEFAULT UTC now | 创建时间（ISO8601） |
| `updated_at` | DATETIME(tz) | DEFAULT UTC now, ON UPDATE | 最后更新时间 |
| `sync_version` | INTEGER | DEFAULT 0 | 同步版本号（每次更新 +1，P2 多端同步用） |

### 2.2 `knowledge_points` — 知识点树

| 列名 | 类型 | 约束/默认 | 说明 |
|---|---|---|---|
| `id` | INTEGER | PK, AUTOINCREMENT | 主键 |
| `name` | VARCHAR(100) | NOT NULL | 知识点名称 |
| `parent_id` | INTEGER | FK → `knowledge_points.id`, ON DELETE SET NULL | 父节点（根节点为 NULL） |
| `subject` | VARCHAR(50) | NOT NULL, DEFAULT '' | 所属科目 |
| `created_at` | DATETIME(tz) | DEFAULT UTC now | 创建时间 |

- 唯一约束：`UNIQUE(name, subject)`（同科目下知识点名唯一）。
- 自引用关系：`parent` / `children` 实现多层级树。
- 种子树（`init_db()` 幂等补种，根节点 name == subject）：

```
数学 -> 代数 / 几何 / 圆 / 函数 / 概率
语文 -> 古诗文 / 现代文阅读 / 写作 / 文言文
英语 -> 词汇 / 语法 / 阅读理解 / 写作
物理 -> 力学 / 电学 / 光学 / 热学
化学 -> 无机化学 / 有机化学 / 化学实验 / 化学计算
```

### 2.3 `question_tags` — 题目 × 知识点 多对多关联

| 列名 | 类型 | 约束 |
|---|---|---|
| `question_id` | INTEGER | FK → `questions.id`, ON DELETE CASCADE；复合 PK |
| `knowledge_point_id` | INTEGER | FK → `knowledge_points.id`, ON DELETE CASCADE；复合 PK |

> 采用 int 主键关联；题目 JSON 中的 `knowledge_points`（名称列表）由
> `question_service._sync_knowledge_points` 在 create/update 时自动 upsert 到
> 知识点表并刷新本关联表，保证「JSON 列表」与「树 + 关联」双向一致。

---

## 3. JSON 字段格式

### 3.1 `questions.knowledge_points`

知识点路径的扁平数组（沿树从根到叶，可含多级）：

```json
["初中", "几何", "圆"]
```

- 落库格式：`json.dumps(..., ensure_ascii=False)`，即明文中文 TEXT。
- 过滤：`Question.knowledge_points.like('%"圆"%')` 精确匹配数组元素。

### 3.2 `questions.options`

```json
["A. 选项一", "B. 选项二", "C. 选项三", "D. 选项四"]
```

### 3.3 `questions.tags`

```json
["圆", "错题", "期中"]
```

### 3.4 对外 QuestionRecord JSON（与 Flutter 共享，`docs/spec.md` §7.1）

```json
{
  "id": "uuid",
  "subject": "数学",
  "knowledge_points": ["初中", "几何", "圆"],
  "question_type": "解答题",
  "difficulty": "中等",
  "stem": "题干",
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
  "similar_matches": [
    {"question": {"...": "QuestionRecord"}, "similarity": 0.9, "matched_by": "vector|tag|both"}
  ]
}
```

> `created_at` / `updated_at` 以带时区 ISO8601 输出（UTC）。
> 转换入口：`QuestionService.to_out(orm_question, similar_matches=[])`。

---

## 4. ChromaDB 向量库

| 项 | 值 |
|---|---|
| Collection 名 | `questions` |
| 持久化目录 | `backend/data/chroma`（`CHROMA_DIR` 配置） |
| Embedding 文本 | `stem + 知识点 + 题型`（`spec.md` §6.2） |
| 距离 | 余弦相似度（`hnsw:space=cosine`），相似度 = 1 - distance |

### 4.1 每条的 Metadata 字段

| 字段 | 类型 | 值 |
|---|---|---|
| `question_id` | str | 题目 UUID（与 SQLite `questions.uuid` 对齐，即 QuestionRecord `id`） |
| `subject` | str | 科目 |
| `knowledge_points` | str | JSON 数组字符串（`json.dumps(ensure_ascii=False)`） |
| `tags` | str | JSON 数组字符串 |
| `created_at` | str | ISO8601（UTC） |
| `image_path` | str | 原图路径/URL |

### 4.2 写入时机与归属

- **归属**：ChromaDB 的写入/查询由 Agent-C 的 `app/retrieval/vector_store.py` 负责；
  业务层（`question_service`）不直接写向量库。
- **约定**：题目 create / update / delete 后，路由层（Agent-D）应调用
  `retrieval.vector_store` 同步 upsert / delete，保持 SQLite 与向量库一致；
  以 `question_id`（uuid）为主键对齐。

---

## 5. 检索契约（`/api/retrieval/match`）

双重检索（Agent-C 实现）：

1. **标签精确匹配**：请求 `knowledge_points` 与库中题目 `knowledge_points` 交集命中 → `matched_by="tag"`。
2. **向量相似度**：`text` 的 embedding 与库中向量余弦 TopN → `matched_by="vector"`。
3. 双重命中 → `matched_by="both"`。

响应按相似度降序，形如：

```json
{
  "items": [
    {"question": {"<QuestionRecord>"}, "similarity": 0.9, "matched_by": "vector"}
  ]
}
```

---

## 6. 初始化 / 迁移策略

- `init_db()`：`Base.metadata.create_all`（建缺失表）+ 种子知识点（缺则补），幂等。
- 字段演进：schema 以 `create_all` 为准（不引入 Alembic 的轻量策略）；
  破坏性变更可执行 `reset_db()`（开发/测试用，会 drop 全部表）。
- 依赖：`app/db/session.py` 中 SQLite 连接事件开启 `PRAGMA foreign_keys=ON`，
  保证 `question_tags` 级联删除生效。
