import 'dart:async';
import 'dart:io';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:smart_wrong_notebook/src/app/design/tokens.dart';
import 'package:smart_wrong_notebook/src/app/providers.dart';
import 'package:smart_wrong_notebook/src/common/widgets/app_button.dart';
import 'package:smart_wrong_notebook/src/common/widgets/app_card.dart';
import 'package:smart_wrong_notebook/src/common/widgets/app_chip.dart';
import 'package:smart_wrong_notebook/src/features/glass/glass_overlays.dart';
import 'package:smart_wrong_notebook/src/features/glass/glass_providers.dart';
import 'package:smart_wrong_notebook/src/features/glass/glass_top_bar.dart';
import 'package:smart_wrong_notebook/src/data/remote/ai/ai_analysis_service.dart';
import 'package:smart_wrong_notebook/src/domain/models/ai_conversation_message.dart';
import 'package:smart_wrong_notebook/src/domain/models/ai_task_spec.dart';
import 'package:smart_wrong_notebook/src/domain/models/analysis_result.dart';
import 'package:smart_wrong_notebook/src/domain/models/analysis_job.dart';
import 'package:smart_wrong_notebook/src/domain/models/mastery_level.dart';
import 'package:smart_wrong_notebook/src/domain/models/question_record.dart';
import 'package:smart_wrong_notebook/src/domain/services/exercise_round_service.dart';
import 'package:smart_wrong_notebook/src/features/review/presentation/review_controller.dart';
import 'package:smart_wrong_notebook/src/shared/widgets/math_content_view.dart';

final _exerciseGenerationJobProvider =
    StreamProvider.autoDispose.family<AnalysisJob?, String>((ref, questionId) {
  final repository = ref.watch(analysisJobRepositoryProvider);
  if (repository == null) return Stream<AnalysisJob?>.value(null);
  return repository.watchByParentQuestionId(questionId).map((jobs) {
    final exerciseJobs = jobs
        .where((job) => job.taskSpec.type == AiTaskType.exerciseGeneration)
        .toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return exerciseJobs.isEmpty ? null : exerciseJobs.first;
  });
});

class QuestionDetailScreen extends ConsumerWidget {
  const QuestionDetailScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final current = ref.watch(currentQuestionProvider);

    if (current == null) {
      return Scaffold(
        appBar: glassTopBar(context, title: const Text('错题详情')),
        body: Center(
          child: Text(
            '未找到该错题',
            style: TextStyle(
              fontSize: AppTokens.textSm,
              color: context.tokens.textSecondary,
            ),
          ),
        ),
      );
    }

    final t = context.tokens;
    final result = current.analysisResult;
    final batchGroups = ref.watch(questionBatchGroupsProvider).valueOrNull;
    final batchGroup = batchGroups?[questionBatchRootId(current)];
    final glassEnabled = ref.watch(glassEnabledProvider);

