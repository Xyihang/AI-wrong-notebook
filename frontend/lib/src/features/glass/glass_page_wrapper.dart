import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';
import 'package:smart_wrong_notebook/src/features/glass/glass_providers.dart';

/// 页面级玻璃外壳：开启玻璃时用 [GlassScaffold] + [GlassAppBar]（内容可滚动到
/// 顶栏下方，产生真实模糊/折射）；关闭时回退 [Scaffold] + Material [AppBar]。
///
/// 注意：body 需要自带顶部内边距（状态栏 + 44 工具栏），因为
/// `extendBody: true` 会让内容从屏幕顶部开始。
class GlassPageWrapper extends ConsumerWidget {
  const GlassPageWrapper({
    required this.title,
    required this.body,
    this.actions,
    this.leading,
    this.bodyNeedsTopInset = true,
    super.key,
  });

  final Widget title;
  final Widget body;
  final List<Widget>? actions;
  final Widget? leading;

  /// body 是否已经/需要自行处理顶部内边距（用于滚动穿透）。
  final bool bodyNeedsTopInset;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final enabled = ref.watch(glassEnabledProvider);
    if (!enabled) {
      return Scaffold(
        appBar: AppBar(title: title, actions: actions, leading: leading),
        body: body,
      );
    }
    // 显式提供背景源：GlassScaffold 需要可采样的背景层，
    // 否则顶栏玻璃没有可折射内容（会退化成透明标题）。
    final scheme = Theme.of(context).colorScheme;
    return GlassScaffold(
      extendBody: bodyNeedsTopInset,
      background: DecoratedBox(
        decoration: BoxDecoration(color: scheme.surface),
        child: const SizedBox.expand(),
      ),
      backgroundColor: scheme.surface,
      appBar: GlassAppBar(title: title, actions: actions, leading: leading),
      body: body,
    );
  }
}
