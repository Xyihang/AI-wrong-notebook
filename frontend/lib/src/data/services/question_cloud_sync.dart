import 'dart:convert';

import 'package:smart_wrong_notebook/src/data/remote/backend/auth_session_store.dart';
import 'package:smart_wrong_notebook/src/data/remote/backend/backend_client.dart';
import 'package:smart_wrong_notebook/src/domain/models/content_status.dart';
import 'package:smart_wrong_notebook/src/domain/models/mastery_level.dart';
import 'package:smart_wrong_notebook/src/domain/models/question_record.dart';
import 'package:smart_wrong_notebook/src/domain/models/subject.dart';

/// 服务端错题（QuestionOut）mastery 文案。
const String _mMastered = '已掌握';
const String _mReviewing = '需巩固';
const String _mNew = '未掌握';

/// 把手机掌握度映射为服务端文案（与后端 MASTERY_LEVELS 一致）。
String masteryToServer(MasteryLevel level) => switch (level) {
      MasteryLevel.mastered => _mMastered,
      MasteryLevel.reviewing => _mReviewing,
      MasteryLevel.newQuestion => _mNew,
    };

/// 把服务端掌握度文案映射回手机枚举（未知回退 newQuestion）。
MasteryLevel masteryFromServer(String? value) {
  if (value == _mMastered) return MasteryLevel.mastered;
  if (value == _mReviewing) return MasteryLevel.reviewing;
  return MasteryLevel.newQuestion;
}

/// 判断某条本地错题是否适合同步到服务器：
/// - 已完成解析（ready，排除处理中草稿/分析队列里的临时题）；
/// - 有可同步的题干文字。
/// （整页拆分保存的子题以「独立错题」入库，也一并同步；它们可能带
///  parent_question_id 且 id 带后缀，服务器键见 [serverKeyForId]。）
bool isSyncableRecord(QuestionRecord q) =>
    q.contentStatus == ContentStatus.ready &&
    (q.normalizedQuestionText.trim().isNotEmpty ||
        q.extractedQuestionText.trim().isNotEmpty) &&
    q.id.isNotEmpty;

/// 派生一个可作服务器行键的稳定短 id：
/// - 长度 ≤36（后端 uuid 列）直接用原 id；
/// - 更长（如拆分后缀 `xxx-N`）用 FNV-1a(64) 十六进制（确定性、够小、冲突可忽略）。
/// 真实的客户端 id 始终完整存在 client_json 里，回拉时以它为准恢复，故无损。
String serverKeyForId(String clientId) {
  if (clientId.length <= 36) return clientId;
  var hash = 0xcbf29ce484222325; // FNV offset basis
  for (final unit in utf8.encode(clientId)) {
    hash ^= unit;
    hash = (hash * 0x100000001b3) & 0xFFFFFFFFFFFFFFFF; // FNV prime
  }
  return hash.toRadixString(16);
}

/// 手机 QuestionRecord -> 后端 QuestionCreate/Out 结构（无损：整条进 client_json）。
///
/// 供「新增/编辑即推送」使用；索引列（stem/subject/mastery/tags）取主要字段，
/// 完整记录原样放 client_json，保证换设备/回拉时可 1:1 恢复。
Map<String, dynamic> recordToServerMap(QuestionRecord q) {
  final text = q.normalizedQuestionText.trim().isNotEmpty
      ? q.normalizedQuestionText.trim()
      : q.extractedQuestionText.trim();
  return <String, dynamic>{
    'id': serverKeyForId(q.id),
    'subject': q.subject.name,
    'stem': text,
    'answer': q.analysisResult?.finalAnswer ?? '',
    'analysis': q.analysisResult?.finalAnswerDerivation ?? '',
    'mistake_reason': q.analysisResult?.mistakeReason ?? '',
    'knowledge_points': List<String>.from(q.aiKnowledgePoints),
    'tags': q.allTags,
    'mastery': masteryToServer(q.masteryLevel),
    'image_path': '',
    'ocr_text': q.extractedQuestionText,
    'created_at': q.createdAt.toUtc().toIso8601String(),
    'updated_at': q.updatedAt.toUtc().toIso8601String(),
    'review_count': q.reviewCount,
    'last_reviewed_at': q.lastReviewedAt?.toUtc().toIso8601String(),
    'client_json': jsonEncode(q.toJson()),
  };
}

/// 把后端返回的单条题目还原成手机 QuestionRecord。
/// 优先用 client_json 无损还原；缺失则用索引字段尽量重建。
QuestionRecord? recordFromServerMap(Map<String, dynamic> server) {
  final clientJson = server['client_json'];
  if (clientJson is String && clientJson.isNotEmpty) {
    try {
      final decoded = jsonDecode(clientJson);
      if (decoded is Map<String, dynamic>) {
        return QuestionRecord.fromJson(decoded);
      }
    } catch (_) {
      // 损坏则回退索引字段
    }
  }
  final id = server['id'];
  if (id is! String || id.isEmpty) return null;
  final text = (server['stem'] as String?) ?? '';
  final subjectName = (server['subject'] as String?) ?? '';
  final subject = Subject.values.firstWhere(
    (s) => s.name == subjectName,
    orElse: () => Subject.unknown,
  );
  return QuestionRecord.draft(
    id: id,
    imagePath: '',
    subject: subject,
    recognizedText: text,
  ).copyWith(
    contentStatus: ContentStatus.ready,
    masteryLevel: masteryFromServer(server['mastery'] as String?),
    aiKnowledgePoints: List<String>.from(
        (server['knowledge_points'] as List?) ?? const <dynamic>[]),
    aiTags: List<String>.from((server['tags'] as List?) ?? const <dynamic>[]),
    reviewCount: (server['review_count'] as num?)?.toInt() ?? 0,
    lastReviewedAt: server['last_reviewed_at'] is String
        ? DateTime.tryParse(server['last_reviewed_at'] as String)
        : null,
  );
}

/// 云端同步客户端：负责把本地错题推到服务器 / 从服务器拉回 / 删除。
///
/// 自动读取全局 [AuthSessionStore.currentToken]，未登录或后端不可达时优雅降级：
/// - 未登录：push/delete 直接跳过（本地仍是权威编辑器，登录后再同步）；
/// - 后端不可达：抛出可捕获的异常，由调用方保留本地数据稍后重试。
class QuestionCloudSync {
  QuestionCloudSync({BackendClient? backend})
      : _backend = backend ?? BackendClient();

  final BackendClient _backend;

  bool get _authed => AuthSessionStore.currentToken.isNotEmpty;

  /// 推送单条（upsert，幂等）。返回 true 表示已同步。
  Future<bool> push(QuestionRecord q) async {
    if (!_authed || !isSyncableRecord(q)) return false;
    await _backend.saveQuestion(recordToServerMap(q));
    return true;
  }

  /// 删除服务器上的记录（按本地 id 派生服务器键）。
  Future<void> deleteRemote(String id) async {
    if (!_authed || id.isEmpty) return;
    await _backend.deleteQuestions(<String>[serverKeyForId(id)]);
  }

  /// 拉回当前账号全部错题（返回还原后的手机记录列表，未做本地合并）。
  Future<List<QuestionRecord>> pull() async {
    if (!_authed) return const <QuestionRecord>[];
    final items = await _backend.fetchQuestions();
    final records = <QuestionRecord>[];
    for (final item in items) {
      final r = recordFromServerMap(item);
      if (r != null) records.add(r);
    }
    return records;
  }
}
