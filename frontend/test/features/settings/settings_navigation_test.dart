import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:smart_wrong_notebook/src/app/providers.dart';
import 'package:smart_wrong_notebook/src/data/repositories/question_repository.dart';
import 'package:smart_wrong_notebook/src/data/repositories/settings_repository.dart';
import 'package:smart_wrong_notebook/src/domain/models/ai_provider_config.dart';
import 'package:smart_wrong_notebook/src/features/settings/presentation/settings_screen.dart';

class _OnboardingDoneSettings implements SettingsRepository {
  @override
  Future<AiProviderConfig?> getAiProviderConfig() async => null;

  @override
  Future<void> saveAiProviderConfig(AiProviderConfig config) async {}

  @override
  Future<String?> getString(String key) async =>
      key == 'onboarding_done' ? 'true' : null;

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
  testWidgets(
      'settings screen shows provider, subject, prompt, and data entries',
      (tester) async {
    await tester.pumpWidget(ProviderScope(
      overrides: [
        settingsRepositoryProvider.overrideWithValue(_OnboardingDoneSettings()),
        questionRepositoryProvider
            .overrideWithValue(InMemoryQuestionRepository()),
      ],
      child: const MaterialApp(home: SettingsScreen()),
    ));
    await tester.pumpAndSettle();

    expect(find.text('外观'), findsOneWidget);
    expect(find.text('系统'), findsOneWidget);
    expect(find.text('浅色'), findsOneWidget);
    expect(find.text('深色'), findsOneWidget);
    expect(find.text('复习提醒'), findsOneWidget);
    expect(find.text('AI 服务'), findsOneWidget);
    expect(find.text('内容'), findsOneWidget);
  });
}