    return Scaffold(
      extendBodyBehindAppBar: glassEnabled,
      appBar: glassTopBar(
        context,
        title: const Text('错题详情'),
        leading: IconButton(
          icon: const Icon(CupertinoIcons.chevron_left),
          // 有返回栈就 pop 回上一页（错题本），没有则回错题本
          onPressed: () =>
              context.canPop() ? context.pop() : context.go('/notebook'),
        ),
        actions: <Widget>[
          IconButton(
            tooltip: current.isFavorite ? '取消收藏' : '收藏',
            icon: Icon(
              current.isFavorite
                  ? CupertinoIcons.bookmark_fill
                  : CupertinoIcons.bookmark,
              color: current.isFavorite ? t.primary : null,
            ),
            onPressed: () => _toggleFavorite(ref, current),
          ),
          // 更多：玻璃开启时用玻璃操作面板，关闭时保留 Material 菜单
          if (glassEnabled)
            IconButton(
              icon: const Icon(CupertinoIcons.ellipsis_vertical),
              onPressed: () => _showGlassActions(context, ref, current),
            )
          else
            PopupMenuButton<String>(
              onSelected: (value) {
                if (value == 'delete') _confirmDelete(context, ref, current);
                if (value == 'edit') _editQuestion(context, ref, current);
                if (value == 'mastery') {
                  _markResult(context, ref, current,
                      current.masteryLevel != MasteryLevel.mastered);
                }
              },
              itemBuilder: (_) => <PopupMenuEntry<String>>[
                PopupMenuItem<String>(
                  value: 'edit',
                  child: Row(
                    children: <Widget>[
                      Icon(CupertinoIcons.pencil, color: t.primary, size: 20),
                      const SizedBox(width: AppTokens.s2),
                      const Text('编辑题目'),
                    ],
                  ),
                ),
                PopupMenuItem<String>(
                  value: 'mastery',
                  child: Row(
                    children: <Widget>[
                      Icon(
                        current.masteryLevel == MasteryLevel.mastered
                            ? CupertinoIcons.arrow_counterclockwise
                            : CupertinoIcons.check_mark_circled,
                        color: t.primary,
                        size: 20,
                      ),
                      const SizedBox(width: AppTokens.s2),
                      Text(current.masteryLevel == MasteryLevel.mastered
                          ? '标记为仍需复习'
                          : '标记为已掌握'),
                    ],
                  ),
                ),
                PopupMenuItem<String>(
                  value: 'delete',
                  child: Row(
                    children: <Widget>[
                      Icon(CupertinoIcons.trash, color: t.error, size: 20),
                      const SizedBox(width: AppTokens.s2),
                      Text('删除', style: TextStyle(color: t.error)),
                    ],
                  ),
                ),
              ],
            ),
        ],
      ),
      body: ListView(
        padding: EdgeInsets.fromLTRB(
          AppTokens.s6,
          AppTokens.s4 + (glassEnabled ? glassTopInset(context) : 0),
          AppTokens.s6,
          AppTokens.s8,
        ),
        children: <Widget>[
          // 顶部同类题横幅：没有同类题（同批）时不显示
          if (batchGroup != null) ...<Widget>[
            _SimilarQuestionBanner(
              current: current,
              group: batchGroup,
              onSelect: (question) {
                ref.read(currentQuestionProvider.notifier).state = question;
                // push 保留栈，返回时回到上一题而不是直接跳回列表
                context.push('/notebook/question/${question.id}');
              },
            ),
            const SizedBox(height: AppTokens.s3),
          ],
          // ① 题目
          _QuestionSectionCard(
            current: current,
            onShowImage: () => _showFullImage(context, current.imagePath),
          ),
          const SizedBox(height: AppTokens.s3),
          if (result == null)
            _NoAnalysisCard(
              onAdd: () {
                ref.read(currentQuestionProvider.notifier).state = current;
                context.go('/capture/correction');
              },
            )
          else ...<Widget>[
            // ② AI 解析（步骤条）
            _AnalysisSectionCard(
              result: result,
              notice: _consistencyNotice(context, result),
            ),
            const SizedBox(height: AppTokens.s3),
            // ③ 我的错因
            _MistakeReasonCard(
              current: current,
              result: result,
              onAddTag: () => _showAddTagDialog(context, ref, current),
            ),
            const SizedBox(height: AppTokens.s4),
            // 底部双按钮：编辑笔记 / 加入复习
            Row(
              children: <Widget>[
                Expanded(
                  child: AppButton(
                    label: '编辑笔记',
                    kind: AppButtonKind.outline,
                    icon: CupertinoIcons.pencil,
                    onPressed: () => _editQuestion(context, ref, current),
                  ),
                ),
                const SizedBox(width: AppTokens.s3),
                Expanded(
                  child: AppButton(
                    label: '加入复习',
                    icon: CupertinoIcons.arrow_counterclockwise,
                    onPressed: () => _markResult(context, ref, current, false),
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppTokens.s6),
            _AskAiCard(current: current),
            const SizedBox(height: AppTokens.s4),
            _PracticeSummaryCard(current: current),
          ],
        ],
      ),
    );
  }

  _ConsistencyNoticeData? _consistencyNotice(
      BuildContext context, AnalysisResult result) {
    final t = context.tokens;
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

  /// 收藏 / 取消收藏：沿用现有仓库更新路径，不改动业务流向。
  Future<void> _toggleFavorite(WidgetRef ref, QuestionRecord question) async {
    final updated = question.copyWith(isFavorite: !question.isFavorite);
    await ref.read(questionRepositoryProvider).update(updated);
    ref.read(currentQuestionProvider.notifier).state = updated;
    invalidateQuestionList(ref);
  }

  void _editQuestion(
      BuildContext context, WidgetRef ref, QuestionRecord question) {
    final controller = TextEditingController(text: question.correctedText);
    showAppDialog<void>(context,
      builder: (ctx) => AlertDialog(
        title: const Text('编辑题目'),
        content: TextFormField(
          controller: controller,
          maxLines: 4,
          decoration: const InputDecoration(border: OutlineInputBorder()),
        ),
        actions: <Widget>[
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
          FilledButton(
            onPressed: () async {
              final updated = question.copyWith(
                  normalizedQuestionText: controller.text.trim());
              await ref.read(questionRepositoryProvider).update(updated);
              ref.read(currentQuestionProvider.notifier).state = updated;
              invalidateQuestionList(ref);
              if (ctx.mounted) Navigator.pop(ctx);
            },
            child: const Text('保存'),
          ),
        ],
      ),
    );
  }

  /// 玻璃操作面板（详情页「更多」）：掌握状态 + 删除。
  Future<void> _showGlassActions(
      BuildContext context, WidgetRef ref, QuestionRecord question) async {
    final t = context.tokens;
    final mastered = question.masteryLevel == MasteryLevel.mastered;
    await showAppSheet<void>(
      context,
      bottomInset: 20,
      builder: (ctx) => Padding(
        padding: const EdgeInsets.fromLTRB(
            AppTokens.s6, AppTokens.s4, AppTokens.s6, AppTokens.s6),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: t.textTertiary.withValues(alpha: 0.35),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: AppTokens.s4),
            ListTile(
              leading: Icon(CupertinoIcons.pencil, color: t.primary),
              title: Text(
                '编辑题目',
                style: TextStyle(
                    color: t.textPrimary, fontWeight: FontWeight.w500),
              ),
              onTap: () {
                Navigator.pop(ctx);
                _editQuestion(context, ref, question);
              },
            ),
            ListTile(
              leading: Icon(
                mastered
                    ? CupertinoIcons.arrow_counterclockwise
                    : CupertinoIcons.check_mark_circled,
                color: t.primary,
              ),
              title: Text(
                mastered ? '标记为仍需复习' : '标记为已掌握',
                style: TextStyle(
                    color: t.textPrimary, fontWeight: FontWeight.w500),
              ),
              onTap: () {
                Navigator.pop(ctx);
                _markResult(context, ref, question, !mastered);
              },
            ),
            ListTile(
              leading: Icon(CupertinoIcons.trash, color: t.error),
              title: Text(
                '删除',
                style: TextStyle(color: t.error, fontWeight: FontWeight.w500),
              ),
              onTap: () {
                Navigator.pop(ctx);
                _confirmDelete(context, ref, question);
              },
            ),
          ],
        ),
      ),
    );
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
    if (!ok || !context.mounted) return;
    await ref.read(questionRepositoryProvider).delete(question.id);
    invalidateQuestionList(ref);
    if (context.mounted) context.go('/notebook');
  }

  void _showAddTagDialog(
      BuildContext context, WidgetRef ref, QuestionRecord question) {
    final t = context.tokens;
    final controller = TextEditingController();
    showAppDialog<void>(context,
      builder: (ctx) => AlertDialog(
        title: const Text('添加标签'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            TextField(
              controller: controller,
              autofocus: true,
              decoration: const InputDecoration(
                hintText: '输入标签名称',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: AppTokens.s3),
            Text('已有标签',
                style: TextStyle(
                    fontSize: AppTokens.textXs, color: t.textSecondary)),
            const SizedBox(height: AppTokens.s1),
            Wrap(
              spacing: AppTokens.s1,
              runSpacing: AppTokens.s1,
              children: <Widget>[
                ...question.aiTags.map((tag) => _dialogTagChip(tag, t.warning)),
                ...question.aiKnowledgePoints
                    .map((kp) => _dialogTagChip(kp, t.warning)),
                ...question.customTags
                    .map((tag) => _dialogTagChip(tag, t.primary)),
              ],
            ),
          ],
        ),
        actions: <Widget>[
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
          FilledButton(
            onPressed: () async {
              final tag = controller.text.trim();
              if (tag.isEmpty) return;

              // 检查是否已存在（去重）
              final allTags = [
                ...question.aiTags,
                ...question.aiKnowledgePoints,
                ...question.customTags
              ];
              if (allTags.contains(tag)) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('标签已存在')),
                );
                return;
              }

              final newTags = [...question.customTags, tag];
              final updated = question.copyWith(customTags: newTags);
              await ref.read(questionRepositoryProvider).update(updated);
              ref.read(currentQuestionProvider.notifier).state = updated;
              invalidateQuestionList(ref);
              if (ctx.mounted) Navigator.pop(ctx);
            },
            child: const Text('添加'),
          ),
        ],
      ),
    );
  }

  Widget _dialogTagChip(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(
          horizontal: AppTokens.s2, vertical: AppTokens.s1),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(AppTokens.radiusSm),
      ),
      child: Text(label,
          style: TextStyle(fontSize: AppTokens.textXs, color: color)),
    );
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

  void _markResult(BuildContext context, WidgetRef ref, QuestionRecord question,
      bool mastered) async {
    final controller = ReviewController(
      repository: ref.read(questionRepositoryProvider),
      logRepository: ref.read(reviewLogRepositoryProvider),
    );
    final updated = mastered
        ? await controller.markMastered(question.id)
        : await controller.markReviewing(question.id);
    invalidateQuestionList(ref);
    ref.read(currentQuestionProvider.notifier).state = updated;
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(mastered ? '已标记为已掌握' : '已标记为待复习')),
    );
  }
}

