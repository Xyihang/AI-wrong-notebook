import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';
import 'package:smart_wrong_notebook/src/features/glass/glass_providers.dart';

/// 玻璃下拉刷新（B6）。
///
/// 用滚动 overscroll 距离驱动一个玻璃胶囊指示器，松手超过阈值触发
/// [onRefresh]；玻璃关闭时不显示指示器（手势仍然无效，保持 Material 观感）。
class GlassRefreshIndicator extends ConsumerStatefulWidget {
  const GlassRefreshIndicator({
    required this.onRefresh,
    required this.child,
    this.edgeOffset = 0,
    this.triggerDistance = 64,
    super.key,
  });

  final Future<void> Function() onRefresh;
  final Widget child;

  /// 指示器距滚动区顶部的距离（穿透式顶栏时可传入顶栏高度）。
  final double edgeOffset;
  final double triggerDistance;

  @override
  ConsumerState<GlassRefreshIndicator> createState() =>
      _GlassRefreshIndicatorState();
}

class _GlassRefreshIndicatorState extends ConsumerState<GlassRefreshIndicator> {
  double _pull = 0;
  bool _refreshing = false;

  Future<void> _run() async {
    setState(() => _refreshing = true);
    try {
      await widget.onRefresh();
    } catch (_) {
      // 刷新失败不打扰用户，列表本身会显示错误态
    }
    if (!mounted) return;
    setState(() {
      _refreshing = false;
      _pull = 0;
    });
  }

  @override
  Widget build(BuildContext context) {
    final enabled = ref.watch(glassEnabledProvider);
    if (!enabled) return widget.child;
    final quality = ref.watch(glassQualityProvider);

    final progress =
        (_pull / widget.triggerDistance).clamp(0.0, 1.0).toDouble();
    final showIndicator = _refreshing || _pull > 4;

    return NotificationListener<ScrollNotification>(
      onNotification: (notification) {
        if (_refreshing) return false;
        if (notification is OverscrollNotification &&
            notification.overscroll < 0) {
          setState(() {
            _pull = math.min(
                widget.triggerDistance * 1.5, _pull - notification.overscroll);
          });
        } else if (notification is ScrollUpdateNotification &&
            notification.metrics.pixels > 0 &&
            _pull > 0) {
          setState(() => _pull = 0);
        } else if (notification is ScrollEndNotification) {
          if (_pull >= widget.triggerDistance) {
            _run();
          } else if (_pull > 0) {
            setState(() => _pull = 0);
          }
        }
        return false;
      },
      child: Stack(
        children: <Widget>[
          widget.child,
          if (showIndicator)
            Positioned(
              top: widget.edgeOffset + 6 + _pull * 0.35,
              left: 0,
              right: 0,
              child: Center(
                child: GlassContainer(
                  quality: quality,
                  shape: const LiquidRoundedSuperellipse(borderRadius: 18),
                  padding: const EdgeInsets.symmetric(
                      horizontal: 14, vertical: 10),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          value: _refreshing ? null : progress,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        _refreshing ? '刷新中…' : (_pull >= widget.triggerDistance ? '松开刷新' : '下拉刷新'),
                        style: const TextStyle(fontSize: 12),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
