import 'package:flutter/material.dart';
import 'package:smart_wrong_notebook/src/app/design/tokens.dart';

/// 筛选 chip（demo `.chip`）：未选 = 卡底 + 描边；选中 = primary 填充白字。
class AppChip extends StatelessWidget {
  const AppChip({
    required this.label,
    required this.selected,
    required this.onTap,
    super.key,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(
            horizontal: AppTokens.s3, vertical: 4),
        decoration: BoxDecoration(
          color: selected ? t.primary : t.card,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: selected ? t.primary : t.cardBorder),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: AppTokens.textXs,
            fontWeight: selected ? FontWeight.w500 : FontWeight.w400,
            color: selected ? t.onPrimary : t.textSecondary,
            height: 1.5,
          ),
        ),
      ),
    );
  }
}

/// 小标签（demo `.q-tag` / `.q-subject`）。
class AppTag extends StatelessWidget {
  const AppTag(
    this.label, {
    this.color,
    this.background,
    this.radius = AppTokens.radiusSm,
    this.fontWeight,
    super.key,
  });

  final String label;
  final Color? color;
  final Color? background;
  final double radius;
  final FontWeight? fontWeight;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: AppTokens.s2, vertical: 2),
      decoration: BoxDecoration(
        color: background ?? t.formulaBg,
        borderRadius: BorderRadius.circular(radius),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: AppTokens.textXs,
          color: color ?? t.textSecondary,
          fontWeight: fontWeight,
        ),
      ),
    );
  }
}
