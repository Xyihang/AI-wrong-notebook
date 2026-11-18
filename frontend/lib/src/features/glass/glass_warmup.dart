import 'dart:async';

import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';

/// shader 预热：在开屏动画期间后台完成（规格 §4.1.1）。
///
/// 与启动流程（远程配置拉取、会话恢复）并行，不阻塞 UI；
/// 未完成时截图上先以 minimal 渲染，完成后再自动升级。
Future<void>? glassWarmUpFuture;

/// 启动预热（幂等）。
void startGlassWarmUp() {
  glassWarmUpFuture ??= _warmUp();
}

Future<void> _warmUp() async {
  try {
    await LiquidGlassWidgets.initialize();
  } catch (_) {
    // 预热失败不影响使用，组件会自行降级。
  }
}
