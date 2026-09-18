import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:smart_wrong_notebook/src/data/remote/backend/auth_session_store.dart';
import 'package:smart_wrong_notebook/src/data/repositories/question_repository.dart';
import 'package:smart_wrong_notebook/src/data/services/question_cloud_sync.dart';
import 'package:smart_wrong_notebook/src/domain/models/question_record.dart';

/// 错题同步仓库：委托给本地存储（Drift），并在本地写操作后把改动推送到服务器。
///
/// 同步是「尽力而为、不阻塞」：写操作先落本地再异步推送；后端不可达或未登录时
/// 静默跳过并把题目标记为待同步，等下次已登录的同步（flushPending）整量补推
/// （upsert 幂等，能自愈离线期间产生的差异）。
///
/// 未同步/拉回不影响本地读写——本机始终是即时可用的编辑器。
class SyncingQuestionRepository implements QuestionRepository {
  SyncingQuestionRepository(this._inner, {QuestionCloudSync? sync})
      : _sync = sync ?? QuestionCloudSync();

  final QuestionRepository _inner;
  final QuestionCloudSync _sync;

  final Set<String> _pending = <String>{};
  bool _pulling = false;
  final List<void Function()> _pendingCallback = <void Function()>[];

  /// 拉取合并完成后通知（用于触发 UI 列表即时刷新）。
  final ChangeNotifier mergedNotifier = ChangeNotifier();

  bool get _authed => AuthSessionStore.currentToken.isNotEmpty;

  @override
  Future<List<QuestionRecord>> listAll() async {
    final records = await _inner.listAll();
    // 已登录且首次读取时，尝试拉回服务器数据 + 补推离线积压。
    if (_authed && !_pulling) {
      _pulling = true;
      unawaited(_syncInBackground());
    }
    return records;
  }

  @override
  Future<QuestionRecord?> getById(String id) => _inner.getById(id);

  @override
  Future<void> saveDraft(QuestionRecord record) async {
    await _inner.saveDraft(record);
    _markAndPush(record);
  }

  @override
  Future<void> saveDrafts(List<QuestionRecord> records) async {
    await _inner.saveDrafts(records);
    for (final record in records) {
      _markAndPush(record);
    }
  }

  @override
  Future<void> update(QuestionRecord record) async {
    await _inner.update(record);
    _markAndPush(record);
  }

  @override
  Future<void> delete(String id) async {
    await _inner.delete(id);
    _pending.remove(id);
    // 已登录则通知服务器删除（尽力而为）。
    if (_authed) {
      unawaited(_sync.deleteRemote(id).catchError((_) {}));
    }
  }

  void _markAndPush(QuestionRecord record) {
    if (!isSyncableRecord(record)) return;
    _pending.add(record.id);
    if (!_authed) return;
    unawaited(_pushNow(record.id));
  }

  /// 推单条；失败保留 pending，等下次 flushPending 补推。
  Future<void> _pushNow(String id) async {
    final record = await _inner.getById(id);
    if (record == null) return;
    try {
      final ok = await _sync.push(record);
      if (ok) _pending.remove(id);
    } catch (_) {
      // 离线/服务器异常：保留 pending，稍后重试。
    }
  }

  /// 把本地所有可同步错题整量补推到服务器（幂等）。用于登录/离线恢复后。
  Future<void> flushPending() async {
    if (!_authed) return;
    final records = await _inner.listAll();
    for (final record in records) {
      if (!isSyncableRecord(record)) continue;
      try {
        final ok = await _sync.push(record);
        if (ok) _pending.remove(record.id);
      } catch (_) {
        _pending.add(record.id);
      }
    }
  }

  /// 拉回服务器数据并合并进本地：仅补入本地缺失的记录（换设备/重装恢复）。
  /// 已存在的记录以本地为准（本机是最新编辑器），不覆盖。完成后触发回调刷新。
  Future<int> pullAndMerge() async {
    if (!_authed) return 0;
    List<QuestionRecord> remote;
    try {
      remote = await _sync.pull();
    } catch (_) {
      return 0;
    }
    final local = await _inner.listAll();
    final localIds = local.map((q) => q.id).toSet();
    var added = 0;
    for (final record in remote) {
      if (localIds.contains(record.id)) continue;
      await _inner.saveDraft(record);
      added++;
    }
    if (added > 0) {
      for (final cb in List.of(_pendingCallback)) {
        try {
          cb();
        } catch (_) {}
      }
      _pendingCallback.clear();
      mergedNotifier.notifyListeners();
    }
    return added;
  }

  /// 注册数据合并后的刷新回调（用于通知 Riverpod 重载列表）。
  void onMerged(void Function() callback) => _pendingCallback.add(callback);

  Future<void> _syncInBackground() async {
    try {
      await pullAndMerge();
      await flushPending();
    } finally {
      _pulling = false;
    }
  }
}
