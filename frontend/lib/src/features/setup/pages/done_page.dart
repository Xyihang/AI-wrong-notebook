import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:smart_wrong_notebook/src/domain/models/ai_provider_config.dart';
import 'package:smart_wrong_notebook/src/features/setup/setup_controller.dart';

/// 向导第 4 步：完成页。总结所选配置，「开始使用」按钮（底部栏）会调用
/// `SettingsRepository.setSetupComplete(true)` 并跳转首页。
class DonePage extends ConsumerStatefulWidget {
  const DonePage({super.key});

  @override
  ConsumerState<DonePage> createState() => DonePageState();
}

class DonePageState extends ConsumerState<DonePage>
    implements SetupWizardStepValidator {
  @override
  Future<String?> validateAndCommit() async => null;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;
    final state = ref.watch(setupWizardProvider);

    return ListView(
      padding: const EdgeInsets.fromLTRB(32, 24, 32, 24),
      children: <Widget>[
        const SizedBox(height: 8),
        Center(
          child: Container(
            width: 96,
            height: 96,
            decoration: BoxDecoration(
              color: isDark
                  ? const Color(0xFF16A34A).withValues(alpha: 0.16)
                  : const Color(0xFFF0FDF4),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              CupertinoIcons.checkmark_circle_fill,
              size: 56,
              color: Color(0xFF16A34A),
            ),
          ),
        ),
        const SizedBox(height: 20),
        Center(
          child: Text(
            '配置完成',
            style: theme.textTheme.headlineSmall
                ?.copyWith(fontWeight: FontWeight.bold),
          ),
        ),
        const SizedBox(height: 8),
        Center(
          child: Text(
            '所有设置已保存，现在开始你的学习之旅',
            style: theme.textTheme.bodySmall
                ?.copyWith(color: colorScheme.onSurfaceVariant),
          ),
        ),
        const SizedBox(height: 28),
        _SummaryCard(
          config: state.providerConfig,
          visionMode: state.useVisionMode,
        ),
        const SizedBox(height: 16),
        Text(
          '之后可随时在「设置」中修改服务商、模型或识别模式。',
          textAlign: TextAlign.center,
          style: theme.textTheme.bodySmall
              ?.copyWith(color: colorScheme.onSurfaceVariant),
        ),
      ],
    );
  }
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({required this.config, required this.visionMode});

  final AiProviderConfig? config;
  final bool visionMode;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    final rows = <(IconData, String, String)>[
      (CupertinoIcons.cloud, '服务商', config?.displayName ?? '自定义服务'),
      (CupertinoIcons.link, 'Base URL', config?.baseUrl ?? '-'),
      (CupertinoIcons.sparkles, '模型', config?.model ?? '-'),
      (
        visionMode ? CupertinoIcons.eye : CupertinoIcons.cloud,
        '识别模式',
        visionMode ? '视觉模式（DeepSeek）' : '标准模式',
      ),
    ];

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: colorScheme.outlineVariant),
      ),
      child: Column(
        children: <Widget>[
          for (final (index, row) in rows.indexed) ...<Widget>[
            if (index > 0)
              Divider(height: 1, color: colorScheme.outlineVariant),
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Row(
                children: <Widget>[
                  Icon(row.$1, size: 18, color: colorScheme.primary),
                  const SizedBox(width: 10),
                  SizedBox(
                    width: 64,
                    child: Text(
                      row.$2,
                      style: theme.textTheme.bodySmall
                          ?.copyWith(color: colorScheme.onSurfaceVariant),
                    ),
                  ),
                  Expanded(
                    child: Text(
                      row.$3,
                      textAlign: TextAlign.right,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodyMedium
                          ?.copyWith(fontWeight: FontWeight.w500),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}
