import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';
import 'package:smart_wrong_notebook/src/features/glass/glass_providers.dart';

/// 玻璃进度条：开启玻璃时用 [GlassProgressIndicator.linear]，否则回退 Material。
Widget appProgressBar(
  BuildContext context,
  WidgetRef ref, {
  double? value,
  double height = 6,
}) {
  if (!ref.watch(glassEnabledProvider)) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(4),
      child: LinearProgressIndicator(
        value: value,
        minHeight: height,
      ),
    );
  }
  return GlassProgressIndicator.linear(
    value: value,
    height: height,
    quality: ref.watch(glassQualityProvider),
  );
}

/// 统一底部弹层：玻璃开启时用 [GlassContainer] 作为弹层表面，
/// 否则回退普通 [showModalBottomSheet]。
Future<T?> showAppSheet<T>(
  BuildContext context, {
  required WidgetBuilder builder,
  bool isScrollControlled = true,
}) {
  final container = ProviderScope.containerOf(context, listen: false);
  final enabled = container.read(glassEnabledProvider);
  final quality = container.read(glassQualityProvider);
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: isScrollControlled,
    backgroundColor: enabled ? Colors.transparent : null,
    elevation: enabled ? 0 : null,
    showDragHandle: !enabled,
    builder: (ctx) {
      final child = builder(ctx);
      if (!enabled) return child;
      return GlassContainer(
        quality: quality,
        padding: const EdgeInsets.only(top: 6),
        child: SafeArea(top: false, child: child),
      );
    },
  );
}

/// 统一确认弹窗：玻璃开启时用 [GlassContainer] 作为弹窗表面，
/// 否则回退 Material [AlertDialog]。返回 true=确认。
Future<bool> showAppConfirm(
  BuildContext context, {
  required String title,
  String? message,
  String confirmText = '确定',
  String cancelText = '取消',
  bool destructive = false,
}) async {
  final container = ProviderScope.containerOf(context, listen: false);
  final enabled = container.read(glassEnabledProvider);
  final quality = container.read(glassQualityProvider);
  final result = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (c) {
      if (!enabled) {
        return AlertDialog(
          title: Text(title),
          content: message == null ? null : Text(message),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: Text(cancelText),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(c, true),
              child: Text(confirmText),
            ),
          ],
        );
      }
      return Dialog(
        backgroundColor: Colors.transparent,
        elevation: 0,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 340),
          child: GlassContainer(
            padding: const EdgeInsets.all(20),
            quality: quality,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (message != null) ...<Widget>[
                  const SizedBox(height: 8),
                  Text(
                    message,
                    style: const TextStyle(fontSize: 14, height: 1.5),
                  ),
                ],
                const SizedBox(height: 18),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: <Widget>[
                    TextButton(
                      onPressed: () => Navigator.pop(c, false),
                      child: Text(cancelText),
                    ),
                    const SizedBox(width: 8),
                    FilledButton(
                      onPressed: () => Navigator.pop(c, true),
                      style: destructive
                          ? FilledButton.styleFrom(
                              backgroundColor:
                                  Theme.of(c).colorScheme.error,
                            )
                          : null,
                      child: Text(confirmText),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      );
    },
  );
  return result ?? false;
}

/// 统一提示：玻璃开启时用 [GlassToast]，否则回退 SnackBar。
void showAppToast(
  BuildContext context,
  String message, {
  bool isError = false,
}) {
  final container = ProviderScope.containerOf(context, listen: false);
  final enabled = container.read(glassEnabledProvider);
  if (enabled) {
    GlassToast.show(
      context,
      message: message,
      type: isError ? GlassToastType.error : GlassToastType.success,
      quality: container.read(glassQualityProvider),
    );
    return;
  }
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text(message)),
  );
}
