import 'dart:io';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:smart_wrong_notebook/src/domain/models/question_record.dart';
import 'package:smart_wrong_notebook/src/features/similar/similar_match.dart';
import 'package:smart_wrong_notebook/src/features/similar/similar_popup_controller.dart';
import 'package:smart_wrong_notebook/src/shared/widgets/math_content_view.dart';

/// 相似错题推荐弹窗内容。
///
/// 通常配合 [similarPopupControllerProvider] 使用（自动包一层 modal bottom
/// sheet）；也可以直接嵌入自定义的 [showModalBottomSheet] / 对话框。
///
/// 每一条展示：原题缩略图、原题摘要（题干预览）、错因、订正答案、
/// 收录时间、相似度徽标、命中方式 chip（向量/标签/两者）。
class SimilarQuestionPopup extends ConsumerWidget {
  const SimilarQuestionPopup({
    super.key,
    required this.matches,
    this.knowledgePoint,
    this.topN,
    this.onOpenQuestion,
    this.onViewAllKnowledgePoint,
    this.onDismiss,
  });

  /// 后端返回的同类错题列表（已按相似度降序）。
  final List<SimilarMatch> matches;

  /// 触发本次匹配的知识点，用于「查看该知识点全部错题」。
  /// 为 null 时会尝试从第一条匹配的 knowledgePoints 推导。
  final String? knowledgePoint;

  /// 最多展示的条数（TopN）。为 null 时展示全部。
  final int? topN;

  /// 点击某条错题的回调；缺省走 [SimilarPopupController.openQuestion]，
  /// 即跳转 `/notebook/question/:id` 详情页。
  final void Function(SimilarMatch match)? onOpenQuestion;

  /// 「查看该知识点全部错题」回调；缺省走
  /// [SimilarPopupController.viewAllKnowledgePoint]，即带上知识点过滤跳转
  /// `/notebook`。
  final void Function(String knowledgePoint)? onViewAllKnowledgePoint;

  /// 关闭回调（控制器用它复位弹窗状态）。
  final VoidCallback? onDismiss;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final shown = _visibleMatches();
    final kp = _effectiveKnowledgePoint();
    final count = shown.length;

