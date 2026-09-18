import 'package:flutter_test/flutter_test.dart';
import 'package:smart_wrong_notebook/src/app/router.dart';
import 'package:smart_wrong_notebook/src/data/repositories/settings_repository.dart';
import 'package:smart_wrong_notebook/src/domain/models/ai_provider_config.dart';

class _TestSettingsRepository implements SettingsRepository {
  @override
  Future<AiProviderConfig?> getAiProviderConfig() async => null;

  @override
  Future<void> saveAiProviderConfig(AiProviderConfig config) async {}

  @override
  Future<String?> getString(String key) async => null;

  @override
  Future<void> setString(String key, String value) async {}

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

void main() {
  test('router includes capture split confirmation route', () {
    final router = buildRouter(_TestSettingsRepository());
    addTearDown(router.dispose);

    expect(
      () => router.configuration.findMatch(Uri.parse('/capture/split-confirmation')),
      returnsNormally,
    );
  });
}
