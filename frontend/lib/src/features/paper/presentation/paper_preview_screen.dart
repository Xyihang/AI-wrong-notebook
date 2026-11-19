import 'dart:io';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:smart_wrong_notebook/src/app/providers.dart';
import 'package:smart_wrong_notebook/src/features/glass/glass_overlays.dart';
import 'package:smart_wrong_notebook/src/features/glass/glass_top_bar.dart';
import 'package:smart_wrong_notebook/src/data/remote/ai/ai_analysis_service.dart';
import 'package:smart_wrong_notebook/src/data/remote/backend/backend_client.dart';
import 'package:smart_wrong_notebook/src/domain/models/paper.dart';

/// AI 变式组卷 - 整卷预览（点开看答案/解析、导出 PDF）。
class PaperPreviewScreen extends ConsumerWidget {
  const PaperPreviewScreen({super.key});

  /// 游客（仅直连）模式：不依赖后端，导出为本地文本文件并分享。
  Future<void> _exportTextLocally(
    BuildContext context,
    PaperResult paper, {
    required bool includeAnswers,
  }) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final buf = StringBuffer()
        ..writeln(paper.title)
        ..writeln('共 ${paper.questions.length} 题')
        ..writeln();
      for (var i = 0; i < paper.questions.length; i++) {
        final q = paper.questions[i];
        buf.writeln('${i + 1}. ${q.stem}');
        for (final opt in q.options) {
          buf.writeln('   $opt');
        }
        if (includeAnswers) {
          buf.writeln('【答案】${q.answer}');
          if (q.analysis.isNotEmpty) buf.writeln('【解析】${q.analysis}');
        }
        buf.writeln();
      }
      final dir = await getTemporaryDirectory();
      final path =
          '${dir.path}/ai_paper_${DateTime.now().millisecondsSinceEpoch}.txt';
      await File(path).writeAsString(buf.toString(), flush: true);
      Rect? origin;
      final renderBox = context.findRenderObject();
      if (renderBox is RenderBox && renderBox.hasSize) {
        origin = renderBox.localToGlobal(Offset.zero) & renderBox.size;
      }
      await Share.shareXFiles(
        <XFile>[XFile(path, mimeType: 'text/plain')],
        sharePositionOrigin: origin,
      );
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('导出失败：$e')));
    }
  }

  Future<void> _exportPdf(
    BuildContext context,
    PaperResult paper, {
    required bool includeAnswers,
  }) async {
    final messenger = ScaffoldMessenger.of(context);
    // 游客模式不使用后端：导出为本地文本（避免依赖后端 PDF 服务）。
    if (AiAnalysisService.directOnly) {
      await _exportTextLocally(context, paper, includeAnswers: includeAnswers);
      return;
    }
    try {
      messenger.showSnackBar(const SnackBar(content: Text('正在生成 PDF…')));
      final bytes = await BackendClient().exportPaperPdf(
        title: paper.title,
        questions: paper.questions.map((q) => q.toExportMap()).toList(),
        includeAnswers: includeAnswers,
      );
      final dir = await getTemporaryDirectory();
      final stamp = DateTime.now().millisecondsSinceEpoch;
      final path = '${dir.path}/ai_paper_$stamp.pdf';
      await File(path).writeAsBytes(bytes, flush: true);
      // sharePositionOrigin：让分享面板锚定在当前界面，分享结束后能正确回到 App
      //（避免 Android 上跳到微信后 Flutter 主界面不被带回前台的问题）。
      Rect? origin;
      final renderBox = context.findRenderObject();
      if (renderBox is RenderBox && renderBox.hasSize) {
        origin = renderBox.localToGlobal(Offset.zero) & renderBox.size;
      }
      if (origin != null) {
        await Share.shareXFiles(
          <XFile>[XFile(path, mimeType: 'application/pdf')],
          sharePositionOrigin: origin,
        );
      } else {
        await Share.shareXFiles(<XFile>[XFile(path, mimeType: 'application/pdf')]);
      }
    } on BackendClientException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('导出失败：${e.message}')));
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('导出失败：$e')));
    }
  }

  Future<void> _chooseExport(BuildContext context, PaperResult paper) async {
    final choice = await showAppSheet<bool>(context,
builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            ListTile(
              leading: const Icon(CupertinoIcons.doc),
              title: const Text('导出题面（不含答案）'),
              onTap: () => Navigator.pop(sheetContext, false),
            ),
            ListTile(
              leading: const Icon(CupertinoIcons.checkmark_alt),
              title: const Text('导出含答案解析'),
              onTap: () => Navigator.pop(sheetContext, true),
            ),
          ],
        ),
      ),
    );
    if (choice == null) return;
    await _exportPdf(context, paper, includeAnswers: choice);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final paper = ref.watch(currentPaperProvider);
    final colorScheme = Theme.of(context).colorScheme;
    if (paper == null) {
      return Scaffold(
        appBar: glassTopBar(context, title: const Text('预览')),
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              const Icon(CupertinoIcons.doc, size: 48,
                  color: Color(0xFF9CA3AF)),
              const SizedBox(height: 12),
              const Text('还没有生成的卷'),
              const SizedBox(height: 16),
              FilledButton.tonal(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('去组卷'),
              ),
            ],
          ),
        ),
      );
    }
    final count = paper.questions.length;
    final existing = paper.questions.where((q) => q.isExisting).length;
    return Scaffold(
      appBar: glassTopBar(
        context,
        title: const Text('组卷预览'),
        actions: <Widget>[
          IconButton(
            tooltip: '导出 PDF',
            icon: const Icon(CupertinoIcons.share),
            onPressed: () => _chooseExport(context, paper),
          ),
          IconButton(
            tooltip: '重新组卷',
            icon: const Icon(CupertinoIcons.refresh),
            onPressed: () => Navigator.of(context).pop(),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
        children: <Widget>[
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: colorScheme.surface,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: colorScheme.outlineVariant),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(paper.title,
                    style: const TextStyle(
                        fontSize: 16, fontWeight: FontWeight.w700)),
                const SizedBox(height: 6),
                Text('共 $count 题 · 本人错题 $existing · AI 变式 ${count - existing}',
                    style: TextStyle(
                        fontSize: 12, color: colorScheme.onSurfaceVariant)),
              ],
            ),
          ),
          const SizedBox(height: 14),
          for (var i = 0; i < count; i++)
            _QuestionTile(index: i + 1, question: paper.questions[i]),
        ],
      ),
    );
  }
}