    return SafeArea(
      top: false,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          // 拖拽把手
          Container(
            width: 36,
            height: 4,
            margin: const EdgeInsets.only(top: 10, bottom: 6),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.outlineVariant,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          _buildHeader(context, count, kp),
          const Divider(height: 1),
          if (shown.isEmpty)
            _buildEmptyState(context)
          else
            Flexible(
              child: ListView.separated(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                shrinkWrap: true,
                itemCount: count,
                separatorBuilder: (_, __) => const SizedBox(height: 10),
                itemBuilder: (context, index) {
                  final match = shown[index];
                  return _SimilarMatchCard(
                    match: match,
                    onTap: () => _handleOpen(ref, match),
                  );
                },
              ),
            ),
          if (kp != null) ...<Widget>[
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton.tonalIcon(
                  onPressed: () => _handleViewAll(ref, kp),
                  icon: const Icon(CupertinoIcons.book, size: 18),
                  label: Text('查看「$kp」全部错题'),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// 应用 TopN 截断。
  List<SimilarMatch> _visibleMatches() {
    final n = topN;
    if (n == null || n <= 0 || n >= matches.length) return matches;
    return matches.sublist(0, n);
  }

  /// 知识点：优先用传入值，否则从第一条匹配项推导。
  String? _effectiveKnowledgePoint() {
    final kp = knowledgePoint?.trim();
    if (kp != null && kp.isNotEmpty) return kp;
    for (final match in matches) {
      if (match.question.knowledgePoints.isNotEmpty) {
        return match.question.knowledgePoints.first;
      }
    }
    return null;
  }

  Widget _buildHeader(BuildContext context, int count, String? kp) {
    final colorScheme = Theme.of(context).colorScheme;
    final subtitle = kp == null
        ? (count > 0 ? '为你找到 $count 道历史相似错题' : '暂未找到相似错题')
        : (count > 0 ? '「$kp」相关的 $count 道历史错题' : '「$kp」暂无相似错题');

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 8, 12),
      child: Row(
        children: <Widget>[
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: colorScheme.primary.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(
              CupertinoIcons.link,
              size: 20,
              color: colorScheme.primary,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  '相似错题推荐',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: colorScheme.onSurface,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: TextStyle(
                    fontSize: 12,
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            onPressed: () {
              onDismiss?.call();
              Navigator.of(context).maybePop();
            },
            icon: const Icon(CupertinoIcons.xmark),
            tooltip: '关闭',
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 40),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(
            CupertinoIcons.sparkles,
            size: 44,
            color: colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
          ),
          const SizedBox(height: 12),
          Text(
            '暂未找到相似错题',
            style: TextStyle(fontSize: 15, color: colorScheme.onSurface),
          ),
          const SizedBox(height: 6),
          Text(
            '换一道题试试，或稍后再来匹配',
            style: TextStyle(
              fontSize: 12,
              color: colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }

  void _handleOpen(WidgetRef ref, SimilarMatch match) {
    final handler = onOpenQuestion;
    if (handler != null) {
      handler(match);
      return;
    }
    ref
        .read(similarPopupControllerProvider.notifier)
        .openQuestion(ref, match);
  }

  void _handleViewAll(WidgetRef ref, String kp) {
    final handler = onViewAllKnowledgePoint;
    if (handler != null) {
      handler(kp);
      return;
    }
    ref
        .read(similarPopupControllerProvider.notifier)
        .viewAllKnowledgePoint(ref, kp);
  }
}

/// 单条相似错题卡片。
class _SimilarMatchCard extends StatelessWidget {
  const _SimilarMatchCard({required this.match, required this.onTap});

  final SimilarMatch match;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final question = match.question;

    return Material(
      color: colorScheme.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: colorScheme.outlineVariant),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  _Thumbnail(question: question),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Row(
                          children: <Widget>[
                            _SimilarityBadge(similarity: match.similarity),
                            const SizedBox(width: 6),
                            _MatchedByChip(matchedBy: match.matchedBy),
                            const Spacer(),
                            Text(
                              _formatCreatedAt(question.createdAt),
                              style: TextStyle(
                                fontSize: 11,
                                color: colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        // 原题摘要
                        MathContentView(
                          question.stem,
                          contentFormat: question.contentFormat,
                          mode: MathContentViewMode.compact,
                          maxLines: 2,
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                            height: 1.4,
                            color: colorScheme.onSurface,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              if (question.mistakeReason.isNotEmpty) ...<Widget>[
                const SizedBox(height: 8),
                _LabeledLine(
                  label: '错因',
                  text: question.mistakeReason,
                  contentFormat: question.contentFormat,
                  color: const Color(0xFFC2410C),
                ),
              ],
              if (question.answer.isNotEmpty) ...<Widget>[
                const SizedBox(height: 6),
                _LabeledLine(
                  label: '订正',
                  text: question.answer,
                  contentFormat: question.contentFormat,
                  color: const Color(0xFF15803D),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  static String _formatCreatedAt(DateTime? date) {
    if (date == null) return '—';
    final now = DateTime.now();
    final diff = now.difference(date);
    if (diff.inDays <= 0) return '今天';
    if (diff.inDays == 1) return '昨天';
    if (diff.inDays < 7) return '${diff.inDays}天前';
    return '${date.month}月${date.day}日';
  }
}

/// 原题缩略图：本地路径用 [Image.file]，http(s) 链接用 [Image.network]，
/// 均带错误兜底，无图时显示科目占位图标。
class _Thumbnail extends StatelessWidget {
  const _Thumbnail({required this.question});

  final SimilarQuestionSummary question;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final path = question.imagePath?.trim() ?? '';

    final Widget placeholder = Container(
      color: colorScheme.surfaceContainerHighest,
      child: Icon(
        question.subject.icon,
        size: 22,
        color: question.subject.color,
      ),
    );

    final Widget child;
    if (path.isEmpty) {
      child = placeholder;
    } else if (path.startsWith('http://') || path.startsWith('https://')) {
      child = Image.network(
        path,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => placeholder,
        loadingBuilder: (_, widget, progress) =>
            progress == null ? widget : placeholder,
      );
    } else {
      child = Image.file(
        File(path),
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => placeholder,
      );
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: SizedBox(width: 64, height: 64, child: child),
    );
  }
}

/// 相似度徽标，如「相似 90%」。
class _SimilarityBadge extends StatelessWidget {
  const _SimilarityBadge({required this.similarity});

  final double similarity;

  @override
  Widget build(BuildContext context) {
    final percent = (similarity.clamp(0.0, 1.0) * 100).round();
    final color = percent >= 80
        ? const Color(0xFF16A34A)
        : percent >= 60
            ? const Color(0xFFD97706)
            : const Color(0xFF64748B);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        '相似 $percent%',
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: color,
        ),
      ),
    );
  }
}

/// 命中方式 chip：向量 / 标签 / 向量+标签。
class _MatchedByChip extends StatelessWidget {
  const _MatchedByChip({required this.matchedBy});

  final SimilarMatchedBy matchedBy;

  @override
  Widget build(BuildContext context) {
    final color = switch (matchedBy) {
      SimilarMatchedBy.vector => const Color(0xFF4F46E5),
      SimilarMatchedBy.tag => const Color(0xFFD97706),
      SimilarMatchedBy.both => const Color(0xFF7C3AED),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        matchedBy.label,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w500,
          color: color,
        ),
      ),
    );
  }
}

/// 「错因 / 订正」带标签的小行，内容走 [MathContentView]（LaTeX 自动渲染）。
class _LabeledLine extends StatelessWidget {
  const _LabeledLine({
    required this.label,
    required this.text,
    required this.contentFormat,
    required this.color,
  });

  final String label;
  final String text;
  final QuestionContentFormat contentFormat;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(4),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: MathContentView(
            text,
            contentFormat: contentFormat,
            mode: MathContentViewMode.compact,
            maxLines: 2,
            style: TextStyle(
              fontSize: 12,
              height: 1.45,
              color: colorScheme.onSurface,
            ),
          ),
        ),
      ],
    );
  }
}
