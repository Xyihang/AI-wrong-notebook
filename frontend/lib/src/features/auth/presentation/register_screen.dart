import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:smart_wrong_notebook/src/app/auth_controller.dart';
import 'package:smart_wrong_notebook/src/features/glass/glass_top_bar.dart';
import 'package:smart_wrong_notebook/src/data/remote/backend/backend_client.dart';
import 'package:smart_wrong_notebook/src/features/auth/presentation/auth_theme.dart';

/// 注册页（含算术验证码）。
class RegisterScreen extends ConsumerStatefulWidget {
  const RegisterScreen({super.key});

  @override
  ConsumerState<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends ConsumerState<RegisterScreen> {
  final _formKey = GlobalKey<FormState>();
  final _username = TextEditingController();
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  final _displayName = TextEditingController();
  final _captchaAnswer = TextEditingController();
  bool _obscure = true;
  bool _submitting = false;
  bool _captchaLoading = true;
  String? _captchaId;
  String? _captchaImageBase64;
  String? _captchaError;

  @override
  void initState() {
    super.initState();
    _loadCaptcha();
  }

  @override
  void dispose() {
    _username.dispose();
    _password.dispose();
    _confirm.dispose();
    _displayName.dispose();
    _captchaAnswer.dispose();
    super.dispose();
  }

  Future<void> _loadCaptcha() async {
    setState(() {
      _captchaLoading = true;
      _captchaError = null;
    });
    try {
      final data = await BackendClient().fetchCaptcha();
      if (!mounted) return;
      setState(() {
        _captchaId = data['captcha_id'] as String?;
        _captchaImageBase64 = data['image_base64'] as String?;
        _captchaLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _captchaLoading = false;
        _captchaError = e is BackendClientException
            ? e.message
            : '验证码加载失败，请重试';
      });
    }
  }

  Future<void> _submit() async {
    if (_submitting) return;
    if (!(_formKey.currentState?.validate() ?? false)) return;
    if (_captchaId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请先加载验证码')),
      );
      return;
    }
    setState(() => _submitting = true);
    final result = await ref
        .read(authControllerProvider.notifier)
        .register(
          _username.text,
          _password.text,
          displayName: _displayName.text.trim(),
          captchaId: _captchaId!,
          captchaAnswer: _captchaAnswer.text.trim(),
        );
    if (!mounted) return;
    setState(() => _submitting = false);
    if (result.success) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('注册成功，已自动登录')),
      );
      context.go('/');
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('注册失败：${result.error ?? '未知错误'}')),
      );
      // 验证码可能已销毁，自动刷新一张
      _captchaAnswer.clear();
      _loadCaptcha();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: glassTopBar(context, title: const Text('注册')),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 16),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: Form(
                key: _formKey,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Center(child: AuthLogo()),
                    const SizedBox(height: 20),
                    Text(
                      '创建账号',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.headlineSmall
                          ?.copyWith(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 24),
                    TextFormField(
                      controller: _username,
                      enabled: !_submitting,
                      textInputAction: TextInputAction.next,
                      decoration: const InputDecoration(
                        labelText: '用户名',
                        prefixIcon: Icon(Icons.person_outline),
                        border: OutlineInputBorder(),
                      ),
                      validator: (v) {
                        final s = v?.trim() ?? '';
                        if (s.isEmpty) return '请输入用户名';
                        if (s.length > 64) return '用户名不能超过 64 字符';
                        return null;
                      },
                    ),
                    const SizedBox(height: 14),
                    TextFormField(
                      controller: _displayName,
                      enabled: !_submitting,
                      textInputAction: TextInputAction.next,
                      decoration: const InputDecoration(
                        labelText: '展示名（可选）',
                        prefixIcon: Icon(Icons.badge_outlined),
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 14),
                    TextFormField(
                      controller: _password,
                      enabled: !_submitting,
                      obscureText: _obscure,
                      textInputAction: TextInputAction.next,
                      decoration: InputDecoration(
                        labelText: '密码',
                        prefixIcon: const Icon(Icons.lock_outline),
                        border: const OutlineInputBorder(),
                        helperText: '至少 6 位',
                        suffixIcon: IconButton(
                          icon: Icon(_obscure
                              ? Icons.visibility_off
                              : Icons.visibility),
                          onPressed: () =>
                              setState(() => _obscure = !_obscure),
                        ),
                      ),
                      validator: (v) =>
                          (v == null || v.length < 6) ? '密码至少 6 位' : null,
                    ),
                    const SizedBox(height: 14),
                    TextFormField(
                      controller: _confirm,
                      enabled: !_submitting,
                      obscureText: _obscure,
                      textInputAction: TextInputAction.next,
                      decoration: const InputDecoration(
                        labelText: '确认密码',
                        prefixIcon: Icon(Icons.lock_outline),
                        border: OutlineInputBorder(),
                      ),
                      validator: (v) =>
                          (v != _password.text) ? '两次密码不一致' : null,
                    ),
                    const SizedBox(height: 18),
                    // 验证码区
                    Text(
                      '验证码',
                      style: theme.textTheme.bodyMedium
                          ?.copyWith(fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Expanded(
                          child: TextFormField(
                            controller: _captchaAnswer,
                            enabled: !_submitting,
                            keyboardType: TextInputType.number,
                            decoration: const InputDecoration(
                              labelText: '图中算式结果',
                              prefixIcon: Icon(Icons.calculate_outlined),
                              border: OutlineInputBorder(),
                              isDense: true,
                            ),
                            validator: (v) =>
                                (v == null || v.trim().isEmpty)
                                    ? '请输入答案'
                                    : null,
                          ),
                        ),
                        const SizedBox(width: 12),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: _buildCaptchaImage(),
                        ),
                        IconButton(
                          tooltip: '换一张',
                          onPressed: _submitting ? null : _loadCaptcha,
                          icon: const Icon(Icons.refresh),
                        ),
                      ],
                    ),
                    if (_captchaError != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: Text(
                          _captchaError!,
                          style: theme.textTheme.bodySmall
                              ?.copyWith(color: theme.colorScheme.error),
                        ),
                      ),
                    const SizedBox(height: 22),
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
                          : const Text('注册并登录'),
                    ),
                    const SizedBox(height: 10),
                    TextButton(
                      onPressed: _submitting ? null : () => context.go('/login'),
                      child: const Text('已有账号？去登录'),
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

  Widget _buildCaptchaImage() {
    if (_captchaLoading) {
      return Container(
        width: 120,
        height: 52,
        alignment: Alignment.center,
        color: Colors.black12,
        child: const SizedBox(
          width: 18,
          height: 18,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      );
    }
    final b64 = _captchaImageBase64;
    if (b64 == null || b64.isEmpty) {
      return Container(
        width: 120,
        height: 52,
        alignment: Alignment.center,
        color: Colors.black12,
        child: const Icon(Icons.broken_image, color: Colors.white),
      );
    }
    return Image.memory(
      base64Decode(b64),
      width: 120,
      height: 52,
      fit: BoxFit.cover,
      gaplessPlayback: true,
    );
  }
}
