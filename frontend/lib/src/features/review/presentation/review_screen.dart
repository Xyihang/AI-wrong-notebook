import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:smart_wrong_notebook/src/app/design/tokens.dart';
import 'package:smart_wrong_notebook/src/app/providers.dart';
import 'package:smart_wrong_notebook/src/common/widgets/app_button.dart';
import 'package:smart_wrong_notebook/src/common/widgets/app_card.dart';
import 'package:smart_wrong_notebook/src/common/widgets/app_chip.dart';
import 'package:smart_wrong_notebook/src/domain/models/mastery_level.dart';
import 'package:smart_wrong_notebook/src/domain/models/question_record.dart';
import 'package:smart_wrong_notebook/src/domain/services/forgetting_curve.dart';
import 'package:smart_wrong_notebook/src/features/glass/glass_providers.dart';
import 'package:smart_wrong_notebook/src/features/glass/glass_top_bar.dart';
import 'package:smart_wrong_notebook/src/features/review/presentation/review_controller.dart';
import 'package:smart_wrong_notebook/src/shared/widgets/math_content_view.dart';

/// 复习页（对应 SPEC T6）。
///
/// 结构：环形今日进度 → 待复习/已掌握 Tab → 复习卡（显示答案 + 三键反馈）
/// → 说明行 → 剩余题目列表 → 下次复习提示。
/// 三键反馈沿用 [ReviewController] 的掌握度更新逻辑，不新增业务规则。
class ReviewScreen extends ConsumerStatefulWidget {
  const ReviewScreen({super.key});

  @override
  ConsumerState<ReviewScreen> createState() => _ReviewScreenState();
}

