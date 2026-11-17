/// 全局应用配置（集中管理环境相关常量）。
///
/// ⚠️ 重要：以后若更换云端 CVM / 服务器，**只需要修改 [apiBaseUrl] 这一个值**，
/// 其它所有依赖后端地址的代码都会自动跟随，无需到处改。
class AppConfig {
  AppConfig._();

  /// 后端 REST API 基础地址（默认云端 CVM）。
  ///
  /// 可通过构建时全局变量覆盖（无需改源码）：
  ///   flutter build apk --dart-define=API_BASE_URL=http://192.168.31.236:8000/api
  /// 未指定时用 [defaultApiBaseUrl]（云端）。
  ///
  /// 默认后端地址（远程配置拉取失败时的兜底）。
  ///
  /// 运行时优先使用远程配置仓库里的 apiBaseUrl（见 BackendConfigResolver），
  /// 因此换服务器只需改配置仓库，不必重新打包。
  static const String defaultApiBaseUrl = 'http://8.213.136.134/api';

  /// 构建期从 --dart-define=API_BASE_URL=... 注入；未指定时用 [defaultApiBaseUrl]。
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
