import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:smart_wrong_notebook/src/app/providers.dart';
import 'package:smart_wrong_notebook/src/features/setup/pages/done_page.dart';
import 'package:smart_wrong_notebook/src/features/setup/pages/provider_page.dart';
import 'package:smart_wrong_notebook/src/features/setup/pages/vision_mode_page.dart';
import 'package:smart_wrong_notebook/src/features/setup/pages/welcome_page.dart';
import 'package:smart_wrong_notebook/src/features/setup/setup_controller.dart';

/// 首次启动配置向导入口。
///
/// 用 [IndexedStack] 管理 4 步（欢迎 → 供应商+Key → 识别模式 → 完成），
/// 所有分页常驻、表单状态不丢失；底部「上一步 / 下一步」驱动推进，
/// 「下一步」先调用当前页的 [SetupWizardStepValidator.validateAndCommit]
/// 校验并提交，校验失败则停留在当前步。
class SetupWizardScreen extends ConsumerStatefulWidget {
  const SetupWizardScreen({super.key});

  @override
  ConsumerState<SetupWizardScreen> createState() => _SetupWizardScreenState();
}

class _SetupWizardScreenState extends ConsumerState<SetupWizardScreen> {
  static const int _totalSteps = 4;
  static const List<String> _stepTitles = <String>[
    '欢迎',
    'AI 服务配置',
    '识别模式',
    '完成',
  ];

  final List<GlobalKey<State<StatefulWidget>>> _pageKeys =
      <GlobalKey<State<StatefulWidget>>>[
    GlobalKey<WelcomePageState>(),
    GlobalKey<ProviderPageState>(),
    GlobalKey<VisionModePageState>(),
    GlobalKey<DonePageState>(),
  ];

  String get _nextLabel => switch (_step) {
        0 => '开始配置',
        3 => '开始使用',
        _ => '下一步',
      };

  int get _step => ref.watch(setupWizardProvider.select((s) => s.currentStep));

  Future<void> _handleNext() async {
    final step = ref.read(setupWizardProvider).currentStep;
    final pageState = _pageKeys[step].currentState;
    final error =
        await (pageState as SetupWizardStepValidator).validateAndCommit();
    if (error != null) return;
    if (step == _totalSteps - 1) {
      await _finish();
      return;
    }
    ref.read(setupWizardProvider.notifier).next();
  }

  void _handleBack() {
    ref.read(setupWizardProvider.notifier).back();
  }

  Future<void> _finish() async {
    await ref.read(settingsRepositoryProvider).setSetupComplete(true);
    if (mounted) context.go('/');
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final step = _step;

    return PopScope(
      canPop: step == 0,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        _handleBack();
      },
      child: Scaffold(
        body: SafeArea(
          child: Column(
            children: <Widget>[
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 16, 24, 4),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Row(
                      children: <Widget>[
                        Container(
                          width: 28,
                          height: 28,
                          decoration: BoxDecoration(
                            color: colorScheme.primaryContainer,
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: Icon(CupertinoIcons.sparkles,
                              size: 15, color: colorScheme.onPrimaryContainer),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          '首次启动配置',
                          style: theme.textTheme.titleMedium
                              ?.copyWith(fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: <Widget>[
                        for (var i = 0; i < _totalSteps; i++)
                          Expanded(
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 250),
                              height: 4,
                              margin: EdgeInsets.only(
                                  right: i < _totalSteps - 1 ? 6 : 0),
                              decoration: BoxDecoration(
                                color: i <= step
                                    ? colorScheme.primary
                                    : colorScheme.surfaceContainerHighest,
                                borderRadius: BorderRadius.circular(2),
                              ),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '第 ${step + 1} / $_totalSteps 步 · ${_stepTitles[step]}',
                      style: theme.textTheme.bodySmall
                          ?.copyWith(color: colorScheme.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: IndexedStack(
                  index: step,
                  children: <Widget>[
                    WelcomePage(key: _pageKeys[0]),
                    ProviderPage(key: _pageKeys[1]),
                    VisionModePage(key: _pageKeys[2]),
                    DonePage(key: _pageKeys[3]),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
                child: Row(
                  children: <Widget>[
                    if (step > 0) ...<Widget>[
                      OutlinedButton(
                        onPressed: _handleBack,
                        style: OutlinedButton.styleFrom(
                          minimumSize: const Size(96, 52),
                        ),
                        child: const Text('上一步'),
                      ),
                      const SizedBox(width: 12),
                    ],
                    Expanded(
                      child: FilledButton(
                        onPressed: _handleNext,
                        style: FilledButton.styleFrom(
                          minimumSize: const Size.fromHeight(52),
                        ),
                        child: Text(_nextLabel),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
