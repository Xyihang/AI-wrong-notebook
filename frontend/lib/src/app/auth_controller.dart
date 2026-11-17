import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:smart_wrong_notebook/src/app/providers.dart';
import 'package:smart_wrong_notebook/src/data/remote/backend/auth_session_store.dart';
import 'package:smart_wrong_notebook/src/data/remote/backend/backend_client.dart';
import 'package:smart_wrong_notebook/src/data/repositories/settings_repository.dart';
import 'package:smart_wrong_notebook/src/domain/models/auth_session.dart';

/// 认证状态。
sealed class AuthState {
  const AuthState();
}

/// 启动中（尚未完成会话加载 / 校验）。
class AuthChecking extends AuthState {
  const AuthChecking();
}

/// 已登录。
class AuthAuthenticated extends AuthState {
  const AuthAuthenticated(this.session);
  final AuthSession session;
}

/// 未登录。
class AuthUnauthenticated extends AuthState {
  const AuthUnauthenticated();
}

/// 游客模式：未登录，数据只存本机；AI 使用用户自己配置的 Key（无额度限制）。
///
/// 每次启动 App 都不会自动恢复游客态——游客需在登录页重新选择，
/// 并且进入时会收到「建议登录云端同步」的提醒。
class AuthGuest extends AuthState {
  const AuthGuest();
}

/// 认证操作结果。
class AuthResult {
  const AuthResult.success()
      : success = true,
        error = null;
  const AuthResult.failure(this.error)
      : success = false;

  final bool success;
  final String? error;
}

/// settings 中持久化会话的键。
const String authSessionKey = 'auth_session';

/// 认证控制器：加载 / 登录 / 注册 / 退出，并维护 [AuthState]。
///
/// 同时把当前 token 写入全局 [AuthSessionStore]，使所有 BackendClient 请求
/// 自动携带 Authorization 头。暴露 [refreshListenable] 供 GoRouter 监听
/// 认证状态变化以触发路由重定向。
class AuthController extends StateNotifier<AuthState> {
  AuthController(this._settingsRepo, {BackendClient? backendClient})
      : _backendClient = backendClient ?? BackendClient(),
        super(const AuthChecking());

  final SettingsRepository _settingsRepo;
  final BackendClient _backendClient;

  // GoRouter refreshListenable：StateNotifier 本身不是 Listenable，
  // 用内部 ChangeNotifier 转发状态变化。
  final ChangeNotifier _notifier = ChangeNotifier();
  Listenable get refreshListenable => _notifier;

  /// 供外部（main.dart 路由守卫）安全读取当前状态。
  AuthState get currentState => state;

  void _setState(AuthState next) {
    state = next;
    _notifier.notifyListeners();
  }

  /// 启动时加载持久化会话并（尽力）校验。由 SplashScreen 调用一次。
  Future<void> load() async {
    final stored = AuthSession.tryParse(
      await _settingsRepo.getString(authSessionKey),
    );
    if (stored == null) {
      _setState(const AuthUnauthenticated());
      return;
    }

    // 先乐观写入 token，再尽力校验；后端不可达时保持登录态（自用更友好）。
    AuthSessionStore.currentToken = stored.token;
    final fresh = await _fetchMe(stored);
    if (fresh == null) {
      // token 失效 -> 清除并回到未登录
      await _clearSession();
      _setState(const AuthUnauthenticated());
    } else {
      await _persist(fresh);
      _setState(AuthAuthenticated(fresh));
    }
  }

  /// 尽力调用 /auth/me 刷新用户信息。
  /// 返回更新后的 session；401/格式异常返回 null；网络错误返回原 session（乐观）。
  Future<AuthSession?> _fetchMe(AuthSession stored) async {
    try {
      final me = await _backendClient.fetchCurrentUser();
      if (me == null) return null;
      return AuthSession(
        token: stored.token,
        userId: (me['id'] as String?) ?? stored.userId,
        username: (me['username'] as String?) ?? stored.username,
        displayName: (me['display_name'] as String?) ?? stored.displayName,
      );
    } on BackendClientException {
      // 后端不可达等网络问题：保持登录态（不阻塞启动）
      return stored;
    }
  }

  /// 登录。成功持久化会话并更新状态。
  Future<AuthResult> login(String username, String password) async {
    try {
      final data = await _backendClient.login(username.trim(), password);
      final token = data['access_token'];
      final user = data['user'];
      if (token is! String || token.isEmpty || user is! Map) {
        return const AuthResult.failure('登录响应异常，请重试');
      }
      final session = AuthSession(
        token: token,
        userId: (user['id'] as String?) ?? '',
        username: (user['username'] as String?) ?? username.trim(),
        displayName: (user['display_name'] as String?) ?? '',
      );
      await _persist(session);
      _setState(AuthAuthenticated(session));
      return const AuthResult.success();
    } on BackendClientException catch (e) {
      return AuthResult.failure(e.message);
    }
  }

  /// 注册：先注册，成功后自动登录。
  Future<AuthResult> register(
    String username,
    String password, {
    String displayName = '',
    required String captchaId,
    required String captchaAnswer,
  }) async {
    try {
      await _backendClient.register(
        username.trim(),
        password,
        displayName: displayName,
        captchaId: captchaId,
        captchaAnswer: captchaAnswer,
      );
      // 注册成功 -> 自动登录（register 不返回 token）
      return login(username.trim(), password);
    } on BackendClientException catch (e) {
      return AuthResult.failure(e.message);
    }
  }

  /// 进入游客模式：清除 token（避免带旧凭证），状态置为游客。
  Future<void> enterGuest() async {
    await _clearSession();
    _setState(const AuthGuest());
  }

  /// 退出登录：清除 token 与持久化会话。
  Future<void> logout() async {
    await _clearSession();
    _setState(const AuthUnauthenticated());
  }

  Future<void> _persist(AuthSession session) async {
    AuthSessionStore.currentToken = session.token;
    await _settingsRepo.setString(authSessionKey, session.toJson());
  }

  Future<void> _clearSession() async {
    AuthSessionStore.currentToken = '';
    await _settingsRepo.setString(authSessionKey, '');
  }

  @override
  void dispose() {
    _notifier.dispose();
    super.dispose();
  }
}

/// 认证状态 Provider。启动时由 SplashScreen 触发 [AuthController.load]。
final StateNotifierProvider<AuthController, AuthState> authControllerProvider =
    StateNotifierProvider<AuthController, AuthState>(
  (ref) => AuthController(ref.watch(settingsRepositoryProvider)),
);
