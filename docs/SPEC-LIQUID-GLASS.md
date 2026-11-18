# 功能规格：液态玻璃（Liquid Glass）按设备分档接入

- 状态：待评审（Spec 阶段，未实施）
- 关联调研：iOS 27 Liquid Glass 调研（2026-11-18）
- 目标组件库：`liquid_glass_widgets: 1.17.5`（MIT，纯 Flutter SDK，要求 Flutter ≥ 3.41.0，本项目 3.41.2）

---

## 1. 概述

### 1.1 背景
iOS 26/27 引入「液态玻璃」设计语言（折射、镜面高光、边缘暗化、随内容自适应）。调研结论：可用 `liquid_glass_widgets`（方案 A）在 Flutter 内跨平台实现，但玻璃效果本质是**每帧背景采样 + 多 pass 重绘**，成本随"玻璃面数"和"是否滚动"上升。

学生用户中大量为中低端安卓机，若一刀切全量玻璃，会出现掉帧、发热、可读性下降。

### 1.2 目标
1. 按**设备性能分低/中/高三档**，自动判档，**默认中档**；
2. 每档提供对应的玻璃强度与组件范围，形成**分级全量**方案；
3. **所有档位都保留底部浮动玻璃栏**（低档用最轻质量），保证观感统一；
4. shader 预编译放在**开屏动画期间**完成，不额外增加等待；
5. 提供用户可覆盖的「玻璃外观」设置，并支持**一键回退**到现有 Material 外观；
6. 不牺牲可读性、不破坏现有功能（错题/复习/组卷/解析流程）。

### 1.3 范围
- 做：设备能力探测、档位判定、玻璃主题与质量档、组件分档白名单、设置项与开关、回退、验收基准。
- 不做：iOS 原生 `glassEffect` 平台视图（`liquid_glass_native`）、输入类玻璃组件（见 §2.4）、整体视觉重设计（配色/字体不变）。

---

## 2. 需求澄清

### 2.1 目标用户
中国初高中学生及家长，主要设备为安卓（含大量 2–4 年前中端机），少量 iOS。

### 2.2 使用场景
- 长时间在错题本列表滚动、逐题查看解析；
- 拍照录题 → 解析等待（加载页）；
- 组卷、复习（短时交互、弹层多）；
- 设置页一次性配置。

玻璃应提升"导航层"的精致感，**不能干扰阅读长文本**。

### 2.3 功能范围
**Must Have**
- 设备档位判定 + 默认中档；
- 每档玻璃质量与组件白名单；
- 设置页「玻璃外观」：自动 / 低 / 中 / 高（自动=按设备判档；默认值为"自动"，判档失败按中档）；
- 全局回退开关（关闭即恢复现有 Material 外观，零残留）；
- 无障碍：Reduce Motion、Increase Contrast、文字对比度达标。

**Should Have**
- 每档性能基准与自动化验收脚本；
- 低档自动降级（运行时帧率不足时降 quality）；
- 玻璃开关状态持久化。

**Nice to Have**
- 玻璃强度滑杆（透明/标准/着色）；
- A/B 对比（灰度比例）。

**Won't Have（明确不做）**
- iOS 原生玻璃（需 iOS 26 SDK + Mac，当前不具备）；
- `GlassTextField/TextArea/PasswordField` 等输入类组件（输入法/表单校验风险）；
- 内容区逐行玻璃、玻璃内嵌玻璃；
- 更换现有配色、图标体系与信息架构。

### 2.4 技术约束
- 仅新增 1 个依赖：`liquid_glass_widgets: ^1.17.5`（需在 `main()` 调用 `initialize()`，并用 `wrap()` 包裹 App）；
- 设备探测**不引入新插件**：`Platform.numberOfProcessors` + `/proc/meminfo`（Android 可读）+ `View.of(context).display.refreshRate`；
- 现有路由为 GoRouter + `StatefulShellRoute`，替换导航壳需保持 4 Tab 行为与返回栈（详见返回键修复）；
- 主项目构建：Flutter 3.41.2 / Android minSdk 由 Flutter 默认 / iOS 13 部署目标。

