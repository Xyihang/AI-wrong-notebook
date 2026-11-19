import 'dart:io';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:smart_wrong_notebook/src/app/design/tokens.dart';
import 'package:smart_wrong_notebook/src/app/providers.dart';
import 'package:smart_wrong_notebook/src/common/widgets/app_card.dart';
import 'package:smart_wrong_notebook/src/features/glass/glass_overlays.dart';
import 'package:smart_wrong_notebook/src/features/glass/glass_top_bar.dart';
import 'package:smart_wrong_notebook/src/data/services/question_analysis_coordinator.dart';
import 'package:smart_wrong_notebook/src/domain/models/analysis_result.dart';
import 'package:smart_wrong_notebook/src/domain/models/mastery_level.dart';
import 'package:smart_wrong_notebook/src/domain/models/question_record.dart';
import 'package:smart_wrong_notebook/src/domain/models/question_split_result.dart';
import 'package:smart_wrong_notebook/src/shared/widgets/math_content_view.dart';

class AnalysisResultScreen extends ConsumerStatefulWidget {
  const AnalysisResultScreen({super.key});

  @override
  ConsumerState<AnalysisResultScreen> createState() =>
      _AnalysisResultScreenState();
}

class _AnalysisResultScreenState extends ConsumerState<AnalysisResultScreen> {
  int _activeCandidateIndex = 0;

