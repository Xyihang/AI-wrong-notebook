import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:smart_wrong_notebook/src/app/providers.dart';
import 'package:smart_wrong_notebook/src/domain/models/mastery_level.dart';
import 'package:smart_wrong_notebook/src/domain/models/question_record.dart';
import 'package:smart_wrong_notebook/src/domain/services/forgetting_curve.dart';
import 'package:smart_wrong_notebook/src/shared/widgets/math_content_view.dart';

class ReviewScreen extends ConsumerWidget {
  const ReviewScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final questionsAsync = ref.watch(questionListProvider);
    final batchGroups = ref.watch(questionBatchGroupsProvider).valueOrNull;
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('复习'),
        actions: <Widget>[
          TextButton.icon(
            onPressed: () => context.go('/review/history'),
            icon: const Icon(CupertinoIcons.clock, size: 18),
            label: const Text('记录'),
          ),
        ],
      ),
      body: questionsAsync.when(
        data: (questions) {
          final mastered = questions
              .where((q) => q.masteryLevel == MasteryLevel.mastered)
              .toList();
          final pendingAll = questions
              .where((q) => q.masteryLevel != MasteryLevel.mastered)
              .toList();
          // 遗忘曲线：到期的优先，未到期的排后并显示"X天后"
          final due = pendingAll.where(isDue).toList();
          final upcoming =
              pendingAll.where((q) => !isDue(q)).toList();
          final pendingList = [...due, ...upcoming];

          return DefaultTabController(
            length: 2,
            child: ListView(
              // 底部仅保留安全区（「复习记录」已移到右上角，无需额外空间）
              padding: EdgeInsets.fromLTRB(
                24,
                24,
                24,
                24 + MediaQuery.of(context).padding.bottom,
              ),
              children: <Widget>[
                _SummaryCard(
                  total: questions.length,
                  pending: due.length,
                  mastered: mastered.length,
                ),
                const SizedBox(height: 20),
                Container(
                  height: 40,
                  padding: const EdgeInsets.all(3),
                  decoration: BoxDecoration(
                    color: colorScheme.surface,
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(color: colorScheme.outlineVariant),
                  ),
                  child: TabBar(
                    dividerColor: Colors.transparent,
                    indicatorSize: TabBarIndicatorSize.tab,
                    indicator: BoxDecoration(
                      color: colorScheme.primary,
                      borderRadius: BorderRadius.circular(999),
                    ),
                    labelColor: colorScheme.onPrimary,
                    unselectedLabelColor: colorScheme.onSurfaceVariant,
                    labelStyle: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                    ),
                    unselectedLabelStyle: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                    tabs: <Widget>[
                      Tab(text: '待复习 ${due.length}'),
                      Tab(text: '已掌握 ${mastered.length}'),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  height: 420,
                  child: TabBarView(
                    children: <Widget>[
                      _ReviewQuestionList(
                        questions: pendingList,
                        emptyMessage: '暂无待复习错题',
                        batchGroups: batchGroups,
                        ref: ref,
                      ),
                      _ReviewQuestionList(
                        questions: mastered,
                        emptyMessage: '暂无已掌握错题',
                        batchGroups: batchGroups,
                        ref: ref,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('加载失败: $e')),
      ),
    );
  }
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard(
      {required this.total, required this.pending, required this.mastered});

  final int total;
  final int pending;
  final int mastered;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: colorScheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Text('整体进度',
                  style: Theme.of(context)
                      .textTheme
                      .titleSmall
                      ?.copyWith(fontWeight: FontWeight.w600)),
              const Spacer(),
              Text('共 $total 题',
                  style: TextStyle(
                      fontSize: 12, color: colorScheme.onSurfaceVariant)),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: <Widget>[
              _MiniStat(
                  value: '$pending',
                  label: '待复习',
                  color: const Color(0xFFEA580C)),
              _MiniStat(
                  value: '$mastered',
                  label: '已掌握',
                  color: const Color(0xFF16A34A)),
              _MiniStat(
                  value: '$total', label: '总错题', color: colorScheme.onSurface),
            ],
          ),
        ],
      ),
    );
  }
}

class _MiniStat extends StatelessWidget {
  const _MiniStat(
      {required this.value, required this.label, required this.color});

  final String value;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: <Widget>[
        Text(value,
            style: TextStyle(
                fontSize: 22, fontWeight: FontWeight.bold, color: color)),
        const SizedBox(height: 2),
        Text(label, style: TextStyle(fontSize: 11, color: color)),
      ],
    );
  }
}

class _EmptyCard extends StatelessWidget {
  const _EmptyCard({required this.message});

  final String message;
  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    const green = Color(0xFF16A34A);

    return Container(
      padding: const EdgeInsets.all(32),
      decoration: BoxDecoration(
        color: isDark ? green.withValues(alpha: 0.12) : const Color(0xFFF0FDF4),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
            color: isDark
                ? green.withValues(alpha: 0.35)
                : const Color(0xFFBBF7D0)),
      ),
      child: Column(
        children: <Widget>[
          Icon(CupertinoIcons.star,
              size: 48, color: green.withValues(alpha: 0.65)),
          const SizedBox(height: 12),
          const Text('太棒了！',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
          const SizedBox(height: 4),
          Text(message, style: TextStyle(color: colorScheme.onSurfaceVariant)),
        ],
      ),
    );
  }
}

