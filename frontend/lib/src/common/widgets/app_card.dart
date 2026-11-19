import 'package:flutter/material.dart';
import 'package:smart_wrong_notebook/src/app/design/tokens.dart';

/// 统一卡片容器（对应 demo `.card`）。
///
/// 浅色：`card` 底 + `radiusLg` + `shadow1`（无需描边）。
/// 深色：`card` 底 + 1px `cardBorder`，无阴影。
class AppCard extends StatelessWidget {
  const AppCard({
    required this.child,
    this.padding,
    this.onTap,
    this.translucent = false,
    this.margin,
    super.key,
  });

  final Widget child;
  final EdgeInsetsGeometry? padding;
  final VoidCallback? onTap;

  /// 有页面背景图时可传 true，让卡片微微透出背景（默认关闭）。
  final bool translucent;
  final EdgeInsetsGeometry? margin;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final radius = BorderRadius.circular(AppTokens.radiusLg);
    final content = Container(
      padding: padding ?? const EdgeInsets.all(AppTokens.s4),
      decoration: BoxDecoration(
        color: translucent ? t.cardTranslucent : t.card,
        borderRadius: radius,
        border: t.isDark || translucent
            ? Border.all(color: t.cardBorder)
            : null,
        boxShadow: t.isDark ? null : t.shadow1,
      ),
      child: child,
    );
    final wrapped = onTap == null
        ? content
        : InkWell(
            onTap: onTap,
            borderRadius: radius,
            child: content,
          );
    return margin == null
        ? wrapped
        : Padding(padding: margin!, child: wrapped);
  }
}

/// 卡片内的小节标题（demo `.detail-label`）。
class AppSectionLabel extends StatelessWidget {
  const AppSectionLabel(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Padding(
      padding: const EdgeInsets.only(bottom: AppTokens.s2),
      child: Text(
        text,
        style: TextStyle(
          fontSize: AppTokens.textXs,
          fontWeight: FontWeight.w600,
          letterSpacing: 1,
          color: t.textTertiary,
        ),
      ),
    );
  }
}
