import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:smart_wrong_notebook/src/core/constants/app_config.dart';

/// 从远程配置仓库解析「后端地址」，实现换服务器不用重新打包 App。
///
/// 配置仓库：https://github.com/Xyihang/ai-wrong-backend-config
/// 文件：backend-config.json，内容形如：
///   { "apiBaseUrl": "http://1.2.3.4/api" }
///
/// 多源并行（谁先返回用谁），并缓存到本地；全部失败时用上次缓存或打包默认值：
/// 1. GitHub API（手机网络实测可达 api.github.com）
/// 2. Gitee raw（国内可达）
/// 3. GitHub raw
class BackendConfigResolver {
  BackendConfigResolver({Dio? dio})
      : _dio = dio ??
            Dio(BaseOptions(
              connectTimeout: const Duration(seconds: 4),
              receiveTimeout: const Duration(seconds: 5),
            ));

  final Dio _dio;

  static const String _cacheKey = 'remote_api_base_url';
  static const String _cacheAtKey = 'remote_api_base_url_at';

  static const String _ghApi =
      'https://api.github.com/repos/Xyihang/ai-wrong-backend-config/contents/backend-config.json';
  static const String _ghRaw =
      'https://raw.githubusercontent.com/Xyihang/ai-wrong-backend-config/main/backend-config.json';
  static const String _giteeRaw =
      'https://gitee.com/Xyihang/ai-wrong-backend-config/raw/master/backend-config.json';

  /// 解析并应用后端地址。任何异常都静默降级，不阻塞启动。
  Future<String> resolve() async {
    SharedPreferences? prefs;
    try {
      prefs = await SharedPreferences.getInstance();
      final cached = prefs.getString(_cacheKey);
      if (_isValidUrl(cached)) {
        AppConfig.currentBaseUrl = _normalize(cached!);
      }
    } catch (_) {}

    try {
      final url = await Future.any(<Future<String>>[
        _fetchFromGitHubApi(),
        _fetchFromRaw(_ghRaw),
        _fetchFromRaw(_giteeRaw),
      ]).timeout(const Duration(seconds: 6));
      if (_isValidUrl(url)) {
        AppConfig.currentBaseUrl = _normalize(url);
        await prefs?.setString(_cacheKey, AppConfig.currentBaseUrl);
        await prefs?.setString(
            _cacheAtKey, DateTime.now().toIso8601String());
      }
    } catch (_) {
      // 远程不可达：保留缓存/默认地址。
    }
    return AppConfig.currentBaseUrl;
  }

  Future<String> _fetchFromGitHubApi() async {
    final resp = await _dio.get<dynamic>(_ghApi, options: Options(
      responseType: ResponseType.json,
      headers: <String, String>{'Accept': 'application/vnd.github+json'},
    ));
    final data = resp.data;
    if (data is! Map) throw const FormatException('bad github api response');
    final content = data['content'];
    if (content is! String || content.isEmpty) {
      throw const FormatException('empty content');
    }
    final decoded = utf8.decode(base64.decode(content.replaceAll('\n', '')));
    return _extractUrl(decoded);
  }

  Future<String> _fetchFromRaw(String url) async {
    final resp = await _dio.get<dynamic>(url,
        options: Options(responseType: ResponseType.plain));
    final data = resp.data;
    return _extractUrl(data is String ? data : data.toString());
  }

  String _extractUrl(String body) {
    final text = body.trim();
    if (text.isEmpty) throw const FormatException('empty body');
    final decoded = jsonDecode(text);
    final url = decoded is Map ? decoded['apiBaseUrl'] : null;
    if (url is! String || !_isValidUrl(url)) {
      throw const FormatException('invalid apiBaseUrl');
    }
    return url;
  }

  bool _isValidUrl(String? url) {
    if (url == null) return false;
    final v = url.trim().toLowerCase();
    return v.startsWith('http://') || v.startsWith('https://');
  }

  String _normalize(String url) {
    var v = url.trim();
    while (v.endsWith('/')) {
      v = v.substring(0, v.length - 1);
    }
    return v;
  }
}
