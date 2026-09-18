import 'dart:typed_data';

import 'package:dio/dio.dart';

import 'package:smart_wrong_notebook/src/core/constants/app_config.dart';
import 'package:smart_wrong_notebook/src/data/remote/backend/auth_session_store.dart';

/// REST API client for the backend (FastAPI), hosted on the cloud CVM.
///
/// Base URL 锁死为 [AppConfig.apiBaseUrl]（云端 CVM），用户无需配置。
/// 若要更换服务器，只需修改 `lib/src/core/constants/app_config.dart` 中的
/// `AppConfig.apiBaseUrl` 一处即可。
///
/// API contract (see docs/spec.md §7):
/// - POST /ocr/recognize        multipart `file` -> {ocr_text, latex_text, blocks, confidence}
/// - POST /questions/analyze    multipart `file` + optional `subject` -> QuestionRecord JSON
/// - POST /questions/analyze-text  JSON {ocr_text, subject} -> QuestionRecord JSON
/// - POST /questions            QuestionRecord JSON -> {id}
/// - GET  /questions            list / filter
/// - POST /retrieval/match      {text, knowledge_points, top_n} -> {items: [{question, similarity, matched_by}]}
/// - GET  /health               -> {status}
class BackendClient {
  BackendClient({String? baseUrl, Dio? dio})
      : baseUrl = _normalizeBaseUrl(baseUrl ?? AppConfig.apiBaseUrl),
        _dio = dio ??
            Dio(BaseOptions(
              baseUrl: _normalizeBaseUrl(baseUrl ?? AppConfig.apiBaseUrl),
              connectTimeout: const Duration(seconds: 10),
              receiveTimeout: const Duration(seconds: 120),
              sendTimeout: const Duration(seconds: 60),
            )) {
    // 自动附带登录 token：已登录时给所有请求加 Authorization: Bearer <token>。
    _dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          final token = AuthSessionStore.currentToken;
          if (token.isNotEmpty) {
            options.headers['Authorization'] = 'Bearer $token';
          }
          handler.next(options);
        },
      ),
    );
  }

  /// 当前后端基础地址（归一化，无尾部 '/'）。
  final String baseUrl;

  final Dio _dio;

  static String _normalizeBaseUrl(String url) {
    var normalized = url.trim();
    while (normalized.endsWith('/')) {
      normalized = normalized.substring(0, normalized.length - 1);
    }
    return normalized;
  }

  /// Persists a new base URL and updates this client to use it.
  /// 更新当前客户端使用的后端地址（默认锁死为全局 [AppConfig.apiBaseUrl]）。
  /// 保留此方法以便未来需要运行时切换时使用；默认情况下后端地址是固定的。
  Future<void> setBaseUrl(String url) async {
    final normalized = _normalizeBaseUrl(url);
    if (normalized.isEmpty) return;
    _dio.options.baseUrl = normalized;
  }

  /// 返回当前后端基础地址（锁死为全局 [AppConfig.apiBaseUrl]）。
  Future<String> getBaseUrl() async {
    return _normalizeBaseUrl(AppConfig.apiBaseUrl);
  }

  /// Optional liveness probe. Returns true when the backend responds to
  /// GET /health with HTTP 200.
  Future<bool> checkHealth() async {
    try {
      final response = await _dio.get<dynamic>('/health');
      return response.statusCode == 200;
    } on DioException {
      return false;
    }
  }

  /// Uploads an image and returns the recognized OCR plain text.
  /// Multipart field name is `file` (see spec §7).
  Future<String> recognizeImage(String imagePath) async {
    final formData = FormData.fromMap(<String, dynamic>{
      'file': await MultipartFile.fromFile(imagePath),
    });
    try {
      final response = await _dio.post<dynamic>(
        '/ocr/recognize',
        data: formData,
      );
      final data = response.data;
      if (data is Map) {
        final ocrText = data['ocr_text'];
        return ocrText is String ? ocrText : (ocrText?.toString() ?? '');
      }
      throw const BackendClientException('后端 OCR 返回格式异常');
    } on DioException catch (e) {
      throw BackendClientException(_friendlyMessage(e));
    }
  }

  /// Uploads an image (with optional subject hint) and returns the full
  /// QuestionRecord JSON map produced by the backend (OCR + AI structuring).
  ///
  /// [hasVisionKey] 表示该用户是否已配置 DeepSeek Key，[useVisionMode] 表示是否
  /// 启用视觉模式，后端据此选择视觉兜底限流档位
  /// （有Key+视觉模式每天50 / 有Key未开视觉模式每天20 / 无Key累计10）。
  Future<Map<String, dynamic>> analyzeImage(
    String imagePath, {
    String? subject,
    bool hasVisionKey = false,
    bool useVisionMode = false,
  }) async {
    final formData = FormData.fromMap(<String, dynamic>{
      'file': await MultipartFile.fromFile(imagePath),
      if (subject != null && subject.trim().isNotEmpty)
        'subject': subject.trim(),
      'has_vision_key': hasVisionKey,
      'use_vision_mode': useVisionMode,
    });
    try {
      final response = await _dio.post<dynamic>(
        '/questions/analyze',
        data: formData,
      );
      final data = response.data;
      if (data is Map) {
        return Map<String, dynamic>.from(data);
      }
      throw const BackendClientException('后端题目分析返回格式异常');
    } on DioException catch (e) {
      throw BackendClientException(_friendlyMessage(e));
    }
  }

  /// 端侧 OCR 文字 -> 结构化（不入库，附带同类题匹配）。
  Future<Map<String, dynamic>> analyzeText(
    String ocrText, {
    String? subject,
  }) async {
    try {
      final response = await _dio.post<dynamic>(
        '/questions/analyze-text',
        data: <String, dynamic>{
          'ocr_text': ocrText,
          if (subject != null && subject.trim().isNotEmpty)
            'subject': subject.trim(),
        },
      );
      final data = response.data;
      if (data is Map) {
        return Map<String, dynamic>.from(data);
      }
      throw const BackendClientException('后端题目分析返回格式异常');
    } on DioException catch (e) {
      throw BackendClientException(_friendlyMessage(e));
    }
  }

  /// Matches the given text + knowledge points against the question bank.
  /// Returns the `items` list, each entry being {question, similarity, matched_by}.
  Future<List<Map<String, dynamic>>> matchSimilar(
    String text,
    List<String> knowledgePoints, {
    int topN = 5,
  }) async {
    try {
      final response = await _dio.post<dynamic>(
        '/retrieval/match',
        data: <String, dynamic>{
          'text': text,
          'knowledge_points': knowledgePoints,
          'top_n': topN,
        },
      );
      final data = response.data;
      if (data is Map) {
        final items = data['items'];
        if (items is List) {
          return items
              .whereType<Map>()
              .map((item) => Map<String, dynamic>.from(item))
              .toList();
        }
      }
      return const <Map<String, dynamic>>[];
    } on DioException catch (e) {
      throw BackendClientException(_friendlyMessage(e));
    }
  }

  /// Persists a QuestionRecord JSON map on the backend. Returns the backend
  /// response map (typically {id: ...}).
  Future<Map<String, dynamic>> saveQuestion(
    Map<String, dynamic> question,
  ) async {
    try {
      final response = await _dio.post<dynamic>(
        '/questions',
        data: question,
      );
      final data = response.data;
      if (data is Map) {
        return Map<String, dynamic>.from(data);
      }
      return const <String, dynamic>{};
    } on DioException catch (e) {
      throw BackendClientException(_friendlyMessage(e));
    }
  }

  /// Fetches questions from the backend. [filters] is passed as query
  /// parameters (subject/kp/type/mastery/keyword/page, see spec §7).
  Future<List<Map<String, dynamic>>> fetchQuestions({
    Map<String, dynamic>? filters,
  }) async {
    try {
      final response = await _dio.get<dynamic>(
        '/questions',
        queryParameters: filters,
      );
      final data = response.data;
      if (data is List) {
        return data
            .whereType<Map>()
            .map((item) => Map<String, dynamic>.from(item))
            .toList();
      }
      if (data is Map && data['items'] is List) {
        return (data['items'] as List)
            .whereType<Map>()
            .map((item) => Map<String, dynamic>.from(item))
            .toList();
      }
      return const <Map<String, dynamic>>[];
    } on DioException catch (e) {
      throw BackendClientException(_friendlyMessage(e));
    }
  }

  /// 批量删除后端错题（按当前账号）。返回删除条数。
  Future<int> deleteQuestions(List<String> ids) async {
    try {
      final response = await _dio.delete<dynamic>(
        '/questions',
        data: <String, dynamic>{'ids': ids},
      );
      final data = response.data;
      if (data is Map) {
        return (data['deleted'] as num?)?.toInt() ?? ids.length;
      }
      return ids.length;
    } on DioException catch (e) {
      throw BackendClientException(_friendlyMessage(e));
    }
  }

  /// 拉取当前账号的连击&成就徽章（服务端权威）。失败抛异常由调用方降级。
  Future<Map<String, dynamic>> fetchGamification() async {
    try {
      final response = await _dio.get<dynamic>('/gamification');
      final data = response.data;
      if (data is Map) {
        return Map<String, dynamic>.from(data);
      }
      throw const BackendClientException('后端游戏化数据格式异常');
    } on DioException catch (e) {
      throw BackendClientException(_friendlyMessage(e));
    }
  }

  /// AI 变式组卷。返回 {paper:{title,subject,questions:[...]}}。
  Future<Map<String, dynamic>> generatePaper({
    required String subject,
    List<String> knowledgePoints = const [],
    String? difficulty,
    int count = 10,
  }) async {
    try {
      final response = await _dio.post<dynamic>(
        '/paper/generate',
        data: <String, dynamic>{
          'subject': subject,
          'knowledge_points': knowledgePoints,
          if (difficulty != null && difficulty.trim().isNotEmpty)
            'difficulty': difficulty.trim(),
          'count': count,
        },
      );
      final data = response.data;
      if (data is Map) {
        return Map<String, dynamic>.from(data);
      }
      throw const BackendClientException('组卷响应格式异常');
    } on DioException catch (e) {
      throw BackendClientException(_friendlyMessage(e));
    }
  }

  /// 把已生成的组卷导出为 PDF（字节）。[includeAnswers] 决定是否含答案解析。
  Future<Uint8List> exportPaperPdf({
    required String title,
    required List<Map<String, dynamic>> questions,
    bool includeAnswers = false,
  }) async {
    try {
      final response = await _dio.post<dynamic>(
        '/paper/export',
        data: <String, dynamic>{
          'title': title,
          'include_answers': includeAnswers,
          'questions': questions,
        },
        options: Options(responseType: ResponseType.bytes),
      );
      final data = response.data;
      if (data is List<int>) return Uint8List.fromList(data);
      throw const BackendClientException('PDF 导出响应格式异常');
    } on DioException catch (e) {
      throw BackendClientException(_friendlyMessage(e));
    }
  }

  /// 查询视觉识别剩余额度。返回 {mode, limit, remaining, used, reset}。
  Future<Map<String, dynamic>> fetchVisionQuota({
    bool hasVisionKey = false,
    bool useVisionMode = false,
  }) async {
    try {
      final response = await _dio.get<dynamic>(
        '/settings/vision-quota',
        queryParameters: <String, dynamic>{
          'has_vision_key': hasVisionKey,
          'use_vision_mode': useVisionMode,
        },
      );
      final data = response.data;
      if (data is Map) {
        return Map<String, dynamic>.from(data);
      }
      return const <String, dynamic>{};
    } on DioException catch (e) {
      throw BackendClientException(_friendlyMessage(e));
    }
  }

  // ------------------------------------------------------------------
  // 认证（/api/auth/*）
  // ------------------------------------------------------------------

  /// 获取算术验证码。返回 {captcha_id, image_base64, image_mime, ttl}。
  Future<Map<String, dynamic>> fetchCaptcha() async {
    try {
      final response = await _dio.get<dynamic>('/auth/captcha');
      final data = response.data;
      if (data is Map) {
        return Map<String, dynamic>.from(data);
      }
      throw const BackendClientException('获取验证码失败：响应格式异常');
    } on DioException catch (e) {
      throw BackendClientException(_friendlyMessage(e));
    }
  }

  /// 注册。成功返回用户信息 {id, username, display_name, created_at}。
  Future<Map<String, dynamic>> register(
    String username,
    String password, {
    String displayName = '',
    required String captchaId,
    required String captchaAnswer,
  }) async {
    try {
      final response = await _dio.post<dynamic>(
        '/auth/register',
        data: <String, dynamic>{
          'username': username,
          'password': password,
          'display_name': displayName,
          'captcha_id': captchaId,
          'captcha_answer': captchaAnswer,
        },
      );
      final data = response.data;
      if (data is Map) {
        return Map<String, dynamic>.from(data);
      }
      throw const BackendClientException('注册失败：响应格式异常');
    } on DioException catch (e) {
      throw BackendClientException(_friendlyMessage(e));
    }
  }

  /// 登录。成功返回 {access_token, token_type, user:{...}}。
  Future<Map<String, dynamic>> login(String username, String password) async {
    try {
      final response = await _dio.post<dynamic>(
        '/auth/login',
        data: <String, dynamic>{
          'username': username,
          'password': password,
        },
      );
      final data = response.data;
      if (data is Map) {
        return Map<String, dynamic>.from(data);
      }
      throw const BackendClientException('登录失败：响应格式异常');
    } on DioException catch (e) {
      throw BackendClientException(_friendlyMessage(e));
    }
  }

  /// 当前用户。成功返回用户信息 {id, username, display_name, created_at}。
  /// 返回 null 表示未登录 / token 失效（无需抛错，由调用方判断）。
  Future<Map<String, dynamic>?> fetchCurrentUser() async {
    try {
      final response = await _dio.get<dynamic>('/auth/me');
      final data = response.data;
      if (data is Map) {
        return Map<String, dynamic>.from(data);
      }
      return null;
    } on DioException {
      // token 缺失/失效 -> 401，返回 null 表示未登录
      return null;
    }
  }

  /// Maps network errors to a friendly, user-facing message.
  String _friendlyMessage(DioException e) {
    final buffer = StringBuffer('后端服务请求失败');
    if (e.type == DioExceptionType.connectionTimeout ||
        e.type == DioExceptionType.receiveTimeout ||
        e.type == DioExceptionType.sendTimeout) {
      buffer.write(': 请求超时，请确认后端服务已启动');
    } else if (e.type == DioExceptionType.connectionError) {
      buffer.write(
          ': 无法连接后端服务（$baseUrl），请确认后端已启动且地址正确');
    } else if (e.response != null) {
      final status = e.response!.statusCode;
      final body = e.response!.data;
      if (status != null) {
        buffer.write(' (HTTP $status)');
        // Backend error format: {"detail": "<msg>"} (spec §7)
        if (body is Map && body['detail'] != null) {
          buffer.write(': ${body['detail']}');
        } else if (body is String && body.isNotEmpty) {
          buffer.write(
              ': ${body.length > 100 ? '${body.substring(0, 100)}...' : body}');
        }
      } else if (e.message != null) {
        buffer.write(': ${e.message}');
      }
    } else if (e.message != null) {
      buffer.write(': ${e.message}');
    }
    return buffer.toString();
  }
}

/// Thrown by [BackendClient] when a request fails; [message] is already
/// user-friendly.
class BackendClientException implements Exception {
  const BackendClientException(this.message);

  final String message;

  @override
  String toString() => message;
}
