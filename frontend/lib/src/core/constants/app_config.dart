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
  /// 默认：腾讯云轻量服务器 Ubuntu-xx8Q（公网 123.207.238.74），Docker 后端监听 8000。
  static const String defaultApiBaseUrl = 'http://123.207.238.74:8000/api';

  /// 构建期从 --dart-define=API_BASE_URL=... 注入；未指定时用 [defaultApiBaseUrl]。
  static const String apiBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: defaultApiBaseUrl,
  );
}
