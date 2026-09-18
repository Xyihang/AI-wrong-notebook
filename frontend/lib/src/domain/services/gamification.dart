import 'dart:convert';

import 'package:smart_wrong_notebook/src/domain/models/achievement.dart';
import 'package:smart_wrong_notebook/src/domain/models/content_status.dart';
import 'package:smart_wrong_notebook/src/domain/models/mastery_level.dart';
import 'package:smart_wrong_notebook/src/domain/models/question_record.dart';
import 'package:smart_wrong_notebook/src/domain/models/review_log.dart';
import 'package:smart_wrong_notebook/src/domain/models/subject.dart';

/// SettingsRepository 中持久化解锁徽章的 key（map id -> iso8601 解锁时间）。
const String gamificationUnlockKey = 'gamification_unlocked_v1';

/// 从本地持久化字符串解析已解锁徽章表。损坏/空值返回空表，不抛异常。
Map<String, DateTime> decodeUnlockedMap(String? raw) {
  if (raw == null || raw.isEmpty) return <String, DateTime>{};
  try {
    final decoded = jsonDecode(raw);
    if (decoded is! Map) return <String, DateTime>{};
    final result = <String, DateTime>{};
    decoded.forEach((key, value) {
      if (key is String && value is String) {
        final time = DateTime.tryParse(value);
        if (time != null) result[key] = time;
      }
    });
    return result;
  } catch (_) {
    return <String, DateTime>{};
  }
}

/// 把已解锁徽章表序列化（按键排序，保证输出稳定）。
String encodeUnlockedMap(Map<String, DateTime> unlockedById) {
  final sortedKeys = unlockedById.keys.toList()..sort();
  final map = <String, String>{
    for (final key in sortedKeys)
      key: unlockedById[key]!.toIso8601String(),
  };
  return jsonEncode(map);
}

/// 学习连击 & 成就徽章的纯函数集合（不依赖 I/O，便于单测）。
///
/// 数据来源：现有本地错题（QuestionRecord.createdAt / lastReviewedAt /
/// reviewCount / masteryLevel / savedExercises）+ 复习日志（ReviewLog.reviewedAt）。
/// 无需新增学习记录源即可推断「活跃天数」。

// ---------------------------------------------------------------------------
// 日期工具
// ---------------------------------------------------------------------------

/// 把任意 [DateTime] 规整为「仅日期」的 UTC 零点再换算成自纪元的天序号。
/// 用 UTC(年/月/日) 避免本地 DST 导致的相邻午夜整除偏移。
int dayKeyOf(DateTime date) {
  final utc = DateTime.utc(date.year, date.month, date.day);
  return utc.millisecondsSinceEpoch ~/ Duration.millisecondsPerDay;
}

/// 汇聚所有「发生过学习行为的日期」（仅日期，去重）。
///
/// 学习行为：新增错题（createdAt）、复习（lastReviewedAt / 复习日志 reviewedAt）。
/// 复习记录同时体现在错题的 lastReviewedAt 上，二者取并集保证健壮。
Set<DateTime> collectActiveDates({
  required List<QuestionRecord> questions,
  List<ReviewLog> reviewLogs = const <ReviewLog>[],
}) {
  final byKey = <int, DateTime>{};
  void add(DateTime? time) {
    if (time == null) return;
    final key = dayKeyOf(time);
    byKey[key] = DateTime(time.year, time.month, time.day);
  }

  for (final q in questions) {
    add(q.createdAt);
    add(q.lastReviewedAt);
  }
  for (final log in reviewLogs) {
    add(log.reviewedAt);
  }
  final result = byKey.values.toList()..sort();
  return result.toSet();
}

