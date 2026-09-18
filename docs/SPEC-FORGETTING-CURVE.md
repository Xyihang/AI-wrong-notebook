# 智能遗忘曲线复习 — 实施规格（SPEC-FORGETTING-CURVE）

> 状态：**规划中（未实施）**　范围：**仅前端**（复习数据已在本地 Drift/SharedPreferences，无需后端改动）
> 目标：把「所有未掌握的题都算待复习」升级为「**按遗忘曲线预测每题的到期时间，只复习到期的题**」

---

## 1. 背景与目标

### 现状问题
- 现有 `review_controller.pendingAll()` / `review_screen`：**所有 `masteryLevel != mastered` 的题都算"待复习"**，没有间隔/到期概念。
- 今天复习完的题，明天、后天依然排在"待复习"里，用户不知道该复习哪些，容易疲劳或漏复习。
- `notification_service` 的 `dueCount` 也是"所有未掌握"，提醒没有针对性。

### 目标
- 引入**艾宾浩斯遗忘曲线**：每题根据「掌握度 + 复习次数 + 上次复习时间」算出**下次复习时间**。
- 复习页只把**到期的**题列为"待复习"；未到期的显示"X 天后复习"。
- 答对 → 间隔指数增长；答错/降级 → 间隔缩短。
- 让"该复习什么"由数据说了算，而不是一锅端。

---

## 2. 现状盘点

| 项 | 现状 | 是否复用 |
|---|---|---|
| 掌握度 | `QuestionRecord.masteryLevel`：newQuestion / reviewing / mastered | ✅ |
| 复习次数 | `QuestionRecord.reviewCount`（int） | ✅ |
| 上次复习 | `QuestionRecord.lastReviewedAt`（DateTime?） | ✅ |
| 复习动作 | `review_controller.markMastered/markReviewing/markNewQuestion`（+1、写 ReviewLog） | ✅ 复用 |
| 复习历史 | `ReviewLog`（SharedPreferences，`review_log_repository`） | ✅ 复用 |
| 到期判定 | 无（全部未掌握=待复习） | ❌ 需新增 |
| 通知 | `notification_service.dueCount` = 全部未掌握 | ❌ 需改为到期 |

> 关键：**所需数据（reviewCount / lastReviewedAt / masteryLevel）已存在**，无需加字段、无需迁移、无需后端。本功能是**纯前端纯函数 + UI 层**改动。

---

## 3. 方案设计：遗忘曲线模型

采用**简化的艾宾浩斯 / SM-2** 间隔策略（不引第三方库，纯函数）：

### 3.1 间隔表（复习间隔，单位：天）
| 掌握度 | 复习次数 reviewCount | 距下次复习（天） |
|---|---|---|
| newQuestion | 0 | **1**（首次复习很快）|
| newQuestion | ≥1 | 1 |
| reviewing | 1 | 1 |
| reviewing | 2 | 2 |
| reviewing | 3 | 4 |
| reviewing | 4 | 7 |
| reviewing | 5 | 15 |
| reviewing | ≥6 | 30（封顶）|
| mastered | — | 不进待复习（或 30 天巩固，见 §4）|

即 `interval = [1, 1, 2, 4, 7, 15, 30][min(reviewCount, 6)]`（reviewing 态）。

### 3.2 到期判定（纯函数，不落库）
```
nextReviewAt = lastReviewedAt == null ? null : lastReviewedAt + intervalDays
isDue:
  - 从未复习（reviewCount == 0 或 lastReviewedAt == null）→ 视为到期（首次复习）
  - 否则 nextReviewAt <= now → 到期
  - mastered → 默认不进待复习（除非启用"巩固"）
```
> `nextReviewAt` **每次实时计算**，不新增数据库字段（避免迁移）。

### 3.3 复习结果反馈（间隔如何变）
- **答对 / 掌握**：`markMastered` → `reviewCount + 1` → 下次间隔按新 reviewCount 增长（指数上升）。
- **答错 / 需巩固**：`markReviewing` → `reviewCount + 1` → 仍按增长；若用户显式"重置"（markNewQuestion）→ `reviewCount = 0`、`mastery = newQuestion` → 间隔回到 1 天。
- **保持简单**：不引入复杂的"连续答对才升级"，沿用现有 markMastered/markReviewing 语义，仅把**间隔**变成 reviewCount 的函数。

---

## 4. 到期展示

- **待复习 tab**：只显示 `isDue == true` 的题（含首次新题）。
- **已掌握 tab**：不变（mastered）。
- **"稍后"区（可选）**：未到期但未掌握的题，显示"X 天后复习"（卡片副标题），避免用户疑惑"我那些题去哪了"。
- 卡片加一行：`下次复习：今天` / `下次复习：3 天后` / `新题·待首次复习`。

---

## 5. 前端改动（全部）

```
frontend/lib/src/
├── domain/services/
│   └── forgetting_curve.dart        # (新增) 纯函数：intervalFor / nextReviewAt / isDue
├── data/services/
│   └── notification_service.dart    # 改：dueCount 按 isDue 计算
├── features/review/presentation/
│   ├── review_controller.dart       # 改：pendingDue() 按到期过滤；新增 pendingUpcoming()
│   └── review_screen.dart           # 改：待复习=到期；未到期显示"X天后"；卡片显示下次复习
```

### 核心纯函数（`forgetting_curve.dart`）
```dart
/// 某题距下次复习的天数（reviewing/newQuestion 态）。
int intervalDaysFor(QuestionRecord q) { ... }   // 查间隔表

/// 下次复习时间。
DateTime? nextReviewAt(QuestionRecord q) { ... }

/// 是否到期（应复习）。
bool isDue(QuestionRecord q, {DateTime? now}) { ... }
```

---

## 6. 是否涉及后端
**否。** 复习所需数据（reviewCount / lastReviewedAt / masteryLevel / ReviewLog）全部在**本地**。
- 本地后端无需改动；
- 暂不上云；（云端多设备同步复习进度 = 属 PLAN-SYNC 范畴，本 spec 不做。）

---

## 7. 实施顺序
1. `domain/services/forgetting_curve.dart`：纯函数（间隔表 + 到期判定）+ 单测。
2. `review_controller.dart`：`pendingDue()` / `pendingUpcoming()`。
3. `review_screen.dart`：待复习 tab 按到期过滤 + 卡片显示"下次复习 X 天后"。
4. `notification_service.dart`：`dueCount` 按 `isDue` 计算。
5. 本地构建 debug APK 装机验证。

---

## 8. 验收标准
- [ ] 新题（reviewCount=0）→ 立即出现在"待复习"。
- [ ] 复习过的题，未到期 → 不在"待复习"，显示"X 天后"。
- [ ] 答对（markMastered）→ reviewCount+1，下次间隔按新计数增长。
- [ ] 重置（markNewQuestion）→ 间隔回 1 天。
- [ ] mastered 题不进待复习。
- [ ] 通知 dueCount 按到期而非全部未掌握。
- [ ] 单测：间隔表 / 到期判定正确。

---

## 9. 风险与注意
- **间隔表参数**（1/2/4/7/15/30）是经验值，可后续按使用数据微调（建议做成可配置常量）。
- **首次复习**：新题 reviewCount=0 立即到期，保证"拍过的题当天/尽快能复习"。
- **不影响现有数据**：纯函数只读现有字段，不迁移、不回写。
- **复习节奏**：若用户很久没复习，到期题会积累很多——可接受（真实情况），后续可加"每日限额"（Should）。
