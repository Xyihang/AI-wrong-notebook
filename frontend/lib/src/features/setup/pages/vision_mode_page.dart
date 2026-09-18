import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:smart_wrong_notebook/src/app/providers.dart';
import 'package:smart_wrong_notebook/src/data/repositories/settings_repository.dart';
import 'package:smart_wrong_notebook/src/domain/models/ai_provider_config.dart';
import 'package:smart_wrong_notebook/src/features/setup/setup_controller.dart';

/// 向导第 3 步：识别模式选择页。
///
/// 单选「标准模式（推荐）」/「视觉模式（DeepSeek）」。选择视觉模式时校验当前
/// 配置是否为 DeepSeek；非 DeepSeek 则提示「视觉模式仅支持 DeepSeek」并回退
/// 标准模式。未填写 API Key 时视觉模式不可用（卡片置灰、提示需先填 Key），
/// 默认标准模式。点「下一步」时把选择保存到 `SettingsRepository.setUseVisionMode`。
class VisionModePage extends ConsumerStatefulWidget {
  const VisionModePage({super.key});

  @override
  ConsumerState<VisionModePage> createState() => VisionModePageState();
}

class VisionModePageState extends ConsumerState<VisionModePage>
    implements SetupWizardStepValidator {
  late bool _visionMode;

  @override
  void initState() {
    super.initState();
    _visionMode = ref.read(setupWizardProvider).useVisionMode;
  }

  AiProviderConfig? get _config => ref.read(setupWizardProvider).providerConfig;

  /// 是否已填写 API Key；未填 Key 时视觉模式不可用（只能标准模式）。
  bool get _hasApiKey {
    final config = _config;
    return config != null && config.apiKey.trim().isNotEmpty;
  }

  void _selectMode(bool vision) {
    if (!vision) {
      setState(() => _visionMode = false);
      ref.read(setupWizardProvider.notifier).setUseVisionMode(false);
      return;
    }
    if (!_hasApiKey) {
      _showNeedKeyMessage();
      setState(() => _visionMode = false);
      ref.read(setupWizardProvider.notifier).setUseVisionMode(false);
      return;
    }
    final config = _config!;
    if (!isDeepSeekKey(config)) {
      _showNotDeepSeekMessage();
      setState(() => _visionMode = false);
      ref.read(setupWizardProvider.notifier).setUseVisionMode(false);
      return;
    }
    setState(() => _visionMode = true);
    ref.read(setupWizardProvider.notifier).setUseVisionMode(true);
  }

  void _showNeedKeyMessage() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('视觉模式需要先配置 DeepSeek API Key，请返回上一步填写或稍后在设置中配置'),
      ),
    );
  }

  void _showNotDeepSeekMessage() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('视觉模式仅支持 DeepSeek，已回退到标准模式')),
    );
  }

  @override
  Future<String?> validateAndCommit() async {
    if (!_visionMode) {
      await ref.read(settingsRepositoryProvider).setUseVisionMode(false);
      ref.read(setupWizardProvider.notifier).setUseVisionMode(false);
      return null;
    }
    if (!_hasApiKey) {
      // 配置被回退为无 Key（如返回上一步清空）时，强制回退标准模式。
      _showNeedKeyMessage();
      setState(() => _visionMode = false);
      ref.read(setupWizardProvider.notifier).setUseVisionMode(false);
      return null;
    }
    final config = _config!;
    if (!isDeepSeekKey(config)) {
      _showNotDeepSeekMessage();
      setState(() => _visionMode = false);
      ref.read(setupWizardProvider.notifier).setUseVisionMode(false);
      return '视觉模式仅支持 DeepSeek，已回退到标准模式';
    }
    await ref.read(settingsRepositoryProvider).setUseVisionMode(true);
    ref.read(setupWizardProvider.notifier).setUseVisionMode(true);
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final config = _config;
    final isDeepSeek = config != null && isDeepSeekKey(config);
    final hasKey = config != null && config.apiKey.trim().isNotEmpty;

    return ListView(
      padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
      children: <Widget>[
        Text(
          '选择识别模式',
          style:
              theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 4),
        Text(
          '识别模式影响题目识别的方式，之后可在「设置」中随时切换。',
          style: theme.textTheme.bodySmall
              ?.copyWith(color: colorScheme.onSurfaceVariant),
        ),
        const SizedBox(height: 16),
        _ModeCard(
          selected: !_visionMode,
          onTap: () => _selectMode(false),
          icon: CupertinoIcons.cloud,
          color: const Color(0xFF2563EB),
          background: const Color(0xFFEFF6FF),
          title: '标准模式',
          badge: '推荐',
          description: '拍照后由云端后端完成识别（RapidOCR + AI 结构化），无需自备 Key，开箱即用。',
        ),
        const SizedBox(height: 12),
        _ModeCard(
          selected: _visionMode,
          enabled: hasKey,
          onTap: () => _selectMode(true),
          icon: CupertinoIcons.eye,
          color: const Color(0xFF16A34A),
          background: const Color(0xFFF0FDF4),
          title: '视觉模式（DeepSeek）',
          badge: !hasKey ? '需先填 Key' : (isDeepSeek ? '已就绪' : null),
          description: hasKey
              ? '拍照后直接调用你的 DeepSeek 视觉模型读图，识别手写、复杂题目更准。仅支持 DeepSeek 服务商与 Key。'
              : '需先在上一步填写 DeepSeek API Key 才能启用；未配置时默认使用标准模式。',
        ),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Icon(CupertinoIcons.info,
                  size: 16, color: colorScheme.onSurfaceVariant),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  config == null
                      ? '尚未保存 AI 服务配置，请先完成上一步。'
                      : !hasKey
                          ? '未填写 API Key，仅支持标准模式；如需视觉模式，请返回上一步填写 DeepSeek Key。'
                          : '当前配置：${config.displayName} · ${config.model}',
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: colorScheme.onSurfaceVariant),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _ModeCard extends StatelessWidget {
  const _ModeCard({
    required this.selected,
    required this.onTap,
    required this.icon,
    required this.color,
    required this.background,
    required this.title,
    required this.description,
    this.badge,
    this.enabled = true,
  });

  final bool selected;
  final VoidCallback onTap;
  final IconData icon;
  final Color color;
  final Color background;
  final String title;
  final String description;
  final String? badge;

  /// 是否可用；为 false 时内容置灰（如未填 API Key 时视觉模式不可选）。
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;

    return Material(
      color: colorScheme.surface,
      shape: RoundedRectangleBorder(
        side: BorderSide(
          color: selected ? color : colorScheme.outlineVariant,
          width: selected ? 2 : 1,
        ),
        borderRadius: BorderRadius.circular(12),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Opacity(
          opacity: enabled ? 1.0 : 0.55,
          child: Padding(
            padding: const EdgeInsets.all(14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: isDark ? color.withValues(alpha: 0.16) : background,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Icon(icon, size: 20, color: color),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Row(
                      children: <Widget>[
                        Flexible(
                          child: Text(
                            title,
                            style: theme.textTheme.titleSmall
                                ?.copyWith(fontWeight: FontWeight.w600),
                          ),
                        ),
                        if (badge != null) ...<Widget>[
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 7, vertical: 2),
                            decoration: BoxDecoration(
                              color: selected
                                  ? color.withValues(alpha: 0.14)
                                  : colorScheme.surfaceContainerHighest,
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              badge!,
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: selected
                                    ? color
                                    : colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      description,
                      style: theme.textTheme.bodySmall
                          ?.copyWith(color: colorScheme.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Container(
                width: 22,
                height: 22,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: selected ? color : colorScheme.outlineVariant,
                    width: 2,
                  ),
                ),
                child: selected
                    ? Center(
                        child: Container(
                          width: 12,
                          height: 12,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: color,
                          ),
                        ),
                      )
                    : null,
              ),
            ],
          ),
        ),
        ),
      ),
    );
  }
}
