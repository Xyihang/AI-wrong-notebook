import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';
import 'package:smart_wrong_notebook/src/app/auth_controller.dart';
import 'package:smart_wrong_notebook/src/app/design/tokens.dart';
import 'package:smart_wrong_notebook/src/app/providers.dart';
import 'package:smart_wrong_notebook/src/common/widgets/app_card.dart';
import 'package:smart_wrong_notebook/src/common/widgets/app_chip.dart';
import 'package:smart_wrong_notebook/src/common/widgets/app_stat_card.dart';
import 'package:smart_wrong_notebook/src/data/services/question_analysis_coordinator.dart';
import 'package:smart_wrong_notebook/src/domain/models/mastery_level.dart';
import 'package:smart_wrong_notebook/src/domain/models/question_record.dart';
import 'package:smart_wrong_notebook/src/features/achievements/presentation/achievement_celebration.dart';
import 'package:smart_wrong_notebook/src/features/capture/presentation/capture_entry_sheet.dart';
import 'package:smart_wrong_notebook/src/features/glass/glass_overlays.dart';
import 'package:smart_wrong_notebook/src/features/glass/glass_providers.dart';
import 'package:smart_wrong_notebook/src/features/glass/glass_top_bar.dart';
import 'package:smart_wrong_notebook/src/features/home/presentation/background_analysis_section.dart';
import 'package:smart_wrong_notebook/src/features/home/presentation/vision_quota_card.dart';
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
        // 延后 350ms：避开首帧渲染高峰
        await Future<void>.delayed(const Duration(milliseconds: 350));
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
        // 延后到下一帧再刷新，避免与进入页面首帧抢主线程
        WidgetsBinding.instance.addPostFrameCallback((_) {
          ref.invalidate(questionListProvider);
          ref.invalidate(gamificationSnapshotProvider);
          ref.invalidate(dueReviewProvider);
        });
      }
    });

    final glassEnabled = ref.watch(glassEnabledProvider);
    return Scaffold(
      backgroundColor: Colors.transparent,
      // 玻璃开启时内容从顶栏下方穿过，产生和其他页面一致的穿透模糊
      extendBodyBehindAppBar: glassEnabled,
      appBar: glassTopBar(context, title: const Text('开始拍错题')),
      body: Stack(
        children: <Widget>[
          SafeArea(
        top: !glassEnabled,
        // 关闭 Material3 拉伸过滚动：拉伸会让玻璃折射错位、出现红黄色散条纹
        child: ScrollConfiguration(
          behavior: ScrollConfiguration.of(context).copyWith(
            overscroll: false,
          ),
          child: ListView(
            padding: EdgeInsets.fromLTRB(
              AppTokens.s4,
              AppTokens.s4 + AppTokens.s1 +
                  (glassEnabled ? glassTopInset(context) : 0),
              AppTokens.s4,
              AppTokens.s6,
            ),
            children: <Widget>[
              if (isGuest) ...<Widget>[
                _GuestBanner(
                  onLogin: () async {
                    await ref.read(authControllerProvider.notifier).logout();
                    if (context.mounted) context.go('/login');
                  },
                ),
                const SizedBox(height: AppTokens.s3),
              ],
              gamificationAsync.when(
                data: (g) => Padding(
                  padding: const EdgeInsets.only(bottom: AppTokens.s3),
                  child: _HomeStreakCard(
                    streak: g.streak,
                    activeToday: g.activeToday,
                    onTap: () => context.push('/achievements'),
                  ),
                ),
                loading: () => const SizedBox.shrink(),
                error: (_, __) => const SizedBox.shrink(),
              ),
              _CaptureButton(onTap: () => _openCaptureSheet(context)),
              const SizedBox(height: AppTokens.s4),
              _QuickActions(
                onCapture: () => _openCaptureSheet(context),
                onReview: () => context.go('/review'),
                onPaper: () => context.push('/paper/setup'),
                onInsight: () => showAppToast(context, '学情报告即将上线'),
              ),
              if (!isGuest) const VisionQuotaCard(),
              // 数据存储提示：仅在游客/未登录时显示（登录后云端有备份，不必提示本机丢失）
              if (auth is! AuthAuthenticated) ...<Widget>[
                const SizedBox(height: AppTokens.s3),
                _LocalDataNotice(onTap: () => context.go('/settings/data')),
              ],
              const SizedBox(height: AppTokens.s4),
              analysisTasksAsync.when(
                data: (tasks) {
                  if (tasks.isEmpty) return const SizedBox.shrink();
                  return Padding(
                    padding: const EdgeInsets.only(bottom: AppTokens.s4),
                    child: BackgroundAnalysisSection(
                      tasks: tasks,
                      onOpenResult: (task) {
                        final result = task.resultQuestion;
                        if (result == null) return;
                        ref.read(currentQuestionProvider.notifier).state =
                            result;
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
                    ? Padding(
                        padding: const EdgeInsets.only(bottom: AppTokens.s3),
                        child: _ReviewBanner(
                            count: due.length,
                            onTap: () => context.go('/review')),
                      )
                    : const SizedBox.shrink(),
                loading: () => const SizedBox.shrink(),
                error: (_, __) => const SizedBox.shrink(),
              ),
              RepaintBoundary(
                child: questionsAsync.when(
                  data: (questions) =>
                      _buildStatsSection(context, ref, questions),
                  loading: () => const _StatsGridSkeleton(),
                  error: (e, _) => _LoadError(message: '$e'),
                ),
              ),
              const SizedBox(height: AppTokens.s6),
              _SectionHeader(
                title: '最近收录',
                actionLabel: '查看全部',
                onAction: () => context.go('/notebook'),
              ),
              const SizedBox(height: AppTokens.s2),
              questionsAsync.when(
                data: (questions) => _RecentList(
                    questions: questions.take(5).toList(), ref: ref),
                // 静态占位：无无限动画，避免 widget 测试 pumpAndSettle 超时
                loading: () => const SizedBox(height: 96),
                error: (e, _) => _LoadError(message: '$e'),
              ),
            ],
          ),
        ),
      ),
        ],
      ),
    );
  }

  /// 打开拍照录题弹层（主按钮与四宫格「拍错题」共用）。
  Future<void> _openCaptureSheet(BuildContext context) async {
    await showAppSheet<void>(
      context,
      bottomInset: 20,
      builder: (_) => const CaptureEntrySheet(),
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
    final confirmed = await showAppDialog<bool>(context,
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

  /// 统计区（T3）：Hero 卡（累计错题 + 进度环 + 语义标签）+ 三宫格科目统计。
  Widget _buildStatsSection(
    BuildContext context,
    WidgetRef ref,
    List<QuestionRecord> questions,
  ) {
    final t = context.tokens;
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

    int subjectCount(String label) =>
        questions.where((q) => q.subject.label == label).length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Semantics(
          button: true,
          label: '累计错题 $total 道，点击查看错题本',
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => _openNotebook(context, ref),
            child: AppStatHero(
              label: '累计错题 · 今日新增 $todayNew',
              value: total,
              unit: '道',
              // 有数据才画进度环，空库时保持极简
              progress: total == 0 ? null : progress,
              chips: <Widget>[
                _StatChip(
                  label: '已掌握 $mastered',
                  color: t.success,
                  background: t.successSoft,
                  onTap: () => _openNotebook(
                    context,
                    ref,
                    masteryLevel: MasteryLevel.mastered,
                  ),
                ),
                _StatChip(
                  label: '待复习 $pending',
                  color: t.warning,
                  background: t.warningSoft,
                  onTap: () => context.go('/review'),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: AppTokens.s3),
        Row(
          children: <Widget>[
            Expanded(
              child: AppStatMini(
                value: subjectCount('数学'),
                label: '数学',
                color: t.subjectColor('数学'),
              ),
            ),
            const SizedBox(width: AppTokens.s3),
            Expanded(
              child: AppStatMini(
                value: subjectCount('物理'),
                label: '物理',
                color: t.subjectColor('物理'),
              ),
            ),
            const SizedBox(width: AppTokens.s3),
            Expanded(
              child: AppStatMini(
                value: subjectCount('英语'),
                label: '英语',
                color: t.subjectColor('英语'),
              ),
            ),
          ],
        ),
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

/// 统计区骨架（Hero + 三宫格），全部走 token。
class _StatsGridSkeleton extends StatelessWidget {
  const _StatsGridSkeleton();

  @override
  Widget build(BuildContext context) {
    return const Column(
      children: <Widget>[
        _SkeletonBlock(height: 132),
        SizedBox(height: AppTokens.s3),
        Row(
          children: <Widget>[
            Expanded(child: _SkeletonBlock(height: 72)),
            SizedBox(width: AppTokens.s3),
            Expanded(child: _SkeletonBlock(height: 72)),
            SizedBox(width: AppTokens.s3),
            Expanded(child: _SkeletonBlock(height: 72)),
          ],
        ),
      ],
    );
  }
}

class _SkeletonBlock extends StatelessWidget {
  const _SkeletonBlock({required this.height});

  final double height;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Container(
      height: height,
      decoration: BoxDecoration(
        color: t.isDark ? t.card : t.formulaBg,
        borderRadius: BorderRadius.circular(AppTokens.radiusLg),
        border: t.isDark ? Border.all(color: t.cardBorder) : null,
      ),
    );
  }
}

/// 统计卡内的语义标签（复用 [AppTag] 视觉，带点击）。
class _StatChip extends StatelessWidget {
  const _StatChip({
    required this.label,
    required this.color,
    required this.background,
    required this.onTap,
  });

  final String label;
  final Color color;
  final Color background;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: label,
      child: GestureDetector(
        onTap: onTap,
        child: AppTag(
          label,
          color: color,
          background: background,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }
}

/// 区块标题（demo `.detail-label`），右侧可带操作入口。
class _SectionHeader extends StatelessWidget {
  const _SectionHeader({
    required this.title,
    this.actionLabel,
    this.onAction,
  });

  final String title;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Row(
      children: <Widget>[
        Expanded(
          child: Text(
            title,
            style: TextStyle(
              fontSize: AppTokens.textXs,
              fontWeight: FontWeight.w600,
              letterSpacing: 1,
              color: t.textTertiary,
            ),
          ),
        ),
        if (actionLabel != null)
          TextButton(
            onPressed: onAction,
            style: TextButton.styleFrom(
              foregroundColor: t.primary,
              minimumSize: const Size(0, 32),
              padding: const EdgeInsets.symmetric(horizontal: AppTokens.s2),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            child: Text(
              actionLabel!,
              style: const TextStyle(
                fontSize: AppTokens.textXs,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
      ],
    );
  }
}

/// 首页四宫格快捷入口（demo `.quick-actions`）：48×48 图标底 + `textXs` 文案。
class _QuickActions extends StatelessWidget {
  const _QuickActions({
    required this.onCapture,
    required this.onReview,
    required this.onPaper,
    required this.onInsight,
  });

  final VoidCallback onCapture;
  final VoidCallback onReview;
  final VoidCallback onPaper;
  final VoidCallback onInsight;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Row(
      children: <Widget>[
        Expanded(
          child: _QuickItem(
            icon: CupertinoIcons.camera,
            label: '拍错题',
            color: t.primary,
            onTap: onCapture,
          ),
        ),
        Expanded(
          child: _QuickItem(
            icon: CupertinoIcons.arrow_2_circlepath,
            label: '去复习',
            color: t.secondary,
            onTap: onReview,
          ),
        ),
        Expanded(
          child: _QuickItem(
            icon: CupertinoIcons.doc_text,
            label: '组卷',
            color: t.warning,
            onTap: onPaper,
          ),
        ),
        Expanded(
          child: _QuickItem(
            icon: CupertinoIcons.chart_bar_alt_fill,
            label: '学情',
            color: t.success,
            onTap: onInsight,
          ),
        ),
      ],
    );
  }
}

class _QuickItem extends StatelessWidget {
  const _QuickItem({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Semantics(
      button: true,
      label: label,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Column(
          children: <Widget>[
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: t.card,
                borderRadius: BorderRadius.circular(AppTokens.radiusLg),
                border: t.isDark ? Border.all(color: t.cardBorder) : null,
                boxShadow: t.isDark ? null : t.shadow1,
              ),
              child: Icon(icon, size: 20, color: color),
            ),
            const SizedBox(height: AppTokens.s2),
            Text(
              label,
              style: TextStyle(
                fontSize: AppTokens.textXs,
                color: t.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 加载失败提示（走 error 语义色）。
class _LoadError extends StatelessWidget {
  const _LoadError({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Text(
      '加载失败: $message',
      style: TextStyle(fontSize: AppTokens.textSm, color: t.error),
    );
  }
}

String _masteryLabel(MasteryLevel level) {
  switch (level) {
    case MasteryLevel.newQuestion:
      return '新增';
    case MasteryLevel.reviewing:
      return '复习中';
    case MasteryLevel.mastered:
      return '已掌握';
  }
}

Color _masteryColor(AppTokens t, MasteryLevel level) {
  switch (level) {
    case MasteryLevel.newQuestion:
      return t.textSecondary;
    case MasteryLevel.reviewing:
      return t.warning;
    case MasteryLevel.mastered:
      return t.success;
  }
}

/// 科目标签底：浅色用科目软底，深色用科目色低透明度底（避免浅色软底在深色下刺眼）。
Color _subjectTagBackground(AppTokens t, String subject) => t.isDark
    ? t.subjectColor(subject).withValues(alpha: 0.18)
    : t.subjectSoft(subject);

String _formatDate(DateTime date) {
  final now = DateTime.now();
  final diff = now.difference(date);
  if (diff.inDays == 0) return '今天';
  if (diff.inDays == 1) return '昨天';
  if (diff.inDays < 7) return '${diff.inDays}天前';
  return '${date.month}月${date.day}日';
}

class _RecentList extends StatelessWidget {
  const _RecentList({required this.questions, required this.ref});

  final List<QuestionRecord> questions;
  final WidgetRef ref;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;

    if (questions.isEmpty) {
      return AppCard(
        padding: const EdgeInsets.symmetric(
            horizontal: AppTokens.s4, vertical: AppTokens.s8),
        child: Column(
          children: <Widget>[
            Icon(CupertinoIcons.photo, size: 40, color: t.textTertiary),
            const SizedBox(height: AppTokens.s3),
            Text(
              '暂无错题，拍照开始添加',
              style: TextStyle(
                fontSize: AppTokens.textSm,
                color: t.textSecondary,
              ),
            ),
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

/// 最近收录卡（demo `.q-card`）：科目 tag + 掌握度 + 时间 / 题干 / 知识点 tags。
class _RecentQuestionCard extends StatelessWidget {
  const _RecentQuestionCard(
      {super.key, required this.question, required this.onTap});

  final QuestionRecord question;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final subjectLabel = question.subject.label;
    final knowledgePoints = question.aiKnowledgePoints.isNotEmpty
        ? question.aiKnowledgePoints
        : question.allTags;
    final tags = knowledgePoints.take(2).toList();

    return Semantics(
      button: true,
      label: '错题: ${question.correctedText}，科目: $subjectLabel',
      child: Padding(
        padding: const EdgeInsets.only(bottom: AppTokens.s3),
        child: AppCard(
          onTap: onTap,
          padding: const EdgeInsets.all(AppTokens.s3),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Row(
                children: <Widget>[
                  AppTag(
                    subjectLabel,
                    color: t.subjectColor(subjectLabel),
                    background: _subjectTagBackground(t, subjectLabel),
                    fontWeight: FontWeight.w600,
                  ),
                  const SizedBox(width: AppTokens.s2),
                  Text(
                    _masteryLabel(question.masteryLevel),
                    style: TextStyle(
                      fontSize: AppTokens.textXs,
                      fontWeight: FontWeight.w500,
                      color: _masteryColor(t, question.masteryLevel),
                    ),
                  ),
                  const Spacer(),
                  Text(
                    _formatDate(question.createdAt),
                    style: TextStyle(
                      fontSize: AppTokens.textXs,
                      color: t.textTertiary,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppTokens.s2),
              MathContentView(
                question.correctedText,
                contentFormat: question.contentFormat,
                mode: MathContentViewMode.compact,
                maxLines: 2,
                style: TextStyle(
                  fontSize: AppTokens.textSm,
                  height: 1.5,
                  color: t.textPrimary,
                ),
              ),
              if (tags.isNotEmpty) ...<Widget>[
                const SizedBox(height: AppTokens.s3),
                Wrap(
                  spacing: AppTokens.s2,
                  runSpacing: AppTokens.s2,
                  children: tags
                      .map((tag) => AppTag(tag, radius: AppTokens.radiusSm))
                      .toList(),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// 待复习提醒条（点击进入复习 Tab）。
class _ReviewBanner extends StatelessWidget {
  const _ReviewBanner({required this.count, required this.onTap});

  final int count;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final radius = BorderRadius.circular(AppTokens.radiusLg);
    return Semantics(
      button: true,
      label: '待复习 $count 道错题，点击进入复习',
      child: Material(
        color: t.primarySoft,
        borderRadius: radius,
        child: InkWell(
          onTap: onTap,
          borderRadius: radius,
          child: Container(
            padding: const EdgeInsets.all(AppTokens.s3),
            decoration: BoxDecoration(
              borderRadius: radius,
              border: Border.all(
                color: t.primary.withValues(alpha: t.isDark ? 0.5 : 0.22),
              ),
            ),
            child: Row(
              children: <Widget>[
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: t.primary.withValues(alpha: t.isDark ? 0.2 : 0.12),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Icon(CupertinoIcons.arrow_2_circlepath,
                      size: 20, color: t.primary),
                ),
                const SizedBox(width: AppTokens.s3),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        '待复习',
                        style: TextStyle(
                          fontSize: AppTokens.textSm,
                          fontWeight: FontWeight.w600,
                          color: t.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '$count 道错题等待巩固',
                        style: TextStyle(
                          fontSize: AppTokens.textXs,
                          color: t.isDark ? t.textSecondary : t.primaryDark,
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(CupertinoIcons.chevron_right,
                    size: 18, color: t.primary),
              ],
            ),
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
    final t = context.tokens;
    final radius = BorderRadius.circular(AppTokens.radiusLg);
    final subtitle = streak == 0
        ? '开启你的连击'
        : (activeToday ? '今天已学习 · 保持住' : '今天还没学，学一下保持连击');

    return Semantics(
      button: true,
      label: '学习连击 $streak 天，点击查看成就徽章',
      child: Material(
        color: t.warningSoft,
        borderRadius: radius,
        child: InkWell(
          onTap: onTap,
          borderRadius: radius,
          child: Container(
            padding: const EdgeInsets.symmetric(
                horizontal: AppTokens.s4, vertical: AppTokens.s3),
            decoration: BoxDecoration(
              borderRadius: radius,
              border: Border.all(
                color: t.warning.withValues(alpha: t.isDark ? 0.45 : 0.3),
              ),
            ),
            child: Row(
              children: <Widget>[
                const Text('🔥', style: TextStyle(fontSize: 28)),
                const SizedBox(width: AppTokens.s3),
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
                                fontSize: AppTokens.textXl,
                                fontWeight: FontWeight.w800,
                                color: t.warning,
                              ),
                            ),
                            TextSpan(
                              text: ' 天连击',
                              style: TextStyle(
                                fontSize: AppTokens.textBase,
                                fontWeight: FontWeight.w600,
                                color: t.textPrimary,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 1),
                      Text(
                        subtitle,
                        style: TextStyle(
                          fontSize: AppTokens.textXs,
                          color: t.isDark ? t.textSecondary : t.warning,
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(CupertinoIcons.star,
                    size: 20, color: t.warning.withValues(alpha: 0.9)),
                const SizedBox(width: AppTokens.s1),
                Icon(CupertinoIcons.chevron_right,
                    size: 16, color: t.warning.withValues(alpha: 0.7)),
              ],
            ),
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
    final t = context.tokens;
    final radius = BorderRadius.circular(AppTokens.radiusLg);
    return Material(
      color: t.warningSoft,
      borderRadius: radius,
      child: InkWell(
        onTap: onTap,
        borderRadius: radius,
        child: Container(
          padding: const EdgeInsets.symmetric(
              horizontal: AppTokens.s3, vertical: AppTokens.s2 + 2),
          decoration: BoxDecoration(
            borderRadius: radius,
            border: Border.all(
              color: t.warning.withValues(alpha: t.isDark ? 0.4 : 0.28),
            ),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Padding(
                padding: const EdgeInsets.only(top: 1),
                child: Icon(CupertinoIcons.device_phone_portrait,
                    size: 16, color: t.warning),
              ),
              const SizedBox(width: AppTokens.s2),
              Expanded(
                child: Text(
                  '错题保存在本机，卸载或清除数据会丢失。点击前往「设置 → 数据管理」导出备份。',
                  style: TextStyle(
                    fontSize: AppTokens.textXs,
                    height: 1.4,
                    color: t.textSecondary,
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Icon(CupertinoIcons.chevron_right,
                    size: 14, color: t.warning),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

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
      // 整块玻璃都可点：opaque 命中测试 + 撑满宽度
      behavior: HitTestBehavior.opaque,
      child: SizedBox(
        width: double.infinity,
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
      ),
    );
  }
}

/// 游客模式提示条：提醒登录以云端同步。
class _GuestBanner extends StatelessWidget {
  const _GuestBanner({required this.onLogin});

  final VoidCallback onLogin;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final radius = BorderRadius.circular(AppTokens.radiusLg);
    return Container(
      padding: const EdgeInsets.symmetric(
          horizontal: AppTokens.s3, vertical: AppTokens.s2),
      decoration: BoxDecoration(
        color: t.primarySoft,
        borderRadius: radius,
        border: Border.all(
          color: t.primary.withValues(alpha: t.isDark ? 0.5 : 0.22),
        ),
      ),
      child: Row(
        children: <Widget>[
          Icon(Icons.person_outline, size: 18, color: t.primary),
          const SizedBox(width: AppTokens.s2),
          Expanded(
            child: Text(
              '游客模式：数据只保存在本机，建议登录后云端同步。',
              style: TextStyle(
                fontSize: AppTokens.textXs,
                height: 1.4,
                color: t.isDark ? t.textPrimary : t.primaryDark,
              ),
            ),
          ),
          TextButton(
            onPressed: onLogin,
            style: TextButton.styleFrom(
              foregroundColor: t.primary,
              minimumSize: const Size(0, 32),
              padding: const EdgeInsets.symmetric(horizontal: AppTokens.s2),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            child: const Text(
              '去登录',
              style: TextStyle(
                fontSize: AppTokens.textXs,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
