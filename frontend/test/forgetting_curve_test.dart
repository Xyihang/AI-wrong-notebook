import 'package:flutter_test/flutter_test.dart';
import 'package:smart_wrong_notebook/src/domain/models/mastery_level.dart';
import 'package:smart_wrong_notebook/src/domain/models/question_record.dart';
import 'package:smart_wrong_notebook/src/domain/models/subject.dart';
import 'package:smart_wrong_notebook/src/domain/services/forgetting_curve.dart';

QuestionRecord _q({
  MasteryLevel mastery = MasteryLevel.newQuestion,
  int reviewCount = 0,
  DateTime? lastReviewedAt,
}) {
  return QuestionRecord.draft(
    id: 'q1',
    imagePath: '',
    subject: Subject.math,
    recognizedText: '测试题',
  ).copyWith(
    masteryLevel: mastery,
    reviewCount: reviewCount,
    lastReviewedAt: lastReviewedAt,
  );
}

void main() {
  group('遗忘曲线纯函数', () {
    test('新题立即到期', () {
      final q = _q();
      expect(isDue(q), isTrue);
      expect(nextReviewLabel(q), '新题 · 待首次复习');
    });

    test('已掌握不进待复习', () {
      final q = _q(
        mastery: MasteryLevel.mastered,
        reviewCount: 3,
        lastReviewedAt: DateTime(2026, 1, 8, 12),
      );
      expect(isDue(q, now: DateTime(2026, 1, 30)), isFalse);
      expect(intervalDaysFor(q), isNull);
      expect(nextReviewLabel(q), isNull);
    });

    test('reviewing 间隔按 reviewCount 指数增长', () {
      expect(intervalDaysFor(_q(mastery: MasteryLevel.reviewing, reviewCount: 1)), 1);
      expect(intervalDaysFor(_q(mastery: MasteryLevel.reviewing, reviewCount: 2)), 2);
      expect(intervalDaysFor(_q(mastery: MasteryLevel.reviewing, reviewCount: 3)), 4);
      expect(intervalDaysFor(_q(mastery: MasteryLevel.reviewing, reviewCount: 4)), 7);
      expect(intervalDaysFor(_q(mastery: MasteryLevel.reviewing, reviewCount: 5)), 15);
      expect(intervalDaysFor(_q(mastery: MasteryLevel.reviewing, reviewCount: 6)), 30);
      expect(intervalDaysFor(_q(mastery: MasteryLevel.reviewing, reviewCount: 99)), 30);
    });

    test('到期待复习', () {
      // reviewCount=1, last=1/8 12:00 -> next=1/9 12:00 -> 到期
      final q = _q(
        mastery: MasteryLevel.reviewing,
        reviewCount: 1,
        lastReviewedAt: DateTime(2026, 1, 8, 12),
      );
      expect(isDue(q, now: DateTime(2026, 1, 10, 12)), isTrue);
      expect(nextReviewLabel(q, now: DateTime(2026, 1, 10, 12)), '今天到期');
    });

    test('未到期不待复习，显示X天后', () {
      // reviewCount=5 -> 间隔15天, last=1/1 12:00 -> next=1/16 12:00 -> 未到期
      final q = _q(
        mastery: MasteryLevel.reviewing,
        reviewCount: 5,
        lastReviewedAt: DateTime(2026, 1, 1, 12),
      );
      final now = DateTime(2026, 1, 10, 12);
      expect(isDue(q, now: now), isFalse);
      expect(nextReviewLabel(q, now: now), '6 天后');
    });

    test('今天稍后到期（未到期但今天）', () {
      // reviewCount=1 -> 间隔1天, last=1/9 12:00 -> next=1/10 12:00, now=1/10 11:00 未到
      final q = _q(
        mastery: MasteryLevel.reviewing,
        reviewCount: 1,
        lastReviewedAt: DateTime(2026, 1, 9, 12),
      );
      final now = DateTime(2026, 1, 10, 11);
      expect(isDue(q, now: now), isFalse);
      expect(nextReviewLabel(q, now: now), '今天');
    });
  });
}
