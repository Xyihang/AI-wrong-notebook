import 'subject.dart';

enum AnalysisConsistencyStatus {
  unchecked,
  consistent,
  repaired,
  needsReview,
  unverifiable,
}

enum VisualAssumptionStatus {
  none,
  reliable,
  needsReview,
}

class VisualMeasurementAssumption {
  const VisualMeasurementAssumption({
    required this.label,
    required this.meaning,
    this.usedInSolution = false,
    this.evidence = '',
    this.confidence = '',
  });

  factory VisualMeasurementAssumption.fromJson(Map<String, dynamic> json) {
    return VisualMeasurementAssumption(
      label: json['label'] as String? ?? '',
      meaning: json['meaning'] as String? ?? '',
      usedInSolution: json['usedInSolution'] as bool? ?? false,
      evidence: json['evidence'] as String? ?? '',
      confidence: json['confidence'] as String? ?? '',
    );
  }

  final String label;
  final String meaning;
  final bool usedInSolution;
  final String evidence;
  final String confidence;

  Map<String, dynamic> toJson() {
    return {
      'label': label,
      'meaning': meaning,
      'usedInSolution': usedInSolution,
      'evidence': evidence,
      'confidence': confidence,
    };
  }
}

class VisualAssumptions {
  const VisualAssumptions({
    this.targetObject = '',
    this.targetQuestion = '',
    this.measurements = const [],
    this.solutionBasis = const [],
    this.uncertainItems = const [],
    this.needsManualReview = false,
    this.reviewReason = '',
  });

  factory VisualAssumptions.fromJson(Map<String, dynamic> json) {
    final measurementsJson = json['measurements'] as List? ?? const <Object>[];
    return VisualAssumptions(
      targetObject: json['targetObject'] as String? ?? '',
      targetQuestion: json['targetQuestion'] as String? ?? '',
      measurements: measurementsJson
          .whereType<Map>()
          .map((item) => VisualMeasurementAssumption.fromJson(
                Map<String, dynamic>.from(item),
              ))
          .toList(),
      solutionBasis:
          List<String>.from(json['solutionBasis'] as List? ?? const <String>[]),
      uncertainItems: List<String>.from(
          json['uncertainItems'] as List? ?? const <String>[]),
      needsManualReview: json['needsManualReview'] as bool? ?? false,
      reviewReason: json['reviewReason'] as String? ?? '',
    );
  }

  final String targetObject;
  final String targetQuestion;
  final List<VisualMeasurementAssumption> measurements;
  final List<String> solutionBasis;
  final List<String> uncertainItems;
  final bool needsManualReview;
  final String reviewReason;

  bool get hasContent =>
      targetObject.isNotEmpty ||
      targetQuestion.isNotEmpty ||
      measurements.isNotEmpty ||
      solutionBasis.isNotEmpty ||
      uncertainItems.isNotEmpty ||
      reviewReason.isNotEmpty;

  Map<String, dynamic> toJson() {
    return {
      'targetObject': targetObject,
      'targetQuestion': targetQuestion,
      'measurements': measurements.map((item) => item.toJson()).toList(),
      'solutionBasis': solutionBasis,
      'uncertainItems': uncertainItems,
      'needsManualReview': needsManualReview,
      'reviewReason': reviewReason,
    };
  }
}

class AnalysisResult {
  const AnalysisResult({
    required this.finalAnswer,
    required this.steps,
    required this.aiTags,
    required this.knowledgePoints,
    required this.mistakeReason,
    required this.studyAdvice,
    this.subject,
    this.finalAnswerDerivation = '',
    this.reconstructedQuestionText = '',
    this.visualAssumptions,
    this.visualAssumptionStatus = VisualAssumptionStatus.none,
    this.consistencyStatus = AnalysisConsistencyStatus.unchecked,
    this.consistencyNote = '',
    this.wasVerifierUsed = false,
  });

  factory AnalysisResult.fromJson(Map<String, dynamic> json) {
    final subjectStr = json['subject'] as String?;
    Subject? subject;
    if (subjectStr != null && subjectStr.isNotEmpty) {
      subject = _parseSubject(subjectStr);
    }

    return AnalysisResult(
      subject: subject,
      finalAnswer: json['finalAnswer'] as String? ?? '',
      finalAnswerDerivation: json['finalAnswerDerivation'] as String? ?? '',
      reconstructedQuestionText:
          json['reconstructedQuestionText'] as String? ?? '',
      visualAssumptions: _parseVisualAssumptions(json['visualAssumptions']),
      visualAssumptionStatus: _parseVisualAssumptionStatus(
        json['visualAssumptionStatus'] as String?,
      ),
      steps: List<String>.from(json['steps'] as List? ?? []),
      aiTags: List<String>.from(json['aiTags'] as List? ?? []),
      knowledgePoints:
          List<String>.from(json['knowledgePoints'] as List? ?? []),
      mistakeReason: json['mistakeReason'] as String? ?? '',
      studyAdvice: json['studyAdvice'] as String? ?? '',
      consistencyStatus: _parseConsistencyStatus(
        json['consistencyStatus'] as String?,
      ),
      consistencyNote: json['consistencyNote'] as String? ?? '',
      wasVerifierUsed: json['wasVerifierUsed'] as bool? ?? false,
    );
  }

