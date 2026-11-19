import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:smart_wrong_notebook/src/app/providers.dart';
import 'package:smart_wrong_notebook/src/app/auth_controller.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';
import 'package:smart_wrong_notebook/src/features/glass/glass_overlays.dart';
import 'package:smart_wrong_notebook/src/features/glass/glass_providers.dart';
import 'package:smart_wrong_notebook/src/common/widgets/stats_chart.dart';
import 'package:smart_wrong_notebook/src/data/services/question_analysis_coordinator.dart';
import 'package:smart_wrong_notebook/src/domain/models/mastery_level.dart';
import 'package:smart_wrong_notebook/src/domain/models/question_record.dart';
import 'package:smart_wrong_notebook/src/features/capture/presentation/capture_entry_sheet.dart';
import 'package:smart_wrong_notebook/src/features/home/presentation/background_analysis_section.dart';
import 'package:smart_wrong_notebook/src/features/home/presentation/vision_quota_card.dart';
import 'package:smart_wrong_notebook/src/features/achievements/presentation/achievement_celebration.dart';
import 'package:smart_wrong_notebook/src/shared/widgets/math_content_view.dart';

/// 本会话已弹过「恭喜」的徽章 id（避免同一次解锁重复弹出）。
final Set<String> _celebratedUnlockIds = <String>{};

