# 功能规格文档 — 首次启动配置向导 + 双识别模式

> 版本：v1.0　状态：已评审　来源：用户需求 + 现有代码分析

## 1. 概述

### 1.1 背景
应用当前第一次启动走的是纯介绍页（onboarding，3 页「拍照/AI解析/举一反三」），没有真正的配置环节。用户希望：**第一次打开应用显示「配置向导」**，引导用户完成 AI 供应商 + API Key 配置，并让用户选择识别模式。

### 1.2 目标
1. 首次启动显示**分步配置向导**（点击「下一步」逐步推进）。
2. 配置项：
   - 供应商 + 对应 API Key
   - 是否启用「更精确的视觉模型」（仅 DeepSeek，且只接受 DeepSeek Key）
3. 据此区分**两种用户/两种识别模式**，影响后续题目识别逻辑。

### 1.3 范围
- 前端 Flutter：新增配置向导页、配置存储、识别模式路由。
- 后端：视觉模型识别已有能力，可能需小调整。
- 不在本次范围：认证、云同步。

---

## 2. 两种用户 / 两种识别模式（核心）

| 模式 | 触发条件 | 识别流程 | 数据来源 |
|---|---|---|---|
| **标准模式** | 用户未启用视觉模型 / 或非 DeepSeek | 当前逻辑：手机拍照 → 云端后端（RapidOCR + DeepSeek-v4-flash 结构化）→ 返回 | 云端后端 |
| **视觉模式** | 用户启用视觉模型 且 配置的是 DeepSeek Key | 手机拍照 → **直接调 DeepSeek 视觉模型**识别题目 → 云端/后端结构化 | 用户自己的 DeepSeek 视觉模型 |

**判定规则（向导第 2 步选择）：**
- 用户选择「不使用视觉模型」→ 标准模式（用现有逻辑）。
- 用户选择「使用视觉模型」→ **校验 API Key 是否为 DeepSeek**：
  - 是 DeepSeek → 视觉模式（直接用 DeepSeek 视觉模型读图）
  - 不是 DeepSeek → 拒绝，提示「视觉模式仅支持 DeepSeek」，保持标准模式。

---

## 3. 用户故事
- 作为新用户，我希望首次启动有清晰的配置向导，以便快速完成设置。
- 作为学生，我希望选择「标准模式」用云端识别，以便无需自己维护 Key。
- 作为深度用户，我希望选择「视觉模式」用 DeepSeek 视觉模型，以便识别手写/复杂题目更准。

---

## 4. 功能需求

### 4.1 配置向导（首次启动显示）
- **触发**：首次启动（`onboarding_done` 未设置 或 新 key `setup_complete` 未设置）。
- **流程**（分步，底部「下一步」按钮）：
  1. **欢迎页**：应用介绍 + 「开始配置」。
  2. **供应商 + Key**：选择供应商（DeepSeek / 其它 / 自定义），填 Base URL + API Key + 模型。校验连通性（可选「测试连接」）。
  3. **识别模式选择**：单选「标准模式（推荐）」/「视觉模式（DeepSeek）」。若选视觉模式，校验 Key 是否 DeepSeek，非 DeepSeek 提示并回退标准。
  4. **完成页**：总结所选配置，「开始使用」进入首页。
- **异常**：Key 为空 → 提示；连通性失败 → 提示但允许继续（标准模式可离线降级）。

### 4.2 供应商 + Key 配置
- 复用现有 `AiProviderConfig`（id/displayName/baseUrl/model/apiKey）存储。
- 支持供应商预设（DeepSeek / VBcode / dohoya / 自定义）。
- 保存到 `settingsRepository`（现有 `saveAiProviderConfig`）。

### 4.3 视觉模式开关（新增存储）
- 新增设置项 `use_vision_mode`（true/false）存到 `settingsRepository`。
- 仅当 `use_vision_mode=true` 且 Key 是 DeepSeek 时，走视觉模式。

### 4.4 识别流程分流（核心改动）
`ai_analysis_service.dart` 分析入口处，根据模式分流：
```
分析入口 analyzeExtractedQuestion / extractQuestionStructure
  → 读取 use_vision_mode + provider 配置
  → 若 视觉模式 且 是 DeepSeek Key：
        用 DeepSeek 视觉模型直接读图（前端直连，max_tokens 大）
     否则（标准模式）：
        走现有逻辑（云端后端 analyzeImage / analyzeText）
```

---

## 5. 非功能需求
- **兼容性**：Android/iOS 一致；不破坏现有标准模式。
- **安全**：API Key 存现有 secure/存储，不硬编码；不泄露到日志。
- **可回退**：用户可在设置里改回标准模式。

---

## 6. 数据规格
### 6.1 新增设置项（settingsRepository）
| key | 类型 | 说明 |
|---|---|---|
| `setup_complete` | string | "true" 表示向导已完成 |
| `use_vision_mode` | string | "true"/"false" 视觉模式开关 |

### 6.2 复用现有
- `AiProviderConfig`（供应商配置）
- `onboarding_done`（旧引导标记，保留兼容）

---

## 7. 验收标准
- [ ] 首次启动显示配置向导，点「下一步」分步推进
- [ ] 完成后进入首页；再次启动不再显示向导
- [ ] 供应商 + Key 可保存
- [ ] 选择视觉模式且 DeepSeek Key → 分析走 DeepSeek 视觉模型读图
- [ ] 选择标准模式 或 非 DeepSeek Key → 分析走云端后端
- [ ] 设置里可切换模式
- [ ] 不破坏现有云端标准模式识别

---

## 8. 风险与依赖
- **视觉模式前端直连 DeepSeek**：依赖用户 Key 有效 + 网络；max_tokens 需足够（推理模型 content 可能为空，需大 token + 重试）。
- **Key 校验**：判断「是否 DeepSeek」需识别 baseUrl/模型名（如 api.deepseek.com）。
- 前端改动较大（向导 UI + 分流逻辑），需回归测试标准模式。

## 9. 明确不做（Won't Have）
- 认证/账号
- 云同步
- 后端视觉模型逻辑重构（已有，保持）
