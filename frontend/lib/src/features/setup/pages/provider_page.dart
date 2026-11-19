import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:smart_wrong_notebook/src/app/providers.dart';
import 'package:smart_wrong_notebook/src/features/glass/glass_overlays.dart';
import 'package:smart_wrong_notebook/src/domain/models/ai_provider_config.dart';
import 'package:smart_wrong_notebook/src/features/settings/presentation/ai_provider_preset.dart';
import 'package:smart_wrong_notebook/src/features/setup/setup_controller.dart';
import 'package:url_launcher/url_launcher.dart';

/// 向导第 2 步：供应商 + API Key 配置页。
///
/// 复用 [AiProviderPreset.supported] 预设，填写 Base URL / API Key / 模型，
/// 可选「获取可用模型」「测试连接」；点「下一步」时校验并保存到
/// `SettingsRepository.saveAiProviderConfig`，同时把配置提交到向导状态。
/// API Key 不强制：可留空跳过（视为不使用 Key，后续走标准模式），
/// 稍后在「设置」中补配即可。
class ProviderPage extends ConsumerStatefulWidget {
  const ProviderPage({super.key});

  @override
  ConsumerState<ProviderPage> createState() => ProviderPageState();
}

class ProviderPageState extends ConsumerState<ProviderPage>
    implements SetupWizardStepValidator {
  late final TextEditingController _urlController;
  late final TextEditingController _modelController;
  late final TextEditingController _apiKeyController;
  AiProviderPreset? _selectedPreset = AiProviderPreset.supported.first;
  bool _showApiKey = false;
  bool _fetchingModels = false;
  bool _testing = false;
  List<String> _availableModels = const <String>[];
  String? _statusMessage;
  bool _statusIsError = false;

  @override
  void initState() {
    super.initState();
    _urlController = TextEditingController(text: _selectedPreset!.baseUrl);
    _modelController = TextEditingController();
    _apiKeyController = TextEditingController();
    _prefillExistingConfig();
  }

  @override
  void dispose() {
    _urlController.dispose();
    _modelController.dispose();
    _apiKeyController.dispose();
    super.dispose();
  }

  /// 若本机已有 AI 服务配置（如曾打开过设置页），预填到表单，减少重复输入。
  Future<void> _prefillExistingConfig() async {
    final config =
        await ref.read(settingsRepositoryProvider).getAiProviderConfig();
    if (!mounted || config == null || config.baseUrl.trim().isEmpty) return;
    setState(() {
      _selectedPreset = AiProviderPreset.fromConfig(config);
      _urlController.text = config.baseUrl;
      _modelController.text = config.model;
      _apiKeyController.text = config.apiKey;
    });
  }

  AiProviderConfig _buildConfig() {
    final preset = _selectedPreset;
    return AiProviderConfig(
      id: preset?.id ?? 'custom',
      displayName: preset?.displayName ?? '自定义服务',
      baseUrl: _urlController.text.trim(),
      model: _modelController.text.trim(),
      apiKey: _apiKeyController.text.trim(),
    );
  }

  String? _validateDraft() {
    if (_urlController.text.trim().isEmpty) return '请填写 Base URL';
    // API Key 不强制：可跳过，未配置时后续使用系统识别模式（标准模式）。
    final apiKey = _apiKeyController.text.trim();
    if (apiKey.isNotEmpty && _modelController.text.trim().isEmpty) {
      return '填写了 API Key 时请填写模型 ID';
    }
    return null;
  }

  @override
  Future<String?> validateAndCommit() async {
    final error = _validateDraft();
    if (error != null) {
      _showStatus(error, isError: true);
      return error;
    }
    final config = _buildConfig();
    await ref.read(settingsRepositoryProvider).saveAiProviderConfig(config);
    ref.read(setupWizardProvider.notifier).updateProviderConfig(config);
    _showStatus(null);
    return null;
  }

  void _showStatus(String? message, {bool isError = false}) {
    if (!mounted) return;
    setState(() {
      _statusMessage = message;
      _statusIsError = isError;
    });
  }

  void _selectPreset(AiProviderPreset? preset) {
    final previousId = _selectedPreset?.id ?? 'custom';
    final nextId = preset?.id ?? 'custom';
    if (previousId == nextId) return;
    setState(() {
      _selectedPreset = preset;
      _urlController.text = preset?.baseUrl ?? '';
      _apiKeyController.clear();
      _modelController.clear();
      _availableModels = const <String>[];
      _statusMessage = null;
    });
  }

  Future<void> _fetchModels() async {
    final draft = _buildConfig();
    if (draft.apiKey.isEmpty || draft.baseUrl.isEmpty) {
      _showStatus('请先填写 API Key 再获取模型', isError: true);
      return;
    }
    setState(() {
      _fetchingModels = true;
      _statusMessage = null;
    });
    try {
      final models =
          await ref.read(aiAnalysisServiceProvider).fetchAvailableModels(draft);
      if (!mounted) return;
      setState(() {
        _availableModels = models;
        _fetchingModels = false;
      });
      await _openModelPicker();
    } catch (error) {
      if (!mounted) return;
      _showStatus('获取模型失败：$error', isError: true);
    } finally {
      if (mounted && _fetchingModels) {
        setState(() => _fetchingModels = false);
      }
    }
  }

  Future<void> _openModelPicker() async {
    if (_availableModels.isEmpty) {
      _showStatus('没有获取到可用模型，可手动填写模型 ID', isError: true);
      return;
    }
    final selected = await showAppSheet<String>(context,
      builder: (_) => _ModelSheet(models: _availableModels),
    );
    if (!mounted || selected == null) return;
    setState(() {
      _modelController.text = selected;
      _statusMessage = null;
    });
    // DeepSeek 下选择模型时提醒：deepseek-flash / 含 vision 的都支持读图
    final isDeepSeek =
        _urlController.text.toLowerCase().contains('deepseek') ||
        selected.toLowerCase().contains('deepseek');
    final selectedModel = selected.toLowerCase();
    final visionCapable = selectedModel.contains('vision') ||
        selectedModel.contains('flash');
    if (isDeepSeek && !visionCapable) {
      _showStatus(
        '当前模型 $selected 可能不支持图片识别。DeepSeek 的 deepseek-flash 已原生支持视觉；'
        '其它服务商请选择含 vision 的视觉模型。',
      );
    }
  }

  Future<void> _testConnection() async {
    final draft = _buildConfig();
    final error = _validateDraft();
    if (error != null) {
      _showStatus(error, isError: true);
      return;
    }
    if (draft.apiKey.isEmpty) {
      _showStatus('测试连接需要先填写 API Key', isError: true);
      return;
    }
    setState(() {
      _testing = true;
      _statusMessage = null;
    });
    try {
      await ref.read(aiAnalysisServiceProvider).testConnection(draft);
      if (!mounted) return;
      _showStatus('连接正常，当前模型支持图片识题');
    } catch (error) {
      if (!mounted) return;
      _showStatus('连接失败：$error（可跳过测试继续）', isError: true);
    } finally {
      if (mounted) setState(() => _testing = false);
    }
  }

  Future<void> _openRegistration() async {
    final preset = _selectedPreset ?? AiProviderPreset.supported.first;
    final opened = await launchUrl(
      Uri.parse(preset.signUpUrl),
      mode: LaunchMode.externalApplication,
    );
    if (!mounted || opened) return;
    await Clipboard.setData(ClipboardData(text: preset.signUpUrl));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('注册链接已复制，请在浏览器打开')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return ListView(
      padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
      children: <Widget>[
        Text(
          '配置 AI 服务',
          style:
              theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 4),
        Text(
          '选择服务商并填写 API Key，用于题目识别。',
          style: theme.textTheme.bodySmall
              ?.copyWith(color: colorScheme.onSurfaceVariant),
        ),
        const SizedBox(height: 16),
        Text('服务商', style: theme.textTheme.titleSmall),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: <Widget>[
            for (final preset in AiProviderPreset.supported)
              ChoiceChip(
                label: Text(preset.displayName),
                selected: _selectedPreset?.id == preset.id,
                onSelected: (_) => _selectPreset(preset),
              ),
            ChoiceChip(
              label: const Text('自定义'),
              selected: _selectedPreset == null,
              onSelected: (_) => _selectPreset(null),
            ),
          ],
        ),
        if (_selectedPreset != null) ...<Widget>[
          const SizedBox(height: 4),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: _openRegistration,
              icon: const Icon(CupertinoIcons.arrow_up_right_square, size: 16),
              label: Text('前往 ${_selectedPreset!.displayName} 获取 API Key'),
            ),
          ),
        ],
        const SizedBox(height: 8),
        TextField(
          controller: _urlController,
          readOnly: _selectedPreset != null,
          keyboardType: TextInputType.url,
          autocorrect: false,
          enableSuggestions: false,
          decoration: InputDecoration(
            labelText: 'Base URL',
            hintText: 'https://example.com/v1',
            helperText:
                _selectedPreset == null ? '填写兼容 OpenAI 的服务地址' : '已根据服务商自动填入',
            prefixIcon: const Icon(CupertinoIcons.link),
            suffixIcon: _selectedPreset == null
                ? null
                : const Icon(CupertinoIcons.lock),
          ),
          onChanged: _selectedPreset == null ? (_) => _showStatus(null) : null,
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _apiKeyController,
          obscureText: !_showApiKey,
          autocorrect: false,
          enableSuggestions: false,
          onChanged: (_) => _showStatus(null),
          decoration: InputDecoration(
            labelText: 'API Key',
            hintText: '粘贴你的 API Key',
            prefixIcon: const Icon(CupertinoIcons.lock),
            suffixIcon: IconButton(
              tooltip: _showApiKey ? '隐藏 API Key' : '显示 API Key',
              icon: Icon(
                _showApiKey ? CupertinoIcons.eye_slash : CupertinoIcons.eye,
              ),
              onPressed: () => setState(() => _showApiKey = !_showApiKey),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: <Widget>[
            Icon(CupertinoIcons.info_circle,
                size: 15, color: colorScheme.onSurfaceVariant),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                '可跳过 API Key：稍后在「设置」中配置即可；未配置时使用系统识别模式（标准模式）。',
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: colorScheme.onSurfaceVariant),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: <Widget>[
            Icon(CupertinoIcons.lock_shield,
                size: 15, color: colorScheme.onSurfaceVariant),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                'Key 仅用于直连所选服务商，不会发送到错题本服务。',
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: colorScheme.onSurfaceVariant),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _modelController,
          autocorrect: false,
          enableSuggestions: false,
          onChanged: (_) => _showStatus(null),
          decoration: const InputDecoration(
            labelText: '模型',
            hintText: '例如 deepseek-chat',
            prefixIcon: Icon(CupertinoIcons.sparkles),
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: <Widget>[
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _fetchingModels ? null : _fetchModels,
                icon: _fetchingModels
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(CupertinoIcons.arrow_clockwise, size: 18),
                label: Text(_fetchingModels ? '获取中...' : '获取可用模型'),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _testing ? null : _testConnection,
                icon: _testing
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(CupertinoIcons.checkmark_shield, size: 18),
                label: Text(_testing ? '测试中...' : '测试连接'),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          '「测试连接」会发送一张极小图片，确认当前模型支持图片识题；失败也可跳过继续。',
          style: theme.textTheme.bodySmall
              ?.copyWith(color: colorScheme.onSurfaceVariant),
        ),
        if (_statusMessage != null) ...<Widget>[
          const SizedBox(height: 12),
          _StatusBanner(message: _statusMessage!, isError: _statusIsError),
        ],
      ],
    );
  }
}

class _ModelSheet extends StatelessWidget {
  const _ModelSheet({required this.models});

  final List<String> models;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SafeArea(
      child: SizedBox(
        height: MediaQuery.sizeOf(context).height * 0.6,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
          children: <Widget>[
            Text('选择模型', style: theme.textTheme.titleLarge),
            const SizedBox(height: 8),
            for (final model in models)
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(model),
                trailing: const Icon(CupertinoIcons.chevron_right, size: 16),
                onTap: () => Navigator.pop(context, model),
              ),
          ],
        ),
      ),
    );
  }
}

class _StatusBanner extends StatelessWidget {
  const _StatusBanner({required this.message, required this.isError});

  final String message;
  final bool isError;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final color = isError ? const Color(0xFFEA580C) : const Color(0xFF16A34A);
    final background =
        isError ? const Color(0xFFFFF7ED) : const Color(0xFFF0FDF4);
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isDark ? color.withValues(alpha: 0.14) : background,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
            color: isDark ? color.withValues(alpha: 0.35) : background),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Icon(
            isError
                ? CupertinoIcons.exclamationmark_triangle_fill
                : CupertinoIcons.checkmark_circle_fill,
            size: 18,
            color: color,
          ),
          const SizedBox(width: 8),
          Expanded(child: Text(message, style: TextStyle(color: color))),
        ],
      ),
    );
  }
}