/// 本次游客会话是否已弹过「建议登录」提醒（避免重复弹）。
bool _guestReminderShown = false;

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final questionsAsync = ref.watch(questionListProvider);
    final dueAsync = ref.watch(dueReviewProvider);
    final analysisTasksAsync = ref.watch(backgroundAnalysisTasksProvider);
    final gamificationAsync = ref.watch(gamificationSnapshotProvider);
    final auth = ref.watch(authControllerProvider);
    final isGuest = auth is AuthGuest;

    // 游客模式「建议登录」提醒：进入首页后弹一次，必须用户确认。
    if (!isGuest) {
      _guestReminderShown = false;
    } else if (!_guestReminderShown) {
      _guestReminderShown = true;
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        if (!context.mounted) return;
        final goLogin = await showAppConfirm(
          context,
          title: '游客模式',
          message: '你正以游客身份使用：错题与数据只保存在本机，卸载/换机不会保留。\n'
              '建议登录账号，以便云端同步、多设备使用。',
          confirmText: '去登录',
          cancelText: '继续游客',
        );
        if (goLogin && context.mounted) {
          await ref.read(authControllerProvider.notifier).logout();
          if (context.mounted) context.go('/login');
        }
      });
    }

    // 新徽章解锁 → 弹「恭喜」（每枚只弹一次）。
    ref.listen(gamificationSnapshotProvider, (prev, next) {
      final data = next.valueOrNull;
      if (data == null || data.newlyUnlocked.isEmpty) return;
      final fresh = data.newlyUnlocked
          .where((a) => !_celebratedUnlockIds.contains(a.id))
          .toList();
      if (fresh.isEmpty) return;
      _celebratedUnlockIds.addAll(fresh.map((a) => a.id));
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!context.mounted) return;
        showAchievementCelebration(context, fresh);
      });
    });

    // 云端拉取合并完成后，即时刷新列表与连击/成就。
    ref.listen(questionSyncMergedProvider, (prev, next) {
      if (next.hasValue && prev?.value != next.value) {
        ref.invalidate(questionListProvider);
        ref.invalidate(gamificationSnapshotProvider);
        ref.invalidate(dueReviewProvider);
      }
    });

    return SafeArea(
      child: ListView(
        padding: const EdgeInsets.fromLTRB(24, 20, 24, 24),
        children: <Widget>[
          if (isGuest) ...<Widget>[
            _GuestBanner(
              onLogin: () async {
                await ref.read(authControllerProvider.notifier).logout();
                if (context.mounted) context.go('/login');
              },
            ),
            const SizedBox(height: 14),
          ],
          gamificationAsync.when(
            data: (g) => Padding(
              padding: const EdgeInsets.only(bottom: 14),
              child: _HomeStreakCard(
                streak: g.streak,
                activeToday: g.activeToday,
                onTap: () => context.push('/achievements'),
              ),
            ),
            loading: () => const SizedBox.shrink(),
            error: (_, __) => const SizedBox.shrink(),
          ),
          Text(
            '开始拍错题',
            style: Theme.of(context)
                .textTheme
                .titleLarge
                ?.copyWith(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 16),
          _CaptureButton(
            onTap: () => showAppSheet<void>(
              context,
              bottomInset: 20,
              builder: (_) => const CaptureEntrySheet(),
            ),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: () => context.push('/paper/setup'),
            icon: const Icon(CupertinoIcons.sparkles, size: 18),
            label: const Text('AI 变式组卷'),
            style: OutlinedButton.styleFrom(
                minimumSize: const Size(double.infinity, 46)),
          ),
          if (!isGuest) const VisionQuotaCard(),
          const SizedBox(height: 10),
          // 数据存储提示：仅在游客/未登录时显示（登录后云端有备份，不必提示本机丢失）
          if (auth is! AuthAuthenticated)
            _LocalDataNotice(onTap: () => context.go('/settings/data')),
          const SizedBox(height: 20),
          analysisTasksAsync.when(
            data: (tasks) {
              if (tasks.isEmpty) return const SizedBox.shrink();
              return Padding(
                padding: const EdgeInsets.only(bottom: 20),
                child: BackgroundAnalysisSection(
                  tasks: tasks,
                  onOpenResult: (task) {
                    final result = task.resultQuestion;
                    if (result == null) return;
                    ref.read(currentQuestionProvider.notifier).state = result;
                    context.go('/analysis/result');
                  },
                  onRetry: (task) {
                    _retryTask(context, ref, task);
                  },
                  onDelete: (task) => _deleteTask(context, ref, task),
                ),
              );
            },
            loading: () => const SizedBox.shrink(),
            error: (_, __) => const SizedBox.shrink(),
          ),
          dueAsync.when(
            data: (due) => due.isNotEmpty
                ? _ReviewBanner(
                    count: due.length, onTap: () => context.go('/review'))
                : const SizedBox.shrink(),
            loading: () => const SizedBox.shrink(),
            error: (_, __) => const SizedBox.shrink(),
          ),
          const SizedBox(height: 20),
          Text('学习统计', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 12),
          RepaintBoundary(
            child: questionsAsync.when(
              data: (questions) => _buildStatsSection(context, ref, questions),
              loading: () => const _StatsGridSkeleton(),
              error: (e, _) => Text('加载失败: $e'),
            ),
          ),
          const SizedBox(height: 24),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: <Widget>[
              Text('最近新增', style: Theme.of(context).textTheme.titleLarge),
              TextButton(
                onPressed: () => context.go('/notebook'),
                child: const Text('查看全部'),
              ),
            ],
          ),
          const SizedBox(height: 8),
          questionsAsync.when(
            data: (questions) =>
                _RecentList(questions: questions.take(5).toList(), ref: ref),
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => Text('加载失败: $e'),
          ),
        ],
      ),
    );
  }

  Future<void> _retryTask(
    BuildContext context,
    WidgetRef ref,
    QuestionAnalysisTaskSnapshot task,
  ) async {
    try {
      await ref
          .read(scanTaskLifecycleServiceProvider)
          .prepareRetry(task.sourceQuestion);
      ref.read(currentQuestionProvider.notifier).state = task.sourceQuestion;
      if (context.mounted) context.go('/analysis/loading');
    } catch (error) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('重新排队失败：$error')),
      );
    }
  }

  Future<void> _deleteTask(
    BuildContext context,
    WidgetRef ref,
    QuestionAnalysisTaskSnapshot task,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('删除扫题任务'),
        content: const Text('确定删除这次扫题及其解析结果吗？此操作不可恢复。'),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await ref
          .read(scanTaskLifecycleServiceProvider)
          .discard(task.sourceQuestion);
      ref.invalidate(scanTaskCountProvider);
    } catch (error) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('删除失败：$error')),
      );
    }
  }

  Widget _buildStatsSection(
    BuildContext context,
    WidgetRef ref,
    List<QuestionRecord> questions,
  ) {
    final colorScheme = Theme.of(context).colorScheme;
    final total = questions.length;
    final mastered =
        questions.where((q) => q.masteryLevel == MasteryLevel.mastered).length;
    final pending = total - mastered;
    final now = DateTime.now();
    final todayNew = questions.where((q) {
      final createdAt = q.createdAt;
      return createdAt.year == now.year &&
          createdAt.month == now.month &&
          createdAt.day == now.day;
    }).length;
    final progress = total == 0 ? 0.0 : mastered / total;
    final percent = (progress * 100).round();

    return Column(
      children: <Widget>[
        StatsGrid(
          total: total,
          todayNew: todayNew,
          pending: pending,
          mastered: mastered,
          onTotalTap: () => _openNotebook(context, ref),
          onTodayNewTap: () => _openNotebook(
            context,
            ref,
            createdToday: true,
          ),
          onMasteredTap: () => _openNotebook(
            context,
            ref,
            masteryLevel: MasteryLevel.mastered,
          ),
          onPendingTap: () => context.go('/review'),
        ),
        if (total > 0) ...<Widget>[
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: colorScheme.surface,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: colorScheme.outlineVariant),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    Text(
                      '掌握进度',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const Spacer(),
                    Text(
                      '$percent%',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: colorScheme.primary,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                ClipRRect(
                  borderRadius: BorderRadius.circular(999),
                  child: LinearProgressIndicator(
                    value: progress,
                    minHeight: 10,
                    backgroundColor: colorScheme.surfaceContainerHighest,
                    color: colorScheme.primary,
                  ),
                ),
                const SizedBox(height: 10),
                Row(
                  children: <Widget>[
                    Text(
                      '$mastered / $total 已掌握',
                      style: TextStyle(
                        fontSize: 12,
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const Spacer(),
                    Text(
                      '$pending 待复习',
                      style: TextStyle(
                        fontSize: 12,
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  void _openNotebook(
    BuildContext context,
    WidgetRef ref, {
    MasteryLevel? masteryLevel,
    bool createdToday = false,
  }) {
    ref.read(selectedSubjectFilterProvider.notifier).state = null;
    ref.read(selectedMasteryFilterProvider.notifier).state = masteryLevel;
    ref.read(selectedCreatedTodayFilterProvider.notifier).state = createdToday;
    ref.read(selectedKnowledgePointFilterProvider.notifier).state = null;
    ref.read(selectedTagsFilterProvider.notifier).state = const <String>[];
    ref.read(searchQueryProvider.notifier).state = '';
    context.go('/notebook');
  }
}

class _StatsGridSkeleton extends StatelessWidget {
  const _StatsGridSkeleton();

  @override
  Widget build(BuildContext context) {
    return const Column(
      children: <Widget>[
        Row(
          children: <Widget>[
            Expanded(child: _StatCardSkeleton()),
            SizedBox(width: 12, height: 70),
            Expanded(child: _StatCardSkeleton()),
          ],
        ),
        SizedBox(height: 12),
        Row(
          children: <Widget>[
            Expanded(child: _StatCardSkeleton()),
            SizedBox(width: 12, height: 70),
            Expanded(child: _StatCardSkeleton()),
          ],
        ),
      ],
    );
  }
}

class _StatCardSkeleton extends StatelessWidget {
  const _StatCardSkeleton();

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      height: 70,
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(10),
      ),
    );
  }
}

class _RecentList extends StatelessWidget {
  const _RecentList({required this.questions, required this.ref});

  final List<QuestionRecord> questions;
  final WidgetRef ref;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    if (questions.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(32),
        decoration: BoxDecoration(
          color: colorScheme.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: colorScheme.outlineVariant),
        ),
        child: Column(
          children: <Widget>[
            Icon(CupertinoIcons.question,
                size: 48,
                color: colorScheme.onSurfaceVariant.withValues(alpha: 0.45)),
            const SizedBox(height: 12),
            Text('暂无错题，拍照开始添加',
                style: TextStyle(color: colorScheme.onSurfaceVariant)),
          ],
        ),
      );
    }
    return Column(
      children: List.generate(questions.length, (index) {
        final q = questions[index];
        return _RecentQuestionCard(
          key: ValueKey(q.id),
          question: q,
          onTap: () {
            ref.read(currentQuestionProvider.notifier).state = q;
            // push 保留返回栈：返回键回到首页而不是退出/跳错题本
            context.push('/notebook/question/${q.id}');
          },
        );
      }),
    );
  }
}

class _RecentQuestionCard extends StatelessWidget {
  const _RecentQuestionCard(
      {super.key, required this.question, required this.onTap});

  final QuestionRecord question;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final aiTags = question.aiTags;
    final customTags = question.customTags;
    final allTags = [...aiTags, ...customTags];

    return Semantics(
      button: true,
      label: '错题: ${question.correctedText}，科目: ${question.subject.label}',
      child: Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Container(
          decoration: BoxDecoration(
            color: colorScheme.surface,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: colorScheme.outlineVariant),
          ),
          child: ListTile(
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            leading: Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: question.subject.color.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(18),
              ),
              child: Icon(question.subject.icon,
                  size: 16, color: question.subject.color),
            ),
            title: MathContentView(
              question.correctedText,
              contentFormat: question.contentFormat,
              mode: MathContentViewMode.compact,
              maxLines: 1,
              style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: colorScheme.onSurface),
            ),
            subtitle: Row(
              children: <Widget>[
                Text(question.subject.label,
                    style:
                        TextStyle(fontSize: 12, color: question.subject.color)),
                if (allTags.isNotEmpty) ...<Widget>[
                  const SizedBox(width: 8),
                  ...allTags.take(2).map((tag) {
                    final isAiTag = aiTags.contains(tag);
                    final tagColor = isAiTag
                        ? const Color(0xFFD97706)
                        : const Color(0xFF4F46E5);
                    final tagBackground = isDark
                        ? tagColor.withValues(alpha: 0.14)
                        : isAiTag
                            ? const Color(0xFFFFF7ED)
                            : const Color(0xFFEEF2FF);
                    return Container(
                      margin: const EdgeInsets.only(right: 4),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 5, vertical: 2),
                      decoration: BoxDecoration(
                        color: tagBackground,
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(
                          color: isDark
                              ? tagColor.withValues(alpha: 0.22)
                              : colorScheme.outlineVariant
                                  .withValues(alpha: 0.5),
                        ),
                      ),
                      child: MathContentView(
                        tag,
                        mode: MathContentViewMode.compact,
                        style: TextStyle(
                            fontSize: 10,
                            color: isDark ? colorScheme.onSurface : tagColor),
                      ),
                    );
                  }),
                ],
              ],
            ),
            trailing: Icon(CupertinoIcons.chevron_right,
                color: colorScheme.onSurfaceVariant.withValues(alpha: 0.65)),
            onTap: onTap,
          ),
        ),
      ),
    );
  }
}

