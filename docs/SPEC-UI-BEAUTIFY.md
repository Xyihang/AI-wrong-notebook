# UI 美化重构 · 需求规格文档

> 版本：v1（2026-11-19）
> 设计依据：`design/ui-beautify-demo.html`
> 现状基础：液态玻璃导航层（顶栏 / 浮动 Dock / 弹层）已上线
> 状态：**待评审**（评审通过后进入 /plan 拆任务）

---

## 0. 需求澄清清单

### 核心诉求
把现有页面（色彩、字阶、间距、卡片、按钮、图标入口）统一收口到一套 **设计 Token 体系**，并把首页 / 错题本 / 错题详情 / 复习 / 设置 5 个核心页按 demo 重构，浅色与深色都要成体系。

### 目标用户
- 主要：高中学生（手机端、单手、碎片时间使用）
- 次要：自己（唯一开发者/维护者），要求后续改样式只改 token 不改页面

### 使用场景
- 拍题 → 解析 → 复习 → 查看统计；
- 深色模式多在夜间复习时使用；
- 低端机 / 深色模式下也要可读、不"死黑"。

### 功能范围
**Must Have**
1. Token 落地为 Dart `ThemeExtension`（颜色 / 字阶 / 间距 / 圆角 / 阴影），页面禁止硬编码色值；
2. 组件层收口：卡片、按钮（主/次/语义三键）、chip、搜索框、统计卡、错题卡、解析步骤、设置条目；
3. 5 个核心页按 demo 重构（浅色 + 深色）；
4. 深色模式配色按 demo token（背景 `#0F172A`、卡片 `#1E293B`、描边 `#334155`、正文 `#E2E8F0`、次要 `#94A3B8`、primary 提亮 `#818CF8`）；
5. 保留已上线的玻璃导航层（顶栏 / Dock / 弹层），内容区**不使用玻璃**。

**Should Have**
6. 首页快捷入口改为「图标 + 短文案」四宫格（拍错题 / 去复习 / 组卷 / 学情），替换现在的大文字按钮；
7. 首页新增右侧拍照 FAB（demo `.fab`，52×52 圆角 18）与底部渐隐（`mask-image` 等效实现）；
8. 错题详情解析改为**步骤条**（step-num 圆形序号）；
9. 同类题推荐提升为顶部横幅（secondary 色）；
10. 复习页改为「环形今日进度 + 复习卡 + 三键反馈（仍不会/模糊/已掌握）+ 下次复习提示」；
11. 设置页统一「图标 + 标题 + 描述 + 值/开关/箭头」三段式。

**Nice to Have**
12. 深色下卡片描边 + 8% 背景通透（与现有 A+B 方案融合）；
13. 难度标签（较易/中等/较难）语义色贯穿全站；
14. 公式块独立排版（serif 斜体 + 中立底色）。

**Won't Have（本次明确不做）**
- 不改任何业务逻辑、数据模型、接口；
- 不改玻璃分档/开关机制、不改背景图机制（仅允许 token 化皮肤级调整）；
- 不做新页面（学情页仅保留入口占位）；
- 不做平板/横屏适配；
- 不做 Web/桌面端。

### 技术约束
- Flutter 3.41.2 + Riverpod；Material 3；
- 已有 `features/glass/*`（`glassTopBar`、`GlassTabBar`、`showAppSheet/showAppDialog`、`AppCardSurface`）必须复用，不得回退；
- 资源零新增（图标继续用 `CupertinoIcons` / 现有 SVG 等价 Material 图标）；
- 每步改动必须保持 `flutter analyze` 干净、`flutter build apk --release` 通过。

### 已确认决策（2026-11-19）
- [x] **Q1 深色卡片**：token 默认**不透明** `#1E293B` + 1px `#334155` 描边；另保留 `cardTranslucent`（半透明）供「有背景图 + 需要通透」时按需切换。
- [x] **Q2 首页主按钮**：**保留**现有玻璃「拍照录题」胶囊主按钮；demo 的四宫格快捷入口作为其下方的辅助入口同时提供。
- [x] **Q3 Dock**：**保持线上四个 Tab（首页/错题本/复习/设置）**；demo 仅作布局参考，不照搬「成就」Tab。
- [x] **Q4 调试环境**：安装 **Android 模拟器 + Android 35 google_apis x86_64 镜像**到 E 盘（`E:\trae_projects\AI-wrong\android-sdk`），用于替代真机自测。
- [x] 单条原则：**demo 只作布局/层级参考，交互与入口以线上实际能力为准**（不因 demo 增删功能）。

