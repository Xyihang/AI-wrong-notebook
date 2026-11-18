import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:smart_wrong_notebook/src/app/auth_controller.dart';
import 'package:smart_wrong_notebook/src/app/providers.dart';
import 'package:smart_wrong_notebook/src/core/constants/app_config.dart';
import 'package:smart_wrong_notebook/src/data/remote/config/backend_config_resolver.dart';
import 'package:smart_wrong_notebook/src/features/auth/presentation/auth_theme.dart';

/// 登录页。
class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _username = TextEditingController();
  final _password = TextEditingController();
  bool _obscure = true;
  bool _submitting = false;

  @override
  void dispose() {
    _username.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_submitting) return;
    if (!(_formKey.currentState?.validate() ?? false)) return;
    // 地址只能由 App 自动获取；若尚未取到则再试一次（不允许用户手动填写）。
    if (AppConfig.currentBaseUrl.trim().isEmpty) {
      await BackendConfigResolver().resolve();
      if (AppConfig.currentBaseUrl.trim().isEmpty) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('暂时无法获取服务器地址，请检查网络后重试'),
          ),
        );
        return;
      }
    }
    setState(() => _submitting = true);
    final result = await ref
        .read(authControllerProvider.notifier)
        .login(_username.text, _password.text);
    if (!mounted) return;
    setState(() => _submitting = false);
    if (result.success) {
      context.go('/');
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('登录失败：${result.error ?? '未知错误'}')),
      );
    }
  }

  /// 游客模式：必须先配置好「支持视觉」的 AI 服务（用自己的 Key 直连，无额度限制）。
  /// 进入时提醒用户登录；游客态不持久化，每次启动都需重新选择。
  Future<void> _enterGuest() async {
    if (_submitting) return;
    final repo = ref.read(settingsRepositoryProvider);
    final config = await repo.getAiProviderConfig();
    final configured = config != null &&
        config.apiKey.trim().isNotEmpty &&
        config.baseUrl.trim().isNotEmpty;

    // 未配置（缺 Base URL / API Key）才拦截。
    if (!configured) {
      if (!mounted) return;
      final go = await showDialog<bool>(
        context: context,
        builder: (c) => AlertDialog(
          title: const Text('游客模式需要先配置 AI'),
          content: const Text(
            '游客模式不消耗平台额度，AI 分析使用你自己的 API Key。\n'
            '请先在「AI 服务配置」里填写 Base URL、API Key 和模型，再进入游客模式。',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(c, true),
              child: const Text('去配置'),
            ),
          ],
        ),
      );
      if (go == true && mounted) context.push('/guest/provider');
      return;
    }

    // 已配置：模型支持视觉时走前端直连（不占平台额度）；
    // 不支持视觉时仍然放行，但明确提示拍照识别会回退平台兜底（有限额）。
    // deepseek-flash 官方支持 Vision（名字含 flash 也视为视觉模型）。
    final visionCapable = config.model.toLowerCase().contains('vision') ||
        config.model.toLowerCase().contains('flash');
    await repo.setUseVisionMode(visionCapable);
    await ref.read(authControllerProvider.notifier).enterGuest();
    if (!mounted) return;

    if (!visionCapable) {
      await showDialog<void>(
        context: context,
        builder: (c) => AlertDialog(
          title: const Text('提示：当前模型不含视觉能力'),
          content: Text(
            '模型「${config.model}」看起来不是视觉模型：\n'
            '· 文字类分析会使用你自己的 Key（无平台额度限制）；\n'
            '· 拍照读图可能会回退到平台视觉兜底（有额度限制）。\n\n'
            '想完全无限制，请在「AI 服务配置」里换成视觉模型'
            '（如 deepseek-flash，已原生支持视觉）。',
          ),
          actions: [
            FilledButton(
              onPressed: () => Navigator.pop(c),
              child: const Text('知道了'),
            ),
          ],
        ),
      );
      if (!mounted) return;
    }

    // 「建议登录」提示框改在首页弹出：进入游客态后路由会立刻重定向到首页，
    // 若在此处弹窗会被登录页销毁一起带走（表现为一闪而过）。
    if (!mounted) return;
    context.go('/');
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Form(
                key: _formKey,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const SizedBox(height: 12),
                    Center(child: AuthLogo()),
                    const SizedBox(height: 20),
                    Text(
                      '登录',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.headlineSmall
                          ?.copyWith(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      '登录后错题按账号隔离保存',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodyMedium
                          ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                    ),
                    const SizedBox(height: 28),
                    TextFormField(
                      controller: _username,
                      enabled: !_submitting,
                      textInputAction: TextInputAction.next,
                      decoration: const InputDecoration(
                        labelText: '用户名',
                        prefixIcon: Icon(Icons.person_outline),
                        border: OutlineInputBorder(),
                      ),
                      validator: (v) =>
                          (v == null || v.trim().isEmpty) ? '请输入用户名' : null,
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _password,
                      enabled: !_submitting,
                      obscureText: _obscure,
                      onFieldSubmitted: (_) => _submit(),
                      decoration: InputDecoration(
                        labelText: '密码',
                        prefixIcon: const Icon(Icons.lock_outline),
                        border: const OutlineInputBorder(),
                        suffixIcon: IconButton(
                          icon: Icon(_obscure
                              ? Icons.visibility_off
                              : Icons.visibility),
                          onPressed: () =>
                              setState(() => _obscure = !_obscure),
                        ),
                      ),
                      validator: (v) =>
                          (v == null || v.isEmpty) ? '请输入密码' : null,
                    ),
                    const SizedBox(height: 24),
                    FilledButton(
                      onPressed: _submitting ? null : _submit,
                      style: FilledButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                      child: _submitting
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Text('登录'),
                    ),
                    const SizedBox(height: 12),
                    TextButton(
                      onPressed: _submitting
                          ? null
                          : () => context.go('/register'),
                      child: const Text('没有账号？去注册'),
                    ),
                    const SizedBox(height: 4),
                    TextButton.icon(
                      onPressed: _submitting ? null : _enterGuest,
                      icon: const Icon(Icons.person_outline, size: 18),
                      label: const Text('游客模式（使用自己的 AI Key）'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