/// 计算学习连击天数。
///
/// 规则（与计划文档一致）：从「今天」往前数连续活跃天数；若今天尚未活跃但
/// 昨天活跃，则沿用昨天的连击（给「今天还没学，学一下保持连击」的缓冲），
/// 一旦出现超过 1 天的断层则计 0。
int computeStreak(Set<DateTime> activeDays, {DateTime? today}) {
  if (activeDays.isEmpty) return 0;
  final activeKeys = activeDays.map(dayKeyOf).toSet();
  final now = today ?? DateTime.now();
  var cursor = dayKeyOf(now);

  // 今天不活跃：若昨天活跃，则从昨天起算（保持连击缓冲）。
  if (!activeKeys.contains(cursor)) {
    if (!activeKeys.contains(cursor - 1)) return 0;
    cursor = cursor - 1;
  }

  var streak = 0;
  while (activeKeys.contains(cursor)) {
    streak++;
    cursor--;
  }
  return streak;
}

/// 今天是否已有学习行为（用于「今天还没学」提示）。
bool isActiveOn(Set<DateTime> activeDays, {DateTime? date}) {
  final key = dayKeyOf(date ?? DateTime.now());
  return activeDays.map(dayKeyOf).contains(key);
}

// ---------------------------------------------------------------------------
// 成就统计
// ---------------------------------------------------------------------------

/// 从本地数据聚合出的成就判定所需统计量。
class AchievementStats {
  const AchievementStats({
    required this.questionCount,
    required this.masteredCount,
    required this.masteredBySubject,
    required this.totalReviews,
    required this.streak,
    required this.anyExercise,
    required this.nightStudy,
  });

  factory AchievementStats.fromLocalData({
    required List<QuestionRecord> questions,
    required List<ReviewLog> reviewLogs,
    int streak = 0,
  }) {
    final ready = questions
        .where((q) => q.contentStatus == ContentStatus.ready)
        .toList();
    final mastered = ready
        .where((q) => q.masteryLevel == MasteryLevel.mastered)
        .toList();

    final bySubject = <Subject, int>{};
    for (final q in mastered) {
      bySubject[q.subject] = (bySubject[q.subject] ?? 0) + 1;
    }

    var totalReviews = 0;
    for (final q in ready) {
      totalReviews += q.reviewCount;
    }

    final anyExercise = ready.any((q) => q.savedExercises.isNotEmpty);
    final hasNight = _hasNightStudy(questions, reviewLogs);

    return AchievementStats(
      questionCount: ready.length,
      masteredCount: mastered.length,
      masteredBySubject: bySubject,
      totalReviews: totalReviews,
      streak: streak,
      anyExercise: anyExercise,
      nightStudy: hasNight,
    );
  }

  final int questionCount;
  final int masteredCount;

  /// 各科目已掌握数（key = Subject，value = 掌握题数）。
  final Map<Subject, int> masteredBySubject;

  /// 累计复习次数（错题上持久化的 reviewCount 之和，重启不回退）。
  final int totalReviews;

  final int streak;
  final bool anyExercise;
  final bool nightStudy;
}

bool _hasNightStudy(
  List<QuestionRecord> questions,
  List<ReviewLog> reviewLogs,
) {
  bool inNight(DateTime? time) {
    if (time == null) return false;
    final hour = time.hour;
    return hour >= 0 && hour < 5; // 0–5 点为深夜
  }

  for (final q in questions) {
    if (inNight(q.createdAt) || inNight(q.lastReviewedAt)) return true;
  }
  for (final log in reviewLogs) {
    if (inNight(log.reviewedAt)) return true;
  }
  return false;
}

// ---------------------------------------------------------------------------
// 徽章定义
// ---------------------------------------------------------------------------

class _AchievementDef {
  const _AchievementDef({
    required this.id,
    required this.name,
    required this.icon,
    required this.description,
    required this.isMet,
  });

  final String id;
  final String name;
  final String icon;
  final String description;

  /// 当前统计是否满足条件（纯函数）。
  final bool Function(AchievementStats stats) isMet;

  Achievement toAchievement([DateTime? unlockedAt]) => Achievement(
        id: id,
        name: name,
        icon: icon,
        description: description,
        unlockedAt: unlockedAt,
      );
}

