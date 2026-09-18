import 'package:flutter_test/flutter_test.dart';
import 'package:smart_wrong_notebook/src/domain/models/question_record.dart';
import 'package:smart_wrong_notebook/src/domain/models/subject.dart';
import 'package:smart_wrong_notebook/src/domain/services/gamification.dart';

void main() {
  DateTime day(int y, int m, int d) => DateTime(y, m, d, 12);

  group('学习连击 computeStreak', () {
    test('连续 3 天（含今天）→ 3', () {
      final now = day(2026, 2, 10);
      final active = {day(2026, 2, 10), day(2026, 2, 9), day(2026, 2, 8)};
      expect(computeStreak(active, today: now), 3);
    });

    test('今天未活跃但昨天活跃 → 沿用昨天连击（缓冲）', () {
      final now = day(2026, 2, 10);
      final active = {day(2026, 2, 9), day(2026, 2, 8), day(2026, 2, 7)};
      expect(computeStreak(active, today: now), 3);
    });

    test('断层（前天活跃、昨天今天没学）→ 0', () {
      final now = day(2026, 2, 10);
      final active = {day(2026, 2, 8)};
      expect(computeStreak(active, today: now), 0);
    });

    test('中途断一天后重计', () {
      final now = day(2026, 2, 10);
      // 2/5、2/6 活跃，2/7 断，2/8~2/10 活跃 → 今天连续 3
      final active = {
        day(2026, 2, 5),
        day(2026, 2, 6),
        day(2026, 2, 8),
        day(2026, 2, 9),
        day(2026, 2, 10),
      };
      expect(computeStreak(active, today: now), 3);
    });

    test('今天 + 昨天今天都活跃 = 2', () {
      final now = day(2026, 2, 10);
      final active = {day(2026, 2, 10), day(2026, 2, 9)};
      expect(computeStreak(active, today: now), 2);
    });

    test('isActiveOn 判断今天', () {
      final now = day(2026, 2, 10);
      expect(isActiveOn({day(2026, 2, 10)}, date: now), isTrue);
      expect(isActiveOn({day(2026, 2, 9)}, date: now), isFalse);
    });
  });

  group('collectActiveDates', () {
    test('同一道题同一天新增+复习只算一天', () {
      final q = QuestionRecord.draft(
        id: 'q1',
        imagePath: '',
        subject: Subject.math,
        recognizedText: '题目',
      ).copyWith(
        lastReviewedAt: DateTime.now(),
      );
      final dates = collectActiveDates(questions: [q]);
      expect(dates.length, 1);
    });
  });

  group('成就判定', () {
    AchievementStats stats({
      int questionCount = 0,
      int mastered = 0,
      int totalReviews = 0,
      int streak = 0,
      bool anyExercise = false,
      bool nightStudy = false,
      Map<Subject, int> bySubject = const {},
    }) {
      return AchievementStats(
        questionCount: questionCount,
        masteredCount: mastered,
        masteredBySubject: bySubject,
        totalReviews: totalReviews,
        streak: streak,
        anyExercise: anyExercise,
        nightStudy: nightStudy,
      );
    }

    test('无错题 → 不满足任何徽章（除无）', () {
      final newly = newlyAchievements(stats(), alreadyUnlockedIds: {});
      expect(newly, isEmpty);
    });

    test('1 道错题 → 首次记录新解锁', () {
      final newly = newlyAchievements(
        stats(questionCount: 1),
        alreadyUnlockedIds: {},
      );
      expect(newly.map((a) => a.id), contains('first_record'));
    });

    test('连击 3 天 → 小火苗解锁；已解锁不重复', () {
      final s = stats(questionCount: 3, streak: 3);
      expect(newlyAchievements(s, alreadyUnlockedIds: {}).map((a) => a.id),
          contains('streak_3'));

      final ids = {
        ...newlyAchievements(s, alreadyUnlockedIds: {}).map((a) => a.id),
      };
      // 再次判定（已持久化）不再返回 streak_3
      expect(
        newlyAchievements(s, alreadyUnlockedIds: ids).map((a) => a.id),
        isNot(contains('streak_3')),
      );
    });

    test('连击未满不触发', () {
      final newly = newlyAchievements(
        stats(questionCount: 3, streak: 2),
        alreadyUnlockedIds: {},
      );
      expect(newly.map((a) => a.id), isNot(contains('streak_3')));
    });

    test('单科掌握 10 → 单科通；累计复习 20 → 巩固达人', () {
      final newly = newlyAchievements(
        stats(
          mastered: 10,
          bySubject: {Subject.math: 10},
          totalReviews: 20,
        ),
        alreadyUnlockedIds: {},
      );
      final ids = newly.map((a) => a.id).toSet();
      expect(ids, contains('subject_master'));
      expect(ids, contains('review_20'));
    });

    test('做过练习 → 举一反三；深夜学习 → 深夜学者', () {
      final newly = newlyAchievements(
        stats(anyExercise: true, nightStudy: true),
        alreadyUnlockedIds: {},
      );
      final ids = newly.map((a) => a.id).toSet();
      expect(ids, contains('first_exercise'));
      expect(ids, contains('night_owl'));
    });

    test('已解锁徽章删题后不回退', () {
      final now = day(2026, 2, 1);
      final previously = {'first_record': now};
      final list = buildAchievements(
        stats(questionCount: 0),
        unlockedById: previously,
      );
      final first = list.firstWhere((a) => a.id == 'first_record');
      expect(first.isUnlocked, isTrue);
      expect(first.unlockedAt, now);
    });

    test('encode/decode 往返一致', () {
      final map = <String, DateTime>{
        'streak_3': day(2026, 2, 1),
        'first_record': day(2026, 1, 20),
      };
      final raw = encodeUnlockedMap(map);
      expect(decodeUnlockedMap(raw), map);
      expect(decodeUnlockedMap('not json'), isEmpty);
      expect(decodeUnlockedMap(null), isEmpty);
    });
  });
}
