import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:smart_wrong_notebook/src/app/providers.dart';
import 'package:smart_wrong_notebook/src/features/glass/glass_overlays.dart';
import 'package:smart_wrong_notebook/src/domain/models/question_record.dart';
import 'package:smart_wrong_notebook/src/features/similar/similar_match.dart';
import 'package:smart_wrong_notebook/src/features/similar/similar_question_popup.dart';

/// 当前「相似错题推荐」弹窗的展示状态。
class SimilarPopupState {
  const SimilarPopupState({
    this.matches = const <SimilarMatch>[],
    this.knowledgePoint,
  });

  /// 最近一次展示的相似错题列表（空列表表示无活动弹窗）。
  final List<SimilarMatch> matches;

  /// 触发匹配的知识点。
  final String? knowledgePoint;

  /// 是否有正在展示的相似错题。
  bool get isVisible => matches.isNotEmpty;

  SimilarPopupState copyWith({
    List<SimilarMatch>? matches,
    String? knowledgePoint,
  }) {
    return SimilarPopupState(
      matches: matches ?? this.matches,
      knowledgePoint: knowledgePoint ?? this.knowledgePoint,
    );
  }
}

/// 相似错题弹窗控制器：负责弹出 bottom sheet，并处理
/// 「查看详情」与「查看该知识点全部错题」两类导航。
///
/// 用法：
/// ```dart
/// final matches = parseSimilarMatches(response);
/// ref.read(similarPopupControllerProvider.notifier).showFor(ref, matches);
/// // 或便捷入口：
/// showSimilarQuestionPopup(ref, matches, knowledgePoint: kp);
/// ```
final NotifierProvider<SimilarPopupController, SimilarPopupState>
    similarPopupControllerProvider =
    NotifierProvider<SimilarPopupController, SimilarPopupState>(
        SimilarPopupController.new);

class SimilarPopupController extends Notifier<SimilarPopupState> {
  @override
  SimilarPopupState build() => const SimilarPopupState();

  /// 弹出「相似错题推荐」底部弹窗并托管其状态。
  ///
  /// [ref] 为调用方（Consumer 组件）的 [WidgetRef]，用于取得可靠的
  /// [BuildContext] 挂载弹窗；[knowledgePoint] 供「查看该知识点全部错题」
  /// 过滤跳转使用。弹窗关闭后自动复位状态。
  Future<void> showFor(
    WidgetRef ref,
    List<SimilarMatch> matches, {
    String? knowledgePoint,
  }) async {
    final snapshot = List<SimilarMatch>.unmodifiable(matches);
    state = SimilarPopupState(
      matches: snapshot,
      knowledgePoint: knowledgePoint,
    );
    if (snapshot.isEmpty) return;

    final context = ref.context;
    if (!context.mounted) return;

    await showAppSheet<void>(context,
      builder: (sheetContext) {
        return ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(sheetContext).size.height * 0.82,
          ),
          child: SimilarQuestionPopup(
            matches: snapshot,
            knowledgePoint: knowledgePoint,
            onDismiss: () => state = const SimilarPopupState(),
          ),
        );
      },
    );

    // 弹窗被关闭（含点条目后导航导致弹窗移除）后复位状态。
    if (state.isVisible) {
      state = const SimilarPopupState();
    }
  }

  /// 打开某条相似错题的详情页。
  ///
  /// 优先从本地仓库按 id 找到完整 [QuestionRecord] 写入
  /// [currentQuestionProvider]，让详情页展示完整内容；本地查不到时仍跳转，
  /// 详情页会走「未找到该错题」兜底。
  Future<void> openQuestion(WidgetRef ref, SimilarMatch match) async {
    final context = ref.context;
    final id = match.question.id.trim();
    if (id.isEmpty) return;

    QuestionRecord? record;
    try {
      final all = await ref.read(questionRepositoryProvider).listAll();
      for (final question in all) {
        if (question.id == id) {
          record = question;
          break;
        }
      }
    } catch (_) {
      // 本地查询失败不影响跳转。
    }
    if (record != null) {
      ref.read(currentQuestionProvider.notifier).state = record;
    }
    if (!context.mounted) return;
    // push 保留返回栈：返回键回到上一页
    context.push('/notebook/question/$id');
  }

  /// 跳转到错题本并只保留该知识点的过滤（「查看该知识点全部错题」）。
  ///
  /// 清除其它筛选（科目/掌握程度/今日/搜索/标签），确保列表只按
  /// [selectedKnowledgePointFilterProvider] 过滤；[knowledgePoint] 为 null
  /// 时清除知识点过滤，等价于查看全部错题。
  void viewAllKnowledgePoint(WidgetRef ref, String? knowledgePoint) {
    ref.read(selectedSubjectFilterProvider.notifier).state = null;
    ref.read(selectedMasteryFilterProvider.notifier).state = null;
    ref.read(selectedCreatedTodayFilterProvider.notifier).state = false;
    ref.read(searchQueryProvider.notifier).state = '';
    ref.read(selectedTagsFilterProvider.notifier).state = const <String>[];
    ref.read(selectedKnowledgePointFilterProvider.notifier).state =
        knowledgePoint;
    if (ref.context.mounted) ref.context.go('/notebook');
  }
}

/// 便捷入口：一行代码弹出相似错题推荐弹窗。
///
/// 示例：
/// ```dart
/// final matches = parseSimilarMatches(response);
/// await showSimilarQuestionPopup(ref, matches, knowledgePoint: '圆');
/// ```
Future<void> showSimilarQuestionPopup(
  WidgetRef ref,
  List<SimilarMatch> matches, {
  String? knowledgePoint,
}) {
  return ref
      .read(similarPopupControllerProvider.notifier)
      .showFor(ref, matches, knowledgePoint: knowledgePoint);
}