class _ReviewBanner extends StatelessWidget {
  const _ReviewBanner({required this.count, required this.onTap});

  final int count;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    const orange = Color(0xFFF97316);

    return Semantics(
      button: true,
      label: '待复习 $count 道错题，点击进入复习',
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: isDark
                ? orange.withValues(alpha: 0.12)
                : const Color(0xFFFFF7ED),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
                color: isDark
                    ? orange.withValues(alpha: 0.35)
                    : const Color(0xFFFED7AA)),
          ),
          child: Row(
            children: <Widget>[
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: isDark
                      ? orange.withValues(alpha: 0.18)
                      : const Color(0xFFFFEDD5),
                  borderRadius: BorderRadius.circular(22),
                ),
                child: const Icon(CupertinoIcons.arrow_2_circlepath,
                    color: Color(0xFFF97316), size: 22),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text('待复习',
                        style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            color: colorScheme.onSurface)),
                    Text('$count 道错题等待巩固',
                        style: TextStyle(
                            fontSize: 12,
                            color: isDark
                                ? colorScheme.onSurfaceVariant
                                : const Color(0xFFC2410C))),
                  ],
                ),
              ),
              const Icon(CupertinoIcons.chevron_right,
                  color: Color(0xFFF97316), size: 22),
            ],
          ),
        ),
      ),
    );
  }
}