class _AskAiCard extends ConsumerStatefulWidget {
  const _AskAiCard({required this.current});

  final QuestionRecord current;

  @override
  ConsumerState<_AskAiCard> createState() => _AskAiCardState();
}

class _AskAiMessage {
  const _AskAiMessage({
    required this.role,
    required this.content,
    required this.createdAt,
  });

  final String role;
  final String content;
  final DateTime createdAt;
}

class _AskAiCardState extends ConsumerState<_AskAiCard> {
  final TextEditingController _controller = TextEditingController();
  final List<_AskAiMessage> _messages = <_AskAiMessage>[];
  bool _isExpanded = false;
  bool _isSending = false;
  bool _isLoadingHistory = true;
  int _historyLoadToken = 0;

  @override
  void initState() {
    super.initState();
    _loadHistory();
  }

  @override
  void didUpdateWidget(covariant _AskAiCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.current.id != widget.current.id) {
      _loadHistory();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _loadHistory() async {
    final token = ++_historyLoadToken;
    setState(() {
      _isLoadingHistory = true;
      _messages.clear();
    });

    try {
      final stored = await ref
          .read(aiConversationRepositoryProvider)
          .getByQuestionId(widget.current.id);
      if (!mounted || token != _historyLoadToken) return;
      setState(() {
        _messages
          ..clear()
          ..addAll(stored.map((message) => _AskAiMessage(
                role: message.role == AiConversationRole.assistant
                    ? 'assistant'
                    : 'user',
                content: message.content,
                createdAt: message.createdAt,
              )));
        _isLoadingHistory = false;
      });
    } catch (e) {
      if (!mounted || token != _historyLoadToken) return;
      setState(() => _isLoadingHistory = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('读取 AI 答疑历史失败：$e')),
      );
    }
  }

  Future<void> _sendQuestion() async {
    final question = _controller.text.trim();
    if (question.isEmpty || _isSending) return;
    final askedAt = DateTime.now();
    final userMessage = _AskAiMessage(
      role: 'user',
      content: question,
      createdAt: askedAt,
    );

    setState(() {
      _isSending = true;
      _messages.add(userMessage);
      _controller.clear();
    });

    try {
      final answer = await ref
          .read(aiLearningTaskCoordinatorProvider)
          .answerQuestionFollowUp(
            question: widget.current,
            userQuestion: question,
            history: _messages
                .take(_messages.length - 1)
                .map((message) => AiFollowUpMessage(
                      role: message.role == 'assistant' ? 'assistant' : 'user',
                      content: message.content,
                    ))
                .toList(),
          );
      if (!mounted) return;
      final answeredAt = DateTime.now();
      final assistantMessage = _AskAiMessage(
        role: 'assistant',
        content: answer,
        createdAt: answeredAt,
      );

      await ref.read(aiConversationRepositoryProvider).insertAll(
        <AiConversationMessage>[
          _toStoredMessage(userMessage, suffix: 'u'),
          _toStoredMessage(assistantMessage, suffix: 'a'),
        ],
      );
      if (!mounted) return;
      setState(() {
        _messages.add(assistantMessage);
        _isSending = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _isSending = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('AI 答疑失败：$e')),
      );
    }
  }

  AiConversationMessage _toStoredMessage(
    _AskAiMessage message, {
    required String suffix,
  }) {
    return AiConversationMessage(
      id: '${widget.current.id}-${message.createdAt.microsecondsSinceEpoch}-$suffix',
      questionId: widget.current.id,
      role: message.role == 'assistant'
          ? AiConversationRole.assistant
          : AiConversationRole.user,
      content: message.content,
      createdAt: message.createdAt,
    );
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final t = context.tokens;
    final accent = t.secondary;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: t.card,
        borderRadius: BorderRadius.circular(AppTokens.radiusLg),
        border: Border.all(color: t.cardBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: isDark ? 0.18 : 0.1),
                  borderRadius: BorderRadius.circular(9),
                ),
                child: Icon(CupertinoIcons.chat_bubble_2,
                    size: 16, color: accent),
              ),
              const SizedBox(width: 10),
              Text('AI 答疑',
                  style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: colorScheme.onSurface)),
              const Spacer(),
              Text(_messages.isEmpty ? '可追问' : '${_messages.length ~/ 2} 轮',
                  style: TextStyle(
                      fontSize: 12, color: colorScheme.onSurfaceVariant)),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            '围绕这道错题继续追问，后续会自动带入题干、答案、步骤、错因和知识点。',
            style: TextStyle(
                fontSize: 14,
                height: 1.45,
                color: colorScheme.onSurfaceVariant),
          ),
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: () {
                setState(() => _isExpanded = !_isExpanded);
              },
              icon: const Icon(CupertinoIcons.chat_bubble_text),
              label: Text(_isExpanded ? '收起追问' : '追问这道题'),
            ),
          ),
          if (_isExpanded) ...<Widget>[
            const SizedBox(height: 14),
            if (_isLoadingHistory) ...<Widget>[
              Row(
                children: <Widget>[
                  SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: colorScheme.primary,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    '正在读取历史追问...',
                    style: TextStyle(
                      fontSize: 13,
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
            ],
            if (_messages.isNotEmpty) ...<Widget>[
              ..._messages.map((message) => _AskAiMessageBubble(
                    message: message,
                  )),
              const SizedBox(height: 4),
            ],
            TextField(
              controller: _controller,
              minLines: 3,
              maxLines: 6,
              keyboardType: TextInputType.multiline,
              textInputAction: TextInputAction.newline,
              decoration: InputDecoration(
                hintText: '哪里没看懂？可以继续追问哦～',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                isDense: true,
              ),
            ),
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: _isSending ? null : _sendQuestion,
                icon: _isSending
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(CupertinoIcons.paperplane_fill),
                label: Text(_isSending ? '正在回答...' : '发送追问'),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _AskAiMessageBubble extends StatelessWidget {
  const _AskAiMessageBubble({required this.message});

  final _AskAiMessage message;

  @override
  Widget build(BuildContext context) {
    final isUser = message.role == 'user';
    final colorScheme = Theme.of(context).colorScheme;
    final t = context.tokens;
    final bg = isUser
        ? colorScheme.primary.withValues(alpha: t.isDark ? 0.18 : 0.1)
        : t.formulaBg;
    final borderColor = isUser
        ? colorScheme.primary.withValues(alpha: 0.22)
        : t.cardBorder;
    final align = isUser ? CrossAxisAlignment.end : CrossAxisAlignment.start;

    return Column(
      crossAxisAlignment: align,
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.only(left: 2, right: 2, bottom: 4),
          child: Text(
            isUser ? '你' : 'AI 解答',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color:
                  isUser ? colorScheme.primary : colorScheme.onSurfaceVariant,
            ),
          ),
        ),
        Container(
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          constraints: BoxConstraints(
            maxWidth: isUser ? 360 : double.infinity,
          ),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: borderColor),
          ),
          child: isUser
              ? Text(
                  message.content,
                  style: TextStyle(
                    fontSize: 14,
                    height: 1.45,
                    color: colorScheme.onSurface,
                  ),
                )
              : _AskAiAnswerView(content: message.content),
        ),
      ],
    );
  }
}

