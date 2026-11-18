/// 全局应用配置（集中管理环境相关常量）。
///
/// 后端地址**不做预编译**：App 每次启动都会从远程配置仓库动态拉取
/// （Gitee / GitHub，见 BackendConfigResolver）；拉取失败时再退到上次缓存，
/// 仍没有时由用户在登录页手动填写服务器地址。
class AppConfig {
  AppConfig._();

  /// 预编译兜底地址：故意留空，避免指向已失效的旧服务器。
  /// 如需本地调试可这样注入：
  ///   flutter run --dart-define=API_BASE_URL=http://192.168.31.236:8000/api
  static const String defaultApiBaseUrl = '';

  /// 构建期从 --dart-define=API_BASE_URL=... 注入；未指定时为空。
  static const String apiBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: defaultApiBaseUrl,
  );

  /// 运行时实际使用的后端地址。
  ///
  /// App 启动时会尝试从远程配置仓库拉取最新地址（见 BackendConfigResolver），
  /// 成功后覆盖此值；因此以后更换服务器**无需重新打包 App**。
  static String currentBaseUrl = apiBaseUrl;
}
