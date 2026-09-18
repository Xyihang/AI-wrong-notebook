# 学习连击 & 成就徽章 — 实施计划（PLAN-GAMIFICATION）

> 状态：已实施（本地，纯前端 + 本地存储）　范围：本地先做（不上云）
> 实现落地：`domain/services/gamification.dart`（streak/徽章纯函数 + 解锁持久化编解码）、
> `domain/models/achievement.dart`、`providers.dart`（gamificationSnapshotProvider）、
> 首页顶部连击小卡 + 新解锁「恭喜」弹层、`features/achievements` 成就墙 + 路由 `/achievements`
> + 设置「成长 → 成就徽章」入口。单测 `test/gamification_test.dart`（21 用例全过）。
> 目标：用「连击 + 成就徽章」给错题本加一点游戏化正反馈，让坚持复习有可见回报。

---

## 1. 目标与价值
- **学习连击**：记录你"连续学习天数"，形成习惯惯性（今天断了会心疼 → 更愿意每天来一下）。
- **成就徽章**：把里程碑（首次拍题、累计 N 道、连续复习 N 天、某科目掌握 X 题…）变成可解锁的"收藏"，给正反馈。
- 二者数据都**来自现有本地数据**，无需新增学习记录源即可推断。

---

## 2. 方案设计

### 2.1 学习连击（Streak）
**定义**：从"今天（或昨天）"往前数，**连续几天每天都发生学习行为**的天然天数。

**学习行为**（任一即算当天活跃）：
- 当天有新错题（`createdAt` 在今天）；
- 当天有复习记录（`reviewLogs` 的 `reviewedAt` 在今天）；
- 当天有练习 / AI 问答（`generatedExercises` / `ai_conversation` 时间在今天）。

**计算**：不存"历史每日表"，启动时用现有数据**聚合出最近连续活跃天数**：
```
streak = 从今天往前：今天或昨天活跃则计；一旦断层（超过 1 天空白）停止。
```
（今天还没活跃但昨天连续 → streak 显示昨天的连击，提示"今天还没学，学一下保持连击"。）

### 2.2 成就徽章（Achievements）
**徽章定义**（一组静态规则 + 条件，可扩展）：
| 徽章 | 条件 |
|---|---|
| 🎉 首次记录 | 错题数 ≥ 1 |
| 📚 收藏家 | 错题数 ≥ 10 / 50 / 100 |
| 🔥 连续 3 天 | streak ≥ 3 |
| ⚡ 连续 7 天 | streak ≥ 7 |
| 🏆 连续 21 天 | streak ≥ 21 |
| ✍️ 单科通 | 某科掌握数 ≥ 10 |
| 🌙 深夜学习 | 有学习行为发生在 0–5 点 |
| 🎯 巩固达人 | 累计复习 ≥ 20 |
| 🤸 举一反三 | 做过一次练习 |

**判定 & 存储**：启动时对每枚徽章检查条件，若满足且未解锁 → 解锁（弹出恭喜）+ 持久化到本地（settings 键/Drift）。解锁状态不再回退。

---

## 3. 前端改动（全部）
```
frontend/lib/src/
├── domain/services/
│   └── gamification.dart              # (新增) 纯函数：streak 计算 / 徽章定义与判定
├── domain/models/
│   └── achievement.dart               # (新增) Achievement（id/name/icon/desc/unlockedAt）
├── app/
│   └── providers.dart                 # 新增 gamificationProvider（读问题/reviewLog 统计）
├── features/home/presentation/
│   └── home_screen.dart               # 顶部加「连击 X 天」小卡
├── features/profile/ (或 settings)
│   └── achievements_screen.dart       # (新增) 成就墙：已解锁 / 未解锁
└── (解锁弹层)                          # 首次解锁时弹窗恭喜
```

### 核心纯函数（`gamification.dart`）
```dart
int computeStreak(List<DateTime> activeDays, {DateTime? today});
List<Achievement> evaluateAchievements({stats, unlockedIds});
```

---

## 4. 是否涉及后端
**本地可完全实现**（统计用本地错题 + reviewLogs）。
可选（Should，后续）：徽章解锁状态同步到用户账号（多设备一致）——属 PLAN-SYNC 扩展。

---

## 5. 实施顺序
1. `gamification.dart` 纯函数 + 单测（streak / 徽章判定）。
2. 徽章模型 + 本地持久化解锁。
3. `providers.dart` 聚合统计。
4. 首页「连击 X 天」小卡。
5. 成就墙页 + 解锁弹层。
6. 本地构建验证。

---

## 6. 验收标准
- [x] 连续学习 3 天 → streak=3；断一天后归 0。
- [x] 满足条件的徽章自动解锁并持久化，重启不丢。
- [x] 已解锁徽章不重复弹。
- [x] 首页显示当前连击。
- [x] 单测：streak 跨天/断层、徽章判定正确。

---

## 7. 风险与注意
- **"今天没学保持连击"语义**：用"昨天活跃=连击仍在"避免因一天还没学就归零的挫败感。
- **徽章条件数值**先给默认（10/50/100 等），后续可调。
- 纯前端，风险低，改动小。