class _AskAiAnswerView extends StatelessWidget {
  const _AskAiAnswerView({required this.content});

  final String content;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final blocks = _splitAnswerBlocks(_normalizeAnswerContent(content));

    if (blocks.isEmpty) {
      return Text(
        '',
        style: TextStyle(
          fontSize: 14,
          height: 1.55,
          color: colorScheme.onSurface,
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: blocks.asMap().entries.map((entry) {
        final block = entry.value;
        final isFormula = _isDisplayFormulaBlock(block);
        final child = isFormula
            ? Container(
                width: double.infinity,
                margin: const EdgeInsets.symmetric(vertical: 4),
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                decoration: BoxDecoration(
                  color: colorScheme.surface,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: colorScheme.outlineVariant),
                ),
                child: MathContentView(
                  _displayFormulaForMathView(block),
                  style: TextStyle(
                    fontSize: 15,
                    height: 1.45,
                    color: colorScheme.onSurface,
                  ),
                ),
              )
            : _AskAiTextBlock(block: block);

        if (entry.key == blocks.length - 1) return child;
        return Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: child,
        );
      }).toList(),
    );
  }

  static List<String> _splitAnswerBlocks(String text) {
    final normalized = text.trim();
    if (normalized.isEmpty) return const <String>[];
    return normalized
        .split(RegExp(r'\n\s*\n'))
        .map((block) => block.trim())
        .where((block) => block.isNotEmpty)
        .toList();
  }

  static bool _isDisplayFormulaBlock(String block) {
    final trimmed = block.trim();
    if (RegExp(r'^\\\[[\s\S]*\\\]$').hasMatch(trimmed) ||
        RegExp(r'^\$\$[\s\S]*\$\$$').hasMatch(trimmed)) {
      return true;
    }
    if (RegExp(r'^\\\([\s\S]*\\\)$').hasMatch(trimmed) ||
        RegExp(r'^\$[^\$]+\$$').hasMatch(trimmed)) {
      return RegExp(r'[=+\-*/^]|\\frac|\\sqrt|\\times|\\begin')
          .hasMatch(trimmed);
    }
    if (trimmed.length > 80 || trimmed.contains(RegExp(r'[\u4e00-\u9fa5]'))) {
      return false;
    }
    return RegExp(r'[=<>]|\\frac|\\sqrt|\\begin|\^').hasMatch(trimmed) &&
        RegExp(r'^[A-Za-z0-9\\{}\[\]().,，:：;；+\-*/=<>_^|\s]+$')
            .hasMatch(trimmed);
  }

  static String _displayFormulaForMathView(String block) {
    final trimmed = block.trim();
    if (RegExp(r'^\\\[[\s\S]*\\\]$').hasMatch(trimmed) ||
        RegExp(r'^\$\$[\s\S]*\$\$$').hasMatch(trimmed)) {
      return trimmed;
    }
    if (RegExp(r'^\\\([\s\S]*\\\)$').hasMatch(trimmed)) {
      return '\\[${trimmed.substring(2, trimmed.length - 2).trim()}\\]';
    }
    if (RegExp(r'^\$[^\$]+\$$').hasMatch(trimmed)) {
      return '\\[${trimmed.substring(1, trimmed.length - 1).trim()}\\]';
    }
    return '\\[$trimmed\\]';
  }

  static String _normalizeAnswerContent(String value) {
    var text = value.replaceAll('\r\n', '\n').trim();
    text = text.replaceAllMapped(
      RegExp(r'\\\[\s*([\s\S]*?)\s*\\\]'),
      (match) => '\n\n\\[${match.group(1)!.trim()}\\]\n\n',
    );
    text = text.replaceAllMapped(
      RegExp(r'\$\$\s*([\s\S]*?)\s*\$\$'),
      (match) => '\n\n\$\$${match.group(1)!.trim()}\$\$\n\n',
    );
    text = text.replaceAll(RegExp(r'\n{3,}'), '\n\n');
    return text;
  }
}

class _AskAiTextBlock extends StatelessWidget {
  const _AskAiTextBlock({required this.block});

  final String block;

  @override
  Widget build(BuildContext context) {
    final normalized = block.trim();
    if (_isBulletBlock(normalized)) {
      return _AskAiBulletList(block: normalized);
    }

    final colorScheme = Theme.of(context).colorScheme;
    final heading = _headingText(normalized);
    if (heading != null) {
      return _AskAiInlineText(
        heading,
        style: TextStyle(
          fontSize: 14,
          height: 1.45,
          fontWeight: FontWeight.w700,
          color: colorScheme.onSurface,
        ),
      );
    }

    return _AskAiInlineText(
      normalized.replaceAll(RegExp(r'\s*\n\s*'), ' '),
      style: TextStyle(
        fontSize: 14,
        height: 1.62,
        color: colorScheme.onSurface,
      ),
    );
  }

  static bool _isBulletBlock(String value) {
    final lines = value
        .split('\n')
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty)
        .toList();
    if (lines.isEmpty) return false;
    return lines
        .every((line) => RegExp(r'^([-*•]\s+|\d+[.)、]\s+)').hasMatch(line));
  }

  static String? _headingText(String value) {
    final markdownHeading = RegExp(r'^\s{0,3}#{1,4}\s+(.+)$').firstMatch(value);
    if (markdownHeading != null) return markdownHeading.group(1)!.trim();
    if (!value.contains('\n') && value.length <= 18 && value.endsWith('：')) {
      return value;
    }
    return null;
  }
}

class _AskAiBulletList extends StatelessWidget {
  const _AskAiBulletList({required this.block});

  final String block;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final lines = block
        .split('\n')
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty)
        .toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: lines.map((line) {
        final text =
            line.replaceFirst(RegExp(r'^([-*•]\s+|\d+[.)、]\s+)'), '').trim();
        return Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Padding(
                padding: const EdgeInsets.only(top: 7),
                child: Container(
                  width: 5,
                  height: 5,
                  decoration: BoxDecoration(
                    color: colorScheme.primary.withValues(alpha: 0.75),
                    shape: BoxShape.circle,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _AskAiInlineText(
                  text,
                  style: TextStyle(
                    fontSize: 14,
                    height: 1.55,
                    color: colorScheme.onSurface,
                  ),
                ),
              ),
            ],
          ),
        );
      }).toList(),
    );
  }
}

class _AskAiInlineText extends StatelessWidget {
  const _AskAiInlineText(
    this.text, {
    required this.style,
  });

  final String text;
  final TextStyle style;