  /// 视觉模式降级提醒条（用户 DeepSeek Key 失效等）。无提醒时返回空列表。
  List<Widget> _buildVisionModeWarning() {
    final warning =
        ref.read(aiAnalysisServiceProvider).visionModeWarning;
    if (warning == null || warning.trim().isEmpty) {
      return const <Widget>[];
    }
    final t = context.tokens;
    return <Widget>[
      Container(
        margin: const EdgeInsets.only(bottom: AppTokens.s4),
        padding: const EdgeInsets.all(AppTokens.s3),
        decoration: BoxDecoration(
          color: t.warningSoft,
          borderRadius: BorderRadius.circular(AppTokens.radiusLg),
          border: Border.all(color: t.warning.withValues(alpha: 0.45)),
        ),
        child: Row(
          children: <Widget>[
            Icon(Icons.warning_amber_rounded, color: t.warning),
            const SizedBox(width: AppTokens.s2),
            Expanded(
              child: Text(
                warning,
                style: TextStyle(
                  color: t.textPrimary,
                  fontSize: AppTokens.textSm,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final selectedRecord = ref.watch(currentQuestionProvider);
    final backgroundTasks =
        ref.watch(backgroundAnalysisTasksProvider).valueOrNull ??
            const <QuestionAnalysisTaskSnapshot>[];
    final record = _latestTaskResultFor(
      selectedRecord,
      backgroundTasks,
    );

    if (record == null) {
      return Scaffold(
        appBar: glassTopBar(context, 
          title: const Text('AI 解析结果'),
          leading: IconButton(
            icon: const Icon(CupertinoIcons.chevron_left),
            onPressed: () => context.go('/analysis/loading'),
          ),
        ),
        body: const Center(child: Text('未找到错题记录')),
      );
    }

    final result = record.analysisResult;
    final splitResult = record.splitResult;
    final hasMultipleCandidates = splitResult?.hasMultipleCandidates ?? false;
    final safeCandidateIndex = hasMultipleCandidates
        ? _activeCandidateIndex.clamp(0, splitResult!.candidates.length - 1)
        : 0;
    final activeCandidate = hasMultipleCandidates
        ? splitResult!.candidates[safeCandidateIndex]
        : null;
    final activeCandidateAnalysis = activeCandidate == null
        ? null
        : record.candidateAnalyses.firstWhereOrNull(
            (candidate) => candidate.candidateId == activeCandidate.id);
    final displayResult = hasMultipleCandidates
        ? activeCandidateAnalysis?.analysisResult
        : result;
    final displayAiTags = hasMultipleCandidates
        ? activeCandidateAnalysis?.aiTags ?? const <String>[]
        : record.aiTags;
    final displayKnowledgePoints = hasMultipleCandidates
        ? activeCandidateAnalysis?.aiKnowledgePoints ?? const <String>[]
        : result?.knowledgePoints ?? const <String>[];
    final displayQuestionText = activeCandidateAnalysis?.questionText ??
        activeCandidate?.text ??
        record.correctedText;
    final hasRetryingCandidate = record.candidateAnalyses.any((candidate) =>
        candidate.status == CandidateAnalysisStatus.queued ||
        candidate.status == CandidateAnalysisStatus.running);
    final candidateInsight = hasMultipleCandidates
        ? _candidateInsight(
            candidateOrder: activeCandidate?.order ?? 1,
            total: splitResult?.candidates.length ?? 1,
            hasIndependentAnalysis: activeCandidateAnalysis != null,
          )
        : null;
    final subjectLabel = displayResult?.subject?.label ?? record.subject.label;
    final needsReview = displayResult?.visualAssumptionStatus ==
        VisualAssumptionStatus.needsReview;
    final t = context.tokens;
    return Scaffold(
      appBar: glassTopBar(context, 
        title: const Text('AI 解析结果'),
        leading: IconButton(
          icon: const Icon(CupertinoIcons.chevron_left),
          onPressed: () => context.go('/'),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: <Widget>[
          // 视觉模式降级醒目提醒（如用户 DeepSeek Key 失效）
          ..._buildVisionModeWarning(),
          // 统一标签分类框：科目 | AI识别 | 状态 | 知识点
          AppCard(
            padding: const EdgeInsets.symmetric(
                horizontal: AppTokens.s3, vertical: 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                // 第一行：科目 + AI识别 + 状态（用 Wrap 防溢出）
                Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  children: <Widget>[
                    _TagChip(
                      label: subjectLabel,
                      color: t.subjectColor(subjectLabel),
                      background: t.subjectSoft(subjectLabel),
                    ),
                    if (displayResult?.subject != null)
                      _TagChip(
                        label: 'AI识别',
                        color: t.success,
                        background: t.successSoft,
                      ),
                    _TagChip(
                      label: _masteryLabel(record.masteryLevel),
                      color: _masteryColor(context, record.masteryLevel),
                      background: _masterySoft(context, record.masteryLevel),
                    ),
                  ],
                ),
                if (record.splitResult != null) ...<Widget>[
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8,
                    runSpacing: 6,
                    children: <Widget>[
                      _TagChip(
                        label: '候选 ${record.splitResult!.candidates.length} 题',
                        color: t.primary,
                        background: t.primarySoft,
                      ),
                      _TagChip(
                        label:
                            _splitStrategyLabel(record.splitResult!.strategy),
                        color: t.textSecondary,
                        background: t.formulaBg,
                      ),
                      if (activeCandidate != null)
                        _TagChip(
                          label: '当前第 ${activeCandidate.order} 题',
                          color: t.warning,
                          background: t.warningSoft,
                        ),
                    ],
                  ),
                  if (record.splitResult!.hasMultipleCandidates) ...<Widget>[
                    const SizedBox(height: 8),
                    Text(
                      '这张图片已识别为多题内容，保存时会进入逐题确认。',
                      style: TextStyle(
                          fontSize: AppTokens.textXs, color: t.textSecondary),
                    ),
                  ],
                ],
                // AI 短标签（橙色）
                if (displayAiTags.isNotEmpty) ...<Widget>[
                  const SizedBox(height: 10),
                  Text('AI标签',
                      style: TextStyle(
                          fontSize: AppTokens.textXs,
                          color: t.textSecondary)),
                  const SizedBox(height: 4),
                  Wrap(
                    spacing: 6,
                    runSpacing: 4,
                    children: displayAiTags
                        .map((tag) => _TagChip(
                              label: tag,
                              color: t.warning,
                              background: t.warningSoft,
                            ))
                        .toList(),
                  ),
                ],
                // 自定义标签（蓝色）
                if (record.customTags.isNotEmpty) ...<Widget>[
                  const SizedBox(height: 8),
                  Text('自定义标签',
                      style: TextStyle(
                          fontSize: AppTokens.textXs,
                          color: t.textSecondary)),
                  const SizedBox(height: 4),
                  Wrap(
                    spacing: 6,
                    runSpacing: 4,
                    children: record.customTags
                        .map((tag) => _TagChip(
                              label: tag,
                              color: t.primary,
                              background: t.primarySoft,
                            ))
                        .toList(),
                  ),
                ],
              ],
            ),
          ),
          if (record.splitResult?.hasMultipleCandidates ?? false) ...<Widget>[
            const SizedBox(height: 12),
            _CandidateSwitcherCard(
              splitResult: splitResult!,
              candidateAnalyses: record.candidateAnalyses,
              safeCandidateIndex: safeCandidateIndex,
              onSelected: (index) =>
                  setState(() => _activeCandidateIndex = index),
            ),
          ],
          if (displayResult == null) ...<Widget>[
            const SizedBox(height: 20),
            _SectionCard(
              icon: CupertinoIcons.exclamationmark_triangle,
              tone: t.error,
              title: _candidateFailureTitle(activeCandidateAnalysis,
                  order: activeCandidate?.order ?? 1),
              contentWidget: MathContentView(
                _candidateFailureMessage(activeCandidateAnalysis),
                style: TextStyle(
                  fontSize: AppTokens.textSm,
                  color: t.error,
                  height: 1.5,
                ),
              ),
            ),
            if (hasMultipleCandidates &&
                activeCandidateAnalysis != null) ...<Widget>[
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: activeCandidateAnalysis.status ==
                              CandidateAnalysisStatus.failed &&
                          activeCandidate != null
                      ? () => _retryCandidate(
                            record,
                            activeCandidateAnalysis,
                          )
                      : null,
                  icon: Icon(_candidateRetryIcon(activeCandidateAnalysis)),
                  label: Text(_candidateRetryLabel(
                    activeCandidateAnalysis,
                    activeCandidate?.order ?? 1,
                  )),
                ),
              ),
            ],
          ],
          if (displayResult != null) ...<Widget>[
            const SizedBox(height: 20),
            // 原题（包含图片和文本）
            _SectionCard(
              icon: CupertinoIcons.doc_text,
              tone: t.primary,
              title: '原题',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  if (File(record.imagePath).existsSync())
                    GestureDetector(
                      onTap: () => _showFullImage(context, record.imagePath),
                      child: Container(
                        height: 120,
                        decoration: BoxDecoration(
                          color: t.formulaBg,
                          borderRadius:
                              BorderRadius.circular(AppTokens.radiusMd),
                        ),
                        child: Stack(
                          children: <Widget>[
                            ClipRRect(
                              borderRadius:
                                  BorderRadius.circular(AppTokens.radiusMd),
                              child: Image.file(
                                File(record.imagePath),
                                width: double.infinity,
                                height: 120,
                                fit: BoxFit.contain,
                              ),
                            ),
                            Positioned(
                              top: 6,
                              right: 6,
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 6, vertical: 3),
                                decoration: BoxDecoration(
                                  color: Colors.black.withValues(alpha: 0.58),
                                  borderRadius: BorderRadius.circular(
                                      AppTokens.radiusSm),
                                ),
                                child: const Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: <Widget>[
                                    Icon(CupertinoIcons.zoom_in,
                                        size: 12, color: Colors.white),
                                    SizedBox(width: 3),
                                    Text('查看原图',
                                        style: TextStyle(
                                            fontSize: 10, color: Colors.white)),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  if (File(record.imagePath).existsSync())
                    const SizedBox(height: 10),
                  MathContentView(
                    displayQuestionText,
                    contentFormat: hasMultipleCandidates
                        ? QuestionContentFormat.latexMixed
                        : record.contentFormat,
                    style: TextStyle(
                        fontSize: AppTokens.textSm,
                        color: t.textPrimary,
                        height: 1.5),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),
            // Answer
            _SectionCard(
              icon: needsReview
                  ? CupertinoIcons.exclamationmark_triangle
                  : CupertinoIcons.checkmark_circle,
              tone: needsReview ? t.warning : t.success,
              title: needsReview ? '可能解法' : '正确解答',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  MathContentView(
                    displayResult.finalAnswer,
                    style: TextStyle(
                        fontSize: AppTokens.textSm,
                        color: needsReview ? t.warning : t.success,
                        fontWeight: FontWeight.w600),
                  ),
                  if (_consistencyNotice(displayResult, t) != null) ...<Widget>[
                    const SizedBox(height: 10),
                    _ConsistencyNotice(
                      notice: _consistencyNotice(displayResult, t)!,
                    ),
                  ],
                  if (_shouldOfferQuestionCorrection(
                    displayResult,
                    hasMultipleCandidates: hasMultipleCandidates,
                  )) ...<Widget>[
                    const SizedBox(height: 12),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: OutlinedButton.icon(
                        onPressed: () =>
                            context.go('/analysis/text-correction'),
                        icon: const Icon(CupertinoIcons.pencil, size: 17),
                        label: const Text('核对题干后重新解析'),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 10),
            // Mistake reason
            _SectionCard(
              icon: CupertinoIcons.exclamationmark_triangle,
              tone: t.error,
              title: '错因分析',
              contentWidget: MathContentView(
                displayResult.mistakeReason,
                style: TextStyle(
                    fontSize: AppTokens.textSm,
                    color: t.textPrimary,
                    height: 1.5),
              ),
            ),
            const SizedBox(height: 10),
            // Study advice
            _SectionCard(
              icon: CupertinoIcons.lightbulb,
              tone: t.warning,
              title: '学习建议',
              contentWidget: MathContentView(
                displayResult.studyAdvice,
                style: TextStyle(
                    fontSize: AppTokens.textSm,
                    color: t.textPrimary,
                    height: 1.5),
              ),
            ),
            if (candidateInsight != null) ...<Widget>[
              const SizedBox(height: 10),
              _SectionCard(
                icon: CupertinoIcons.layers,
                tone: t.secondary,
                title: '当前子题状态',
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    MathContentView(
                      candidateInsight,
                      style: TextStyle(
                          fontSize: AppTokens.textSm,
                          color: t.textPrimary,
                          height: 1.5),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      activeCandidateAnalysis != null
                          ? '当前已切换到第 ${activeCandidate?.order ?? 1} 题独立解析。'
                          : '第 ${activeCandidate?.order ?? 1} 题暂无独立解析。',
                      style: TextStyle(
                          fontSize: AppTokens.textXs,
                          color: t.textSecondary,
                          height: 1.5),
                    ),
                  ],
                ),
              ),
            ],
            // Knowledge points
            if (displayKnowledgePoints.isNotEmpty) ...<Widget>[
              const SizedBox(height: 16),
              Text('知识点',
                  style: TextStyle(
                      fontSize: AppTokens.textSm,
                      fontWeight: FontWeight.w600,
                      color: t.textPrimary)),
              const SizedBox(height: 8),
              Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: displayKnowledgePoints
                    .map((p) => Container(
                          margin: const EdgeInsets.only(bottom: 6),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 5),
                          decoration: BoxDecoration(
                            color: t.primarySoft,
                            borderRadius:
                                BorderRadius.circular(AppTokens.radiusMd),
                            border: Border.all(color: t.cardBorder),
                          ),
                          child: MathContentView(
                            p,
                            style: TextStyle(
                                fontSize: AppTokens.textXs,
                                height: 1.45,
                                color: t.primary),
                          ),
                        ))
                    .toList(),
              ),
            ],
            // Steps
            if (displayResult.steps.isNotEmpty) ...<Widget>[
              const SizedBox(height: 16),
              Text('解题步骤',
                  style: TextStyle(
                      fontSize: AppTokens.textSm,
                      fontWeight: FontWeight.w600,
                      color: t.textPrimary)),
              const SizedBox(height: 10),
              ...displayResult.steps.asMap().entries.map((e) => Container(
                    margin: const EdgeInsets.only(bottom: 10),
                    padding: const EdgeInsets.all(AppTokens.s3),
                    decoration: BoxDecoration(
                      color: t.formulaBg,
                      borderRadius: BorderRadius.circular(AppTokens.radiusLg),
                      border: Border.all(color: t.cardBorder),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Container(
                          width: 24,
                          height: 24,
                          decoration: BoxDecoration(
                            color: t.primarySoft,
                            borderRadius:
                                BorderRadius.circular(AppTokens.radiusLg),
                          ),
                          child: Center(
                              child: Text('${e.key + 1}',
                                  style: TextStyle(
                                      fontSize: AppTokens.textXs,
                                      fontWeight: FontWeight.w600,
                                      color: t.primary))),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                            child: MathContentView(e.value,
                                style: TextStyle(
                                    fontSize: AppTokens.textSm,
                                    color: t.textPrimary,
                                    height: 1.5))),
                      ],
                    ),
                  )),
            ],
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: hasRetryingCandidate
                    ? null
                    : () async {
                        final splitter = ref.read(questionSplitServiceProvider);
                        ref
                            .read(currentQuestionSplitSessionProvider.notifier)
                            .state = await buildQuestionSplitSession(
                          record,
                          splitter: splitter,
                        );
                        if (!context.mounted) return;
                        context.go('/capture/split-confirmation');
                      },
                child: Text(hasRetryingCandidate ? '有题正在重新解析' : '保存到错题本'),
              ),
            ),
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () => _discardResult(record),
                icon: const Icon(CupertinoIcons.delete, size: 18),
                label: const Text('放弃本次结果'),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _discardResult(QuestionRecord record) async {
    final confirmed = await showAppDialog<bool>(context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('放弃本次结果'),
        content: const Text('确定放弃这次解析结果吗？此操作不可恢复。'),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('放弃'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await ref.read(scanTaskLifecycleServiceProvider).discard(record);
      ref.read(currentQuestionProvider.notifier).state = null;
      ref.read(currentQuestionSplitSessionProvider.notifier).state = null;
      ref.invalidate(scanTaskCountProvider);
      if (mounted) context.go('/');
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('放弃失败：$error')),
      );
    }
  }

  QuestionRecord? _latestTaskResultFor(
    QuestionRecord? selected,
    List<QuestionAnalysisTaskSnapshot> tasks,
  ) {
    if (selected == null) return null;
    for (final task in tasks) {
      if (task.handle.parentQuestionId != selected.id) continue;
      final result = task.resultQuestion;
      if (result != null) return result;
    }
    return selected;
  }

  String _candidateFailureTitle(
    CandidateAnalysisSnapshot? candidate, {
    required int order,
  }) {
    return switch (candidate?.status) {
      CandidateAnalysisStatus.queued => '第 $order 题排队中',
      CandidateAnalysisStatus.running => '正在重新解析第 $order 题',
      _ => '第 $order 题解析失败',
    };
  }

  String _candidateFailureMessage(CandidateAnalysisSnapshot? candidate) {
    return switch (candidate?.status) {
      CandidateAnalysisStatus.queued => '已加入解析队列，完成后会补全到当前结果。',
      CandidateAnalysisStatus.running => '正在重新解析本题，完成后会补全到当前结果。',
      _ => candidate?.errorMessage?.isNotEmpty == true
          ? '已自动重试，仍未成功。该题暂不可保存，可单独重试。\n${candidate!.errorMessage}'
          : '已自动重试，仍未成功。该题暂不可保存，可单独重试。',
    };
  }

  IconData _candidateRetryIcon(CandidateAnalysisSnapshot candidate) {
    return switch (candidate.status) {
      CandidateAnalysisStatus.queued => CupertinoIcons.clock,
      CandidateAnalysisStatus.running => CupertinoIcons.arrow_clockwise,
      CandidateAnalysisStatus.success => CupertinoIcons.checkmark,
      CandidateAnalysisStatus.failed => CupertinoIcons.refresh,
    };
  }

  String _candidateRetryLabel(
    CandidateAnalysisSnapshot candidate,
    int order,
  ) {
    return switch (candidate.status) {
      CandidateAnalysisStatus.queued => '第 $order 题排队中',
      CandidateAnalysisStatus.running => '正在重新解析第 $order 题',
      CandidateAnalysisStatus.success => '第 $order 题已解析',
      CandidateAnalysisStatus.failed => '重试第 $order 题',
    };
  }

  Future<void> _retryCandidate(
    QuestionRecord source,
    CandidateAnalysisSnapshot candidate,
  ) async {
    final coordinator = ref.read(questionAnalysisCoordinatorProvider);
    final CandidateAnalysisRetryCoordinator? retryCoordinator =
        coordinator is CandidateAnalysisRetryCoordinator
            ? coordinator as CandidateAnalysisRetryCoordinator
            : null;
    if (retryCoordinator == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('当前解析任务不支持单题重试，请返回首页重新解析。')),
      );
      return;
    }
    try {
      final queued = await retryCoordinator.retryCandidate(source, candidate);
      if (!mounted) return;
      if (queued) {
        ref.read(currentQuestionProvider.notifier).state =
            _withQueuedCandidate(source, candidate.candidateId);
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            queued
                ? '已加入队列，将只重新解析第 ${candidate.order} 题'
                : '第 ${candidate.order} 题已在解析队列中',
          ),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('重新解析失败：$error')),
      );
    }
  }

  QuestionRecord _withQueuedCandidate(
    QuestionRecord source,
    String candidateId,
  ) {
    return source.copyWith(
      candidateAnalyses: source.candidateAnalyses.map((candidate) {
        if (candidate.candidateId != candidateId) return candidate;
        return CandidateAnalysisSnapshot(
          candidateId: candidate.candidateId,
          order: candidate.order,
          questionText: candidate.questionText,
          analysisResult: candidate.analysisResult,
          savedExercises: candidate.savedExercises,
          subject: candidate.subject,
          aiTags: candidate.aiTags,
          aiKnowledgePoints: candidate.aiKnowledgePoints,
          status: CandidateAnalysisStatus.queued,
        );
      }).toList(growable: false),
    );
  }

  bool _shouldOfferQuestionCorrection(
    AnalysisResult result, {
    required bool hasMultipleCandidates,
  }) {
    if (hasMultipleCandidates) return false;
    return result.visualAssumptionStatus ==
            VisualAssumptionStatus.needsReview ||
        result.consistencyStatus == AnalysisConsistencyStatus.needsReview;
  }

  String _candidateInsight({
    required int candidateOrder,
    required int total,
    required bool hasIndependentAnalysis,
  }) {
    return hasIndependentAnalysis
        ? '当前正在查看第 $candidateOrder / $total 题，已切换到独立解析结果。'
        : '当前正在查看第 $candidateOrder / $total 题，题干切换已生效。';
  }

  String _splitStrategyLabel(Object strategy) {
    switch (strategy.toString().split('.').last) {
      case 'numbered':
        return '编号拆题';
      case 'paragraph':
        return '分段拆题';
      default:
        return '单题回退';
    }
  }

  _ConsistencyNoticeData? _consistencyNotice(
    AnalysisResult result,
    AppTokens t,
  ) {
    switch (result.consistencyStatus) {
      case AnalysisConsistencyStatus.repaired:
        if (result.visualAssumptionStatus ==
            VisualAssumptionStatus.needsReview) {
          return _ConsistencyNoticeData(
            text: result.consistencyNote.isNotEmpty
                ? result.consistencyNote
                : 'AI 已复核答案；图中关键标注含义仍需核对',
            icon: CupertinoIcons.exclamationmark_triangle,
            color: t.warning,
            background: t.warningSoft,
          );
        }
        return _ConsistencyNoticeData(
          text: 'AI 已复核并修正答案',
          icon: CupertinoIcons.checkmark_shield,
          color: t.success,
          background: t.successSoft,
        );
      case AnalysisConsistencyStatus.needsReview:
        if (result.visualAssumptionStatus ==
            VisualAssumptionStatus.needsReview) {
          return _ConsistencyNoticeData(
            text: result.consistencyNote.isNotEmpty
                ? result.consistencyNote
                : '图中关键标注含义需核对，当前为可能解法',
            icon: CupertinoIcons.exclamationmark_triangle,
            color: t.warning,
            background: t.warningSoft,
          );
        }
        return _ConsistencyNoticeData(
          text: '答案与步骤可能不一致，请核对',
          icon: CupertinoIcons.exclamationmark_triangle,
          color: t.warning,
          background: t.warningSoft,
        );
      case AnalysisConsistencyStatus.unchecked:
      case AnalysisConsistencyStatus.consistent:
      case AnalysisConsistencyStatus.unverifiable:
        return null;
    }
  }

  void _showFullImage(BuildContext context, String imagePath) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => Scaffold(
          backgroundColor: Colors.black,
          appBar: AppBar(
            backgroundColor: Colors.transparent,
            foregroundColor: Colors.white,
            title: const Text('原图'),
          ),
          body: Center(
            child: InteractiveViewer(
              child: Image.file(File(imagePath)),
            ),
          ),
        ),
      ),
    );
  }
}

extension _IterableFirstOrNullExtension<E> on Iterable<E> {
  E? firstWhereOrNull(bool Function(E item) test) {
    for (final item in this) {
      if (test(item)) return item;
    }
    return null;
  }
}

class _CandidateSwitcherCard extends StatelessWidget {
  const _CandidateSwitcherCard({
    required this.splitResult,
    required this.candidateAnalyses,
    required this.safeCandidateIndex,
    required this.onSelected,
  });

