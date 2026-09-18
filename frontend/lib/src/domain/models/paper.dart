/// AI 变式组卷 领域模型。
class PaperQuestion {
  const PaperQuestion({
    required this.stem,
    required this.options,
    required this.answer,
    required this.analysis,
    required this.difficulty,
    required this.knowledgePoints,
    required this.questionType,
    required this.source,
    this.sourceQuestionId,
  });

  factory PaperQuestion.fromJson(Map<String, dynamic> json) {
    return PaperQuestion(
      stem: json['stem'] as String? ?? '',
      options:
          List<String>.from(json['options'] as List? ?? const <dynamic>[]),
      answer: json['answer'] as String? ?? '',
      analysis: json['analysis'] as String? ?? '',
      difficulty: json['difficulty'] as String? ?? '中等',
      knowledgePoints: List<String>.from(
          json['knowledge_points'] as List? ?? const <dynamic>[]),
      questionType: json['question_type'] as String? ?? '',
      source: json['source'] as String? ?? 'ai',
      sourceQuestionId: json['source_question_id'] as String?,
    );
  }

  final String stem;
  final List<String> options;
  final String answer;
  final String analysis;
  final String difficulty;
  final List<String> knowledgePoints;
  final String questionType;
  final String source; // existing=本人错题 / ai=AI 变式
  final String? sourceQuestionId;

  bool get isExisting => source == 'existing';

  /// 导出到后端 PDF 所需的字段映射（snake_case）。
  Map<String, dynamic> toExportMap() => <String, dynamic>{
        'stem': stem,
        'options': options,
        'answer': answer,
        'analysis': analysis,
        'difficulty': difficulty,
        'knowledge_points': knowledgePoints,
        'question_type': questionType,
        'source': source,
        'source_question_id': sourceQuestionId,
      };
}

class PaperResult {
  const PaperResult({
    required this.title,
    required this.subject,
    required this.questions,
  });

  factory PaperResult.fromJson(Map<String, dynamic> json) {
    return PaperResult(
      title: json['title'] as String? ?? '',
      subject: json['subject'] as String? ?? '',
      questions: ((json['questions'] as List?) ?? const <dynamic>[])
          .whereType<Map>()
          .map((q) => PaperQuestion.fromJson(Map<String, dynamic>.from(q)))
          .toList(),
    );
  }

  final String title;
  final String subject;
  final List<PaperQuestion> questions;
}
