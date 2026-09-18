# AI 变式组卷 — 实施规格（SPEC-AI-PAPER）

> 状态：**规划中（未实施）**　范围：先本地后端，后按需上云
> 目标：让用户选「科目 / 知识点 / 难度 / 题数」→ 系统**优先复用自己错题、不足用 AI 生成变式题补齐** → 生成一套针对个人薄弱点的小卷（屏上预览 / 可导出）

---

## 1. 背景与目标
### 现状
- 已有「举一反三」：对**单道题**生成几道同知识点变式题（`generateExercisesForQuestion`，用户 Key 直连）。
- 已有错题库 + 知识点 + 掌握度（`knowledge_points` / `masteryLevel` / `reviewCount`）。
- 已有 `reportlab` PDF 导出、科目/知识点管理。

### 目标（B 档：AI 变式组卷）
让 AI **按用户挑的范围**批量出卷，而不仅是"单题"：
- **优先**：从自己错题里按薄弱点挑"原题"；
- **补齐**：不够时用 AI 生成**同知识点变式题**把题数凑够；
- **编排**：按题型/难度/知识点排序 → 一套卷（含每题答案/解析）；
- 可屏上预览 + PDF 导出。

---

## 2. 方案设计

### 2.1 组卷输入（前端表单）
用户可选：
- 科目（必选，如数学）；
- 知识点范围（可多选，来自该科目的知识点/薄弱点）；
- 难度偏好（可不选，自动均衡：简单/中等/困难）；
- 题数（如 5 / 10 / 20）。

### 2.2 组卷流程（后端接口，一次请求返回整卷）
```
POST /api/paper/generate
body: { subject, knowledge_points?:[], difficulty?:str, count:int }
响应: { paper: { title, questions: [ {stem, options, answer, analysis, source, difficulty, kp} ] } }
```
流程：
1. **选材（SQLite）**：查当前用户 `user_id`（+共享）在该知识点、难度下的错题；
   - 按薄弱度（掌握低 / 复习间隔到期）排序；
   - 取可用的原题（≤ count 的一部分）。
2. **AI 变式补齐**：若原题不够 count，对薄弱知识点调用**变式生成**补齐剩余题数；
   - 补题时传"种子题干/知识点"给 DeepSeek 生成同类型变式（每题带答案+解析）。
3. **编排**：按难度（简单→中等→困难）或按知识点分组排序；
4. **返回整卷**；前端预览；可转 PDF（`reportlab`）。

> 关于"用谁的 Key"：与举一反三一致——**优先用户 Key 直连**；后端在云端也保留自有 Key 路径。本 spec 按**本地后端**先做：后端接 DeepSeek（自有 Key）批量生成变式。

### 2.3 AI 变式生成（关键能力）
复用举一反三思路但**无"原题分析"依赖、可脱离具体题**：
```
给"学科 + 知识点 + 难度 + 题号" -> AI 生成一道题干/选项/答案/解析
每次调用生成 1 题（或一次请求生成多题 JSON 数组）
```
- 若选了具体种子错题 → 变式围绕该题类型（换数字/条件/图形）。
- 只给知识点 → 生成该知识点下的典型题。
- **按题目逐题/小批量调 DeepSeek**，控制单次输出避免截断（沿用 max_tokens 经验）。

---

## 3. 数据结构

### 后端
- 无需新表：组卷是"读错题 + 实时 AI 生成"，不落库（可选存"已生成卷"历史，Should）。
- 复用现有 `questions`（选材）+ LLM 服务（变式生成）。

### 前端
- `PaperQuestion` / `PaperResult` 模型（stem/options/answer/analysis/source/difficulty/kp/title）。
- 状态 Provider 存"当前生成的卷"（便于预览/练习/导出）。

---

## 4. 前端 / 后端改动清单

### 后端（本地）
```
backend/app/
├── schemas/paper.py           # (新增) PaperGenerateRequest / PaperQuestion / PaperResult
├── services/paper_service.py  # (新增) 选材 + 编排
├── services/variant_service.py# (新增) AI 变式生成（复用 llm_service / prompts）
├── llm/prompts.py             # 加 build_variant_prompt（按知识点/种子生成变式）
└── api/paper_routes.py        # (新增) POST /api/paper/generate
```
- router.py 挂载 /paper。

### 前端
```
frontend/lib/src/
├── domain/models/paper.dart         # (新增) PaperQuestion / PaperResult
├── features/paper/presentation/
│   ├── paper_setup_screen.dart      # (新增) 选科目/知识点/难度/题数
│   ├── paper_preview_screen.dart    # (新增) 整卷预览（可看答案）
│   └── (导出/打印入口)               # 复用 reportlab PDF（后端生成或本地）
└── app/router.dart / main.dart      # 加路由
```

---

## 5. 实施顺序
1. 后端 `prompts.build_variant_prompt` + `variant_service`（单题变式生成，先验证 AI 输出）。
2. 后端 `paper_service`（选材 SQLite）+ `paper_routes`（接口）。
3. 前端 `paper_setup_screen`（选范围）+ 调后端 → `paper_preview_screen`。
4. PDF 导出（复用 reportlab）。
5. 本地构建、真机验证（不同知识点/难度/题数）。

---

## 6. 验收标准
- [ ] 输入科目+题数 → 返回整卷，题数满足要求。
- [ ] 有足够错题时优先用自己错题（source=错题）；不足用 AI 变式（source=AI 变式）。
- [ ] 每题含题干/选项/答案/解析/难度/知识点。
- [ ] 同一知识点生成的多道变式**不雷同**（题干不同）。
- [ ] 用户数据隔离（按账号）。
- [ ] 超时/失败有兜底（部分题失败仍返回已生成的）。

---

## 7. 风险与注意
- **多题一次生成易截断/不合法**：优先**逐题或小批量（1–3题）生成**，沿用结构层容错 + max_tokens 经验。
- **AI 变式质量**：纯知识点生成的题可能超纲/不典型——优先给"种子错题"让变式有据可依。
- **耗时**：10 题逐题生成可能几十秒——前端要 loading 状态、支持部分失败继续返回。
- 先本地后端（接自有 Key）；上云与否后续定。
