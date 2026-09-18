import 'package:smart_wrong_notebook/src/domain/models/mastery_level.dart';
import 'package:smart_wrong_notebook/src/domain/models/question_record.dart';

/// 智能遗忘曲线复习 —— 纯函数（不落库，每次实时计算）。
///
/// 基于简化的艾宾浩斯间隔策略：按「掌握度 + 复习次数 + 上次复习时间」
/// 预测每题何时该复习，避免"所有未掌握题都算待复习"。
///
/// 本文件不依赖任何 I/O / Provider，便于单元测试。

/// 复习中的间隔表（单位：天），index = min(reviewCount - 1, 末尾)。
const List<int> reviewIntervalsDays = [1, 2, 4, 7, 15, 30];

/// 新题首次复习间隔（天）。
const int newQuestionIntervalDays = 1;

/// 某题距下次复习的间隔天数。
///
/// - mastered（已掌握）：返回 null（不进待复习）；
/// - newQuestion：返回 [newQuestionIntervalDays]；
/// - reviewing：按 [reviewCount] 查 [reviewIntervalsDays]（指数增长，封顶 30 天）。
int? intervalDaysFor(QuestionRecord q) {
  switch (q.masteryLevel) {
    case MasteryLevel.mastered:
      return null;
    case MasteryLevel.newQuestion:
      return newQuestionIntervalDays;
    case MasteryLevel.reviewing:
      final idx =
          (q.reviewCount - 1).clamp(0, reviewIntervalsDays.length - 1);
      return reviewIntervalsDays[idx];
  }
}

/// 下次复习时间。从未复习或已掌握（无可计算间隔）返回 null。
DateTime? nextReviewAt(QuestionRecord q) {
  final last = q.lastReviewedAt;
  if (last == null) return null;
  final interval = intervalDaysFor(q);
  if (interval == null) return null;
  return last.add(Duration(days: interval));
}

/// 是否到期（现在该复习）。
///
/// - 已掌握：false；
/// - 从未复习（reviewCount==0 或 lastReviewedAt 为空）：视为首次，立即到期；
/// - 否则：`lastReviewedAt + 间隔 <= now`。
bool isDue(QuestionRecord q, {DateTime? now}) {
  if (q.masteryLevel == MasteryLevel.mastered) return false;
  if (q.reviewCount == 0 || q.lastReviewedAt == null) return true;
  final next = nextReviewAt(q);
  if (next == null) return false;
  return !next.isAfter(now ?? DateTime.now());
}

/// 下次复习的人读描述（供 UI 显示）。
///
/// 返回如「今天到期」「3 天后」；已掌握返回 null；新题返回「新题 · 待首次复习」。
String? nextReviewLabel(QuestionRecord q, {DateTime? now}) {
  if (q.masteryLevel == MasteryLevel.mastered) return null;
  if (q.reviewCount == 0 || q.lastReviewedAt == null) return '新题 · 待首次复习';
  final next = nextReviewAt(q);
  if (next == null) return null;
  final reference = now ?? DateTime.now();
  if (isDue(q, now: reference)) return '今天到期';
  final days = next.difference(reference).inDays;
  if (days <= 0) return '今天';
  return '$days 天后';
}
