import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';
import 'package:smart_wrong_notebook/src/features/glass/glass_providers.dart';
import 'package:smart_wrong_notebook/src/config/scroll_tint.dart';

/// 顶栏高度 + 状态栏高度（内容穿透时需要给 body 的顶部内边距）。
double glassTopInset(BuildContext context) =>
    MediaQuery.paddingOf(context).top + kToolbarHeight;

/// 构造玻璃顶栏（替代 `Scaffold.appBar`）。
///
/// 开启玻璃时返回一个包含状态栏内边距的 `PreferredSize`（内部为
/// [GlassContainer]，可真实采样其后方滚动内容）；关闭时直接返回 [AppBar]。
/// 页面需要同时设置 `extendBodyBehindAppBar: true` 并把 body 顶部内边距设为
/// [glassTopInset]，内容才会从顶栏下方开始、滚动时穿过顶栏。
PreferredSizeWidget glassTopBar(
  BuildContext context, {
  required Widget title,
  List<Widget>? actions,
  Widget? leading,
  bool centerTitle = true,
}) {
  final container = ProviderScope.containerOf(context, listen: false);
  if (!container.read(glassEnabledProvider)) {
    return AppBar(
      title: title,
      actions: actions,
      leading: leading,
      centerTitle: centerTitle,
    );
  }
  final inset = MediaQuery.paddingOf(context).top;
  return PreferredSize(
    preferredSize: Size.fromHeight(kToolbarHeight + inset),
    child: GlassTopBar(
      title: title,
      actions: actions,
      leading: leading,
      centerTitle: centerTitle,
      topInset: inset,
    ),
  );
}

/// 自建玻璃顶栏：用 [GlassContainer] 直接采样顶栏后方内容。
class GlassTopBar extends ConsumerWidget {
  const GlassTopBar({
    required this.title,
    required this.topInset,
    this.actions,
    this.leading,
    this.centerTitle = true,
    super.key,
  });

  final Widget title;
  final double topInset;
  final List<Widget>? actions;
  final Widget? leading;
  final bool centerTitle;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    // 滚动进度 0..1：顶部时为 0（完全透明），下滑 72px 后变成完整玻璃面
    return ValueListenableBuilder<double>(
      valueListenable: globalScrollOffset,
      builder: (context, offset, _) {
        final progress = (offset / 72).clamp(0.0, 1.0);
        return _buildBar(context, ref, scheme, progress);
      },
    );
  }

  Widget _buildBar(
      BuildContext context, WidgetRef ref, ColorScheme scheme, double progress) {
    // 平滑过渡：模糊强度与着色都按 progress 线性增长（不做阈值跳变）
    final sigma = 18.0 * progress;
    return SizedBox(
      height: kToolbarHeight + topInset,
      child: Stack(
        children: <Widget>[
          if (sigma > 0.2)
            Positioned.fill(
              child: ProgressiveBlur(
                maxSigma: sigma,
                direction: ProgressiveBlurDirection.topToBottom,
              ),
            ),
          Positioned.fill(
            child: ColoredBox(
              color: scheme.surface.withValues(alpha: 0.42 * progress),
            ),
          ),
          Padding(
            padding: EdgeInsets.only(top: topInset),
            child: _buildContent(scheme),
          ),
        ],
      ),
    );
  }

  Widget _buildContent(ColorScheme scheme) {
    return SizedBox(
      height: kToolbarHeight,
      child: Stack(
        children: <Widget>[
          if (centerTitle)
            Positioned.fill(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 64),
                child: Center(
                  child: DefaultTextStyle(
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w600,
                      color: scheme.onSurface,
                    ),
                    child: title,
                  ),
                ),
              ),
            ),
          if (!centerTitle)
            Positioned.fill(
              child: Padding(
                padding: EdgeInsets.only(left: leading == null ? 16 : 56),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: DefaultTextStyle(
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w600,
                      color: scheme.onSurface,
                    ),
                    child: title,
                  ),
                ),
              ),
            ),
          if (leading != null)
            Align(alignment: Alignment.centerLeft, child: leading!),
          if (actions != null && actions!.isNotEmpty)
            Align(
              alignment: Alignment.centerRight,
              child: Row(mainAxisSize: MainAxisSize.min, children: actions!),
            ),
        ],
      ),
    );
  }
}
