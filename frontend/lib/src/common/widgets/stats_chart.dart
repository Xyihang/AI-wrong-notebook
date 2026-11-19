import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:smart_wrong_notebook/src/app/design/tokens.dart';
import 'package:smart_wrong_notebook/src/domain/models/mastery_level.dart';

// ---------------------------------------------------------------------------
// 图表数据系列色（柱体之间需要互相区分，故刻意保留既有色值，不替换为语义 token）。
// 除这三条系列色外，本文件的轴文字 / 网格线 / 提示框 / 容器底色一律走
// `context.tokens`。
// ---------------------------------------------------------------------------
const Color _seriesMastered = Color(0xFF16A34A);
const Color _seriesReviewing = Color(0xFFD97706);
const Color _seriesNew = Color(0xFF6B7280);

const Map<MasteryLevel, Color> _seriesColors = <MasteryLevel, Color>{
  MasteryLevel.mastered: _seriesMastered,
  MasteryLevel.reviewing: _seriesReviewing,
  MasteryLevel.newQuestion: _seriesNew,
};

class StatsBarChart extends StatelessWidget {
  const StatsBarChart({
    super.key,
    required this.total,
    required this.mastered,
    required this.reviewing,
    required this.newQ,
  });

  final int total;
  final int mastered;
  final int reviewing;
  final int newQ;

  static const _labels = {
    MasteryLevel.mastered: '已掌握',
    MasteryLevel.reviewing: '复习中',
    MasteryLevel.newQuestion: '新增',
  };

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final maxY =
        [mastered, reviewing, newQ].reduce((a, b) => a > b ? a : b).toDouble();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        SizedBox(
          height: 160,
          child: BarChart(
            BarChartData(
              alignment: BarChartAlignment.spaceAround,
              maxY: maxY < 1 ? 5 : maxY * 1.3,
              barTouchData: BarTouchData(
                enabled: total > 0,
                touchTooltipData: BarTouchTooltipData(
                  getTooltipColor: (_) => t.card,
                  tooltipRoundedRadius: AppTokens.radiusSm,
                  getTooltipItem: (group, groupIndex, rod, rodIndex) {
                    final level = MasteryLevel.values[group.x.toInt()];
                    return BarTooltipItem(
                      '${_labels[level]}\n${rod.toY.toInt()} 题',
                      TextStyle(
                        color: t.textPrimary,
                        fontSize: AppTokens.textXs,
                      ),
                    );
                  },
                ),
              ),
              titlesData: FlTitlesData(
                show: true,
                bottomTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    getTitlesWidget: (value, meta) {
                      final level = MasteryLevel.values[value.toInt()];
                      return Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Text(
                          _labels[level]!,
                          style: TextStyle(
                            fontSize: AppTokens.textXs,
                            color: t.textTertiary,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      );
                    },
                    reservedSize: 32,
                  ),
                ),
                leftTitles:
                    const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                topTitles:
                    const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                rightTitles:
                    const AxisTitles(sideTitles: SideTitles(showTitles: false)),
              ),
              gridData: FlGridData(
                show: true,
                drawVerticalLine: false,
                getDrawingHorizontalLine: (value) =>
                    FlLine(color: t.cardBorder, strokeWidth: 1),
              ),
              borderData: FlBorderData(show: false),
              barGroups: <BarChartGroupData>[
                BarChartGroupData(
                  x: MasteryLevel.newQuestion.index,
                  barRods: [
                    BarChartRodData(
                      toY: newQ.toDouble(),
                      color: _seriesColors[MasteryLevel.newQuestion],
                      width: 28,
                      borderRadius: const BorderRadius.vertical(
                          top: Radius.circular(AppTokens.radiusSm)),
                    ),
                  ],
                ),
                BarChartGroupData(
                  x: MasteryLevel.reviewing.index,
                  barRods: [
                    BarChartRodData(
                      toY: reviewing.toDouble(),
                      color: _seriesColors[MasteryLevel.reviewing],
                      width: 28,
                      borderRadius: const BorderRadius.vertical(
                          top: Radius.circular(AppTokens.radiusSm)),
                    ),
                  ],
                ),
                BarChartGroupData(
                  x: MasteryLevel.mastered.index,
                  barRods: [
                    BarChartRodData(
                      toY: mastered.toDouble(),
                      color: _seriesColors[MasteryLevel.mastered],
                      width: 28,
                      borderRadius: const BorderRadius.vertical(
                          top: Radius.circular(AppTokens.radiusSm)),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        Row(
          children: <Widget>[
            _LegendDot(
                color: _seriesColors[MasteryLevel.newQuestion]!,
                label: '新增 ($newQ)'),
            const SizedBox(width: 16),
            _LegendDot(
                color: _seriesColors[MasteryLevel.reviewing]!,
                label: '复习中 ($reviewing)'),
            const SizedBox(width: 16),
            _LegendDot(
                color: _seriesColors[MasteryLevel.mastered]!,
                label: '已掌握 ($mastered)'),
          ],
        ),
      ],
    );
  }
}

class _LegendDot extends StatelessWidget {
  const _LegendDot({required this.color, required this.label});

  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(
              color: color, borderRadius: BorderRadius.circular(5)),
        ),
        const SizedBox(width: 4),
        Text(
          label,
          style: TextStyle(fontSize: AppTokens.textXs, color: t.textTertiary),
        ),
      ],
    );
  }
}

