import 'package:flutter/material.dart';
import 'package:smart_wrong_notebook/src/app/design/tokens.dart';
import 'package:smart_wrong_notebook/src/common/widgets/app_card.dart';

/// 首页主统计卡（demo `.stat-hero`）：大数字 + 副标签 + 右侧进度环。
class AppStatHero extends StatelessWidget {
  const AppStatHero({
    required this.label,
    required this.value,
    this.unit,
    this.progress,
    this.chips = const <Widget>[],
    super.key,
  });

  final String label;
  final int value;
  final String? unit;

  /// 0..1，为 null 时不显示进度环。
  final double? progress;
  final List<Widget> chips;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return AppCard(
      padding: const EdgeInsets.symmetric(
          horizontal: AppTokens.s4, vertical: AppTokens.s6),
      child: Stack(
        children: <Widget>[
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                label,
                style: TextStyle(
                    fontSize: AppTokens.textXs, color: t.textSecondary),
              ),
              const SizedBox(height: AppTokens.s1),
              Row(
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: <Widget>[
                  Text(
                    '$value',
                    style: TextStyle(
                      fontSize: AppTokens.textXxl,
                      fontWeight: FontWeight.w600,
                      color: t.textPrimary,
                      height: 1.25,
                    ),
                  ),
                  if (unit != null) ...<Widget>[
                    const SizedBox(width: AppTokens.s1),
                    Text(
                      unit!,
                      style: TextStyle(
                          fontSize: AppTokens.textSm, color: t.textTertiary),
                    ),
                  ],
                ],
              ),
              if (chips.isNotEmpty) ...<Widget>[
                const SizedBox(height: AppTokens.s3),
                Wrap(spacing: AppTokens.s2, runSpacing: AppTokens.s2, children: chips),
              ],
            ],
          ),
          if (progress != null)
            Positioned(
              right: 0,
              top: 0,
              bottom: 0,
              child: Center(
                child: SizedBox(
                  width: 72,
                  height: 72,
                  child: Stack(
                    alignment: Alignment.center,
                    children: <Widget>[
                      SizedBox(
                        width: 72,
                        height: 72,
                        child: CircularProgressIndicator(
                          value: progress!.clamp(0.0, 1.0),
                          strokeWidth: 8,
                          backgroundColor: t.primarySoft,
                          valueColor: AlwaysStoppedAnimation<Color>(t.primary),
                        ),
                      ),
                      Text(
                        '${(progress! * 100).round()}%',
                        style: TextStyle(
                          fontSize: AppTokens.textBase,
                          fontWeight: FontWeight.w600,
                          color: t.primary,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// 小统计卡（demo `.stat-mini`）：数字 + 标签，用于三宫格科目统计。
class AppStatMini extends StatelessWidget {
  const AppStatMini({
    required this.value,
    required this.label,
    required this.color,
    this.onTap,
    super.key,
  });

  final int value;
  final String label;
  final Color color;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return AppCard(
      onTap: onTap,
      padding: const EdgeInsets.symmetric(
          horizontal: AppTokens.s2, vertical: AppTokens.s3),
      child: Column(
        children: <Widget>[
          Text(
            '$value',
            style: TextStyle(
              fontSize: AppTokens.textLg,
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style:
                TextStyle(fontSize: AppTokens.textXs, color: t.textSecondary),
          ),
        ],
      ),
    );
  }
}