---

## 1. 概述

### 1.1 背景
页面样式目前散落在各页面：颜色有硬编码（`0xFF6366F1`、`0xFFEA580C`、`0xFFD97706`…），字阶与间距混用（13/14/15/16px、20/24 padding 混排），深色下卡片偏黑、缺少层级。玻璃导航层已经统一，但**内容层**仍是"各写各的"。

### 1.2 目标
1. 建立单点可控的设计 Token（浅/深两套），页面只消费 token；
2. 5 个核心页按 demo 重构，信息层级与观感统一；
3. 深色模式有明确的层级色（卡片 / 描边 / 文本三档）；
4. 让"新加一个页面"变成拼组件而不是重新配色。

### 1.3 范围
`frontend/lib/src/**` 的展示层（presentation）与共享组件（common/widgets），新增 token/组件层；不动 data/domain。

---

## 2. 用户故事
- 作为学生，我在深色模式下看错题卡，能一眼分清「科目 / 难度 / 题干 / 知识点」，不再是一块黑砖。
- 作为学生，我在首页能一步点到「拍错题 / 去复习 / 组卷」，而不是先读一大段按钮文字。
- 作为学生，我看解析时是按步骤读，而不是一坨文字。
- 作为维护者，我改主色只改 1 个文件，全站跟着变。

---

## 3. 功能需求

### 3.1 功能清单
| 模块 | 优先级 | 描述 |
|---|---|---|
| T1 设计 Token（ThemeExtension） | P0 | 颜色/字阶/间距/圆角/阴影双主题 |
| T2 组件层收口 | P0 | AppCard / AppButton / AppChip / AppStatCard / AppQuestionCard / AppStep / AppSettingTile |
| T3 首页重构 | P0 | 统计 Hero 卡 + 三宫格科目统计 + 四宫格快捷入口 + 最近收录卡 |
| T4 错题本重构 | P0 | 玻璃搜索框 + 筛选 chips + 统一错题卡（科目/难度/时间/知识点/同类标记） |
| T5 错题详情重构 | P0 | 分区卡片（题目 / AI 解析步骤 / 我的错因）+ 同类题横幅 + 底部双按钮 |
| T6 复习页重构 | P0 | 环形进度 + 复习卡 + 三键反馈 + 下次复习提示 |
| T7 设置页重构 | P0 | 分组 + 三段式条目 + 开关/值/箭头 |
| T8 深色模式调校 | P0 | demo 的深色 token 全量落地 |
| T9 其余页面跟随 | P1 | 组卷/OCR 确认/结果页/练习页按 token 换肤，不重排结构 |
| T10 首页 FAB + 底部渐隐 | P2 | 52×52 拍照 FAB、滚动区底部渐隐遮罩 |

### 3.2 详细规格

#### T1 设计 Token
新增 `lib/src/app/design/tokens.dart`：

```dart
@immutable
class AppTokens extends ThemeExtension<AppTokens> {
  // 颜色
  final Color primary, primaryDark, primarySoft;
  final Color secondary, secondarySoft;
  final Color success, successSoft;
  final Color warning, warningSoft;
  final Color error, errorSoft;
  final Color bg, bgPage, card, cardBorder;
  final Color textPrimary, textSecondary, textTertiary;
  // 字阶
  final double textXs /*12*/, textSm /*14*/, textBase /*16*/,
               textLg /*20*/, textXl /*24*/, textXxl /*32*/;
  // 间距（4px 栅格）
  final double s1 /*4*/, s2 /*8*/, s3 /*12*/, s4 /*16*/,
               s6 /*24*/, s8 /*32*/, s12 /*48*/;
  // 圆角 / 阴影
  final double radiusSm /*6*/, radiusMd /*8*/, radiusLg /*12*/;
  final List<BoxShadow> shadow1, shadow2;
}
```