### 2.5 已确认结论（2026-11-18）
- [x] Q1：**所有档位都保留底部浮动玻璃栏**（低档用 `minimal` 最轻质量）；AppBar 低档保留极轻模糊，其余重效果按档位裁剪。
- [x] Q2：RAM 指**运行内存**（`/proc/meminfo` 的 MemTotal）。阈值确定为：**高档 ≥10GB、中档 ≥6GB、其余为低**。
- [x] Q3：接受 shader 预编译开销，且要求**在开屏动画期间加载**（不额外增加用户等待）。
- [x] Q4：设置项放在**设置 → 外观**新分区。

---

## 3. 功能规格

### 3.1 设备分档（P0）

| 档位 | 判定条件（全部满足） | 说明 |
|---|---|---|
| 高 | 核心数 ≥ 8 且 **运行内存 ≥ 10GB** 且 刷新率 ≥ 90Hz 且 Android API ≥ 31 | 允许 `premium` |
| 中（默认） | 核心数 ≥ 6 且 **运行内存 ≥ 6GB** | 允许 `standard` |
| 低 | 其余（核心数 < 6 或 运行内存 < 6GB） | 仅 `minimal` / 关闭重效果（但保留底部玻璃栏） |

- **判定失败/信息缺失 → 中档**（用户要求默认中）；
- iOS：`premium` 允许（iOS 26+）；其余按同规则判；
- Web/桌面：默认中档，质量按平台文档走 `standard`；
- 用户手动选择档位后**覆盖自动判定**，并持久化。

### 3.2 档位 → 玻璃策略（P0）

| 项 | 低 | 中 | 高 |
|---|---|---|---|
| 质量档 | `minimal` | `standard` | `premium`（chrome）/ `standard`（body） |
| **底部浮动玻璃栏** | ✅ 必保留（minimal） | ✅（standard） | ✅（premium） |
| 常驻玻璃面上限 | 2（AppBar + 底部栏） | 3（+1 浮动控件） | 4 |
| 内容区玻璃 | 禁止 | 禁止 | 允许 C1 用 `solid` 卡（不折射） |
| 弹层玻璃 | 允许（minimal） | 允许（standard） | 允许（premium） |
| 逐行玻璃 | 禁止 | 禁止 | **仍禁止**（性能陷阱） |
| adaptiveQuality | 开 | 开 | 开 |
| 玻璃总开关 | 可全关 | 可全关 | 可全关 |

### 3.3 组件分档白名单（P1–P3）

> 编号沿用调研清单（A/B/C）。

| 编号 | 组件 | 低 | 中 | 高 | 落地页面 |
|---|---|---|---|---|---|
| A1 | `GlassScaffold` | ✅ | ✅ | ✅ | 全局骨架 |
| A2 | `GlassAppBar` | ✅(minimal) | ✅ | ✅ | 首页/错题本/复习/设置/详情 |
| A3 | `GlassTabBar.bottom`（底部浮动玻璃栏） | ✅(minimal) | ✅ | ✅ | 底部 4 Tab（**所有档位必保留**） |
| A4 | `GlassTabBar.minimizable` | ❌ | ❌ | ✅ | 底部 Tab（滚动缩小） |
| A5 | `GlassDialog` | ✅ | ✅ | ✅ | 游客提醒/删除确认/错误提示 |
| A6 | `GlassModalSheet` / `showGlassActionSheet` | ✅ | ✅ | ✅ | 拍照入口/AI 模型选择/知识点选择 |
| A7 | `GlassToast` | ✅ | ✅ | ✅ | 保存/同步提示 |
| B1 | `GlassSegmentedControl` | ❌ | ✅ | ✅ | 错题本筛选、复习范围 |
| B2 | `GlassSearchBar` | ❌ | ✅ | ✅ | 错题本搜索 |
| B3 | `GlassSwipeActions` | ❌ | ✅(单行按需) | ✅ | 错题本左滑删除/收藏 |
| B4 | `GlassButton` / `GlassIconButton` | ❌ | ✅ | ✅ | 拍照按钮、详情页操作 |
| B5 | `GlassMenu` / `GlassContextMenu` | ❌ | ✅ | ✅ | 长按菜单/更多操作 |
| B6 | `GlassProgressIndicator` | ✅ | ✅ | ✅ | 解析加载页 |
| B7 | `GlassChip` | ❌ | ✅ | ✅ | 知识点/标签筛选 |
| B8 | `GlassListTile` + `GlassGroupedSection` | ❌ | ✅(solid) | ✅(solid) | 设置页分组 |
| C1 | `GlassContainer.card` | ❌ | ❌ | ✅(solid) | 首页统计卡/额度卡 |
| C2 | `GlassNavigationStack` / `GlassNavigationLink` | ❌ | ❌ | ✅ | 详情页转场 |
| C3 | `GlassPageTransitionsBuilder` | ❌ | ❌ | ✅ | 全局转场 |
| C4 | `ProgressiveBlur` | ❌ | ❌ | ✅ | 滚动边缘渐隐 |
| C5 | `GlassMaterialize` | ❌ | ❌ | ✅ | 首次进入动效 |
| C6 | `GlassSwitch` | ❌ | ✅ | ✅ | 设置页开关 |
| C7 | `GlassPullDownButton` | ❌ | ✅ | ✅ | 组卷难度/科目下拉 |
| C8 | `GlassDatePicker` | ❌ | ❌ | ✅ | （若有）日期选择 |
| C9 | `GlassBadge` | ❌ | ✅ | ✅ | 错题数量角标 |

