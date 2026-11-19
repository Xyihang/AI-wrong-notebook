import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:smart_wrong_notebook/src/app/providers.dart';
import 'package:smart_wrong_notebook/src/features/glass/glass_providers.dart';
import 'package:smart_wrong_notebook/src/features/glass/glass_top_bar.dart';
import 'package:smart_wrong_notebook/src/data/remote/ai/ai_analysis_service.dart';
import 'package:smart_wrong_notebook/src/data/remote/backend/backend_client.dart';
import 'package:smart_wrong_notebook/src/domain/models/content_status.dart';
import 'package:smart_wrong_notebook/src/domain/models/mastery_level.dart';
import 'package:smart_wrong_notebook/src/domain/models/paper.dart';
import 'package:smart_wrong_notebook/src/domain/models/subject.dart';

/// AI 变式组卷 - 选择范围并生成。
class PaperSetupScreen extends ConsumerStatefulWidget {
  const PaperSetupScreen({super.key});

  @override
  ConsumerState<PaperSetupScreen> createState() => _PaperSetupScreenState();
}

class _PaperSetupScreenState extends ConsumerState<PaperSetupScreen> {
  Subject? _subject;
  String? _difficulty; // 简单/中等/困难
  int _count = 10;
  final TextEditingController _kpController = TextEditingController();
  bool _loading = false;
  String? _error;

  @override
  void dispose() {
    _kpController.dispose();
    super.dispose();
  }

  List<String> get _kps => _kpController.text
      .split(RegExp(r'[,，;；]'))
      .map((e) => e.trim())
      .where((e) => e.isNotEmpty)
      .toList();

