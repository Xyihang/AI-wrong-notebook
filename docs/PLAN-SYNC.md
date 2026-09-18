# 错题云端同步 — 实施计划（PLAN-SYNC）

> 状态：**规划中（未实施）**　对应需求：把错题题库从「手机本地」同步到服务器（本地后端 / 云端 CVM）
> 目标：错题真正存在服务器端，按账号隔离；支持多设备统一、防止换机/重装丢失

---

## 1. 背景与现状

当前数据流（已核实）：

| 功能 | 数据存哪 | 说明 |
|---|---|---|
| 错题（题干/答案/解析/标签） | **手机本地 Drift**（`question_records`）| App 增删改查走 `questionRepositoryProvider` → `DriftQuestionRepository` |
| OCR / AI 结构化 / 同类题匹配 | 后端处理 | `BackendClient` 只做加工，结果回填手机 |
| 用户登录/注册 | 后端 | `users` 表 + JWT |
| 视觉额度 | 后端 | 按 IP/Key 限流 |

**关键问题**：后端 `/api/questions`（增删改查接口）在代码里**已实现且支持按 `user_id` 隔离**（PLAN-AUTH 已接入），但 **App 从未调用它**——错题只存手机本地。因此换机/重装即丢失，也无法多设备统一。

> 三处数据库现状均为 0 题（本地后端 / 手机 / 云端），尚无实际题库数据。

---

## 2. 目标（方案 A：云端同步）

- 错题以**服务器为准**（本地后端或云端 CVM），手机作为**客户端缓存**。
- 新增 / 修改 / 删除错题时**推送**到后端 `/api/questions`；进入错题本时**拉取**。
- 数据按账号隔离（`user_id`），登录哪个账号就看到哪个账号的题。

---

## 3. 技术方案

| 项 | 选择 | 理由 |
|---|---|---|
| 存储 | 复用后端 `/api/questions`（SQLite `questions` 表，已有 `user_id`）| 后端已具备，零新表 |
| 同步方向 | **手机 → 服务器（推送）+ 服务器 → 手机（拉取）** | 服务器为权威 |
| 触发时机 | 保存/编辑/删除后**推**；错题本/首页进入时**拉** | 简单、可接受少量延迟 |
| 冲突 | 以**最新 `updated_at` / `sync_version` 为准** | 单用户低冲突，够用 |
| 鉴权 | 复用登录 token（`AuthController` + Dio 拦截器已带 `Authorization`）| 已具备 |

### 同步字段映射（Drift `question_records` ↔ 后端 `QuestionRecord`）

| 手机 Drift | 后端 QuestionRecord | 说明 |
|---|---|---|
| `id` | `id`（uuid）| 后端 uuid 与手机 id 对齐；缺省生成 |
| `subject` | `subject` | |
| `corrected_text`/`original_text` | `stem` | 题干（以订正文本优先）|
| `mastery_level` | `mastery` | 掌握程度 |
| `tags`/`ai_tags`/`ai_knowledge_points` | `tags` / `knowledge_points` | 标签 |
| `ai_analysis_json` | `analysis`/`answer`/`mistake_reason` 等 | 解析 |
| `updated_at` | `updated_at` / `sync_version` | 冲突判定 |

---

## 4. 范围

### Must（必做）
- [ ] 新增 `CloudQuestionRepository`（或扩展现有 repository）：封装后端 `/api/questions` 的增删改查 + 分页
- [ ] 保存 / 编辑 / 删除错题后**自动推送**到后端（异步，失败可重试）
- [ ] 进入错题本 / 首页时**拉取**后端题目并合并进本地缓存
- [ ] 多设备 / 重装后：登录即可拉回自己的题
- [ ] 离线降级：后端不可达时照常本地读写，恢复后重试推送

### Should（应有）
- [ ] 拉取/推送状态提示（同步中 / 成功 / 失败）
- [ ] 软删除：手机删除 → 后端标记或删除，避免拉取时复活
- [ ] 同步冲突：以 `updated_at` 更新者为准

### Won't（暂不做）
- [ ] 实时推送 / WebSocket / 后台静默同步
- [ ] 增量增量同步协议（全量拉取足够小规模）
- [ ] 图片文件上传到服务器（`image_path` 仍为手机本地路径或 URL）

---

## 5. 目录 / 文件改动（前端）

```
frontend/lib/src/
├── data/repositories/
│   └── cloud_question_repository.dart   # (新增) 后端 /api/questions 封装
├── data/services/
│   └── question_sync_service.dart       # (新增) 推送/拉取/合并/冲突/离线队列
├── app/
│   ├── providers.dart                   # 新增同步服务 Provider（注入 AuthController/BackendClient）
│   └── auth_controller.dart             # 登录成功后触发首次拉取
├── features/notebook/
│   └── presentation/notebook_screen.dart # 进入时触发拉取 + 同步状态提示
└── features/ocr/...                      # 保存成功后触发推送
```

后端：**无需改动**（`/api/questions` 已实现 + 已按 `user_id` 隔离）。仅需确认字段映射兼容。

---

## 6. 实施顺序

1. **契约核对**：后端 `/api/questions` 的 `QuestionRecord` 字段与 Drift `question_records` 对齐，明确映射。
2. **后端封装**：`CloudQuestionRepository`（create / update / delete / list，带 token）。
3. **同步服务**：`QuestionSyncService`（推送队列 + 拉取合并 + 离线降级）。
4. **接线**：保存/编辑/删除后推；错题本/首页进入时拉；登录后首次拉。
5. **状态提示**：同步中/成功/失败 UI。
6. **测试**：手机加题 → 后端出现（按当前账号 user_id）；换账号看不到别人的题；删除不复活。

---

## 7. 验收标准
- [ ] 手机新增一题 → 后端 `/api/questions` 出现该题（带当前账号 `user_id`）
- [ ] 编辑 / 删除后，后端数据同步更新 / 删除
- [ ] 重装 App 或换设备，登录同一账号后能拉回全部题
- [ ] 账号 A 登录看不到账号 B 的题（隔离）
- [ ] 后端不可达时 App 可正常本地读写，恢复后补推

---

## 8. 风险与注意
- **数据源一致性**：迁移期手机可能已有本地题，需「首次登录合并」策略（手机无题 → 直接拉；有题 → 以服务器为准或双向合并，取较新）。
- **冲突**：单用户低风险；多设备同时编辑以 `updated_at` 更新者为准。
- **删除语义**：后端 `/api/questions` 是物理删除，手机软删需处理「拉取时是否复活」。
- **离线队列**：需内存/本地待推送队列，避免重启丢失。
- **图片**：`image_path` 目前是手机本地路径，同步到后端后其它设备无法查看原图（暂不解决，错题文字内容可同步）。

---

## 9. 后续扩展（本计划之外）
- 图片上传到后端 / 对象存储，实现跨设备原图
- 增量同步协议（`sync_version` 已预留）减少流量
- 实时推送（WebSocket）
- 把题库整体迁移到云端 CVM 后，App 指向云端地址（`--dart-define=API_BASE_URL=...`）
