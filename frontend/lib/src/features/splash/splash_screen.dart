import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:smart_wrong_notebook/src/app/auth_controller.dart';
import 'package:smart_wrong_notebook/src/app/providers.dart';
import 'package:smart_wrong_notebook/src/features/glass/glass_warmup.dart';

/// 启动页：纯代码 Logo + 版本号 + 版权信息。
///
/// 流程：蓝色原生启动屏 → 本页（代码 Logo + 文案）→ 停留片刻 →
/// 加载持久化登录会话 → 首次启动进配置向导（/setup），否则进首页（/）。
/// 未登录时由路由守卫重定向到登录页（/login）。
class SplashScreen extends ConsumerStatefulWidget {
  const SplashScreen({super.key});

  @override
  ConsumerState<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends ConsumerState<SplashScreen> {
  bool _navigated = false;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    // 停留约 5 秒后跳转（期间加载登录会话）
    _timer = Timer(const Duration(seconds: 5), _finish);
  }

  Future<void> _finish() async {
    if (_navigated || !mounted) return;
    _navigated = true;
    _timer?.cancel();
    // 玻璃 shader 在开屏期间并行预热；最多等 1.2s，超时则先以最小档渲染。
    try {
      await glassWarmUpFuture?.timeout(const Duration(milliseconds: 1200));
    } catch (_) {}
    // 加载持久化会话（含自动登录）。加载完成后路由守卫依据 auth 状态决定去向。
    await ref.read(authControllerProvider.notifier).load();
    if (!mounted) return;
    // 首次启动（未完成配置向导）→ 进 /setup；否则进首页 /（未登录由守卫转登录页）
    bool setupDone = false;
    try {
      setupDone = await ref.read(settingsRepositoryProvider).getSetupComplete();
    } catch (_) {}
    if (!mounted) return;
    context.go(setupDone ? '/' : '/setup');
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // 品牌主色（靛蓝，与图标一致）
    const brandColor = Color(0xFF6366F1);
    return Scaffold(
      backgroundColor: Colors.white,
      body: Stack(
        fit: StackFit.expand,
        children: [
          // 居中内容：代码 Logo + 应用名 + 版本号
          Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // 代码 Logo：圆角方块 + 对勾 + 铅笔
              _buildLogo(brandColor),
              const SizedBox(height: 24),
              const Text(
                'AI 错题本',
                style: TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF1F2937),
                ),
              ),
              const SizedBox(height: 10),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                decoration: BoxDecoration(
                  color: const Color(0xFF6366F1).withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const Text(
                  'V2.3 内测版',
                  style: TextStyle(
                    fontSize: 13,
                    color: brandColor,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          // 底部版权小字
          const SafeArea(
            child: Align(
              alignment: Alignment.bottomCenter,
              child: Padding(
                padding: EdgeInsets.only(bottom: 24),
                child: Text(
                  '@Xyihang 2026/8/23',
                  style: TextStyle(
                    fontSize: 12,
                    color: Color(0xFF9CA3AF),
                  ),
                ),
              ),
            ),
          ),
          // 跳过按钮
          SafeArea(
            child: Align(
              alignment: Alignment.topRight,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: TextButton(
                  onPressed: _finish,
                  style: TextButton.styleFrom(foregroundColor: brandColor),
                  child: const Text('跳过'),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// 用代码绘制的 Logo：圆角方块 + 白色对勾 + 斜放铅笔。
  Widget _buildLogo(Color brandColor) {
    return Container(
      width: 96,
      height: 96,
      decoration: BoxDecoration(
        color: brandColor,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: brandColor.withValues(alpha: 0.3),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: const Center(
        child: Icon(
          Icons.edit_note,
          color: Colors.white,
          size: 52,
        ),
      ),
    );
  }
}
