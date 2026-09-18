import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:smart_wrong_notebook/src/domain/models/ai_provider_config.dart';

/// 向导分页统一校验契约。
///
/// 向导在点击「下一步」时调用当前页的 [validateAndCommit]：
/// - 返回 `null` 表示校验通过（页面应在内部完成保存/提交）；
/// - 返回非 `null` 表示校验失败，向导不推进，页面应已自行展示错误提示。
abstract class SetupWizardStepValidator {
  Future<String?> validateAndCommit();
}

/// 向导全局状态：当前步 + 各页已提交的配置。
class SetupWizardState {
  const SetupWizardState({
    this.currentStep = 0,
    this.providerConfig,
    this.useVisionMode = false,
  });

  /// 当前步（0=欢迎 / 1=供应商+Key / 2=识别模式 / 3=完成）。
  final int currentStep;

  /// 供应商页提交的 AI 配置草稿（供识别模式页校验 DeepSeek、完成页展示）。
  final AiProviderConfig? providerConfig;

  /// 是否启用视觉模式（仅 DeepSeek 配置下有效）。
  final bool useVisionMode;

  SetupWizardState copyWith({
    int? currentStep,
    AiProviderConfig? providerConfig,
    bool? useVisionMode,
  }) {
    return SetupWizardState(
      currentStep: currentStep ?? this.currentStep,
      providerConfig: providerConfig ?? this.providerConfig,
      useVisionMode: useVisionMode ?? this.useVisionMode,
    );
  }
}

class SetupWizardNotifier extends Notifier<SetupWizardState> {
  static const int totalSteps = 4;

  @override
  SetupWizardState build() => const SetupWizardState();

  void next() => _go(state.currentStep + 1);

  void back() => _go(state.currentStep - 1);

  void _go(int step) {
    if (step < 0 || step >= totalSteps) return;
    if (step == state.currentStep) return;
    state = state.copyWith(currentStep: step);
  }

  void updateProviderConfig(AiProviderConfig config) {
    state = state.copyWith(providerConfig: config);
  }

  void setUseVisionMode(bool value) {
    state = state.copyWith(useVisionMode: value);
  }
}

final NotifierProvider<SetupWizardNotifier, SetupWizardState>
    setupWizardProvider =
    NotifierProvider<SetupWizardNotifier, SetupWizardState>(
        SetupWizardNotifier.new);
