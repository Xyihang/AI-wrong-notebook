import 'package:smart_wrong_notebook/src/domain/models/question_record.dart';
import 'package:smart_wrong_notebook/src/domain/models/subject.dart';

/// 相似命中方式，对应后端 `/retrieval/match` 返回的 `matched_by` 字段
/// （`vector | tag | both`）。
enum SimilarMatchedBy {
  vector('向量'),
  tag('标签'),
  both('向量+标签');

  const SimilarMatchedBy(this.label);

  /// 展示用中文标签。
  final String label;

  /// 解析后端字段值（大小写不敏感，兼容 `matchedBy` 驼峰写法）。
  static SimilarMatchedBy parse(Object? value) {
    final text = value?.toString().trim().toLowerCase() ?? '';
    if (text.contains('both')) return SimilarMatchedBy.both;
    if (text.contains('vector')) return SimilarMatchedBy.vector;
    if (text.contains('tag')) return SimilarMatchedBy.tag;
    for (final item in SimilarMatchedBy.values) {
      if (item.name == text) return item;
    }
    return SimilarMatchedBy.both;
  }
}

/// 后端 QuestionRecord JSON（见 docs/spec.md §7.1）的轻量摘要视图。
///
/// 只保留「相似错题弹窗」展示所需字段（题干、错因、答案、收录时间、
/// 缩略图、知识点等），不依赖本地持久化模型，避免把后端 `stem/answer/
/// mistake_reason/image_path/created_at` 硬塞进本地 [QuestionRecord]。
class SimilarQuestionSummary {
  const SimilarQuestionSummary({
    required this.id,
    required this.subject,
    this.knowledgePoints = const <String>[],
    this.questionType,
    this.difficulty,
    required this.stem,
    this.options = const <String>[],
    required this.answer,
    this.analysis = '',
    required this.mistakeReason,
    this.mastery,
    this.tags = const <String>[],
    this.imagePath,
    this.ocrText = '',
    this.latexText = '',
    this.createdAt,
    this.contentFormat = QuestionContentFormat.plain,
  });

  factory SimilarQuestionSummary.fromJson(Map<String, dynamic> json) {
    final stem = _string(json['stem']) ?? _string(json['ocr_text']) ?? '';
    final answer = _string(json['answer']) ?? '';
    final analysis = _string(json['analysis']) ?? '';
    final mistakeReason = _string(json['mistake_reason']) ?? '';
    final latexText = _string(json['latex_text']) ?? '';
    final knowledgePoints = _stringList(json['knowledge_points']);
    return SimilarQuestionSummary(
      id: _string(json['id']) ?? '',
      subject: _parseSubject(_string(json['subject'])),
      knowledgePoints: knowledgePoints.isEmpty
          ? _stringList(json['tags'])
          : knowledgePoints,
      questionType: _string(json['question_type']),
      difficulty: _string(json['difficulty']),
      stem: stem,
      options: _stringList(json['options']),
      answer: answer,
      analysis: analysis,
      mistakeReason: mistakeReason,
      mastery: _string(json['mastery']),
      tags: _stringList(json['tags']),
      imagePath: _string(json['image_path']) ?? _string(json['imagePath']),
      ocrText: _string(json['ocr_text']) ?? '',
      latexText: latexText,
      createdAt: _date(json['created_at']) ?? _date(json['createdAt']),
      contentFormat: _detectContentFormat(<String>[
        stem,
        answer,
        analysis,
        latexText,
      ]),
    );
  }

  /// 错题 id（对应本地 QuestionRecord.id，用于跳转详情页）。
  final String id;

  /// 科目（后端中文名映射到 [Subject]，未知时为 [Subject.unknown]）。
  final Subject subject;

  /// 多层级知识点，如 `['初中', '几何', '圆']`。
  final List<String> knowledgePoints;

  /// 题型，如「解答题」。
  final String? questionType;

  /// 难度，如「中等」。
  final String? difficulty;

  /// 题干（后端 `stem`）。
  final String stem;

  /// 选项。
  final List<String> options;

  /// 订正答案。
  final String answer;

  /// 解析。
  final String analysis;

  /// 错因。
  final String mistakeReason;

  /// 掌握程度，如「未掌握」。
  final String? mastery;

  /// 标签。
  final List<String> tags;

  /// 原题缩略图（本地路径或 http(s) URL，可为 null）。
  final String? imagePath;

  /// OCR 原文。
  final String ocrText;

  /// LaTeX 原文。
  final String latexText;

