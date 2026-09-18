import 'package:smart_wrong_notebook/src/domain/models/ai_provider_config.dart';

/// Whether the setup wizard has been completed.
const String setupCompleteKey = 'setup_complete';

/// Whether the vision-based recognition mode is enabled.
const String useVisionModeKey = 'use_vision_mode';

/// 判断用户是否已配置可用的 DeepSeek Key（apiKey 与 baseUrl 均非空）。
///
/// 视觉兜底限流档位（有 Key 每天 50 次 / 无 Key 累计 10 次）的判断依据
/// 统一使用这里：额度卡片查询与拍照分析请求必须用同一个谓词，否则会出现
/// 「配置了 Key 但卡片显示 10 / 重装后额度归零」的错位。
Future<bool> hasConfiguredProviderKey(SettingsRepository repo) async {
  try {
    final config = await repo.getAiProviderConfig();
    return config != null &&
        config.apiKey.trim().isNotEmpty &&
        config.baseUrl.trim().isNotEmpty;
  } catch (_) {
    return false;
  }
}

/// Returns whether [config] targets DeepSeek.
///
/// A config is considered DeepSeek when its base URL contains
/// `api.deepseek.com` or its model name contains `deepseek`
/// (case-insensitive).
bool isDeepSeekKey(AiProviderConfig config) {
  final baseUrl = config.baseUrl.toLowerCase();
  final model = config.model.toLowerCase();
  return baseUrl.contains('api.deepseek.com') || model.contains('deepseek');
}

abstract class SettingsRepository {
  Future<AiProviderConfig?> getAiProviderConfig();
  Future<void> saveAiProviderConfig(AiProviderConfig config);
  Future<String?> getString(String key);
  Future<void> setString(String key, String value);

  /// Whether the setup wizard has been completed. Defaults to false.
  Future<bool> getSetupComplete() async {
    return await getString(setupCompleteKey) == 'true';
  }

  Future<void> setSetupComplete(bool done) async {
    await setString(setupCompleteKey, done.toString());
  }

  /// Whether the vision-based recognition mode is enabled. Defaults to false.
  Future<bool> getUseVisionMode() async {
    return await getString(useVisionModeKey) == 'true';
  }

  Future<void> setUseVisionMode(bool enabled) async {
    await setString(useVisionModeKey, enabled.toString());
  }
}

class InMemorySettingsRepository implements SettingsRepository {
  AiProviderConfig? _config;
  final Map<String, String> _strings = {};

  InMemorySettingsRepository() {
    _config = const AiProviderConfig(
      id: 'test',
      displayName: 'Test',
      baseUrl: 'https://api.test.com',
      model: 'test-model',
      apiKey: 'test-key',
    );
  }

  @override
  Future<AiProviderConfig?> getAiProviderConfig() async => _config;

  @override
  Future<void> saveAiProviderConfig(AiProviderConfig config) async {
    _config = config;
  }

  @override
  Future<String?> getString(String key) async => _strings[key];

  @override
  Future<void> setString(String key, String value) async {
    _strings[key] = value;
  }

  @override
  Future<bool> getSetupComplete() async =>
      await getString(setupCompleteKey) == 'true';

  @override
  Future<void> setSetupComplete(bool done) async {
    await setString(setupCompleteKey, done.toString());
  }

  @override
  Future<bool> getUseVisionMode() async =>
      await getString(useVisionModeKey) == 'true';

  @override
  Future<void> setUseVisionMode(bool enabled) async {
    await setString(useVisionModeKey, enabled.toString());
  }
}
