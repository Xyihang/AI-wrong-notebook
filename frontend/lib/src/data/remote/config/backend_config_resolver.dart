import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:smart_wrong_notebook/src/core/constants/app_config.dart';

/// 从远程配置仓库解析「后端地址」，实现换服务器不用重新打包 App。
///
/// 配置仓库（两个镜像，任选其一更新即可）：
/// - Gitee（国内首选）：https://gitee.com/xiyihang360/ai-wrong-backend-config
/// - GitHub：https://github.com/Xyihang/ai-wrong-backend-config
/// 文件：backend-config.json，内容形如：
///   { "apiBaseUrl": "http://1.2.3.4/api" }
///
/// **每次启动都动态拉取**，多源并行（谁先成功用谁）：
/// 1. Gitee API v5（实测无需登录可读，国内可达，首选）
/// 2. GitHub API
/// 3. Gitee raw
/// 4. GitHub raw
/// 全部失败时才使用上次缓存（仅离线兜底）；用户无需、也不能手动填写地址。
class BackendConfigResolver {
  BackendConfigResolver({Dio? dio})
      : _dio = dio ??
            Dio(BaseOptions(
              connectTimeout: const Duration(seconds: 8),
              receiveTimeout: const Duration(seconds: 10),
              headers: <String, String>{'User-Agent': 'AI-Wrong-App'},
            ));

  final Dio _dio;

  static const String _cacheKey = 'remote_api_base_url';
  static const String _cacheAtKey = 'remote_api_base_url_at';

  static const String _giteeApi =
      'https://gitee.com/api/v5/repos/xiyihang360/ai-wrong-backend-config/contents/backend-config.json';
  static const String _giteeRaw =
      'https://gitee.com/xiyihang360/ai-wrong-backend-config/raw/master/backend-config.json';
  static const String _ghApi =
      'https://api.github.com/repos/Xyihang/ai-wrong-backend-config/contents/backend-config.json';
  static const String _ghRaw =
      'https://raw.githubusercontent.com/Xyihang/ai-wrong-backend-config/main/backend-config.json';

  /// 解析并应用后端地址。任何异常都静默降级，不阻塞启动。
  Future<String> resolve() async {
    SharedPreferences? prefs;
    try {
      prefs = await SharedPreferences.getInstance();
    } catch (_) {}

    String? resolved;
    try {
      resolved = await Future.any(<Future<String>>[
        _fetchFromGiteeApi(),
        _fetchFromGitHubApi(),
        _fetchFromRaw(_giteeRaw),
        _fetchFromRaw(_ghRaw),
      ]).timeout(const Duration(seconds: 12));
    } catch (_) {
      resolved = null;
    }

    if (_isValidUrl(resolved)) {
      AppConfig.currentBaseUrl = _normalize(resolved!);
      try {
        await prefs?.setString(_cacheKey, AppConfig.currentBaseUrl);
        await prefs?.setString(_cacheAtKey, DateTime.now().toIso8601String());
      } catch (_) {}
      return AppConfig.currentBaseUrl;
    }

    // 全部远程源失败：仅此时使用上次缓存兜底（离线场景）。
    try {
      final cached = prefs?.getString(_cacheKey);
      if (_isValidUrl(cached)) {
        AppConfig.currentBaseUrl = _normalize(cached!);
      }
    } catch (_) {}
    return AppConfig.currentBaseUrl;
  }

  Future<String> _fetchFromGitHubApi() async {
    final resp = await _dio.get<dynamic>(_ghApi,
        options: Options(
          responseType: ResponseType.json,
          headers: <String, String>{'Accept': 'application/vnd.github+json'},
        ));
    final data = resp.data;
    if (data is! Map) throw const FormatException('bad github api response');
    return _decodeContentField(data['content']);
  }

  Future<String> _fetchFromGiteeApi() async {
    final resp = await _dio.get<dynamic>(_giteeApi,
        options: Options(responseType: ResponseType.json));
    final data = resp.data;
    if (data is! Map) throw const FormatException('bad gitee api response');
    return _decodeContentField(data['content']);
  }

  /// 解析 GitHub/Gitee API 的 content 字段（base64，可能带换行）。
  String _decodeContentField(dynamic content) {
    if (content is! String || content.trim().isEmpty) {
      throw const FormatException('empty content');
    }
    final cleaned = content.replaceAll(RegExp(r'\s'), '');
    final decoded = utf8.decode(base64.decode(cleaned));
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