  @override
  Widget build(BuildContext context) {
    return Text.rich(
      TextSpan(children: _inlineSpans(text, style)),
      style: style,
    );
  }

  static List<InlineSpan> _inlineSpans(String value, TextStyle style) {
    final spans = <InlineSpan>[];
    final pattern = RegExp(r'\\\(([\s\S]*?)\\\)|(?<!\\)\$([^\$]+)\$');
    var cursor = 0;
    for (final match in pattern.allMatches(value)) {
      if (match.start > cursor) {
        spans.add(TextSpan(text: value.substring(cursor, match.start)));
      }
      final formula = match.group(1) ?? match.group(2) ?? '';
      spans.add(TextSpan(
        text: _inlineFormulaToReadable(formula),
        style: style.copyWith(fontWeight: FontWeight.w500),
      ));
      cursor = match.end;
    }
    if (cursor < value.length) {
      spans.add(TextSpan(text: value.substring(cursor)));
    }
    return spans;
  }

  static String _inlineFormulaToReadable(String value) {
    var text = value.trim();
    text = text
        .replaceAll(r'\left', '')
        .replaceAll(r'\right', '')
        .replaceAll(r'\,', ' ')
        .replaceAll(r'\;', ' ')
        .replaceAll(r'\quad', ' ')
        .replaceAll(r'\qquad', ' ')
        .replaceAllMapped(
          RegExp(r'\\mathrm\{([^}]*)\}'),
          (match) => match.group(1)!,
        )
        .replaceAllMapped(
          RegExp(r'\\text\{([^}]*)\}'),
          (match) => match.group(1)!,
        )
        .replaceAllMapped(
          RegExp(r'\\frac\{([^}]*)\}\{([^}]*)\}'),
          (match) => '${match.group(1)!}/${match.group(2)!}',
        )
        .replaceAllMapped(
          RegExp(r'\\sqrt\{([^}]*)\}'),
          (match) => '√${match.group(1)!}',
        )
        .replaceAll(r'\times', '×')
        .replaceAll(r'\cdot', '·')
        .replaceAll(r'\div', '÷')
        .replaceAll(r'\pm', '±')
        .replaceAll(r'\mp', '∓')
        .replaceAll(r'\leq', '≤')
        .replaceAll(r'\geq', '≥')
        .replaceAll(r'\neq', '≠')
        .replaceAll(r'\approx', '≈')
        .replaceAll(r'\angle', '∠')
        .replaceAll(r'\triangle', '△')
        .replaceAll(r'\circ', '°')
        .replaceAll(r'\pi', 'π')
        .replaceAll(r'\Delta', 'Δ')
        .replaceAll(r'\alpha', 'α')
        .replaceAll(r'\beta', 'β')
        .replaceAll(r'\gamma', 'γ')
        .replaceAll(r'\theta', 'θ');
    text = text.replaceAllMapped(
      RegExp(r'\^\{?([0-9+\-]+)\}?'),
      (match) => _superscript(match.group(1)!),
    );
    text = text.replaceAllMapped(
      RegExp(r'_\{?([0-9+\-]+)\}?'),
      (match) => _subscript(match.group(1)!),
    );
    return text
        .replaceAll('{', '')
        .replaceAll('}', '')
        .replaceAll(r'\ ', ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  static String _superscript(String value) {
    const map = <String, String>{
      '0': '⁰',
      '1': '¹',
      '2': '²',
      '3': '³',
      '4': '⁴',
      '5': '⁵',
      '6': '⁶',
      '7': '⁷',
      '8': '⁸',
      '9': '⁹',
      '+': '⁺',
      '-': '⁻',
    };
    return value.split('').map((char) => map[char] ?? char).join();
  }

  static String _subscript(String value) {
    const map = <String, String>{
      '0': '₀',
      '1': '₁',
      '2': '₂',
      '3': '₃',
      '4': '₄',
      '5': '₅',
      '6': '₆',
      '7': '₇',
      '8': '₈',
      '9': '₉',
      '+': '₊',
      '-': '₋',
    };
    return value.split('').map((char) => map[char] ?? char).join();
  }
}


class _PracticeSummaryCard extends ConsumerStatefulWidget {
  const _PracticeSummaryCard({required this.current});

  final QuestionRecord current;

  @override
  ConsumerState<_PracticeSummaryCard> createState() =>
      _PracticeSummaryCardState();
}

class _PracticeSummaryCardState extends ConsumerState<_PracticeSummaryCard> {
  bool _isGenerating = false;
  String? _statusMessage;
  bool _statusIsError = false;
  String? _lastSyncedCompletedExerciseJobId;

  Future<void> _generateAndStartPractice({bool forceNew = false}) async {
    if (_isGenerating) return;

    final current = widget.current;
    if (current.savedExercises.isNotEmpty && !forceNew) {
      _startPractice(current);
      return;
    }

    setState(() {
      _isGenerating = true;
      _statusMessage = '正在生成练习题，请稍等...';
      _statusIsError = false;
    });
    try {
      final exercises = await ref
          .read(aiLearningTaskCoordinatorProvider)
          .generateExercisesForQuestion(current, forceNew: forceNew);
      if (!mounted) return;

      if (exercises.isEmpty ||
          (forceNew && exercises.length <= current.savedExercises.length)) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('暂未生成可用练习，请稍后重试')),
        );
        setState(() {
          _isGenerating = false;
          _statusMessage = '这次没有生成可用练习，可以稍后重试。';
          _statusIsError = true;
        });
        return;
      }

      final latest =
          await ref.read(questionRepositoryProvider).getById(current.id);
      final updated = (latest ?? current).copyWith(savedExercises: exercises);
      await ref.read(questionRepositoryProvider).update(updated);
      if (!mounted) return;

      ref.read(currentQuestionProvider.notifier).state = updated;
      invalidateQuestionList(ref);
      final latestGeneratedRound = latestExerciseRound(exercises);
      final generatedCount = latestGeneratedRound.isEmpty
          ? exercises.length
          : latestGeneratedRound.length;
      setState(() {
        _isGenerating = false;
        _statusMessage = '已生成 $generatedCount 道练习题，可以开始练习。';
        _statusIsError = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('举一反三已生成，可以开始练习')),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isGenerating = false;
        _statusMessage = '生成失败，请检查网络或稍后重试。';
        _statusIsError = true;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('举一反三生成失败：$e')),
      );
    }
  }

  void _startPractice(QuestionRecord current) {
    ref.read(currentPracticeContextProvider.notifier).state = PracticeContext(
      source: PracticeContextSource.notebook,
      returnRoute: '/notebook/question/${current.id}',
    );
    ref.read(currentQuestionProvider.notifier).state = current;
    context.go('/exercise/practice');
  }

  Future<void> _syncCompletedExerciseJob(AnalysisJob job) async {
    if (_lastSyncedCompletedExerciseJobId == job.id) return;
    _lastSyncedCompletedExerciseJobId = job.id;

    final latest =
        await ref.read(questionRepositoryProvider).getById(widget.current.id);
    if (!mounted || latest == null || latest.savedExercises.isEmpty) return;

    ref.read(currentQuestionProvider.notifier).state = latest;
    invalidateQuestionList(ref);
    setState(() {
      _isGenerating = false;
      _statusMessage = '已生成 ${latest.savedExercises.length} 道练习题，可以开始练习。';
      _statusIsError = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final current = widget.current;
    final colorScheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final hasExercises = current.savedExercises.isNotEmpty;
    final latestRound = latestExerciseRound(current.savedExercises);
    final latestRoundCompleted =
        isLatestExerciseRoundCompleted(current.savedExercises);
    final generationJob =
        ref.watch(_exerciseGenerationJobProvider(current.id)).valueOrNull;
    ref.listen<AsyncValue<AnalysisJob?>>(
      _exerciseGenerationJobProvider(current.id),
      (_, next) {
        final job = next.valueOrNull;
        if (job?.status == AnalysisJobStatus.completed) {
          unawaited(_syncCompletedExerciseJob(job!));
        }
      },
    );
    final isQueued = generationJob?.status == AnalysisJobStatus.queued;
    final isRunning = generationJob?.status == AnalysisJobStatus.running;
    final hasActiveGenerationJob = isQueued || isRunning;
    final isSubmitting = _isGenerating && generationJob == null;
    final isGenerating = isSubmitting || hasActiveGenerationJob;
    final jobStatusMessage = _exerciseGenerationStatusMessage(
      generationJob,
      hasExercises: hasExercises,
    );
    final effectiveStatusMessage = hasActiveGenerationJob
        ? jobStatusMessage
        : (_statusMessage ?? jobStatusMessage);
    final effectiveStatusIsError = (!hasActiveGenerationJob &&
            _statusIsError) ||
        generationJob?.status == AnalysisJobStatus.failed ||
        (generationJob?.status == AnalysisJobStatus.completed &&
            !hasExercises &&
            (generationJob?.resultJson?.contains('"exercises":[]') ?? false));
    final inlineStatusIsLoading = isSubmitting || isRunning;
    final answeredCount = latestRound.where((e) => e.isCorrect != null).length;
    final totalCount = latestRound.isNotEmpty
        ? latestRound.length
        : current.savedExercises.length;
    final accent = context.tokens.primary;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: context.tokens.card,
        borderRadius: BorderRadius.circular(AppTokens.radiusLg),
        border: Border.all(color: context.tokens.cardBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: isDark ? 0.16 : 0.1),
                  borderRadius: BorderRadius.circular(9),
                ),
                child: Icon(CupertinoIcons.arrow_2_circlepath,
                    size: 16, color: accent),
              ),
              const SizedBox(width: 10),
              Text('举一反三',
                  style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: colorScheme.onSurface)),
              const Spacer(),
              Text(
                hasExercises
                    ? '$answeredCount/$totalCount 已答'
                    : isQueued
                        ? '排队中'
                        : isGenerating
                            ? '生成中'
                            : generationJob?.status == AnalysisJobStatus.failed
                                ? '生成失败'
                                : '未生成',
                style: TextStyle(
                    fontSize: 12, color: colorScheme.onSurfaceVariant),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            hasExercises
                ? latestRoundCompleted
                    ? '本轮练习已完成，可以再生成一组新的举一反三。'
                    : '已基于这道错题生成 $totalCount 道练习，继续完成剩余题目。'
                : '根据这道错题的题干、知识点和解析生成练习；宁可少生成，也不展示低质量练习。',
            style: TextStyle(
                fontSize: 14,
                height: 1.45,
                color: colorScheme.onSurfaceVariant),
          ),
          if (hasExercises) ...<Widget>[
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: <Widget>[
                _PracticeStatusChip(
                  icon: CupertinoIcons.square_list,
                  label: '$totalCount 题',
                  color: accent,
                ),
                _PracticeStatusChip(
                  icon: CupertinoIcons.check_mark_circled,
                  label: '$answeredCount 已答',
                  color: answeredCount == totalCount
                      ? context.tokens.success
                      : colorScheme.onSurfaceVariant,
                ),
              ],
            ),
          ],
          if (effectiveStatusMessage != null) ...<Widget>[
            const SizedBox(height: 12),
            _PracticeInlineStatus(
              message: effectiveStatusMessage,
              isError: effectiveStatusIsError,
              isLoading: inlineStatusIsLoading,
            ),
          ],
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: isGenerating
                  ? null
                  : hasExercises
                      ? latestRoundCompleted
                          ? () => _generateAndStartPractice(forceNew: true)
                          : () => _startPractice(current)
                      : _generateAndStartPractice,
              icon: isQueued
                  ? const Icon(CupertinoIcons.clock)
                  : isGenerating
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Icon(hasExercises
                          ? CupertinoIcons.play_fill
                          : CupertinoIcons.add_circled),
              label: Text(isGenerating
                  ? isQueued
                      ? '排队中...'
                      : isSubmitting
                          ? '提交中...'
                          : '正在生成...'
                  : hasExercises
                      ? latestRoundCompleted
                          ? '再生成一组'
                          : '继续练习'
                      : '生成举一反三'),
            ),
          ),
          if (!hasExercises && !isGenerating) ...<Widget>[
            const SizedBox(height: 8),
            Center(
              child: Text(
                '生成练习不会影响原题解析。',
                style: TextStyle(
                  fontSize: 12,
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  String? _exerciseGenerationStatusMessage(
    AnalysisJob? job, {
    required bool hasExercises,
  }) {
    if (job == null) return null;
    return switch (job.status) {
      AnalysisJobStatus.queued => '已加入 AI 队列，会在前面的任务完成后继续；你可以先返回首页继续使用。',
      AnalysisJobStatus.running => '正在生成练习题，请稍等...',
      AnalysisJobStatus.completed => hasExercises ? null : '这次没有生成可用练习，可以稍后重试。',
      AnalysisJobStatus.failed => '生成失败，请检查网络或稍后重试。',
      AnalysisJobStatus.cancelled => '生成任务已取消，可以重新生成。',
    };
  }
}

class _PracticeStatusChip extends StatelessWidget {
  const _PracticeStatusChip({
    required this.icon,
    required this.label,
    required this.color,
  });

  final IconData icon;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: isDark ? 0.18 : 0.1),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.18)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(icon, size: 13, color: color),
          const SizedBox(width: 5),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

class _PracticeInlineStatus extends StatelessWidget {
  const _PracticeInlineStatus({
    required this.message,
    required this.isError,
    required this.isLoading,
  });

  final String message;
  final bool isError;
  final bool isLoading;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final color = isError ? colorScheme.error : context.tokens.primary;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.18)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          if (isLoading)
            SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: color,
              ),
            )
          else
            Icon(
              isError
                  ? CupertinoIcons.exclamationmark_triangle
                  : CupertinoIcons.check_mark_circled,
              size: 15,
              color: color,
            ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: TextStyle(
                fontSize: 12,
                height: 1.35,
                color: isError ? colorScheme.error : colorScheme.onSurface,
              ),
            ),
          ),
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
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color:
            isDark ? notice.color.withValues(alpha: 0.14) : notice.background,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: notice.color.withValues(alpha: 0.28)),
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
                fontSize: 12,
                height: 1.35,
                color: isDark
                    ? Theme.of(context).colorScheme.onSurface
                    : notice.color,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}


