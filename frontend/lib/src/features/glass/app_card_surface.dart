import 'package:flutter/material.dart';

/// 内容卡片表面色 / 描边（方案 A+B）。
///
/// 浅色：保持不透明 `surface`（与原来一致）。
/// 深色 + 页面背景：用半透明的 `surfaceContainerHigh` 轻微提亮，露出一点背景，
/// 并加 1px 亮描边，避免出现"死黑大块"。
class AppCardSurface {
  const AppCardSurface._();

  static bool _dark(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark;

  static Color color(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    if (!_dark(context)) return scheme.surface;
    return scheme.surfaceContainerHigh.withValues(alpha: 0.82);
  }

  static Color borderColor(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    if (!_dark(context)) return scheme.outlineVariant;
    return Colors.white.withValues(alpha: 0.14);
  }

  static Border border(BuildContext context) =>
      Border.all(color: borderColor(context));

  /// 带统一卡片外观的容器（圆角 + 背景 + 描边）。
  static BoxDecoration decoration(
    BuildContext context, {
    double radius = 12,
    BorderSide? side,
  }) =>
      BoxDecoration(
        color: color(context),
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(
          color: side?.color ?? borderColor(context),
          width: side?.width ?? 1,
        ),
      );
}