  final QuestionSplitResult splitResult;
  final List<CandidateAnalysisSnapshot> candidateAnalyses;
  final int safeCandidateIndex;
  final void Function(int index) onSelected;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  color: t.primarySoft,
                  borderRadius: BorderRadius.circular(AppTokens.radiusMd),
                ),
                child: Icon(CupertinoIcons.square_list,
                    size: 16, color: t.primary),
              ),
              const SizedBox(width: 10),
              Text('题号切换',
                  style: TextStyle(
                      fontSize: AppTokens.textBase,
                      fontWeight: FontWeight.w600,
                      color: t.textPrimary)),
            ],
          ),
          const SizedBox(height: 14),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: splitResult.candidates.asMap().entries.map((entry) {
                final candidate = entry.value;
                final isActive = entry.key == safeCandidateIndex;
                final analysis = candidateAnalyses.firstWhereOrNull(
                  (item) => item.candidateId == candidate.id,
                );
                final statusColor = switch (analysis?.status) {
                  CandidateAnalysisStatus.failed => t.error,
                  CandidateAnalysisStatus.queued ||
                  CandidateAnalysisStatus.running =>
                    t.warning,
                  _ => t.textSecondary,
                };
                return Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChoiceChip(
                    label: Text('第 ${candidate.order} 题'),
                    selected: isActive,
                    onSelected: (_) => onSelected(entry.key),
                    labelStyle: TextStyle(
                      fontSize: AppTokens.textSm,
                      color: isActive ? t.onPrimary : statusColor,
                      fontWeight: FontWeight.w500,
                    ),
                    selectedColor: t.primary,
                    backgroundColor: t.card,
                    side: BorderSide(
                      color: isActive ? t.primary : t.cardBorder,
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionCard extends StatelessWidget {
  const _SectionCard({
    required this.icon,
    required this.tone,
    required this.title,
    this.child,
    this.contentWidget,
  });

  final IconData icon;

  /// 语义主色（`success` / `warning` / `error` / `primary` / `secondary`），
  /// 只用于图标与图标底，卡片底统一由 `AppCard` 提供。
  final Color tone;
  final String title;
  final Widget? child;
  final Widget? contentWidget;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Container(
                width: 24,
                height: 24,
                decoration: BoxDecoration(
                  color: tone.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(AppTokens.radiusSm),
                ),
                child: Icon(icon, size: 15, color: tone),
              ),
              const SizedBox(width: AppTokens.s2),
              Text(title,
                  style: TextStyle(
                      fontSize: AppTokens.textSm,
                      fontWeight: FontWeight.w600,
                      color: t.textPrimary)),
            ],
          ),
          const SizedBox(height: 10),
          if (child != null)
            child!
          else if (contentWidget != null)
            contentWidget!
          else
            const SizedBox.shrink(),
        ],
      ),
    );
  }
}