浅色值（来自 demo `:root`）：
| Token | 值 |
|---|---|
| primary / dark / soft | `#4F46E5` / `#4338CA` / `#EEF2FF` |
| secondary / soft | `#0D9488` / `#F0FDFA` |
| success / soft | `#16A34A` / `#F0FDF4` |
| warning / soft | `#D97706` / `#FFFBEB` |
| error / soft | `#DC2626` / `#FEF2F2` |
| bg / bgPage | `#FFFFFF` / `#F8F9FA` |
| card / cardBorder | `#FFFFFF` / `#E5E7EB` |
| textPrimary / secondary / tertiary | `#111827` / `#6B7280` / `#9CA3AF` |
| shadow1 / shadow2 | `0 1 3 rgba(0,0,0,.08)` / `0 4 12 rgba(0,0,0,.10)` |

深色值（来自 demo `.dark`）：
| Token | 值 |
|---|---|
| bg / bgPage | `#0F172A` / `#0F172A` |
| card / cardBorder | `#1E293B` / `#334155` |
| textPrimary / secondary / tertiary | `#E2E8F0` / `#94A3B8` / `#64748B` |
| primary（提亮） | `#818CF8` |
| primarySoft（深色） | `#312E81` |
| 公式/标签底 | `#0F172A` |
| 卡片阴影 | 无（改用 1px 描边） |

约束：`tokens.dart` 之外的文件禁止出现 `Color(0x...)`（逐步清理，白名单：`features/glass/` 内的玻璃渲染参数、图片资源）。

#### T2 组件层
| 组件 | 规格 |
|---|---|
| `AppCard` | 浅：`bg=card` + `radiusLg` + `shadow1`；深：`bg=card` + `1px cardBorder`，无阴影；padding `s4` |
| `AppButton.primary` | 填充 primary，白字，`radiusMd`，高 40，图标 16 + 文字 `textSm` |
| `AppButton.outline` | 透明底 + `1px cardBorder`，文字 `textSecondary` |
| `AppButton.soft(semantic)` | `successSoft/warningSoft/errorSoft` 底 + 对应前景色（复习三键、危险操作） |
| `AppChip` | 高 26，`radius 999`，未选：`bg=card`+描边+`textSecondary`；选中：primary 填充白字 |
| `AppStatCard.hero` | 大数字 `textXxl/600`，右上进度环（72×72，primary 72%），副标签 `textXs` |
| `AppStatCard.mini` | 数字 `textLg/600`，标签 `textXs` |
| `AppQuestionCard` | 头部：科目标签（软底小胶囊）+ 难度（成功/警告/错误色文字）+ 时间（右对齐 `textTertiary`）；题干 `textSm`；公式块（serif 斜体 + 中立底 `radiusSm`）；底部知识点 tag + 「×N 同类」secondary 标记 |
| `AppStep` | 20×20 圆形序号（primarySoft 底 + primary 文字）+ 步骤正文 `textSm`，行距 `s2` |
| `AppSettingTile` | 图标 32×32（`radiusMd` + 中立底）+ 标题 `textSm/500` + 描述 `textXs/tertiary` + 右侧值/开关/箭头（16px） |
| `AppSwitch` | 40×24 胶囊，选中 primary，未选 `#E5E7EB`（深色 `#334155`） |
| `AppFab` | 52×52，`radius 18`，primary 底白图标，`shadow2`，距 Dock 上方 `88` |
| `AppBottomFade` | 滚动区底部 28px 渐隐（`ShaderMask`/渐变遮罩），替代 demo 的 `mask-image` |

#### T3 首页
1. 顶栏：保持 `glassTopBar`，标题「首页」→ 依 demo 为「错题本」？**按线上语义保留「开始拍错题」/或改「首页」，见 Q2**；
2. 统计 Hero 卡：累计错题大数字 + 进度环 + 两个 soft 标签（本周掌握 +N / 待复习 N）；
3. 三宫格科目统计（数学 primary / 物理 secondary / 英语 warning…按科目色 token）；
4. 四宫格快捷入口（48×48 图标底 + `textXs` 文案）：拍错题 / 去复习 / 组卷 / 学情（学情未实现时点击提示"即将上线"）；
5. 「最近收录」列表：复用 `AppQuestionCard`（最多 5 条）；
6. 右下 `AppFab`（拍照）+ 底部渐隐；
7. 游客提示条保留，改用 token 色。