/// 首页顶部的「连击 X 天」小卡。
class _HomeStreakCard extends StatelessWidget {
  const _HomeStreakCard({
    required this.streak,
    required this.activeToday,
    required this.onTap,
  });

  final int streak;
  final bool activeToday;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    const orange = Color(0xFFF97316);
    final subtitle = streak == 0
        ? '开启你的连击'
        : (activeToday ? '今天已学习 · 保持住' : '今天还没学，学一下保持连击');

    return Semantics(
      button: true,
      label: '学习连击 $streak 天，点击查看成就徽章',
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: isDark
                  ? [orange.withValues(alpha: 0.26), const Color(0xFF7C2D12)]
                  : [const Color(0xFFFFF7ED), const Color(0xFFFFEDD5)],
            ),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color:
                  isDark ? orange.withValues(alpha: 0.35) : const Color(0xFFFED7AA),
            ),
          ),
          child: Row(
            children: <Widget>[
              const Text('🔥', style: TextStyle(fontSize: 28)),
              const SizedBox(width: 12),
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
                              fontSize: 24,
                              fontWeight: FontWeight.w800,
                              color: orange,
                            ),
                          ),
                          TextSpan(
                            text: ' 天连击',
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                              color: colorScheme.onSurface,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 1),
                    Text(
                      subtitle,
                      style: TextStyle(
                        fontSize: 11,
                        color: isDark
                            ? colorScheme.onSurfaceVariant
                            : const Color(0xFFC2410C),
                      ),
                    ),
                  ],
                ),
              ),
              Icon(CupertinoIcons.star,
                  size: 20, color: orange.withValues(alpha: 0.9)),
              const SizedBox(width: 4),
              Icon(CupertinoIcons.chevron_right,
                  size: 16, color: orange.withValues(alpha: 0.7)),
            ],
          ),
        ),
      ),
    );
  }
}

