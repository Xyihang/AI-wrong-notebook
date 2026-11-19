import 'package:flutter/material.dart';

/// 统一页面转场：淡入 + 轻微上移（轻量、iOS 感）。
///
/// - 中/高档：淡入 + 12px 上移（0.02 屏高），220ms easeOutCubic
/// - 低档：只淡入（不位移，省一次合成）
/// - 返回：180ms easeOutCubic
class AppFadeSlideTransitionsBuilder extends PageTransitionsBuilder {
  const AppFadeSlideTransitionsBuilder({
    this.slideFraction = 0.02,
    this.duration = const Duration(milliseconds: 220),
  });

  /// 位移幅度（占屏高比例），0 表示纯淡入。
  final double slideFraction;
  final Duration duration;

  @override
  Duration get transitionDuration => duration;

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    final curved = CurvedAnimation(
      parent: animation,
      curve: Curves.easeOutCubic,
      reverseCurve: Curves.easeOutCubic,
    );
    final faded = FadeTransition(opacity: curved, child: child);
    if (slideFraction <= 0) return faded;
    return SlideTransition(
      position: Tween<Offset>(
        begin: Offset(0, slideFraction),
        end: Offset.zero,
      ).animate(curved),
      child: faded,
    );
  }
}