  Future<void> _generate() async {
    final subject = _subject;
    if (subject == null) {
      setState(() => _error = '请先选择科目');
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      // 游客（仅直连）模式：组卷完全在本地完成，不请求后端。
      if (AiAnalysisService.directOnly) {
        final paper = await _generatePaperLocally(subject);
        ref.read(currentPaperProvider.notifier).state = paper;
        if (!mounted) return;
        context.push('/paper/preview');
        return;
      }
      final resp = await BackendClient().generatePaper(
        subject: subject.name,
        knowledgePoints: _kps,
        difficulty: _difficulty,
        count: _count,
      );
      final paperMap = resp['paper'];
      if (paperMap is! Map) {
        throw const BackendClientException('组卷返回数据异常');
      }
      final paper = PaperResult.fromJson(Map<String, dynamic>.from(paperMap));
      ref.read(currentPaperProvider.notifier).state = paper;
      if (!mounted) return;
      context.push('/paper/preview');
    } on BackendClientException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (e) {
      if (mounted) setState(() => _error = '生成失败：$e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  /// 本地组卷：优先本地错题 + 用自己的模型直连生成变式补齐（不经过后端）。
  Future<PaperResult> _generatePaperLocally(Subject subject) async {
    final repo = ref.read(questionRepositoryProvider);
    final all = await repo.listAll();
    final kps = _kps;
    final candidates = all.where((q) {
      if (q.contentStatus != ContentStatus.ready) return false;
      if (q.subject != subject) return false;
      if (kps.isNotEmpty &&
          !q.aiKnowledgePoints.any((k) => kps.any((w) => k.contains(w)))) {
        return false;
      }
      return true;
    }).toList();

    int rank(MasteryLevel m) => switch (m) {
          MasteryLevel.newQuestion => 0,
          MasteryLevel.reviewing => 1,
          MasteryLevel.mastered => 2,
        };
    candidates.sort((a, b) => rank(a.masteryLevel).compareTo(rank(b.masteryLevel)));

    String textOf(dynamic q) => q.normalizedQuestionText.trim().isNotEmpty
        ? q.normalizedQuestionText.trim()
        : q.extractedQuestionText.trim();

    final questions = <PaperQuestion>[];
    for (final q in candidates) {
      if (questions.length >= _count) break;
      final text = textOf(q);
      if (text.isEmpty) continue;
      final a = q.analysisResult;
      questions.add(PaperQuestion(
        stem: text,
        options: const <String>[],
        answer: a?.finalAnswer ?? '',
        analysis: (a?.steps ?? const <String>[])
            .where((s) => s.isNotEmpty)
            .join('\n'),
        difficulty: _difficulty ?? '中等',
        knowledgePoints: List<String>.from(q.aiKnowledgePoints),
        questionType: '',
        source: 'existing',
        sourceQuestionId: q.id,
      ));
    }

    final ai = AiAnalysisService(
      settingsRepository: ref.read(settingsRepositoryProvider),
    );
    final seed = candidates.isEmpty ? '' : textOf(candidates.first);
    const diffs = <String>['简单', '中等', '困难'];
    for (var i = questions.length; i < _count; i++) {
      final variant = await ai.generateVariantQuestionDirect(
        subjectName: subject.label,
        knowledgePoints: kps,
        difficulty: _difficulty ?? diffs[(i - questions.length) % diffs.length],
        seedStem: seed,
      );
      if (variant != null) questions.add(variant);
    }
    if (questions.isEmpty) {
      throw Exception('该条件下没有可用错题，AI 变式也未生成成功');
    }
    const order = <String, int>{'简单': 0, '中等': 1, '困难': 2};
    questions.sort((a, b) =>
        (order[a.difficulty] ?? 1).compareTo(order[b.difficulty] ?? 1));
    return PaperResult(
      title: '${subject.label} · AI 变式组卷（本地）',
      subject: subject.name,
      questions: questions,
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final glassEnabled = ref.watch(glassEnabledProvider);
    return Scaffold(
      extendBodyBehindAppBar: glassEnabled,
      appBar: glassTopBar(context, title: const Text('AI 变式组卷')),
      body: Stack(
        children: <Widget>[
          ListView(
        padding: EdgeInsets.fromLTRB(
          20,
          16 + (glassEnabled ? glassTopInset(context) : 0),
          20,
          32,
        ),
        children: <Widget>[
          Text('挑范围，AI 帮你优先用本人错题、不足自动补变式出一套小卷',
              style: TextStyle(fontSize: 13, color: colorScheme.onSurfaceVariant)),
          const SizedBox(height: 20),
          Text('科目', style: theme.textTheme.titleMedium),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: Subject.selectableValues
                .map((s) => ChoiceChip(
                      label: Text(s.label),
                      selected: _subject == s,
                      onSelected: (_) => setState(() => _subject = s),
                    ))
                .toList(),
          ),
          const SizedBox(height: 20),
          Text('难度（可选，自动均衡）', style: theme.textTheme.titleMedium),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            children: <String>['均衡', '简单', '中等', '困难'].map((label) {
              final value = label == '均衡' ? null : label;
              return ChoiceChip(
                label: Text(label),
                selected: _difficulty == value,
                onSelected: (_) => setState(() => _difficulty = value),
              );
            }).toList(),
          ),
          const SizedBox(height: 20),
          Text('题数', style: theme.textTheme.titleMedium),
          const SizedBox(height: 4),
          SegmentedButton<int>(
            segments: const <ButtonSegment<int>>[
              ButtonSegment(value: 5, label: Text('5')),
              ButtonSegment(value: 10, label: Text('10')),
              ButtonSegment(value: 20, label: Text('20')),
            ],
            selected: <int>{_count},
            onSelectionChanged: (s) => setState(() => _count = s.first),
          ),
          const SizedBox(height: 20),
          Text('知识点范围（可选，逗号分隔）', style: theme.textTheme.titleMedium),
          const SizedBox(height: 6),
          TextField(
            controller: _kpController,
            decoration: const InputDecoration(
              hintText: '如：力学, 压强 / 一元二次方程',
              border: OutlineInputBorder(),
            ),
          ),
          if (_error != null) ...<Widget>[
            const SizedBox(height: 16),
            Text(_error!, style: const TextStyle(color: Color(0xFFB91C1C))),
          ],
          const SizedBox(height: 28),
          FilledButton.icon(
            onPressed: _loading ? null : _generate,
            icon: _loading
                ? const SizedBox(
                    width: 18, height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(CupertinoIcons.doc_append),
            label: Text(_loading ? 'AI 组卷中…' : '生成一套卷'),
            style: FilledButton.styleFrom(
                minimumSize: const Size(double.infinity, 50)),
          ),
          const SizedBox(height: 8),
          Text('生成可能耗时数十秒，期间请勿离开此页',
              style: TextStyle(fontSize: 11, color: colorScheme.onSurfaceVariant)),
        ],
      ),
        ],
      ),
    );
  }
}