/// 数据存储提示：错题保存在本机，卸载 / 清除数据会丢失；点击跳设置导出备份。
class _LocalDataNotice extends StatelessWidget {
  const _LocalDataNotice({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: const Color(0xFFFEF9C3),
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Padding(
                padding: EdgeInsets.only(top: 1),
                child: Icon(CupertinoIcons.device_phone_portrait,
                    size: 16, color: Color(0xFF92400E)),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '错题保存在本机，卸载或清除数据会丢失。点击前往「设置 → 数据管理」导出备份。',
                  style: TextStyle(
                    fontSize: 12,
                    height: 1.4,
                    color: theme.brightness == Brightness.dark
                        ? const Color(0xFFD6B15E)
                        : const Color(0xFF92400E),
                  ),
                ),
              ),
              const Padding(
                padding: EdgeInsets.only(top: 2),
                child: Icon(CupertinoIcons.chevron_right,
                    size: 14, color: Color(0xFF92400E)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 游客模式提示条：提醒登录以云端同步。
/// 首页「拍照录题」按钮：玻璃开启时用 `GlassButton`，否则回退 Material。
class _CaptureButton extends ConsumerWidget {
  const _CaptureButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!ref.watch(glassEnabledProvider)) {
      return FilledButton.icon(
        onPressed: onTap,
        icon: const Icon(CupertinoIcons.camera),
        label: const Text('拍照录题'),
        style: FilledButton.styleFrom(
            minimumSize: const Size(double.infinity, 52)),
      );
    }
    // 玻璃胶囊按钮：GlassButton 本身不渲染文字（label 仅语义），
    // 这里用 GlassContainer + 图标/文字自绘，效果与 Material 主按钮一致。
    final scheme = Theme.of(context).colorScheme;
    return GestureDetector(
      onTap: onTap,
      child: GlassContainer(
        quality: ref.watch(glassQualityProvider),
        shape: const LiquidRoundedSuperellipse(borderRadius: 26),
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: SizedBox(
          height: 52,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              Icon(CupertinoIcons.camera,
                  size: 20, color: scheme.onSurface),
              const SizedBox(width: 8),
              Text(
                '拍照录题',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: scheme.onSurface,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _GuestBanner extends StatelessWidget {
  const _GuestBanner({required this.onLogin});

  final VoidCallback onLogin;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Material(
      color: isDark ? const Color(0xFF1F2937) : const Color(0xFFEEF2FF),
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Row(
          children: <Widget>[
            const Icon(Icons.person_outline, size: 18, color: Color(0xFF4F46E5)),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                '游客模式：数据只保存在本机，建议登录后云端同步。',
                style: TextStyle(
                  fontSize: 12,
                  height: 1.4,
                  color: isDark ? const Color(0xFFC7D2FE) : const Color(0xFF3730A3),
                ),
              ),
            ),
            TextButton(
              onPressed: onLogin,
              child: const Text('去登录', style: TextStyle(fontSize: 12)),
            ),
          ],
        ),
      ),
    );
  }
}