class _ReviewScreenState extends ConsumerState<ReviewScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  int _tabIndex = 0;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _tabController.addListener(_syncTabIndex);
  }

  @override
  void dispose() {
    _tabController
      ..removeListener(_syncTabIndex)
      ..dispose();
    super.dispose();
  }

  void _syncTabIndex() {
    if (_tabIndex != _tabController.index) {
      setState(() => _tabIndex = _tabController.index);
    }
  }

  void _openQuestion(QuestionRecord question) {
    ref.read(currentQuestionProvider.notifier).state = question;
    // push 保留返回栈：返回键回到复习页
    context.push('/notebook/question/${question.id}');
  }

  /// 三键反馈：仍不会 / 模糊 / 已掌握 → 写入掌握度并刷新列表。
  Future<void> _submitReview(
    QuestionRecord question,
    MasteryLevel target,
  ) async {
    final controller = ReviewController(
      repository: ref.read(questionRepositoryProvider),
      logRepository: ref.read(reviewLogRepositoryProvider),
    );
    try {
      switch (target) {
        case MasteryLevel.newQuestion:
          await controller.resetToNew(question.id);
        case MasteryLevel.reviewing:
          await controller.markReviewing(question.id);
        case MasteryLevel.mastered:
          await controller.markMastered(question.id);
      }
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('更新复习状态失败：$error')),
      );
      return;
    }
    if (!mounted) return;
    invalidateQuestionList(ref);
  }

  @override
  Widget build(BuildContext context) {
    final questionsAsync = ref.watch(questionListProvider);
    final batchGroups = ref.watch(questionBatchGroupsProvider).valueOrNull;
    final glassEnabled = ref.watch(glassEnabledProvider);
    final t = context.tokens;

    return Scaffold(
      extendBodyBehindAppBar: glassEnabled,
      appBar: glassTopBar(
        context,
        title: const Text('今日复习'),
        actions: <Widget>[
          TextButton.icon(
            onPressed: () => context.go('/review/history'),
            style: TextButton.styleFrom(foregroundColor: t.primary),
            icon: const Icon(CupertinoIcons.clock, size: 18),
            label: const Text(
              '记录',
              style: TextStyle(fontSize: AppTokens.textSm),
            ),
          ),
        ],
      ),
      body: questionsAsync.when(
        data: (questions) => _buildBody(
          context,
          questions,
          batchGroups,
          glassEnabled,
        ),
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('加载失败: $e')),
      ),
    );
  }

  Widget _buildBody(
    BuildContext context,
    List<QuestionRecord> questions,
    Map<String, QuestionBatchGroup>? batchGroups,
    bool glassEnabled,
  ) {
    final now = DateTime.now();
    final mastered = questions
        .where((q) => q.masteryLevel == MasteryLevel.mastered)
        .toList();
    final pendingAll = questions
        .where((q) => q.masteryLevel != MasteryLevel.mastered)
        .toList();
    // 遗忘曲线：到期的优先，未到期的排后并显示"X天后"
    final due = pendingAll.where((q) => isDue(q, now: now)).toList();
    final upcoming = pendingAll.where((q) => !isDue(q, now: now)).toList();
    final pendingList = <QuestionRecord>[...due, ...upcoming];
    final reviewedToday = questions
        .where(
          (q) => q.lastReviewedAt != null && _isSameDay(q.lastReviewedAt!, now),
        )
        .length;
    final current = due.isNotEmpty ? due.first : null;
    final restPending = current == null
        ? pendingList
        : pendingList.where((q) => q.id != current.id).toList();

    // 头部（进度环 / Tab / 当前复习卡），下方题目列表用 SliverList 懒加载
    final header = <Widget>[
      _TodayProgress(
        done: reviewedToday,
        total: due.length + reviewedToday,
      ),
      const SizedBox(height: AppTokens.s6),
      _ReviewTabBar(
        controller: _tabController,
        pendingCount: due.length,
        masteredCount: mastered.length,
      ),
      const SizedBox(height: AppTokens.s3),
    ];
    final List<QuestionRecord> tiles;
    if (_tabIndex == 0) {
      if (current == null) {
        header.add(const _EmptyCard(message: '今天没有到期的错题，休息一下吧'));
        tiles = restPending;
        if (tiles.isNotEmpty) {
          header.addAll(<Widget>[
            const SizedBox(height: AppTokens.s4),
            AppSectionLabel('接下来 ${tiles.length} 道'),
          ]);
        }
      } else {
        final question = current;
        header.addAll(<Widget>[
          _CurrentReviewCard(
            question: question,
            onOpen: () => _openQuestion(question),
            onResult: (level) => _submitReview(question, level),
          ),
          const SizedBox(height: AppTokens.s3),
          Text(
            '依据艾宾浩斯遗忘曲线安排',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: AppTokens.textXs,
              color: context.tokens.textTertiary,
            ),
          ),
        ]);
        tiles = restPending;
        if (tiles.isNotEmpty) {
          header.addAll(<Widget>[
            const SizedBox(height: AppTokens.s4),
            AppSectionLabel('还有 ${tiles.length} 道待复习'),
          ]);
        }
      }
    } else if (mastered.isEmpty) {
      header.add(const _EmptyCard(message: '暂无已掌握错题'));
      tiles = const <QuestionRecord>[];
    } else {
      tiles = mastered;
    }

    return CustomScrollView(
      slivers: <Widget>[
        SliverPadding(
          padding: EdgeInsets.fromLTRB(
            AppTokens.s4,
            AppTokens.s4 + (glassEnabled ? glassTopInset(context) : 0),
            AppTokens.s4,
            0,
          ),
          sliver: SliverList(
            delegate: SliverChildListDelegate(header),
          ),
        ),
        SliverPadding(
          padding: const EdgeInsets.symmetric(horizontal: AppTokens.s4),
          sliver: SliverList.builder(
            itemCount: tiles.length,
            itemBuilder: (context, index) {
              final question = tiles[index];
              return _ReviewTile(
                question: question,
                batchLabel: _batchLabel(question, batchGroups),
                nextReview: nextReviewLabel(question),
                onTap: () => _openQuestion(question),
              );
            },
          ),
        ),
        SliverPadding(
          padding: EdgeInsets.fromLTRB(
            AppTokens.s4,
            AppTokens.s4,
            AppTokens.s4,
            AppTokens.s6 + MediaQuery.paddingOf(context).bottom,
          ),
          sliver: SliverToBoxAdapter(
            child: _NextReviewCard(
              summary: _nextReviewSummary(questions, now),
            ),
          ),
        ),
      ],
    );
  }
}

/// 环形今日进度（88×88，`N/M` + 「今日进度」）。
class _TodayProgress extends StatelessWidget {
  const _TodayProgress({required this.done, required this.total});

