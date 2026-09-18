import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:smart_wrong_notebook/src/app/providers.dart';
import 'package:smart_wrong_notebook/src/domain/models/achievement.dart';

/// 成就墙：展示所有徽章（已解锁彩色 / 未解锁置灰）与学习连击进度。
class AchievementsScreen extends ConsumerWidget {
  const AchievementsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final snapshotAsync = ref.watch(gamificationSnapshotProvider);
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('成就徽章')),
      body: snapshotAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('加载失败: $e')),
        data: (snapshot) {
          final unlocked =
              snapshot.achievements.where((a) => a.isUnlocked).length;
          final total = snapshot.achievements.length;

          return ListView(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
            children: <Widget>[
              _StreakSummaryCard(
                streak: snapshot.streak,
                activeToday: snapshot.activeToday,
              ),
              const SizedBox(height: 16),
              _ProgressCard(unlocked: unlocked, total: total),
              const SizedBox(height: 20),
              Text('徽章收藏', style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 12),
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: snapshot.achievements
                    .map((a) => _AchievementTile(achievement: a))
                    .toList(),
              ),
              const SizedBox(height: 16),
              _LegendHint(colorScheme: colorScheme),
            ],
          );
        },
      ),
    );
  }
}

/// 顶部连击摘要。
class _StreakSummaryCard extends StatelessWidget {
  const _StreakSummaryCard({required this.streak, required this.activeToday});

  final int streak;
  final bool activeToday;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    const orange = Color(0xFFF97316);
    final subtitle = streak == 0
        ? '今天学一道题，开启你的连击'
        : (activeToday ? '已保持 $streak 天，很棒！' : '今天还没学，学一下保持连击');

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: isDark
              ? [orange.withValues(alpha: 0.30), orange.withValues(alpha: 0.12)]
              : [const Color(0xFFFFF7ED), const Color(0xFFFFEDD5)],
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isDark ? orange.withValues(alpha: 0.4) : const Color(0xFFFED7AA),
        ),
      ),
      child: Row(
        children: <Widget>[
          const Text('🔥', style: TextStyle(fontSize: 34)),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text.rich(
                  TextSpan(
                    children: <InlineSpan>[
                      TextSpan(
                        text: '$streak',
                        style: TextStyle(
                          fontSize: 30,
                          fontWeight: FontWeight.w800,
                          color: orange,
                        ),
                      ),
                      TextSpan(
                        text: ' 天连击',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: colorScheme.onSurface,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: TextStyle(
                    fontSize: 12,
                    color: isDark
                        ? colorScheme.onSurfaceVariant
                        : const Color(0xFFC2410C),
                  ),
                ),
              ],
            ),
          ),
          Icon(CupertinoIcons.flame_fill,
              color: orange.withValues(alpha: 0.9), size: 26),
        ],
      ),
    );
  }
}

/// 收集进度卡片。
class _ProgressCard extends StatelessWidget {
  const _ProgressCard({required this.unlocked, required this.total});

  final int unlocked;
  final int total;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final ratio = total == 0 ? 0.0 : unlocked / total;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: colorScheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              const Text('🏅'),
              const SizedBox(width: 8),
              Text('收集进度',
                  style: TextStyle(
                      fontSize: 15, fontWeight: FontWeight.w700)),
              const Spacer(),
              Text('$unlocked / $total',
                  style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: colorScheme.primary)),
            ],
          ),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(
              value: ratio,
              minHeight: 8,
              backgroundColor: colorScheme.surfaceContainerHighest,
              color: const Color(0xFFF97316),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            '坚持拍照与复习，解锁全部徽章',
            style: TextStyle(
              fontSize: 12,
              color: colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

/// 单枚徽章磁贴。
class _AchievementTile extends StatelessWidget {
  const _AchievementTile({required this.achievement});

  final Achievement achievement;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final unlocked = achievement.isUnlocked;
    final width = (MediaQuery.sizeOf(context).width - 40 - 12) / 2;

    return Container(
      width: width,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: unlocked
            ? (isDark
                ? const Color(0xFFF97316).withValues(alpha: 0.10)
                : const Color(0xFFFFF7ED))
            : colorScheme.surfaceContainerHighest.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: unlocked
              ? (isDark
                  ? const Color(0xFFF97316).withValues(alpha: 0.4)
                  : const Color(0xFFFED7AA))
              : colorScheme.outlineVariant,
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: <Widget>[
              Text(
                unlocked ? achievement.icon : '🔒',
                style: TextStyle(
                  fontSize: 28,
                  // 未解锁的 emoji 与锁一起变灰
                  color: unlocked ? null : colorScheme.onSurfaceVariant,
                ),
              ),
              if (unlocked)
                Text('✓',
                    style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: const Color(0xFF16A34A)))
              else
                Text('未解锁',
                    style: TextStyle(
                        fontSize: 11, color: colorScheme.onSurfaceVariant)),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            achievement.name,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: unlocked ? colorScheme.onSurface : colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            achievement.description,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 11,
              height: 1.3,
              color: unlocked
                  ? (isDark
                      ? colorScheme.onSurfaceVariant
                      : const Color(0xFFC2410C))
                  : colorScheme.onSurfaceVariant.withValues(alpha: 0.8),
            ),
          ),
        ],
      ),
    );
  }
}

class _LegendHint extends StatelessWidget {
  const _LegendHint({required this.colorScheme});

  final ColorScheme colorScheme;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: <Widget>[
        const Text('🔒'),
        const SizedBox(width: 4),
        Text('= 尚未解锁',
            style: TextStyle(fontSize: 12, color: colorScheme.onSurfaceVariant)),
        const SizedBox(width: 16),
        const Text('✓'),
        const SizedBox(width: 4),
        Text('= 已解锁',
            style: TextStyle(fontSize: 12, color: colorScheme.onSurfaceVariant)),
      ],
    );
  }
}
