# 实施计划 — 配置向导 + 双识别模式

> 来源：`docs/SPEC-SETUP-WIZARD.md`　策略：多 Agent 并行（前端为主，按目录隔离）

## 交付布局（前端 frontend/ 下新增/修改）
```
lib/src/features/setup/               # 配置向导（Agent-1 新建）
├── setup_wizard_screen.dart          # 向导入口（分步，PageView/Stepper）
├── pages/
│   ├── welcome_page.dart             # 欢迎页
│   ├── provider_page.dart            # 供应商+Key 配置页
│   ├── vision_mode_page.dart         # 识别模式选择页
│   └── done_page.dart                # 完成页
└── setup_controller.dart             # 向导状态（Riverpod 可选）
lib/src/data/repositories/settings_repository.dart  # 加 setup_complete/use_vision_mode（Agent-2）
lib/src/data/remote/ai/ai_analysis_service.dart     # 分流逻辑 + DeepSeek 视觉直连（Agent-3）
lib/main.dart                          # 首次启动进向导的路由（Agent-4）
```

## Agent 分工（依赖关系）
1. **Agent-2（存储层，先行）**：`settings_repository.dart` 加 `getUseVisionMode/setUseVisionMode/getSetupComplete/setSetupComplete`。定义视觉模式判定工具 `isDeepSeekKey(config)`。产出共享契约。
2. **Agent-1（向导 UI，依赖 Agent-2 存储）**：`lib/src/features/setup/` 完整分步向导，调用存储层保存配置。
3. **Agent-3（分流逻辑，依赖存储层）**：`ai_analysis_service.dart` 分析入口按 `use_vision_mode + isDeepSeekKey` 分流：视觉模式走 DeepSeek 视觉直连读图，标准模式走云端。
4. **Agent-4（路由接入）**：`main.dart` 首次启动（`setup_complete` 未设）→ 进向导；否则正常流程。

## 顺序
- Agent-2 先落存储层（1/3/4 都依赖它）。
- Agent-1 与 Agent-3 基于存储层并行（1 写 UI，3 写分流，文件不冲突）。
- Agent-4 最后接线路由。

## 验证
- flutter analyze 0 错误。
- 首次启动进向导 → 配置 → 进首页。
- 视觉模式 + DeepSeek → 前端直连视觉识别。
- 标准模式 → 云端识别（回归）。