  final int done;
  final int total;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final double value =
        total == 0 ? 0 : (done / total).clamp(0.0, 1.0).toDouble();
    return Center(
      child: SizedBox(
        width: 88,
        height: 88,
        child: Stack(
          alignment: Alignment.center,
          children: <Widget>[
            SizedBox(
              width: 88,
              height: 88,
              child: CircularProgressIndicator(
                value: value,
                strokeWidth: 8,
                backgroundColor: t.primarySoft,
                valueColor: AlwaysStoppedAnimation<Color>(t.primary),
              ),
            ),
            Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Text(
                  '$done/$total',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                    height: 1.1,
                    color: t.textPrimary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '今日进度',
                  style: TextStyle(fontSize: 10, color: t.textSecondary),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// 待复习 / 已掌握 分段 Tab（沿用 TabBar，改为 token 胶囊样式）。
class _ReviewTabBar extends StatelessWidget {
  const _ReviewTabBar({
    required this.controller,
    required this.pendingCount,
    required this.masteredCount,
  });

  final TabController controller;
  final int pendingCount;
  final int masteredCount;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Container(
      height: 40,
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: t.card,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: t.cardBorder),
        boxShadow: t.isDark ? null : t.shadow1,
      ),
      child: TabBar(
        controller: controller,
        dividerColor: Colors.transparent,
        indicatorSize: TabBarIndicatorSize.tab,
        indicator: BoxDecoration(
          color: t.primary,
          borderRadius: BorderRadius.circular(999),
        ),
        labelColor: t.onPrimary,
        unselectedLabelColor: t.textSecondary,
        labelStyle: const TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w700,
        ),
        unselectedLabelStyle: const TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w600,
        ),
        tabs: <Widget>[
          Tab(text: '待复习 $pendingCount'),
          Tab(text: '已掌握 $masteredCount'),
        ],
      ),
    );
  }
}

/// 当前复习卡（居中）：科目/掌握度 → 题干 → 公式块 → 显示答案 → 三键反馈。
class _CurrentReviewCard extends StatefulWidget {
  const _CurrentReviewCard({
    required this.question,
    required this.onOpen,
    required this.onResult,
  });

  final QuestionRecord question;
  final VoidCallback onOpen;
  final ValueChanged<MasteryLevel> onResult;

  @override
  State<_CurrentReviewCard> createState() => _CurrentReviewCardState();
}

class _CurrentReviewCardState extends State<_CurrentReviewCard> {
  bool _revealed = false;

  @override
  void didUpdateWidget(covariant _CurrentReviewCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 换题后收起答案
    if (oldWidget.question.id != widget.question.id) _revealed = false;
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final question = widget.question;
    final stem = _splitStem(question);
    final answer = question.analysisResult?.finalAnswer.trim() ?? '';

    return AppCard(
      padding: const EdgeInsets.all(AppTokens.s4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              AppTag(
                question.subject.label,
                color: t.subjectColor(question.subject.label),
                background: t.subjectSoft(question.subject.label),
                fontWeight: FontWeight.w500,
              ),
              const SizedBox(width: AppTokens.s2),
              AppTag(
                _masteryLabel(question.masteryLevel),
                color: _masteryColor(t, question.masteryLevel),
                background: _masterySoft(t, question.masteryLevel),
              ),
            ],
          ),
          const SizedBox(height: AppTokens.s3),
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: widget.onOpen,
            // 短题干居中（与样机一致）；长题干自然占满宽度
            child: Center(
              child: MathContentView(
                stem.stem,
                contentFormat: question.contentFormat,
                style: TextStyle(
                  fontSize: AppTokens.textBase,
                  fontWeight: FontWeight.w500,
                  height: 1.6,
                  color: t.textPrimary,
                ),
              ),
            ),
          ),
          if (stem.formula != null) ...<Widget>[
            const SizedBox(height: AppTokens.s3),
            _FormulaBlock(formula: stem.formula!),
          ],
          if (_revealed && answer.isNotEmpty) ...<Widget>[
            const SizedBox(height: AppTokens.s3),
            _AnswerBlock(answer: answer),
          ],
          const SizedBox(height: AppTokens.s3),
          AppButton(
            label: _revealed ? '收起答案' : '显示答案',
            icon: CupertinoIcons.eye,
            kind: AppButtonKind.outline,
            height: 36,
            onPressed: () => setState(() => _revealed = !_revealed),
          ),
          const SizedBox(height: AppTokens.s3),
          Row(
            children: <Widget>[
              Expanded(
                child: AppButton(
                  label: '仍不会',
                  kind: AppButtonKind.error,
                  height: 36,
                  fontSize: AppTokens.textXs,
                  onPressed: () =>
                      widget.onResult(MasteryLevel.newQuestion),
                ),
              ),
              const SizedBox(width: AppTokens.s2),
              Expanded(
                child: AppButton(
                  label: '模糊',
                  kind: AppButtonKind.warning,
                  height: 36,
                  fontSize: AppTokens.textXs,
                  onPressed: () => widget.onResult(MasteryLevel.reviewing),
                ),
              ),
              const SizedBox(width: AppTokens.s2),
              Expanded(
                child: AppButton(
                  label: '已掌握',
                  kind: AppButtonKind.success,
                  height: 36,
                  fontSize: AppTokens.textXs,
                  onPressed: () => widget.onResult(MasteryLevel.mastered),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// 公式块：中立底 + serif 斜体（有公式时展示）。
class _FormulaBlock extends StatelessWidget {
  const _FormulaBlock({required this.formula});

  final String formula;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(
        horizontal: AppTokens.s3,
        vertical: AppTokens.s2,
      ),
      decoration: BoxDecoration(
        color: t.formulaBg,
        borderRadius: BorderRadius.circular(AppTokens.radiusSm),
      ),
      child: Center(
        child: MathContentView(
          '\$\$$formula\$\$',
          style: TextStyle(
            fontSize: AppTokens.textSm,
            fontStyle: FontStyle.italic,
            color: t.textPrimary,
          ),
        ),
      ),
    );
  }
}

/// 答案块（点「显示答案」后出现）。
class _AnswerBlock extends StatelessWidget {
  const _AnswerBlock({required this.answer});

  final String answer;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppTokens.s3),
      decoration: BoxDecoration(
        color: t.successSoft,
        borderRadius: BorderRadius.circular(AppTokens.radiusSm),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            '答案',
            style: TextStyle(
              fontSize: AppTokens.textXs,
              fontWeight: FontWeight.w600,
              color: t.success,
            ),
          ),
          const SizedBox(height: AppTokens.s1),
          MathContentView(
            answer,
            style: TextStyle(
              fontSize: AppTokens.textSm,
              color: t.textPrimary,
            ),
          ),
        ],
      ),
    );
  }
}