  /// 收录时间。
  final DateTime? createdAt;

  /// 内容格式（按题干/答案是否含 LaTeX 自动判定）。
  final QuestionContentFormat contentFormat;

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'id': id,
      'subject': subject.name,
      'knowledge_points': knowledgePoints,
      'question_type': questionType,
      'difficulty': difficulty,
      'stem': stem,
      'options': options,
      'answer': answer,
      'analysis': analysis,
      'mistake_reason': mistakeReason,
      'mastery': mastery,
      'tags': tags,
      'image_path': imagePath,
      'ocr_text': ocrText,
      'latex_text': latexText,
      'created_at': createdAt?.toIso8601String(),
      'content_format': contentFormat.name,
    };
  }
}

/// 一条同类错题匹配结果，对应后端 `/retrieval/match` 响应 items 元素：
/// `{question: {...QuestionRecord JSON...}, similarity: 0.9, matched_by: "vector|tag|both"}`。
class SimilarMatch {
  const SimilarMatch({
    required this.question,
    required this.similarity,
    required this.matchedBy,
  });

  factory SimilarMatch.fromJson(Map<String, dynamic> json) {
    final questionJson = json['question'];
    return SimilarMatch(
      question: questionJson is Map
          ? SimilarQuestionSummary.fromJson(
              Map<String, dynamic>.from(questionJson))
          : const SimilarQuestionSummary(
              id: '',
              subject: Subject.unknown,
              stem: '',
              answer: '',
              mistakeReason: '',
            ),
      similarity: _similarity(json['similarity']),
      matchedBy:
          SimilarMatchedBy.parse(json['matched_by'] ?? json['matchedBy']),
    );
  }

  /// 相似的历史错题摘要。
  final SimilarQuestionSummary question;

  /// 相似度（0~1，如 0.9）。
  final double similarity;

  /// 命中方式：向量 / 标签 / 两者。
  final SimilarMatchedBy matchedBy;

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'question': question.toJson(),
      'similarity': similarity,
      'matched_by': matchedBy.name,
    };
  }
}

/// 解析后端 `/retrieval/match` 响应，读取 `items` 数组。
///
/// 同时兼容 `similar_matches` / `matches` 键，便于本地缓存复用同一解析逻辑；
/// 单条脏数据会被跳过，不拖垮整批解析。
List<SimilarMatch> parseSimilarMatches(Map<String, dynamic> response) {
  final raw = response['items'] ??
      response['similar_matches'] ??
      response['matches'];
  if (raw is! List) return const <SimilarMatch>[];
  final result = <SimilarMatch>[];
  for (final item in raw) {
    if (item is! Map) continue;
    try {
      result.add(SimilarMatch.fromJson(Map<String, dynamic>.from(item)));
    } catch (_) {
      // 忽略单条解析失败的匹配项。
    }
  }
  return result;
}

String? _string(Object? value) {
  if (value == null) return null;
  final text = value.toString().trim();
  return text.isEmpty ? null : text;
}

List<String> _stringList(Object? value) {
  if (value is! List) return const <String>[];
  return value
      .whereType<String>()
      .map((item) => item.trim())
      .where((item) => item.isNotEmpty)
      .toList();
}

DateTime? _date(Object? value) {
  if (value == null) return null;
  return DateTime.tryParse(value.toString());
}

Subject _parseSubject(Object? value) {
  final text = _string(value);
  if (text == null) return Subject.unknown;
  for (final subject in Subject.values) {
    if (subject.name == text || subject.label == text) return subject;
  }
  return Subject.unknown;
}

double _similarity(Object? value) {
  final parsed = value is num
      ? value.toDouble()
      : double.tryParse(value?.toString() ?? '');
  if (parsed == null) return 0.0;
  return parsed.clamp(0.0, 1.0).toDouble();
}

QuestionContentFormat _detectContentFormat(List<String> texts) {
  for (final text in texts) {
    if (_looksLikeLatex(text)) return QuestionContentFormat.latexMixed;
  }
  return QuestionContentFormat.plain;
}

bool _looksLikeLatex(String value) {
  if (value.contains(r'$$') ||
      value.contains(r'\(') ||
      value.contains(r'\)') ||
      value.contains(r'\[') ||
      value.contains(r'\]')) {
    return true;
  }
  return RegExp(r'\$[^$\n]+\$').hasMatch(value) ||
      RegExp(r'\\(frac|sqrt|begin|mathrm|text|times|cdot|leq|geq|pm|left|right)\b')
          .hasMatch(value);
}