class _ConsistencyNoticeData {
  const _ConsistencyNoticeData({
    required this.text,
    required this.icon,
    required this.color,
    required this.background,
  });

  final String text;
  final IconData icon;
  final Color color;
  final Color background;
}

class _ConsistencyNotice extends StatelessWidget {
  const _ConsistencyNotice({required this.notice});

  final _ConsistencyNoticeData notice;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Container(
      padding: const EdgeInsets.symmetric(
          horizontal: 10, vertical: AppTokens.s2),
      decoration: BoxDecoration(
        color: notice.background,
        borderRadius: BorderRadius.circular(AppTokens.radiusMd),
        border: Border.all(color: notice.color.withValues(alpha: 0.32)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Icon(notice.icon, size: 15, color: notice.color),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              notice.text,
              style: TextStyle(
                fontSize: AppTokens.textXs,
                height: 1.35,
                color: t.textPrimary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 小标签：`color` 为文字色，`background` 为软底（默认公式底）。
class _TagChip extends StatelessWidget {
  const _TagChip({
    required this.label,
    required this.color,
    this.background,
  });

  final String label;
  final Color color;
  final Color? background;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;

    return Container(
      padding: const EdgeInsets.symmetric(
          horizontal: AppTokens.s2, vertical: AppTokens.s1),
      decoration: BoxDecoration(
        color: background ?? t.formulaBg,
        borderRadius: BorderRadius.circular(AppTokens.radiusSm),
        border: Border.all(color: t.cardBorder),
      ),
      child: Text(label,
          style: TextStyle(
              fontSize: AppTokens.textXs,
              color: color,
              fontWeight: FontWeight.w500)),
    );
  }
}

String _masteryLabel(MasteryLevel level) {
  switch (level) {
    case MasteryLevel.newQuestion:
      return '未复习';
    case MasteryLevel.reviewing:
      return '复习中';
    case MasteryLevel.mastered:
      return '已掌握';
  }
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