class StatsGrid extends StatelessWidget {
  const StatsGrid({
    super.key,
    required this.total,
    required this.todayNew,
    required this.pending,
    required this.mastered,
    this.onTotalTap,
    this.onTodayNewTap,
    this.onPendingTap,
    this.onMasteredTap,
  });

  final int total;
  final int todayNew;
  final int pending;
  final int mastered;
  final VoidCallback? onTotalTap;
  final VoidCallback? onTodayNewTap;
  final VoidCallback? onPendingTap;
  final VoidCallback? onMasteredTap;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;

    return Column(
      children: <Widget>[
        Row(
          children: <Widget>[
            Expanded(
              child: _StatCard(
                label: '题库总量',
                value: '$total',
                accent: t.primary,
                background: t.primarySoft,
                onTap: onTotalTap,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _StatCard(
                label: '今日新增',
                value: '$todayNew',
                accent: t.textSecondary,
                background: t.formulaBg,
                onTap: onTodayNewTap,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: <Widget>[
            Expanded(
              child: _StatCard(
                label: '已掌握',
                value: '$mastered',
                accent: t.success,
                background: t.successSoft,
                onTap: onMasteredTap,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _StatCard(
                label: '待复习',
                value: '$pending',
                accent: t.warning,
                background: t.warningSoft,
                onTap: onPendingTap,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _StatCard extends StatelessWidget {
  const _StatCard({
    required this.label,
    required this.value,
    required this.accent,
    required this.background,
    this.onTap,
  });

  final String label;
  final String value;

  /// 语义强调色（主色 / 次要 / 成功 / 警告）。
  final Color accent;

  /// 浅色下的软底；深色下由 [accent] 叠透明度得出。
  final Color background;

  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final fill = t.isDark ? accent.withValues(alpha: 0.14) : background;
    final border = t.isDark
        ? accent.withValues(alpha: 0.35)
        : accent.withValues(alpha: 0.22);

    return Material(
      color: fill,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppTokens.radiusMd),
        side: BorderSide(color: border),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            children: <Widget>[
              Text(
                value,
                style: TextStyle(
                  fontSize: AppTokens.textLg,
                  fontWeight: FontWeight.bold,
                  color: accent,
                ),
              ),
              const SizedBox(height: 2),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Text(label,
                      style: TextStyle(
                          fontSize: AppTokens.textXs, color: accent)),
                  if (onTap != null) ...<Widget>[
                    const SizedBox(width: 2),
                    Icon(Icons.chevron_right, size: 14, color: accent),
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