/// 列表里的紧凑错题条（点击进入详情）。
class _ReviewTile extends StatelessWidget {
  const _ReviewTile({
    required this.question,
    required this.onTap,
    this.batchLabel,
    this.nextReview,
  });

  final QuestionRecord question;
  final VoidCallback onTap;
  final String? batchLabel;
  final String? nextReview;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final subjectLabel = question.subject.label;
    final subjectColor = t.subjectColor(subjectLabel);
    final next = nextReview;

    return AppCard(
      onTap: onTap,
      margin: const EdgeInsets.only(bottom: AppTokens.s2),
      padding: const EdgeInsets.all(AppTokens.s3),
      child: Row(
        children: <Widget>[
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: t.subjectSoft(subjectLabel),
              borderRadius: BorderRadius.circular(AppTokens.radiusMd),
            ),
            child: Icon(question.subject.icon, size: 18, color: subjectColor),
          ),
          const SizedBox(width: AppTokens.s3),
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
                    fontSize: AppTokens.textSm,
                    fontWeight: FontWeight.w500,
                    color: t.textPrimary,
                  ),
                ),
                if (batchLabel != null) ...<Widget>[
                  const SizedBox(height: 2),
                  Text(
                    batchLabel!,
                    style: TextStyle(
                      fontSize: AppTokens.textXs,
                      color: t.textTertiary,
                    ),
                  ),
                ],
                const SizedBox(height: AppTokens.s1),
                Wrap(
                  spacing: AppTokens.s2,
                  runSpacing: AppTokens.s1,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: <Widget>[
                    AppTag(
                      subjectLabel,
                      color: subjectColor,
                      background: t.subjectSoft(subjectLabel),
                    ),
                    AppTag(
                      _masteryLabel(question.masteryLevel),
                      color: _masteryColor(t, question.masteryLevel),
                      background: _masterySoft(t, question.masteryLevel),
                    ),
                    if (next != null)
                      AppTag(next, color: t.textTertiary, background: t.formulaBg),
                    for (final tag in question.aiTags.take(2))
                      AppTag(tag, color: t.warning, background: t.warningSoft),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: AppTokens.s2),
          Icon(
            CupertinoIcons.chevron_forward,
            size: 18,
            color: t.textTertiary,
          ),
        ],
      ),
    );
  }
}

/// 下次复习提示卡（图标 + 标题 + 描述 + 箭头）。
class _NextReviewCard extends StatelessWidget {
  const _NextReviewCard({this.summary});

