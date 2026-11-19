import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:smart_wrong_notebook/src/app/providers.dart';

class CaptureEntrySheet extends ConsumerStatefulWidget {
  const CaptureEntrySheet({super.key});

  @override
  ConsumerState<CaptureEntrySheet> createState() => _CaptureEntrySheetState();
}

class _CaptureEntrySheetState extends ConsumerState<CaptureEntrySheet> {
  bool _isLoading = false;
  String? _errorMessage;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    const orange = Color(0xFFEA580C);

    return SizedBox(
      width: double.infinity,
      // 固定高度：入口态与「正在打开相机」态占据完全相同的尺寸与位置
      height: 300,
      child: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: colorScheme.onSurfaceVariant.withValues(alpha: 0.35),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 20),
            Text(
              '添加错题',
              style: Theme.of(context)
                  .textTheme
                  .titleMedium
                  ?.copyWith(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 20),
            if (_isLoading)
              Container(
                padding: const EdgeInsets.all(40),
                child: Column(
                  children: <Widget>[
                    const CircularProgressIndicator(),
                    const SizedBox(height: 16),
                    Text('正在打开相机...',
                        style: TextStyle(color: colorScheme.onSurfaceVariant)),
                  ],
                ),
              )
            else ...<Widget>[
              _EntryOption(
                icon: CupertinoIcons.camera,
                iconColor: const Color(0xFF6366F1),
                iconBg: isDark
                    ? const Color(0xFF6366F1).withValues(alpha: 0.16)
                    : const Color(0xFFEEF2FF),
                label: '拍照',
                description: '使用相机拍摄错题',
                onTap: () => _pickAndNavigate(fromCamera: true),
              ),
              const SizedBox(height: 10),
              _EntryOption(
                icon: CupertinoIcons.photo,
                iconColor: const Color(0xFFD97706),
                iconBg: isDark
                    ? const Color(0xFFD97706).withValues(alpha: 0.16)
                    : const Color(0xFFFFFBEB),
                label: '相册',
                description: '从相册选择图片',
                onTap: () => _pickAndNavigate(fromCamera: false),
              ),
            ],
            if (_errorMessage != null) ...<Widget>[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: isDark
                      ? orange.withValues(alpha: 0.14)
                      : const Color(0xFFFFF7ED),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                      color: isDark
                          ? orange.withValues(alpha: 0.35)
                          : const Color(0xFFFED7AA)),
                ),
                child: Row(
                  children: <Widget>[
                    const Icon(CupertinoIcons.exclamationmark_triangle,
                        size: 18, color: orange),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(_errorMessage!,
                          style: TextStyle(
                              fontSize: 12,
                              color:
                                  isDark ? orange : const Color(0xFF9A3412))),
                    ),
                    IconButton(
                      icon: const Icon(CupertinoIcons.xmark, size: 16),
                      onPressed: () => setState(() => _errorMessage = null),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                    ),
                  ],
                ),
              ),
            ],
          ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _pickAndNavigate({required bool fromCamera}) async {
    final router = GoRouter.of(context);

    // 检查是否有可用的后端地址（云端地址已锁死，未配置 Key 也能用标准模式）。
    // 无 Key 用户拍照后走后端标准模式（云端后端识别），不强制要求本地配置 API Key。
    final config =
        await ref.read(settingsRepositoryProvider).getAiProviderConfig();
    final hasUsableBackend = config != null && config.baseUrl.trim().isNotEmpty;
    if (!hasUsableBackend) {
      setState(() => _isLoading = false);
      setState(() => _errorMessage = '请先在设置中配置 AI 服务');
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final capture = ref.read(captureServiceProvider);
      final result = fromCamera
          ? await capture.pickFromCamera()
          : await capture.pickFromGallery();

      if (!mounted) return;

      setState(() => _isLoading = false);

      if (result.isCancelled) {
        // User cancelled - just close the sheet silently
        Navigator.pop(context);
        return;
      }

      if (result.errorMessage != null) {
        // Show error message
        String message;
        if (result.errorMessage!.contains('permission')) {
          message = '相机权限被拒绝，请在系统设置中开启';
        } else {
          message = '打开失败: ${result.errorMessage}';
        }
        setState(() => _errorMessage = message);
        return;
      }

      if (result.record != null) {
        Navigator.pop(context);
        ref.read(currentQuestionProvider.notifier).state = result.record;
        // 拍照后进裁剪屏（自由裁剪）
        debugPrint('[CaptureEntrySheet] Navigating to /capture/crop');
        router.go('/capture/crop');
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _errorMessage = '操作失败: $e';
      });
    }
  }
}

class _EntryOption extends StatelessWidget {
  const _EntryOption({
    required this.icon,
    required this.iconColor,
    required this.iconBg,
    required this.label,
    required this.description,
    required this.onTap,
  });

  final IconData icon;
  final Color iconColor;
  final Color iconBg;
  final String label;
  final String description;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: colorScheme.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: colorScheme.outlineVariant),
        ),
        child: Row(
          children: <Widget>[
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: iconBg,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Icon(icon, size: 20, color: iconColor),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Text(label,
                  style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w500,
                      color: colorScheme.onSurface)),
            ),
            Icon(CupertinoIcons.chevron_right,
                size: 20,
                color: colorScheme.onSurfaceVariant.withValues(alpha: 0.5)),
          ],
        ),
      ),
    );
  }
}
