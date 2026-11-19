import 'package:flutter/material.dart';

/// 全局滚动偏移（0 = 顶部）。由外壳层监听滚动更新，供顶栏做"透明→实心"过渡。
final ValueNotifier<double> globalScrollOffset = ValueNotifier<double>(0);

/// 包裹页面内容，把滚动偏移写入 [globalScrollOffset]。
class ScrollTintListener extends StatelessWidget {
  const ScrollTintListener({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return NotificationListener<ScrollNotification>(
      onNotification: (notification) {
        final metrics = notification.metrics;
        final v = metrics.pixels;
        if (globalScrollOffset.value != v) globalScrollOffset.value = v;
        return false;
      },
      child: child,
    );
  }
}