  static Subject? _parseSubject(String input) {
    final lower = input.toLowerCase();

    for (final s in Subject.values) {
      if (s.label == input || s.name == input) {
        return s;
      }
    }

    if (lower.contains('物理') || lower == 'wuli' || lower == 'physics') {
      return Subject.physics;
    }
    if (lower.contains('语文') || lower == 'chinese' || lower == 'chinese') {
      return Subject.chinese;
    }
    if (lower.contains('英语') ||
        lower == 'english' ||
        lower.contains('english')) {
      return Subject.english;
    }
    if (lower.contains('化学') || lower == 'chemistry') {
      return Subject.chemistry;
    }
    if (lower.contains('生物') || lower == 'biology') {
      return Subject.biology;
    }
    if (lower.contains('历史') || lower == 'history') {
      return Subject.history;
    }
    if (lower.contains('地理') || lower == 'geography') {
      return Subject.geography;
    }
    if (lower.contains('政治') || lower == 'politics') {
      return Subject.politics;
    }
    if (lower.contains('科学') || lower == 'science') {
      return Subject.science;
    }
    if (lower.contains('数学') ||
        lower == 'math' ||
        lower.contains('mathematics')) {
      return Subject.math;
    }

    return null;
  }

  static AnalysisConsistencyStatus _parseConsistencyStatus(String? value) {
    for (final status in AnalysisConsistencyStatus.values) {
      if (status.name == value) return status;
    }
    return AnalysisConsistencyStatus.unchecked;
  }

  static VisualAssumptionStatus _parseVisualAssumptionStatus(String? value) {
    for (final status in VisualAssumptionStatus.values) {
      if (status.name == value) return status;
    }
    return VisualAssumptionStatus.none;
  }

  static VisualAssumptions? _parseVisualAssumptions(Object? value) {
    if (value is Map<String, dynamic>) {
      return VisualAssumptions.fromJson(value);
    }
    if (value is Map) {
      return VisualAssumptions.fromJson(Map<String, dynamic>.from(value));
    }
    return null;
  }

  Map<String, dynamic> toJson() {
    return {
      'subject': subject?.label ?? subject?.name ?? '',
      'finalAnswer': finalAnswer,
      'finalAnswerDerivation': finalAnswerDerivation,
      'reconstructedQuestionText': reconstructedQuestionText,
      'visualAssumptions': visualAssumptions?.toJson(),
      'visualAssumptionStatus': visualAssumptionStatus.name,
      'steps': steps,
      'aiTags': aiTags,
      'knowledgePoints': knowledgePoints,
      'mistakeReason': mistakeReason,
      'studyAdvice': studyAdvice,
      'consistencyStatus': consistencyStatus.name,
      'consistencyNote': consistencyNote,
      'wasVerifierUsed': wasVerifierUsed,
    };
  }

  final Subject? subject;
  final String finalAnswer;
  final String finalAnswerDerivation;
  final String reconstructedQuestionText;
  final VisualAssumptions? visualAssumptions;
  final VisualAssumptionStatus visualAssumptionStatus;
  final List<String> steps;
  final List<String> aiTags;
  final List<String> knowledgePoints;
  final String mistakeReason;
  final String studyAdvice;
  final AnalysisConsistencyStatus consistencyStatus;
  final String consistencyNote;
  final bool wasVerifierUsed;

  AnalysisResult copyWith({
    Subject? subject,
    String? finalAnswer,
    String? finalAnswerDerivation,
    String? reconstructedQuestionText,
    VisualAssumptions? visualAssumptions,
    VisualAssumptionStatus? visualAssumptionStatus,
    List<String>? steps,
    List<String>? aiTags,
    List<String>? knowledgePoints,
    String? mistakeReason,
    String? studyAdvice,
    AnalysisConsistencyStatus? consistencyStatus,
    String? consistencyNote,
    bool? wasVerifierUsed,
  }) {
    return AnalysisResult(
      subject: subject ?? this.subject,
      finalAnswer: finalAnswer ?? this.finalAnswer,
      finalAnswerDerivation:
          finalAnswerDerivation ?? this.finalAnswerDerivation,
      reconstructedQuestionText:
          reconstructedQuestionText ?? this.reconstructedQuestionText,
      visualAssumptions: visualAssumptions ?? this.visualAssumptions,
      visualAssumptionStatus:
          visualAssumptionStatus ?? this.visualAssumptionStatus,
      steps: steps ?? this.steps,
      aiTags: aiTags ?? this.aiTags,
      knowledgePoints: knowledgePoints ?? this.knowledgePoints,
      mistakeReason: mistakeReason ?? this.mistakeReason,
      studyAdvice: studyAdvice ?? this.studyAdvice,
      consistencyStatus: consistencyStatus ?? this.consistencyStatus,
      consistencyNote: consistencyNote ?? this.consistencyNote,
      wasVerifierUsed: wasVerifierUsed ?? this.wasVerifierUsed,
    );
  }
}