// ───────────────────────────── 详情页分区组件 ─────────────────────────────

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

String _recordedDate(DateTime date) => '${date.month}月${date.day}日';

/// 把解析拆成步骤：优先用 AI 给出的步骤，否则把推导文本按行 / 句号切分（最多 6 步）。
List<String> _analysisSteps(AnalysisResult result) {
  final steps = result.steps
      .map((step) => step.trim())
      .where((step) => step.isNotEmpty)
      .toList();
  if (steps.isNotEmpty) return steps.take(6).toList();
  final derivation = result.finalAnswerDerivation.trim();
  if (derivation.isEmpty) return const <String>[];
  var parts = derivation
      .split('\n')
      .map((part) => part.trim())
      .where((part) => part.isNotEmpty)
      .toList();
  if (parts.length <= 1) {
    parts = derivation
        .split(RegExp(r'[。；;]'))
        .map((part) => part.trim())
        .where((part) => part.isNotEmpty)
        .toList();
  }
  return parts.take(6).toList();
}

/// 顶部同类题横幅（demo `.similar-banner`）：secondarySoft 底 + 1px 描边，
/// 同时保留同批题目的快速跳转。
class _SimilarQuestionBanner extends StatelessWidget {
  const _SimilarQuestionBanner({
    required this.current,
    required this.group,
    required this.onSelect,
  });

