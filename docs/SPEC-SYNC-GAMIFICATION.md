# 错题 + 连击&徽章 按账号同步上服务器 — 实施规格（SPEC-SYNC-GAMIFICATION）

> 状态：**已在本地测试后端实现并端到端验证通过**（生产 CVM 部署待用户确认后进行）
> 依赖用户确认决策：
>   A) 服务器为准 + 本地缓存（错题同步）
>   B) 文字同步，图片暂不上传
>   C) 连击&徽章服务端权威，按账号存储与计算

---

## 1. 目标
- 错题成为**服务器数据**（按 `user_id` 隔离），手机是客户端缓存：增删改推、登录/进错题本拉、重装/换设备可拉回。
- 连击 & 成就徽章**按账号**由服务端推算/存储，跨账号、跨设备一致。
- 先落在本地测试后端验证，代码保持可一键部署生产 CVM。

## 2. 现状核对（已读源码确认）
- 后端已有 `/api/questions`、`/api/questions/{id}`（PUT/DELETE？待核对方法）、`/api/questions/batch-move`，Question 表带 `user_id`（默认 0=共享），已按用户隔离。
- 后端**无游戏化接口**；Question 表**缺手机端的复习/连击所需字段**（`review_count`、`last_reviewed_at`、`created_at` 已有、无独立 `is_favorite`/练习等）。
- 后端 `QuestionOut` 字段为**分析中心化**（stem/answer/analysis/knowledge_points…），与手机 Drift `question_records` 的**记录中心化**结构不同 → 需字段映射（见 §4）。
- 手机端运行态存储：错题走 **Drift**（`DriftQuestionRepository`，`questionRepositoryProvider` 在 `main.dart` override）；复习日志仍 SharedPreferences（未 override）。→ 同步读 Drift。

## 3. 需要做的事
### 后端
1. Question 表补列（轻量迁移，仿照 init_db `_run_lightweight_migrations`）：
   - `review_count INT NOT NULL DEFAULT 0`
   - `last_reviewed_at DATETIME NULL`
   - （`created_at` 已有；`mastery` 已有）
   - QuestionBase/QuestionUpdate 相应加这两个字段。
2. 新建 `user_achievements` 表（user_id, achievement_id, unlocked_at）按用户存已解锁徽章。
3. 新建 `/api/gamification`：
   - `GET` → 依当前用户错题的 `created_at`/`last_reviewed_at` 的日期集合算 streak、active_today，并依「错题数/掌握数/复习数/练习/深夜」等判徽章条件，返回 `{streak, active_today, unlocked: [{id, unlocked_at}], newly: [...]}`（unlocked 从表 + 本次判定合并并落库；幂等不回退）。
   - 简单起见 `GET /api/gamification` 即拉取并落库（服务端权威）。保留卸载后重登可回。
4. 复用 `get_current_user`（依赖注入）+ `settings` 鉴权。

### 前端
1. `CloudQuestionRepository`：封装 `/api/questions` CRUD（带 token），DTO 映射 §4。
2. `QuestionSyncService`：保存/编辑/删除后异步推；登录/进错题本/首页拉；离线队列（本地待推，恢复补推）；合并按 `updated_at`。
3. `BackendClient` 增加 gamification get。
4. 登录成功/进入连击页时：从服务器拉取账号的 streak+unlocked 替换本地判定结果；离线回退本地。首次登录把本地徽章上传合并（服务端为准）。
5. UI：同步状态提示；退出按钮（成就页 push 后 AppBar 返回即可退，已修 go→push）。

## 4. 字段映射（Drift question_records ↔ 后端 QuestionOut）
> 以「订正文本 = stem、题干+答案+解析进 analysis 结构」为主；方向：手机→服务器写分析相关；服务器→手机重建 QuestionRecord。
- id：手机 id 作为服务器 uuid（两者对齐；服务端缺省则生成）。后端当前 create 由服务端生成 uuid → 需允许客户端传 id 或用手机 id 作 uuid。
- subject：文案互通（后端"数学"字符串 ↔ 手机 Subject 枚举 name）。
- stem ← 订正文本 corrected_text/normalized（优先）。
- answer/analysis ← QuestionRecord.analysisResult.answer / analysis。
- knowledge_points / tags ← 手机 aiKnowledgePoints / (aiTags+customTags) 合并标签。
- mastery_level（new/reviewing/mastered）→ mastery（未掌握/需巩固/已掌握）。
- review_count / last_reviewed_at / created_at / updated_at 直通（新增字段）。
- 手机独有（candidateAnalyses/split/exercises/favorite/contentFormat 等）暂不同步（文字主体同步即可）；举一反三徽章若依赖 savedExercises，需在同步期允许（is_favorite/练习暂缓）。

## 5. 验收
- [ ] 手机加一题 → 本地后端该账号 questions 表出现；编辑/删除同步。
- [ ] 换账号互不可见；重登可拉回。
- [ ] 连击/徽章按账号：A 连击 3 天登出，B 看不到；A 重登仍 3 天；徽章解锁落库不回退。
- [ ] 断网：本地可读写，恢复后补推。
- [ ] 测试后端验证通过后，同代码可部署生产。

## 6. 风险
- 双向同步契约差异大 → 先做「新增+编辑+删除」最小闭环，再扩展。
- 后端 create 强制服务端生成 id → 需改为可接受客户端 id（幂等 upsert）以对齐本地题。
- 图片路径不跨设备（已知接受）。
- 生产部署：后端文件 + .env 到 CVM 容器；前端仅默认地址差异。

## 7. 文件改动预估
后端：`db/models.py`（+列、+UserAchievement）、`db/init_db.py`（迁移）、`schemas/question.py`、`schemas/gamification.py`、`api/gamification_routes.py`、`api/router.py`、`api/question_routes.py`（create 允许 id/upsert）。
前端：`data/remote/backend/backend_client.dart`、`data/repositories/cloud_question_repository.dart`(新)、`data/services/question_sync_service.dart`(新)、`app/providers.dart`、`app/auth_controller.dart`、`features/notebook/notebook_screen.dart`、`features/home/home_screen.dart`、`features/achievements/...`（接服务端）。