#### T4 错题本
1. 顶栏：标题「错题本」+ 右侧相机图标（保留玻璃）；
2. 搜索：`GlassSearchBar` 保留，内部文字/图标走 token；
3. 筛选 chips：`AppChip`（全部 / 各科带数量 / 未掌握），横向滚动；
4. 列表：`AppQuestionCard`（含公式块 / 配图占位 / 同类标记），`radiusLg + shadow1`（深色描边）；
5. 左滑删除保留（`GlassSwipeActions`），下拉刷新保留（`GlassRefreshIndicator`）；
6. 空状态：图标 + 标题 + 描述 + 「拍照添加」按钮（token 化）。

#### T5 错题详情
1. 顶栏：返回 / 标题「错题详情」/ 收藏 + 更多（沿用现有 `glassTopBar` + 玻璃操作面板）；
2. 顶部同类题横幅（secondary soft 底 + 描边 `#99F6E4`）：`找到 N 道同类错题` + 考查点；
3. 分区卡片：① 题目（科目/难度/收录日期 + 题干 + 公式）② AI 解析（步骤条）③ 我的错因（错误色正文 + 知识点 tag）；
4. 底部双按钮：`编辑笔记`（outline）+ `加入复习`（primary），各占一半；
5. 原图/查看原图入口保留（放在题目卡内）。

#### T6 复习页
1. 顶栏：标题「今日复习」+ 右侧统计入口（原「记录」）；
2. 环形进度（88×88，`5/12 今日进度`）；
3. 复习卡（居中）：科目/难度 → 题干 → 公式 → 「显示答案」outline → 三键（仍不会 error soft / 模糊 warning soft / 已掌握 success soft）；
4. 说明行：`依据艾宾浩斯遗忘曲线安排`（`textXs/tertiary`）；
5. 下次复习卡（图标 + 标题 + 描述 + 箭头）；
6. 保留现有「复习记录」页入口与逻辑。

#### T7 设置
1. 顶栏：标题「设置」居中；
2. 分组：外观 / 学习 / 数据（现有分组内容映射进来）；
3. 条目三段式：`图标 + 标题(+描述) + 右侧(值/开关/箭头)`；
4. 危险项（清空数据）用 error 色 + errorSoft 图标底；
5. 现有「玻璃外观」「页面背景」「外观模式」保留并纳入「外观」组；
6. 组间距 `s4`，组内分隔线 `1px neutral-100`（深色 `#0F172A`）。

#### T8 深色模式
- 全部按 §T1 深色表；
- 卡片一律「#1E293B + 1px #334155」，无阴影；
- 玻璃顶栏/Dock 保持现有实现（demo 的 0.72 透明度 + blur 与现有一致）；
- 深色下 primary 使用 `#818CF8`，按钮/选中 chips/进度环同步。

---

## 4. 非功能需求

### 4.1 性能
- 列表滚动保持 ≥ 55fps（中档）/ ≥ 50fps（低档）；不得引入每卡 BackdropFilter；
- 新增组件不得增加额外的 `Image.asset` 解码（图标用矢量）；
- 首页/错题本首帧耗时不高于现状 +10%。

### 4.2 可读性 / 无障碍
- 正文与背景对比度 ≥ 4.5:1，次要文字 ≥ 3:1（深色、浅色都测）；
- 点击热区 ≥ 44×44（图标按钮、chips 除外但需 ≥ 32 高）；
- 字号最小 12px（`textXs`）。

### 4.3 兼容性
- 玻璃关闭（Material 回退）时，所有组件必须仍是 token 化后的观感（不依赖玻璃）；
- 低档设备（minimal 玻璃）不得因新组件导致闪烁/掉帧；
- Android 10（API 29）及以上；iOS 侧样式一致（不单独适配原生控件）。

