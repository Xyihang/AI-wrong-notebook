import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';
import 'package:smart_wrong_notebook/src/app/design/tokens.dart';
import 'package:smart_wrong_notebook/src/app/providers.dart';
import 'package:smart_wrong_notebook/src/common/widgets/app_button.dart';
import 'package:smart_wrong_notebook/src/common/widgets/app_card.dart';
import 'package:smart_wrong_notebook/src/common/widgets/app_chip.dart';
import 'package:smart_wrong_notebook/src/domain/models/mastery_level.dart';
import 'package:smart_wrong_notebook/src/domain/models/question_record.dart';
import 'package:smart_wrong_notebook/src/domain/models/subject.dart';
import 'package:smart_wrong_notebook/src/features/capture/presentation/capture_entry_sheet.dart';
import 'package:smart_wrong_notebook/src/features/glass/glass_overlays.dart';
import 'package:smart_wrong_notebook/src/features/glass/glass_providers.dart';
import 'package:smart_wrong_notebook/src/features/glass/glass_refresh_indicator.dart';
import 'package:smart_wrong_notebook/src/features/glass/glass_top_bar.dart';
import 'package:smart_wrong_notebook/src/shared/widgets/math_content_view.dart';

class NotebookScreen extends ConsumerStatefulWidget {
  const NotebookScreen({super.key});

  @override
  ConsumerState<NotebookScreen> createState() => _NotebookScreenState();
}

class _NotebookScreenState extends ConsumerState<NotebookScreen> {
  final _searchController = TextEditingController();

  /// 页面级「未掌握」筛选：筛选 provider 只支持单一掌握度，
  /// 这里在展示层过滤掉已掌握，不改动 provider。
  bool _unmasteredOnly = false;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _confirmDelete(
      BuildContext context, WidgetRef ref, QuestionRecord question) async {
    final ok = await showAppConfirm(
      context,
      title: '确认删除',
      message: '删除后无法恢复，确定要删除这道错题吗？',
      confirmText: '删除',
      destructive: true,
    );
    if (!ok) return;
    await ref.read(questionRepositoryProvider).delete(question.id);
    invalidateQuestionList(ref);
  }

  void _openCapture(BuildContext context) {
    showAppSheet<void>(
      context,
      bottomInset: 20,
      builder: (_) => const CaptureEntrySheet(),
    );
  }