  final String? summary;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return AppCard(
      padding: const EdgeInsets.symmetric(
        horizontal: AppTokens.s4,
        vertical: AppTokens.s3,
      ),
      child: Row(
        children: <Widget>[
          Icon(CupertinoIcons.time, size: 20, color: t.primary),
          const SizedBox(width: AppTokens.s3),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  '下次复习',
                  style: TextStyle(
                    fontSize: AppTokens.textSm,
                    fontWeight: FontWeight.w500,
                    color: t.textPrimary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  summary ?? '暂无待巩固的题目',
                  style: TextStyle(
                    fontSize: AppTokens.textXs,
                    color: t.textTertiary,
                  ),
                ),
              ],
            ),
          ),
          Icon(
            CupertinoIcons.chevron_forward,
            size: 16,
            color: t.textTertiary,
          ),
        ],
      ),
    );
  }
}

/// 空状态卡（今日已清空）。
class _EmptyCard extends StatelessWidget {
  const _EmptyCard({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Container(
      padding: const EdgeInsets.all(AppTokens.s8),
      decoration: BoxDecoration(
        color: t.successSoft,
        borderRadius: BorderRadius.circular(AppTokens.radiusLg),
        border: Border.all(color: t.success.withValues(alpha: 0.35)),
      ),
      child: Column(
        children: <Widget>[
          Icon(CupertinoIcons.star, size: 40, color: t.success),
          const SizedBox(height: AppTokens.s3),
          Text(
            '太棒了！',
            style: TextStyle(
              fontSize: AppTokens.textBase,
              fontWeight: FontWeight.w600,
              color: t.textPrimary,
            ),
          ),
          const SizedBox(height: AppTokens.s1),
          Text(
            message,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: AppTokens.textSm,
              color: t.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}

String? _batchLabel(
  QuestionRecord question,
  Map<String, QuestionBatchGroup>? batchGroups,
) {
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
    case MasteryLevel.reviewing:
      return '待复习';
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

Color _masterySoft(AppTokens t, MasteryLevel level) {
  switch (level) {
    case MasteryLevel.newQuestion:
      return t.formulaBg;
    case MasteryLevel.reviewing:
      return t.warningSoft;
    case MasteryLevel.mastered:
      return t.successSoft;
  }
}

bool _isSameDay(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;

/// 下次复习描述，如「明天 · 6 道待巩固」；无待巩固题时返回 null。
String? _nextReviewSummary(List<QuestionRecord> questions, DateTime now) {
  final upcoming = questions
      .where((q) => q.masteryLevel != MasteryLevel.mastered && !isDue(q, now: now))
      .toList();
  DateTime? earliest;
  for (final question in upcoming) {
    final at = nextReviewAt(question);
    if (at == null) continue;
    if (earliest == null || at.isBefore(earliest)) earliest = at;
  }
  if (earliest == null) return null;

  final dayCount = upcoming.where((question) {
    final at = nextReviewAt(question);
    return at != null && _isSameDay(at, earliest!);
  }).length;

  return '${_relativeDayLabel(earliest, now)} · $dayCount 道待巩固';
}

String _relativeDayLabel(DateTime at, DateTime now) {
  final today = DateTime(now.year, now.month, now.day);
  final target = DateTime(at.year, at.month, at.day);
  final days = target.difference(today).inDays;
  if (days <= 0) return '今天';
  if (days == 1) return '明天';
  if (days == 2) return '后天';
  return '$days 天后';
}

/// 题干里第一个公式的匹配式（`$$…$$` / `\[…\]` / `\(…\)` / `$…$`）。
final List<RegExp> _formulaPatterns = <RegExp>[
  RegExp(r'\$\$([\s\S]*?)\$\$'),
  RegExp(r'\\\[([\s\S]*?)\\\]'),
  RegExp(r'\\\(([\s\S]*?)\\\)'),
  RegExp(r'(?<!\\)\$([^\$]+)\$'),
];

/// 把题干里的第一个公式抽出来单独成块，避免题干与公式块重复展示同一段公式。
({String stem, String? formula}) _splitStem(QuestionRecord question) {
  final text = question.correctedText;
  for (final pattern in _formulaPatterns) {
    final match = pattern.firstMatch(text);
    if (match == null) continue;
    final formula = match.group(1)?.trim();
    if (formula == null || formula.isEmpty) continue;
    final stem = <String>[
      text.substring(0, match.start),
      text.substring(match.end),
    ].join(' ').replaceAll(RegExp(r'[ \t]{2,}'), ' ').trim();
    return (stem: stem, formula: formula);
  }
  return (stem: text, formula: null);
}
