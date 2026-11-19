import 'package:flutter/material.dart';
import 'package:smart_wrong_notebook/src/app/design/tokens.dart';

/// 首页右下角悬浮拍照按钮（demo `.fab`）：52×52、圆角 18、primary 底、shadow2。
class AppFab extends StatelessWidget {
  const AppFab({
    required this.icon,
    required this.onTap,
    this.tooltip,
    super.key,
  });

  final IconData icon;
  final VoidCallback onTap;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final button = Material(
      color: t.primary,
      borderRadius: BorderRadius.circular(18),
      elevation: 0,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: SizedBox(
          width: 52,
          height: 52,
          child: Icon(icon, size: 24, color: t.onPrimary),
        ),
      ),
    );
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        boxShadow: t.isDark ? null : t.shadow2,
      ),
      child: tooltip == null
          ? button
          : Tooltip(message: tooltip!, child: button),
    );
  }
}

/// 滚动区底部渐隐：把列表最后一段柔和过渡到页面背景（demo `mask-image`）。
class AppBottomFade extends StatelessWidget {
  const AppBottomFade({this.height = 28, this.ignorePointer = true, super.key});

  final double height;
  final bool ignorePointer;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final fade = SizedBox(
      height: height,
      width: double.infinity,
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: <Color>[
              t.bgPage.withValues(alpha: 0),
              t.bgPage.withValues(alpha: 0.85),
            ],
          ),
        ),
      ),
    );
    return ignorePointer ? IgnorePointer(child: fade) : fade;
  }
}