/// 徽章规则表（顺序即成就墙展示顺序）。数值为默认，后续可调。
final List<_AchievementDef> _definitions = <_AchievementDef>[
  _AchievementDef(
    id: 'first_record',
    name: '首次记录',
    icon: '🎉',
    description: '记录第一道错题',
    isMet: (s) => s.questionCount >= 1,
  ),
  _AchievementDef(
    id: 'collector_10',
    name: '收藏家 · 10 题',
    icon: '📚',
    description: '错题本累计 10 道错题',
    isMet: (s) => s.questionCount >= 10,
  ),
  _AchievementDef(
    id: 'collector_50',
    name: '收藏家 · 50 题',
    icon: '🗂️',
    description: '错题本累计 50 道错题',
    isMet: (s) => s.questionCount >= 50,
  ),
  _AchievementDef(
    id: 'collector_100',
    name: '收藏家 · 100 题',
    icon: '🏛️',
    description: '错题本累计 100 道错题',
    isMet: (s) => s.questionCount >= 100,
  ),
  _AchievementDef(
    id: 'streak_3',
    name: '燃起小火苗',
    icon: '🔥',
    description: '学习连击达到 3 天',
    isMet: (s) => s.streak >= 3,
  ),
  _AchievementDef(
    id: 'streak_7',
    name: '一鼓作气',
    icon: '⚡',
    description: '学习连击达到 7 天',
    isMet: (s) => s.streak >= 7,
  ),
  _AchievementDef(
    id: 'streak_21',
    name: '坚持之王',
    icon: '🏆',
    description: '学习连击达到 21 天',
    isMet: (s) => s.streak >= 21,
  ),
  _AchievementDef(
    id: 'subject_master',
    name: '单科通',
    icon: '✍️',
    description: '任意一科掌握 10 道错题',
    isMet: (s) => s.masteredBySubject.values.any((count) => count >= 10),
  ),
  _AchievementDef(
    id: 'night_owl',
    name: '深夜学者',
    icon: '🌙',
    description: '曾在 0–5 点学习',
    isMet: (s) => s.nightStudy,
  ),
  _AchievementDef(
    id: 'review_20',
    name: '巩固达人',
    icon: '🎯',
    description: '累计复习 20 次',
    isMet: (s) => s.totalReviews >= 20,
  ),
  _AchievementDef(
    id: 'first_exercise',
    name: '举一反三',
    icon: '🤸',
    description: '完成一次变式练习',
    isMet: (s) => s.anyExercise,
  ),
];

int get achievementCount => _definitions.length;

/// 当前满足条件的徽章（尚未解锁判定）。
List<Achievement> metAchievements(AchievementStats stats) {
  return _definitions
      .where((def) => def.isMet(stats))
      .map((def) => def.toAchievement())
      .toList();
}

/// 汇总成就墙展示列表：每枚徽章带「已解锁」状态。
///
/// [unlockedById] 来自本地持久化（id -> 解锁时间）。已解锁徽章即使当前条件
/// 不再满足（如删题）也保持解锁，不回退。
List<Achievement> buildAchievements(
  AchievementStats stats, {
  required Map<String, DateTime> unlockedById,
}) {
  return _definitions.map((def) {
    final previously = unlockedById[def.id];
    if (previously != null) return def.toAchievement(previously);
    if (def.isMet(stats)) return def.toAchievement();
    return def.toAchievement();
  }).toList();
}

/// 本次统计中新解锁（条件满足且此前未持久化）的徽章 id。
///
/// 判定用「条件满足 + 之前未解锁」，用于触发解锁持久化与「恭喜」弹层，保证
/// 已解锁徽章不会重复弹出。
List<Achievement> newlyAchievements(
  AchievementStats stats, {
  required Set<String> alreadyUnlockedIds,
}) {
  return _definitions
      .where((def) => def.isMet(stats) && !alreadyUnlockedIds.contains(def.id))
      .map((def) => def.toAchievement())
      .toList();
}