### 4.4 可维护性
- 页面文件不得出现裸色值（白名单见 T1 约束）；
- 组件全部放在 `lib/src/common/widgets/` 或 `lib/src/app/design/`；
- 每个组件一个文件，带 1 段类注释说明使用场景。

---

## 5. 数据规格
无数据模型变更。仅以下展示映射：
- 科目 → 颜色：语文 success / 数学 primary / 英语 warning / 物理 secondary / 化学 `#7C3AED` / 生物 `#0EA5E9` / 其他 neutral；
- 难度 → 语义色：较易 success / 中等 warning / 较难 error；
- 掌握度 → 复习三键语义色（不会 error / 模糊 warning / 已掌握 success）。

---

## 6. 接口规格
无后端接口变更。

---

## 7. 验收标准
- [ ] 1. `lib/src/app/design/tokens.dart` 存在，浅/深两套 token 与 demo 数值一致；
- [ ] 2. 5 个核心页（首页/错题本/详情/复习/设置）在浅色与深色下各出一张对比截图，与 demo 样机结构一致（Hero 卡 / 步骤条 / 三键 / 三段式条目等特征可见）；
- [ ] 3. 全仓 `Color(0x` 硬编码数量下降 ≥ 80%（白名单除外）；
- [ ] 4. `flutter analyze` 无 error；`flutter build apk --release` 通过；
- [ ] 5. 玻璃关闭时 5 个页面无视觉错乱（回退观感仍统一）；
- [ ] 6. 深色下正文对比度 ≥ 4.5:1（抽查 10 处文本）；
- [ ] 7. 错题本 100 条数据滚动无掉帧（目视 + 帧率采样二选一）；
- [ ] 8. 既有功能回归：拍照→裁剪→解析→入库、复习三键、删除、组卷、导出，全部可用。

---

## 8. 风险与依赖

### 8.1 技术风险
| 风险 | 影响 | 缓解 |
|---|---|---|
| 深色 token 与现有 A+B 半透明卡片冲突 | 深色观感不统一 | Q1 拍板后统一走 token；过渡期两套并存但只允许一处定义 |
| 组件重构面广（20+ 页面） | 回归成本高 | 先做 5 个核心页（P0），其余按 T9 仅换肤；每页独立提交 |
| 玻璃顶栏与 demo 顶栏结构差异（demo 顶栏内含搜索框） | 错题本顶部高度变化 | 采用 demo 结构：搜索框并入顶栏区域，滚动区 padding 相应调整 |
| 主题切换时 token 重建 | 闪动 | Token 挂在 ThemeExtension，随 Theme 重建，避免 per-widget 计算 |

### 8.2 外部依赖
- 设计稿：`design/ui-beautify-demo.html`（唯一视觉依据，随改随存）；
- 已上线能力：`features/glass/*`、`AppCardSurface`；
- 调试环境：Android Studio 2026.2.2.9（已装 `E:\Android\AndroidStudio`）+ SDK（`E:\trae_projects\AI-wrong\android-sdk`）；**模拟器尚未安装**（见 Q4）。

---

## 9. 调试环境说明（Android Studio）
- Android Studio 已安装并可在 GUI 中打开工程 `frontend/`（Flutter 插件首次会下载）；
- 我（Agent）**无法操作 GUI**，只能通过命令行：`flutter analyze` / `flutter build` / `flutter run`（需设备或模拟器）+ `adb` 截图；
- 因此"用它调试"的可行路径有两种：
  1. **装模拟器**（推荐）：`sdkmanager` 安装 `emulator` + `system-images;android-35;google_apis;x86_64` 到 E 盘（约 2–3 GB），之后我可 `flutter run -d emulator-5554` 自测并截图；
  2. **你在 IDE 里跑**：你在 Android Studio 里点 Run，我改代码后你 hot reload，反馈截图给我。
- 真机调试按你的要求：**暂停使用**手机。

---

## 10. 评审待办（Review）
- [ ] 确认 Q1–Q4 四个决策
- [ ] 确认"Won't Have"清单
- [ ] 确认验收标准可接受
- [ ] 通过后进入 `/plan`：按 T1→T2→T3..T7→T9 拆任务，每个任务独立提交 + 构建验证
