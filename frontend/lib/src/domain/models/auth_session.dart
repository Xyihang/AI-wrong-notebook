import 'dart:convert';

/// 用户会话：登录成功后由后端返回的 JWT 与用户信息。
class AuthSession {
  const AuthSession({
    required this.token,
    required this.userId,
    required this.username,
    this.displayName = '',
  });

  /// JWT（请求头 Authorization: Bearer <token>）。
  final String token;

  /// 用户对外 uuid（后端 /api/auth/* 返回的 id）。
  final String userId;

  final String username;

  final String displayName;

  /// 持久化到 settings 存储的 JSON 序列化。
  String toJson() => jsonEncode({
        'token': token,
        'userId': userId,
        'username': username,
        'displayName': displayName,
      });

  /// 从存储 JSON 反序列化；非法时返回 null。
  static AuthSession? tryParse(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    try {
      final map = jsonDecode(raw);
      if (map is! Map) return null;
      final token = map['token'];
      final userId = map['userId'];
      final username = map['username'];
      if (token is! String || token.isEmpty) return null;
      if (userId is! String || userId.isEmpty) return null;
      if (username is! String || username.isEmpty) return null;
      return AuthSession(
        token: token,
        userId: userId,
        username: username,
        displayName: map['displayName'] is String
            ? map['displayName'] as String
            : '',
      );
    } catch (_) {
      return null;
    }
  }
}