  void _clearAllFilters(WidgetRef ref) {
    ref.read(selectedSubjectFilterProvider.notifier).state = null;
    ref.read(selectedMasteryFilterProvider.notifier).state = null;
    ref.read(selectedCreatedTodayFilterProvider.notifier).state = false;
    ref.read(selectedKnowledgePointFilterProvider.notifier).state = null;
    setState(() => _unmasteredOnly = false);
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final questionsAsync = ref.watch(filteredQuestionListProvider);
    final selectedSubject = ref.watch(selectedSubjectFilterProvider);
    final selectedMastery = ref.watch(selectedMasteryFilterProvider);
    final selectedCreatedToday = ref.watch(selectedCreatedTodayFilterProvider);
    final selectedKnowledgePoint =
        ref.watch(selectedKnowledgePointFilterProvider);
    // 各科数量取全量列表，不受当前科目筛选影响。
    final allQuestions = ref.watch(questionListProvider).valueOrNull ??
        const <QuestionRecord>[];
    final batchGroups =
        ref.watch(questionBatchGroupsProvider).valueOrNull ??
            const <String, QuestionBatchGroup>{};

    final glassEnabled = ref.watch(glassEnabledProvider);
    final subjectCounts = <Subject, int>{};
    for (final question in allQuestions) {
      subjectCounts[question.subject] =
          (subjectCounts[question.subject] ?? 0) + 1;
    }
    final hasAnyFilter = selectedSubject != null ||
        selectedMastery != null ||
        selectedCreatedToday ||
        selectedKnowledgePoint != null ||
        _unmasteredOnly;

    return Scaffold(
      extendBodyBehindAppBar: glassEnabled,
      appBar: glassTopBar(
        context,
        title: const Text('错题本'),
        actions: <Widget>[
          IconButton(
            icon: const Icon(CupertinoIcons.camera),
            onPressed: () => _openCapture(context),
            tooltip: '添加错题',
          ),
        ],
      ),
      body: Column(
        children: <Widget>[
          // 玻璃顶栏穿透时，给内容让出状态栏 + 工具栏高度
          if (glassEnabled) SizedBox(height: glassTopInset(context)),
          // Search bar（玻璃开启时用 GlassSearchBar）
          Padding(
            padding: const EdgeInsets.fromLTRB(
                AppTokens.s6, AppTokens.s2, AppTokens.s6, AppTokens.s2),
            child: glassEnabled
                ? GlassSearchBar(
                    controller: _searchController,
                    placeholder: '搜索题干、知识点…',
                    height: 46,
                    quality: ref.watch(glassQualityProvider),
                    onChanged: (v) {
                      ref.read(searchQueryProvider.notifier).state = v;
                      setState(() {});
                    },
                  )
                : TextField(
                    controller: _searchController,
                    style: TextStyle(
                        fontSize: AppTokens.textSm, color: t.textPrimary),
                    decoration: InputDecoration(
                      hintText: '搜索题干、知识点…',
                      hintStyle: TextStyle(
                          fontSize: AppTokens.textSm, color: t.textTertiary),
                      prefixIcon: Icon(CupertinoIcons.search,
                          size: 18, color: t.textTertiary),
                      suffixIcon: _searchController.text.isNotEmpty
                          ? IconButton(
                              icon: Icon(CupertinoIcons.xmark_circle,
                                  size: 18, color: t.textTertiary),
                              onPressed: () {
                                _searchController.clear();
                                ref.read(searchQueryProvider.notifier).state =
                                    '';
                                setState(() {});
                              },
                            )
                          : null,
                      isDense: true,
                      contentPadding:
                          const EdgeInsets.symmetric(vertical: 12),
                      filled: true,
                      fillColor: t.card,
                      border: OutlineInputBorder(
                        borderRadius:
                            BorderRadius.circular(AppTokens.radiusMd),
                        borderSide: BorderSide(color: t.cardBorder),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius:
                            BorderRadius.circular(AppTokens.radiusMd),
                        borderSide: BorderSide(color: t.cardBorder),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius:
                            BorderRadius.circular(AppTokens.radiusMd),
                        borderSide: BorderSide(color: t.primary),
                      ),
                    ),
                    onChanged: (v) {
                      ref.read(searchQueryProvider.notifier).state = v;
                      setState(() {});
                    },
                  ),
          ),
          // 筛选 chips
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: AppTokens.s6),
            child: Row(
              children: <Widget>[
                AppChip(
                  label: '全部',
                  selected: !hasAnyFilter,
                  onTap: () => _clearAllFilters(ref),
                ),
                if (selectedCreatedToday) ...<Widget>[
                  const SizedBox(width: AppTokens.s2),
                  AppChip(
                    label: '今日新增',
                    selected: true,
                    onTap: () {
                      ref
                          .read(selectedCreatedTodayFilterProvider.notifier)
                          .state = false;
                    },
                  ),
                ],
                const SizedBox(width: AppTokens.s2),
                AppChip(
                  label: '未掌握',
                  selected: _unmasteredOnly,
                  onTap: () =>
                      setState(() => _unmasteredOnly = !_unmasteredOnly),
                ),
                if (selectedMastery != null) ...<Widget>[
                  const SizedBox(width: AppTokens.s2),
                  AppChip(
                    label: _masteryFilterLabel(selectedMastery),
                    selected: true,
                    onTap: () {
                      ref.read(selectedMasteryFilterProvider.notifier).state =
                          null;
                    },
                  ),
                ],
                ...Subject.selectableValues
                    .where((s) =>
                        (subjectCounts[s] ?? 0) > 0 || selectedSubject == s)
                    .map((s) => Padding(
                          padding:
                              const EdgeInsets.only(left: AppTokens.s2),
                          child: AppChip(
                            label: (subjectCounts[s] ?? 0) > 0
                                ? '${s.label} ${subjectCounts[s]}'
                                : s.label,
                            selected: selectedSubject == s,
                            onTap: () {
                              ref
                                  .read(selectedSubjectFilterProvider.notifier)
                                  .state = selectedSubject == s ? null : s;
                            },
                          ),
                        )),
                // AI 知识点过滤
                if (selectedKnowledgePoint != null) ...<Widget>[
                  const SizedBox(width: AppTokens.s2),
                  AppChip(
                    label: '知识点：$selectedKnowledgePoint',
                    selected: true,
                    onTap: () {
                      ref
                          .read(selectedKnowledgePointFilterProvider.notifier)
                          .state = null;
                    },
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: AppTokens.s2),
          // List
          Expanded(
            child: questionsAsync.when(
              data: (questions) {
                final visible = _unmasteredOnly
                    ? questions
                        .where((q) => q.masteryLevel != MasteryLevel.mastered)
                        .toList()
                    : questions;
                if (visible.isEmpty) {
                  return _NotebookEmptyState(
                    filtered: questions.isNotEmpty,
                    onAdd: () => _openCapture(context),
                  );
                }
                // B6：玻璃下拉刷新（关闭玻璃时内部直接透传，不显示指示器）
                return GlassRefreshIndicator(
                  onRefresh: () async {
                    ref.invalidate(questionListProvider);
                    await Future<void>.delayed(
                        const Duration(milliseconds: 350));
                  },
                  edgeOffset: glassEnabled ? glassTopInset(context) : 0,
                  child: ListView.builder(
                    padding: const EdgeInsets.fromLTRB(
                        AppTokens.s6, AppTokens.s1, AppTokens.s6, AppTokens.s6),
                    itemCount: visible.length,
                    itemBuilder: (context, index) {
                      final q = visible[index];
                      final batchGroup = batchGroups[questionBatchRootId(q)];
                      final card = _QuestionCard(
                        question: q,
                        sameCount: batchGroup == null
                            ? 0
                            : batchGroup.questions.length - 1,
                        onTap: () {
                          ref.read(currentQuestionProvider.notifier).state =
                              q;
                          // 用 push 保留返回栈：系统返回键回到错题本而不是首页
                          context.push('/notebook/question/${q.id}');
                        },
                        onDelete: () => _confirmDelete(context, ref, q),
                        // 按需求：点击知识点标签不再筛选
                        onKnowledgePointTap: (_) {},
                      );
                      return RepaintBoundary(
                        child: glassEnabled
                            // 玻璃开启：左滑出玻璃操作（删除）
                            ? GlassSwipeActions(
                                trailingActions: <GlassSwipeAction>[
                                  GlassSwipeAction(
                                    icon: const Icon(CupertinoIcons.trash),
                                    label: const Text('删除'),
                                    isDestructive: true,
                                    onTap: () =>
                                        _confirmDelete(context, ref, q),
                                  ),
                                ],
                                child: card,
                              )
                            : card,
                      );
                    },
                  ),
                );
              },
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(
                child: Text(
                  '加载失败: $e',
                  style: TextStyle(
                      fontSize: AppTokens.textSm, color: t.textSecondary),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

String _masteryFilterLabel(MasteryLevel level) {
  return switch (level) {
    MasteryLevel.newQuestion => '新题',
    MasteryLevel.reviewing => '复习中',
    MasteryLevel.mastered => '已掌握',
  };
}

/// 空状态（demo `.empty-state`）：图标 + 标题 + 描述 + 拍照入口。
class _NotebookEmptyState extends StatelessWidget {
  const _NotebookEmptyState({required this.filtered, required this.onAdd});

  /// true 表示有错题、只是当前筛选条件下没有结果。
  final bool filtered;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppTokens.s8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(
              filtered ? CupertinoIcons.search : CupertinoIcons.book,
              size: 48,
              color: t.textTertiary.withValues(alpha: 0.6),
            ),
            const SizedBox(height: AppTokens.s3),
            Text(
              filtered ? '没有符合条件的错题' : '暂无错题',
              style: TextStyle(
                fontSize: AppTokens.textBase,
                fontWeight: FontWeight.w500,
                color: t.textSecondary,
              ),
            ),
            const SizedBox(height: AppTokens.s1),
            Text(
              filtered ? '换个筛选条件试试' : '拍下题目，AI 自动解析入库',
              style: TextStyle(
                  fontSize: AppTokens.textSm, color: t.textTertiary),
            ),
            if (!filtered) ...<Widget>[
              const SizedBox(height: AppTokens.s4),
              AppButton(
                label: '拍照添加',
                icon: CupertinoIcons.camera,
                expand: false,
                onPressed: onAdd,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// 错题卡（demo `.q-card`）：科目软底标签 + 掌握状态 + 时间 + 题干 + 公式块 +
/// 知识点标签 + 同类题标记。
class _QuestionCard extends StatelessWidget {
  const _QuestionCard({
    required this.question,
    required this.sameCount,
    required this.onTap,
    required this.onDelete,
    required this.onKnowledgePointTap,
  });

  final QuestionRecord question;
  final int sameCount;
  final VoidCallback onTap;
  final VoidCallback onDelete;
  final void Function(String knowledgePoint) onKnowledgePointTap;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final masteryColor = _masteryColor(context, question.masteryLevel);
    final masterySoft = _masterySoft(context, question.masteryLevel);
    final knowledgePoints = <String>{
      ...question.aiKnowledgePoints,
      ...question.customTags,
    }.toList();
    final formula = _displayFormula(question.correctedText);

    return Dismissible(
      key: ValueKey(question.id),
      direction: DismissDirection.endToStart,
      confirmDismiss: (_) async {
        onDelete();
        return false;
      },
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: AppTokens.s6),
        margin: const EdgeInsets.only(bottom: AppTokens.s3),
        decoration: BoxDecoration(
          color: t.errorSoft,
          borderRadius: BorderRadius.circular(AppTokens.radiusLg),
        ),
        child: Icon(CupertinoIcons.trash, color: t.error),
      ),
      child: Semantics(
        button: true,
        label:
            '错题: ${question.correctedText}，科目: ${question.subject.label}，状态: ${_masteryLabel(question.masteryLevel)}，日期: ${_formatDate(question.createdAt)}，左滑删除',
        child: Padding(
          padding: const EdgeInsets.only(bottom: AppTokens.s3),
          child: GestureDetector(
            onTap: onTap,
            behavior: HitTestBehavior.opaque,
            child: AppCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Row(
                    children: <Widget>[
                      AppTag(
                        question.subject.label,
                        color: t.subjectColor(question.subject.label),
                        background: t.subjectSoft(question.subject.label),
                        fontWeight: FontWeight.w600,
                      ),
                      const SizedBox(width: AppTokens.s2),
                      AppTag(
                        _masteryLabel(question.masteryLevel),
                        color: masteryColor,
                        background: masterySoft,
                        fontWeight: FontWeight.w500,
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
                    // 列表里用紧凑模式，保证卡片高度稳定、长题干自动省略
                    mode: MathContentViewMode.compact,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: AppTokens.textSm,
                      height: 1.6,
                      color: t.textPrimary,
                    ),
                  ),
                  if (formula != null) ...<Widget>[
                    const SizedBox(height: AppTokens.s2),
                    _FormulaBlock(formula: formula),
                  ],
                  if (knowledgePoints.isNotEmpty || sameCount > 0) ...<Widget>[
                    const SizedBox(height: AppTokens.s3),
                    Wrap(
                      spacing: AppTokens.s2,
                      runSpacing: AppTokens.s1,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: <Widget>[
                        ...knowledgePoints.take(3).map(
                              (tag) => AppTag(tag),
                            ),
                        if (sameCount > 0)
                          AppTag(
                            '×$sameCount 同类',
                            color: t.secondary,
                            background: t.secondarySoft,
                            fontWeight: FontWeight.w500,
                          ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  String _formatDate(DateTime date) {
    final now = DateTime.now();
    final diff = now.difference(date);
    if (diff.inDays == 0) return '今天';
    if (diff.inDays == 1) return '昨天';
    if (diff.inDays < 7) return '${diff.inDays}天前';
    return '${date.month}月${date.day}日';
  }

  Color _masteryColor(BuildContext context, MasteryLevel level) {
    final t = context.tokens;
    switch (level) {
      case MasteryLevel.newQuestion:
        return t.textSecondary;
      case MasteryLevel.reviewing:
        return t.warning;
      case MasteryLevel.mastered:
        return t.success;
    }
  }

  Color _masterySoft(BuildContext context, MasteryLevel level) {
    final t = context.tokens;
    switch (level) {
      case MasteryLevel.newQuestion:
        return t.formulaBg;
      case MasteryLevel.reviewing:
        return t.warningSoft;
      case MasteryLevel.mastered:
        return t.successSoft;
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
}

/// 公式块（demo `.q-formula`）：serif 斜体 + 中立底色。
class _FormulaBlock extends StatelessWidget {
  const _FormulaBlock({required this.formula});

  final String formula;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(
          horizontal: AppTokens.s3, vertical: AppTokens.s2),
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
            fontFamily: 'serif',
            fontFamilyFallback: const <String>['Times New Roman', 'serif'],
            color: t.textPrimary,
          ),
        ),
      ),
    );
  }
}

/// 题干里的第一个公式（`$$…$$` / `\[…\]` / `\(…\)` / `$…$`），没有则返回 null。
String? _displayFormula(String raw) {
  final patterns = <RegExp>[
    RegExp(r'\$\$([\s\S]*?)\$\$'),
    RegExp(r'\\\[([\s\S]*?)\\\]'),
    RegExp(r'\\\(([\s\S]*?)\\\)'),
    RegExp(r'(?<!\\)\$([^\$]+)\$'),
  ];
  for (final pattern in patterns) {
    final found = pattern.firstMatch(raw)?.group(1)?.trim();
    if (found != null && found.isNotEmpty) return found;
  }
  return null;
}