class _ReviewQuestionList extends StatelessWidget {
  const _ReviewQuestionList({
    required this.questions,
    required this.emptyMessage,
    required this.batchGroups,
    required this.ref,
  });

  final List<QuestionRecord> questions;
  final String emptyMessage;
  final Map<String, QuestionBatchGroup>? batchGroups;
  final WidgetRef ref;

  @override
  Widget build(BuildContext context) {
    if (questions.isEmpty) return _EmptyCard(message: emptyMessage);

    return ListView(
      padding: EdgeInsets.zero,
      children: questions
          .map((q) => _ReviewCard(
                question: q,
                batchLabel: _batchLabel(q, batchGroups),
                nextReview: nextReviewLabel(q),
                onOpen: () {
                  ref.read(currentQuestionProvider.notifier).state = q;
                  // push 保留返回栈：返回键回到复习页
                  context.push('/notebook/question/${q.id}');
                },
              ))
          .toList(),
    );
  }
}

String? _batchLabel(
    QuestionRecord question, Map<String, QuestionBatchGroup>? batchGroups) {
  final rootId = questionBatchRootId(question);
  if (rootId == null) return null;

  final group = batchGroups?[rootId];
  if (group == null || group.questions.length < 2) return null;

  final order = question.splitOrder;
  return order == null ? '来自同一拍照批次' : '来自同一拍照批次 · 第 $order 题';
}

String _masteryLabel(MasteryLevel level) {
  switch (level) {
    case MasteryLevel.newQuestion:
      return '待复习';
    case MasteryLevel.reviewing:
      return '待复习';
    case MasteryLevel.mastered:
      return '已掌握';
  }
}

Color _masteryColor(BuildContext context, MasteryLevel level) {
  final colorScheme = Theme.of(context).colorScheme;
  switch (level) {
    case MasteryLevel.newQuestion:
      return colorScheme.onSurfaceVariant;
    case MasteryLevel.reviewing:
      return const Color(0xFFD97706);
    case MasteryLevel.mastered:
      return const Color(0xFF16A34A);
  }
}

class _MasteryChip extends StatelessWidget {
  const _MasteryChip({required this.level});

  final MasteryLevel level;

  @override
  Widget build(BuildContext context) {
    final color = _masteryColor(context, level);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: BoxDecoration(
        color: color.withValues(alpha: isDark ? 0.16 : 0.1),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        _masteryLabel(level),
        style: TextStyle(fontSize: 10, color: color),
      ),
    );
  }
}

class _ReviewCard extends StatelessWidget {
  const _ReviewCard({
    required this.question,
    required this.onOpen,
    this.batchLabel,
    this.nextReview,
  });

  final QuestionRecord question;
  final VoidCallback onOpen;
  final String? batchLabel;
  final String? nextReview;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: GestureDetector(
        onTap: onOpen,
        behavior: HitTestBehavior.opaque,
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: colorScheme.surface,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: colorScheme.outlineVariant),
          ),
          child: Row(
            children: <Widget>[
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: question.subject.color.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Icon(question.subject.icon,
                    size: 18, color: question.subject.color),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    MathContentView(
                      question.correctedText,
                      contentFormat: question.contentFormat,
                      mode: MathContentViewMode.compact,
                      maxLines: 1,
                      style: TextStyle(
                          fontWeight: FontWeight.w500,
                          fontSize: 14,
                          color: colorScheme.onSurface),
                    ),
                    if (batchLabel != null) ...<Widget>[
                      const SizedBox(height: 4),
                      Text(
                        batchLabel!,
                        style: TextStyle(
                            fontSize: 11, color: colorScheme.onSurfaceVariant),
                      ),
                    ],
                    const SizedBox(height: 4),
                    Wrap(
                      spacing: 8,
                      runSpacing: 4,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: <Widget>[
                        Text(
                          question.subject.label,
                          style: TextStyle(
                              fontSize: 12, color: question.subject.color),
                        ),
                        _MasteryChip(level: question.masteryLevel),
                        // 下次复习时间（遗忘曲线）
                        if (nextReview != null) ...<Widget>[
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: isDark
                                  ? colorScheme.onSurfaceVariant
                                      .withValues(alpha: 0.15)
                                  : const Color(0xFFEEF2FF),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              nextReview!,
                              style: TextStyle(
                                  fontSize: 10,
                                  color: colorScheme.onSurfaceVariant),
                            ),
                          ),
                        ],
                        ...question.aiTags.take(3).map((tag) {
                          const tagColor = Color(0xFFD97706);
                          return Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: isDark
                                  ? tagColor.withValues(alpha: 0.14)
                                  : const Color(0xFFFFF7ED),
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
                                  color: isDark
                                      ? colorScheme.onSurface
                                      : tagColor),
                            ),
                          );
                        }),
                      ],
                    ),
                  ],
                ),
              ),
              Icon(CupertinoIcons.chevron_right,
                  color: colorScheme.onSurfaceVariant.withValues(alpha: 0.65),
                  size: 22),
            ],
          ),
        ),
      ),
    );
  }
}