  final QuestionRecord current;
  final QuestionBatchGroup group;
  final void Function(QuestionRecord question) onSelect;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final others = group.questions.length - 1;
    final knowledgePoint = current.aiKnowledgePoints.isNotEmpty
        ? current.aiKnowledgePoints.first
        : null;
    return Container(
      padding: const EdgeInsets.all(AppTokens.s3),
      decoration: BoxDecoration(
        color: t.secondarySoft,
        borderRadius: BorderRadius.circular(AppTokens.radiusMd),
        border: Border.all(color: t.secondary.withValues(alpha: 0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Icon(CupertinoIcons.sparkles, size: 20, color: t.secondary),
              const SizedBox(width: AppTokens.s3),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      '找到 $others 道同类错题',
                      style: TextStyle(
                        fontSize: AppTokens.textSm,
                        fontWeight: FontWeight.w600,
                        color: t.secondary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      knowledgePoint == null
                          ? '来自同一次拍照收录'
                          : '考查点：$knowledgePoint',
                      style: TextStyle(
                        fontSize: AppTokens.textXs,
                        height: 1.4,
                        color: t.isDark ? t.textSecondary : t.secondary,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: AppTokens.s2),
          Wrap(
            spacing: AppTokens.s2,
            runSpacing: AppTokens.s1,
            children: group.questions.map((question) {
              final selected = question.id == current.id;
              return GestureDetector(
                onTap: selected ? null : () => onSelect(question),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: AppTokens.s3, vertical: AppTokens.s1),
                  decoration: BoxDecoration(
                    color: selected ? t.primary : t.card,
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(
                        color: selected ? t.primary : t.cardBorder),
                  ),
                  child: Text(
                    _siblingLabel(question),
                    style: TextStyle(
                      fontSize: AppTokens.textXs,
                      fontWeight: selected ? FontWeight.w500 : null,
                      color: selected ? t.onPrimary : t.textSecondary,
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  String _siblingLabel(QuestionRecord question) {
    final order = question.splitOrder;
    return order == null ? '同批题' : '第 $order 题';
  }
}

/// ① 题目卡：科目 / 掌握状态 / 收录日期 + 原图 + 题干 + 公式块 + AI 标签。
class _QuestionSectionCard extends StatelessWidget {
  const _QuestionSectionCard({
    required this.current,
    required this.onShowImage,
  });

  final QuestionRecord current;
  final VoidCallback onShowImage;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final result = current.analysisResult;
    final formula = _displayFormula(current.correctedText);
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              AppTag(
                current.subject.label,
                color: t.subjectColor(current.subject.label),
                background: t.subjectSoft(current.subject.label),
                fontWeight: FontWeight.w600,
              ),
              if (result?.subject != null) ...<Widget>[
                const SizedBox(width: AppTokens.s2),
                AppTag(
                  'AI识别',
                  color: t.success,
                  background: t.successSoft,
                  fontWeight: FontWeight.w500,
                ),
              ],
              const SizedBox(width: AppTokens.s2),
              AppTag(
                _masteryLabel(current.masteryLevel),
                color: _masteryColor(context, current.masteryLevel),
                background: _masterySoft(context, current.masteryLevel),
                fontWeight: FontWeight.w500,
              ),
              const Spacer(),
              Text(
                '收录于 ${_recordedDate(current.createdAt)}',
                style: TextStyle(
                    fontSize: AppTokens.textXs, color: t.textTertiary),
              ),
            ],
          ),
          const SizedBox(height: AppTokens.s3),
          const AppSectionLabel('题目'),
          if (current.imagePath.isNotEmpty) ...<Widget>[
            GestureDetector(
              onTap: onShowImage,
              child: Container(
                height: 120,
                decoration: BoxDecoration(
                  color: t.formulaBg,
                  borderRadius: BorderRadius.circular(AppTokens.radiusMd),
                ),
                child: Stack(
                  children: <Widget>[
                    ClipRRect(
                      borderRadius: BorderRadius.circular(AppTokens.radiusMd),
                      child: Image.file(
                        File(current.imagePath),
                        width: double.infinity,
                        height: 120,
                        fit: BoxFit.contain,
                        errorBuilder: (_, __, ___) => Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: <Widget>[
                              Icon(CupertinoIcons.photo,
                                  size: 30, color: t.textTertiary),
                              const SizedBox(height: AppTokens.s1),
                              Text('图片加载失败',
                                  style: TextStyle(
                                      fontSize: AppTokens.textXs,
                                      color: t.textTertiary)),
                            ],
                          ),
                        ),
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
                          borderRadius: BorderRadius.circular(10),
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
            const SizedBox(height: AppTokens.s3),
          ],
          MathContentView(
            current.correctedText,
            contentFormat: current.contentFormat,
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
          if (current.aiTags.isNotEmpty) ...<Widget>[
            const SizedBox(height: AppTokens.s3),
            Wrap(
              spacing: AppTokens.s2,
              runSpacing: AppTokens.s1,
              children: current.aiTags
                  .take(5)
                  .map((tag) => AppTag(tag,
                      color: t.warning,
                      background: t.warningSoft,
                      fontWeight: FontWeight.w500))
                  .toList(),
            ),
          ],
        ],
      ),
    );
  }
}

/// ② AI 解析卡：正确答案（含一致性提示）+ 步骤条 + 学习建议。
class _AnalysisSectionCard extends StatelessWidget {
  const _AnalysisSectionCard({required this.result, required this.notice});

  final AnalysisResult result;
  final _ConsistencyNoticeData? notice;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final needsReview =
        result.visualAssumptionStatus == VisualAssumptionStatus.needsReview;
    final answerColor = needsReview ? t.warning : t.success;
    final answerSoft = needsReview ? t.warningSoft : t.successSoft;
    final steps = _analysisSteps(result);
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const AppSectionLabel('AI 解析'),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(AppTokens.s3),
            decoration: BoxDecoration(
              color: answerSoft,
              borderRadius: BorderRadius.circular(AppTokens.radiusMd),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    Icon(
                      needsReview
                          ? CupertinoIcons.exclamationmark_triangle
                          : CupertinoIcons.checkmark_circle,
                      size: 14,
                      color: answerColor,
                    ),
                    const SizedBox(width: AppTokens.s1),
                    Text(
                      needsReview ? '可能解法' : '正确答案',
                      style: TextStyle(
                        fontSize: AppTokens.textXs,
                        fontWeight: FontWeight.w600,
                        color: answerColor,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: AppTokens.s2),
                MathContentView(
                  result.finalAnswer,
                  style: TextStyle(
                    fontSize: AppTokens.textSm,
                    height: 1.5,
                    fontWeight: FontWeight.w600,
                    color: answerColor,
                  ),
                ),
                if (notice != null) ...<Widget>[
                  const SizedBox(height: AppTokens.s2),
                  _ConsistencyNotice(notice: notice!),
                ],
              ],
            ),
          ),
          if (steps.isNotEmpty) ...<Widget>[
            const SizedBox(height: AppTokens.s3),
            ...steps.asMap().entries.map(
                  (entry) => _AnalysisStepTile(
                    index: entry.key + 1,
                    text: entry.value,
                  ),
                ),
          ],
          if (result.studyAdvice.trim().isNotEmpty) ...<Widget>[
            const SizedBox(height: AppTokens.s2),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(AppTokens.s3),
              decoration: BoxDecoration(
                color: t.formulaBg,
                borderRadius: BorderRadius.circular(AppTokens.radiusMd),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Row(
                    children: <Widget>[
                      Icon(CupertinoIcons.lightbulb,
                          size: 14, color: t.warning),
                      const SizedBox(width: AppTokens.s1),
                      Text(
                        '学习建议',
                        style: TextStyle(
                          fontSize: AppTokens.textXs,
                          fontWeight: FontWeight.w600,
                          color: t.warning,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: AppTokens.s1),
                  MathContentView(
                    result.studyAdvice,
                    style: TextStyle(
                      fontSize: AppTokens.textSm,
                      height: 1.6,
                      color: t.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// 解析步骤（demo `.analysis-step`）：20×20 圆形序号 + 正文。
class _AnalysisStepTile extends StatelessWidget {
  const _AnalysisStepTile({required this.index, required this.text});

  final int index;
  final String text;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Padding(
      padding: const EdgeInsets.only(bottom: AppTokens.s2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Container(
            width: 20,
            height: 20,
            margin: const EdgeInsets.only(top: 2),
            alignment: Alignment.center,
            decoration:
                BoxDecoration(color: t.primarySoft, shape: BoxShape.circle),
            child: Text(
              '$index',
              style: TextStyle(
                fontSize: AppTokens.textXs,
                height: 1,
                fontWeight: FontWeight.w600,
                color: t.primary,
              ),
            ),
          ),
          const SizedBox(width: AppTokens.s3),
          Expanded(
            child: MathContentView(
              text,
              style: TextStyle(
                fontSize: AppTokens.textSm,
                height: 1.6,
                color: t.textPrimary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 暂无解析时的占位卡（保留原有「去添加」入口）。
class _NoAnalysisCard extends StatelessWidget {
  const _NoAnalysisCard({required this.onAdd});

  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return AppCard(
      padding: const EdgeInsets.all(AppTokens.s6),
      child: Column(
        children: <Widget>[
          Icon(CupertinoIcons.sparkles, size: 40, color: t.textTertiary),
          const SizedBox(height: AppTokens.s3),
          Text(
            '暂无 AI 解析结果',
            style:
                TextStyle(fontSize: AppTokens.textBase, color: t.textPrimary),
          ),
          const SizedBox(height: AppTokens.s2),
          Text(
            '可以补拍或补充题目内容后重新解析',
            style: TextStyle(fontSize: AppTokens.textXs, color: t.textTertiary),
          ),
          const SizedBox(height: AppTokens.s4),
          AppButton(
            label: '去添加',
            icon: CupertinoIcons.camera,
            expand: false,
            onPressed: onAdd,
          ),
        ],
      ),
    );
  }
}

/// ③ 我的错因卡：error 色正文 + 知识点 / 自定义标签 + 添加标签入口。
class _MistakeReasonCard extends StatelessWidget {
  const _MistakeReasonCard({
    required this.current,
    required this.result,
    required this.onAddTag,
  });

  final QuestionRecord current;
  final AnalysisResult result;
  final VoidCallback onAddTag;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final reason = result.mistakeReason.trim();
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const AppSectionLabel('我的错因'),
          if (reason.isEmpty)
            Text(
              '暂未记录错因，可以补充标签方便后面复习。',
              style:
                  TextStyle(fontSize: AppTokens.textSm, color: t.textTertiary),
            )
          else
            MathContentView(
              reason,
              style: TextStyle(
                fontSize: AppTokens.textSm,
                height: 1.6,
                color: t.error,
              ),
            ),
          if (result.knowledgePoints.isNotEmpty) ...<Widget>[
            const SizedBox(height: AppTokens.s3),
            Wrap(
              spacing: AppTokens.s2,
              runSpacing: AppTokens.s1,
              children: result.knowledgePoints
                  .map((point) => AppTag(point,
                      color: t.primary,
                      background: t.primarySoft,
                      fontWeight: FontWeight.w500))
                  .toList(),
            ),
          ],
          if (current.customTags.isNotEmpty) ...<Widget>[
            const SizedBox(height: AppTokens.s2),
            Wrap(
              spacing: AppTokens.s2,
              runSpacing: AppTokens.s1,
              children:
                  current.customTags.map((tag) => AppTag(tag)).toList(),
            ),
          ],
          const SizedBox(height: AppTokens.s3),
          GestureDetector(
            onTap: onAddTag,
            child: Container(
              padding: const EdgeInsets.symmetric(
                  horizontal: AppTokens.s3, vertical: AppTokens.s1),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(AppTokens.radiusMd),
                border: Border.all(color: t.cardBorder),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Icon(CupertinoIcons.plus, size: 14, color: t.textSecondary),
                  const SizedBox(width: AppTokens.s1),
                  Text(
                    '添加标签',
                    style: TextStyle(
                        fontSize: AppTokens.textXs, color: t.textSecondary),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
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
