import 'package:uuid/uuid.dart';
import 'package:smart_wrong_notebook/src/data/repositories/question_repository.dart';
import 'package:smart_wrong_notebook/src/domain/models/mastery_level.dart';
import 'package:smart_wrong_notebook/src/domain/models/question_record.dart';
import 'package:smart_wrong_notebook/src/domain/models/review_log.dart';
import 'package:smart_wrong_notebook/src/domain/repositories/review_log_repository.dart';
import 'package:smart_wrong_notebook/src/domain/services/forgetting_curve.dart';

class ReviewController {
  ReviewController({
    required QuestionRepository repository,
    ReviewLogRepository? logRepository,
  })  : _repository = repository,
        _logRepository = logRepository;

  factory ReviewController.fake() => ReviewController(
        repository: InMemoryQuestionRepository(),
        logRepository: InMemoryReviewLogRepository(),
      );

  final QuestionRepository _repository;
  final ReviewLogRepository? _logRepository;

  Future<QuestionRecord> markMastered(String id) async {
    final question = await _repository.getById(id);
    if (question == null) {
      throw ArgumentError('Question not found: $id');
    }
    final updated = question.copyWith(
      masteryLevel: MasteryLevel.mastered,
      reviewCount: question.reviewCount + 1,
      lastReviewedAt: DateTime.now(), // 遗忘曲线依赖上次复习时间
    );
    await _repository.update(updated);
    await _writeLog(id, 'mastered', MasteryLevel.mastered);
    return updated;
  }

  Future<QuestionRecord> markReviewing(String id) async {
    final question = await _repository.getById(id);
    if (question == null) {
      throw ArgumentError('Question not found: $id');
    }
    final updated = question.copyWith(
      masteryLevel: MasteryLevel.reviewing,
      reviewCount: question.reviewCount + 1,
      lastReviewedAt: DateTime.now(), // 遗忘曲线依赖上次复习时间
    );
    await _repository.update(updated);
    await _writeLog(id, 'reviewing', MasteryLevel.reviewing);
    return updated;
  }

  Future<QuestionRecord> resetToNew(String id) async {
    final question = await _repository.getById(id);
    if (question == null) {
      throw ArgumentError('Question not found: $id');
    }
    final updated = question.copyWith(
      masteryLevel: MasteryLevel.newQuestion,
      reviewCount: 0, // 重置后回到首次，间隔回 1 天
      lastReviewedAt: DateTime.now(),
    );
    await _repository.update(updated);
    await _writeLog(id, 'reset', MasteryLevel.newQuestion);
    return updated;
  }

  Future<List<QuestionRecord>> getDueQuestions() async {
    final all = await _repository.listAll();
    return all.where(isDue).toList();
  }

  Future<void> _writeLog(String questionId, String result, MasteryLevel masteryAfter) async {
    final repo = _logRepository;
    if (repo == null) return;
    final log = ReviewLog(
      id: const Uuid().v4(),
      questionRecordId: questionId,
      reviewedAt: DateTime.now(),
      result: result,
      masteryAfter: masteryAfter,
    );
    await repo.insert(log);
  }
}