### 3.4 设置项（P0）

- 位置：设置 → 外观 → **玻璃外观**
- 选项：`自动（推荐）` / `低` / `中` / `高` / `关闭`
  - `自动`：按 §3.1 判定（失败=中）；
  - `关闭`：完全恢复 Material（不加载 shader 主题）。
- 默认值：**自动 → 判档失败按中**；即"默认中"。
- 变更立即生效（无需重启），持久化到设置仓库。

### 3.5 异常处理
| 场景 | 行为 |
|---|---|
| 设备信息读取失败 | 按中档 |
| shader 编译失败/不支持 | 自动降为 `minimal`，再失败则关闭玻璃并记录日志 |
| 帧率持续低于阈值 | `adaptiveQuality` 自动降档（premium→standard→minimal） |
| 用户系统开启"增强对比度" | 玻璃替换为高对比磨砂面 |
| 用户系统开启"减弱动态" | 关闭弹性/形变动画 |
| 玻璃导致文字对比不足 | 该页回退不透明（白名单兜底） |

---

## 4. 非功能需求

### 4.1 性能（各档验收）
| 指标 | 低 | 中 | 高 |
|---|---|---|---|
| 错题本 100 条滚动帧率（60Hz 基准） | ≥ 50 fps | ≥ 55 fps | ≥ 55 fps（120Hz 设备 ≥ 90fps） |
| 切页首帧（含玻璃） | < 120 ms | < 100 ms | < 80 ms |
| 冷启动增量 | < 80 ms | < 120 ms | < 150 ms |
| 内存增量 | < 20 MB | < 50 MB | < 80 MB |
| 首帧 shader 卡顿 | 无（**开屏动画期间预热**） | 无 | 无 |

### 4.1.1 shader 预热时机
- 在 **SplashScreen 出现时**（开屏动画开始）后台启动 `LiquidGlassWidgets.initialize(warmUpMode: ...)`；
- 与现有启动流程（配置拉取、会话恢复）**并行**，不阻塞 UI；
- 若开屏结束时仍未完成：首帧先按 `minimal` 渲染，完成后自动升级到目标档（用户无感）；
- 失败时记录日志并保持 `minimal`，不阻塞使用。

### 4.2 兼容性
- Android 8.0+（Flutter 默认 minSdk）；Impeller 不支持时回退 `minimal`；
- iOS 13+（现有部署目标），iOS 26+ 可用 `premium`；
- 桌面/Web：`standard`，不启用 premium。

### 4.3 可访问性
- 文字对比度 ≥ 4.5:1（玻璃上的标题/按钮）；
- 支持 Reduce Motion / Increase Contrast（跟随系统）；
- 玻璃不承载唯一信息（不靠颜色/高光传达状态）。

### 4.4 可回滚
- 设置里「关闭」一键恢复；
- 代码层以 `GlassFeature.enabled` 单点开关包裹，关闭时不实例化任何玻璃组件（避免残留开销）。

---

## 5. 数据规格

### 5.1 持久化字段（SettingsRepository）
| key | 类型 | 说明 |
|---|---|---|
| `glass_appearance` | string | `auto` / `low` / `mid` / `high` / `off`，默认 `auto` |
| `glass_tier_resolved` | string | 最近一次解析出的档位（调试用） |