class _QuestionTile extends StatefulWidget {
  const _QuestionTile({required this.index, required this.question});

  final int index;
  final PaperQuestion question;

  @override
  State<_QuestionTile> createState() => _QuestionTileState();
}

class _QuestionTileState extends State<_QuestionTile> {
  bool _revealed = false;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final q = widget.question;
    final existing = q.isExisting;
    final tagBg = existing
        ? (isDark ? const Color(0xFFF97316).withValues(alpha: 0.16) : const Color(0xFFFFF7ED))
        : (isDark ? const Color(0xFF6366F1).withValues(alpha: 0.16) : const Color(0xFFEEF2FF));
    final tagFg = existing ? const Color(0xFFC2410C) : const Color(0xFF4F46E5);

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
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
              Container(
                width: 24, height: 24, alignment: Alignment.center,
                decoration: BoxDecoration(
                    color: colorScheme.primary, shape: BoxShape.circle),
                child: Text('${widget.index}',
                    style: TextStyle(
                        fontSize: 12, fontWeight: FontWeight.bold,
                        color: colorScheme.onPrimary)),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text('${q.difficulty}${q.questionType.isNotEmpty ? ' · ${q.questionType}' : ''}',
                    style: TextStyle(fontSize: 12, color: colorScheme.onSurfaceVariant)),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: tagBg,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(existing ? '本人错题' : 'AI 变式',
                    style: TextStyle(fontSize: 10, color: tagFg)),
              ),
            ],
          ),
          const SizedBox(height: 10),
          SelectableText(q.stem, style: const TextStyle(height: 1.5, fontSize: 14)),
          if (q.options.isNotEmpty) ...<Widget>[
            const SizedBox(height: 8),
            for (final opt in q.options)
              Padding(
                padding: const EdgeInsets.only(bottom: 2),
                child: SelectableText(opt, style: const TextStyle(fontSize: 13)),
              ),
          ],
          const SizedBox(height: 10),
          if (_revealed) ...<Widget>[
            const Divider(height: 1),
            const SizedBox(height: 10),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: const Color(0xFFF0FDF4),
                borderRadius: BorderRadius.circular(8),
              ),
              child: SelectableText('答案：${q.answer}',
                  style: const TextStyle(
                      fontSize: 14, fontWeight: FontWeight.w600,
                      color: Color(0xFF166534))),
            ),
            if (q.analysis.isNotEmpty) ...<Widget>[
              const SizedBox(height: 8),
              SelectableText('解析：${q.analysis}',
                  style: const TextStyle(fontSize: 13, height: 1.5)),
            ],
          ] else
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: () => setState(() => _revealed = true),
                icon: const Icon(CupertinoIcons.eye, size: 16),
                label: const Text('查看答案与解析'),
              ),
            ),
        ],
      ),
    );
  }
}
