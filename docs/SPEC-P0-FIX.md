# P0 修复规格 — 多题识别丢失 + 额度按账户计（SPEC-P0-FIX）

> 状态：**已修复并部署云端（本地+云端验证通过）**　对应三个 P0：
> 1. 后端路径（纯OCR / 后端视觉兜底）无法识别多道题目，仅前端直连可正确识别 ✅
> 2. 三种情况的剩余额度未分开计算，同一天换 Key 会「重置」✅
> 3. 额度需改为按账户计算 ✅

---

## 1. P0-1 多题识别丢失

### 现象
- 一张照片含**多道题目**时：
  - 前端直连视觉（视觉模式）→ 正确识别全部题目；
  - 后端路径（纯 OCR 或后端视觉兜底）→ **只剩第一道题**，其余丢失。

### 根因（代码证据）
1. 后端结构化 prompt：`backend/app/llm/prompts.py` `build_extraction_prompt` 第 84 行：
   > 「若文本包含多个小题，**只提取第一道完整的题**」
   → 无论 OCR 文本含几道题，后端 `QuestionOut.stem` 只保留第一题。
2. 前端取后端结果：`ai_analysis_service.dart` `_extractionFromBackendRecord`：
   ```dart
   final rawText = stem.isNotEmpty ? stem : ocrText;
   ```
   → 优先用 `stem`（只剩第一题），多题内容被丢弃。
3. 前端直连视觉 prompt（`_buildExtractionPrompt`）**无**「只提取第一道」限制 → 视觉模型直读原图、完整返回全部题目。
4. 云端日志佐证：`analyze` 均 200、视觉兜底「成功」，说明不是调用失败，而是**结构化阶段主动丢弃多题**。

### 修复方案
- **后端**：`build_extraction_prompt` 去掉「只提取第一道完整的题」，改为：
  > 「若 OCR 文本包含多道题目，**完整保留全部题目内容**，不要遗漏、不要合并、不要只取第一道；题号/序号原样保留。」
- `stem` 在多题场景下为「完整题目文本」（含全部题）；`ocr_text` 保持完整原文不变。
- **前端**：`_extractionFromBackendRecord` 保持 `stem` 优先（修复后 stem 已含全部题）；无前端代码改动（后端修复即生效）。
- 影响：单题场景不变；多题场景前端拿到完整文本，后续拆分/保存逻辑（question_split）可正确处理。

---

## 2. P0-2 额度三种情况分开计算 + 换 Key 不重置

### 现象
- 同一天：先无 Key 用（累计 10 池）→ 配 Key（切到每日 50 池）→ 显示「满额」，像被重置；再删 Key 又回 10 池。
- 三种识别路径的额度没有分开表达。

### 现状（代码证据）
`backend/app/core/vision_rate_limiter.py`：
- 有 Key：`_daily_counter[ip]` 每 IP 每天 50；
- 无 Key：`_total_counter[ip]` 每 IP 累计 10；
- 两个池子**已独立**，但都按 **IP** 计；档位由 `has_vision_key` 布尔切换 → 切换时前端看到的「剩余」跳到另一个池子，造成「重置」错觉。

### 三种情况定义（修复后明确）
| 情况 | 是否扣云端额度 | 池子 |
|---|---|---|
| A. 纯本地 OCR（质量良好） | **不扣** | 无 |
| B. 后端视觉兜底（有 Key 档） | 扣 1 次 | 每日 50 / 账户 |
| C. 后端视觉兜底（无 Key 档） | 扣 1 次 | 累计 10 / 账户 |
| （另：前端直连视觉 = 用用户自己的 Key，**不占后端额度**）| 不扣 | 无 |

- B / C 两个池子**完全独立**：换 Key（档位切换）只改变「当前显示哪个池子」，**两个池子的计数各自保留、互不重置**。
- A 与前端直连永不扣额度。

### 修复方案
- `vision_rate_limiter` 改造为**按账户**计数（见 §3），同时保持 B/C 池子分离语义。
- 前端额度卡片：显示当前档位池子的剩余 + 说明「换 Key 不会重置各池计数」（文案可微调）。

---

## 3. P0-3 额度按账户计算

### 现状
- 按 IP 计数：同一账号换设备/换网络额度就换池；不同账号共挤同一 IP 池。

### 修复方案
- `vision_rate_limiter` 的 key 从 `ip` 改为 **`user:{user_id}`**（登录用户）或 **`ip:{ip}`**（匿名/未登录，兼容旧客户端）：
  ```text
  计数键 = 登录用户 ? f"user:{user_id}" : f"ip:{client_ip}"
  ```
- 数据来源：
  - `question_routes.analyze` 已有 `current_user`（get_optional_user）→ 传 `user_id` 给限流器；
  - `settings_routes.vision-quota` 增加 `get_optional_user` → 按用户返回剩余；匿名按 IP（当前行为保留）。
- 内存存储不变（单实例）；重启清零（可选优化：持久化到 SQLite，见 Should）。

### 影响面
- `vision_rate_limiter.py`：API 增加 `user_id` 维度；`try_consume_vision_slot` / `remaining_vision_slots` 签名扩展。
- `question_routes.py` analyze：`try_consume_vision_slot(client_ip, has_vision_key, user_id=...)`、`remaining_vision_slots(...)` 同步。
- `settings_routes.py` vision-quota：按当前用户（或匿名 IP）返回。
- 前端：`GET /settings/vision-quota` 无需改参数（后端从 token 取用户；匿名仍传 has_vision_key 走 IP）。

---

## 4. 实施顺序

1. 后端 `prompts.py`：多题完整保留（P0-1）。
2. 后端 `vision_rate_limiter.py`：按账户 key + 双池独立（P0-2/3）。
3. 后端 `question_routes.py` / `settings_routes.py`：接入 user_id。
4. 本地测试：
   - 多题图走后端路径 → 返回完整多题文本（对比前端直连）。
   - 登录用户 A 用额度 → 换 Key → 池子计数不重置、各自独立。
   - 用户 A 与 B 额度互不影响；匿名按 IP。
5. 前端文案（额度卡片说明）微调（如需要）。
6. 部署云端 + 真机验证。

## 5. 验收标准
- [ ] 后端路径（纯OCR/后端视觉兜底）识别多题：`stem`/`ocr_text` 含全部题目，不丢题
- [ ] 单题场景结果与修复前一致（无回归）
- [ ] 有 Key / 无 Key 两个池子独立计数，换 Key 不重置对方
- [ ] 登录用户额度按 user_id 计：换设备/换 IP 不丢；不同账户独立
- [ ] 匿名用户按 IP 计（兼容旧版）
- [ ] 纯 OCR / 前端直连不扣额度

## 6. 多 Agent vs 自己 评估
- 三处改动**强耦合**（限流器 → 两个路由 → 前端展示），共用同一数据模型与签名；
- 需要连贯理解现有 prompt / 限流 / 前端取数逻辑，任务边界不清晰时拆分反而增加协调成本；
- **结论：自己直接修复**（串行、可控、可快速本地验证）。不启用多 Agent 团队；如需并行验证可后续用子代理做回归测试。

## 7. 风险与注意
- 多题保留可能使 `stem` 变长：`analyze` 返回体变大，前端大 token 模式已兼容（8000 tokens）。
- 限流器改 key 后，**云端旧计数（按 IP）失效**（部署即重新计）——可接受，属预期重置。
- **额度池已持久化到 SQLite**（`data/vision_quota.db`，挂载卷内）：后端重启不清零；写库失败仅告警，不影响识别。