### 5.2 档位解析数据流
```
启动 → DeviceProfile 采集（cores/RAM/refreshRate/API）
     → TierResolver（用户覆盖优先 → 自动判定 → 失败=中）
     → GlassTheme（quality + 是否 premium）
     → 组件白名单（按档位决定渲染玻璃或不透明）
```

---

## 6. 接口规格（内部）

### 6.1 DeviceProfile
```dart
class DeviceProfile {
  final int cores;        // Platform.numberOfProcessors
  final int ramMb;        // /proc/meminfo MemTotal（Android）
  final double refreshHz; // View.display.refreshRate
  final int sdkInt;       // Platform.operatingSystemVersion 解析
}
```

### 6.2 GlassTier
```dart
enum GlassTier { low, mid, high }
GlassTier resolveTier(DeviceProfile p, GlassAppearance preference);
```

### 6.3 组件门面（示例）
```dart
// 低档自动降级为普通 Material 组件
Widget appBarFor(BuildContext c, String title);
Widget tabBarFor(...);
```

---

## 7. 验收标准

- [ ] 设置页可选择 自动/低/中/高/关闭，重启后保持；
- [ ] 未做任何选择时，低端机判为"低"、中端机"中"、高端机"高"，判档失败为"中"；
- [ ] **三档均保留底部浮动玻璃栏**；关闭玻璃后，所有页面与当前已发布版本视觉一致（逐页 screenshot diff 为零差异）；
- [ ] 低档：错题本滚动 ≥50fps，底部玻璃栏正常显示，无 shader 卡顿；
- [ ] 中档：错题本滚动 ≥55fps，弹窗打开 <200ms，内存增量 <50MB；
- [ ] 高档：premium 常驻面 ≤4，无逐行玻璃；
- [ ] shader 预热在开屏动画期间完成，首帧无额外卡顿；
- [ ] 文字对比度抽检 ≥4.5:1（首页/错题本/详情/设置）；
- [ ] 系统开启"增强对比度/减弱动态"时表现符合 §3.5；
- [ ] 现有功能回归：拍照→解析→入库、错题本筛选/搜索/删除、复习、组卷、导出、游客/登录、返回键。

---

## 8. 风险与依赖

### 8.1 技术风险
| 风险 | 影响 | 缓解 |
|---|---|---|
| 玻璃层覆盖内容导致文字色散（Demo 已观察到红/黄描边） | 可读性 | 内容区禁玻璃；必须让 body 处于玻璃层之外（补 padding / 关闭 extendBody） |
| 中低端机掉帧 | 体验 | 分档 + adaptiveQuality + 逐行禁玻璃 |
| 替换导航壳影响返回栈/Tab 状态 | 功能回归 | 保留现有 GoRouter 结构，只替换视觉层；回归用例覆盖 |
| 包升级 API 变化（1.x → 2.0 默认改 solid） | 维护成本 | 锁定 `^1.17.5`，升级前跑验收 |
| shader 首次编译卡顿 | 首帧 | `initialize()` 预编译 |

### 8.2 外部依赖
- `liquid_glass_widgets` 1.17.5（MIT）及其 shader 资源；
- 现有 Material 3 主题（保留）；
- 真机测试：Redmi M511CD（高端参照）+ 至少 1 台中低端真机/模拟器限频。

---

## 9. 实施分期（供 Plan 阶段引用）
1. **P0 基础设施**：依赖接入、`GlassFeature` 开关、DeviceProfile、TierResolver、设置项、回退路径；
2. **P1 导航层**：A1–A3（+A4 仅高档）；
3. **P2 交互层**：A5–A7、B1–B8、B9；
4. **P3 内容层/动效**：C1–C9（仅高档，C1 用 solid）；
5. **P4 调优与验收**：分档帧率基准、无障碍、回归测试、文档。


---

## 10. 实现备注（A2 顶栏）

- 包自带 `GlassAppBar` 在普通 `Scaffold.appBar` 或嵌套 `GlassScaffold` 中**无法渲染**（无玻璃层/无可采样背景）。
- 最终方案：自建 `GlassTopBar`（`lib/src/features/glass/glass_top_bar.dart`）：
  - 内部用 `GlassContainer` 直接采样背景；
  - 页面 `Scaffold(extendBodyBehindAppBar: true)` + body 顶部内边距 `glassTopInset(context)`；
  - 内容滚动时穿过顶栏，产生真实模糊/折射。
- 已在「设置」「错题本」验证通过；复习/首页待接入。
