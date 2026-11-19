import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';
import 'package:smart_wrong_notebook/src/features/glass/glass_providers.dart';

/// P3/C4：滚动区域的边缘渐隐（ProgressiveBlur）。
///
/// 放在滚动内容上方（`Stack` + `Positioned`），让内容在顶栏/状态栏边缘
/// 渐隐而不是硬切；玻璃关闭时不渲染任何东西。
class GlassEdgeFade extends ConsumerWidget {
  const GlassEdgeFade({
    this.height = 48,
    this.maxSigma = 12,
    this.direction = ProgressiveBlurDirection.topToBottom,
    super.key,
  });

  final double height;
  final double maxSigma;
  final ProgressiveBlurDirection direction;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!ref.watch(glassEnabledProvider)) return const SizedBox.shrink();
    return IgnorePointer(
      child: SizedBox(
        height: height,
        child: ProgressiveBlur(maxSigma: maxSigma, direction: direction),
      ),
    );
  }
}
