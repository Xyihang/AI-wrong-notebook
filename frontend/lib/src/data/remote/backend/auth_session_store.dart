/// 全局登录 token 持有者。
///
/// 因为 [BackendClient] 在多个地方被临时 new 出来（OCR / 分析 / 额度查询），
/// 无法统一通过 Riverpod 注入，故用一个进程级全局持有当前登录 token。
/// 登录 / 自动登录 / 退出时由 [AuthController] 更新它；[BackendClient] 的
/// Dio 拦截器据此自动附加 `Authorization: Bearer <token>`。
class AuthSessionStore {
  AuthSessionStore._();

  static String currentToken = '';

  /// 是否已登录（有 token）。
  static bool get isLoggedIn => currentToken.isNotEmpty;
}
