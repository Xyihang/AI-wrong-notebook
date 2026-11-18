import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:smart_wrong_notebook/src/app/theme/app_theme.dart';

/// 接管 Android 物理返回键：
/// - 有可回退的页面栈（push 出来的页面）→ 正常应用内返回；
/// - 没有栈但不在首页（用 go() 切换的页面/底部 Tab）→ 回到首页；
/// - 已在首页 → 交给系统，正常退出。
///
/// 说明：之前把 PopScope 放在 MaterialApp 外面是无效的（不在路由栈内，
/// 收不到返回事件），所以会直接退出。这里改为在根返回分发器上拦截。
class _AppBackButtonDispatcher extends RootBackButtonDispatcher {
  _AppBackButtonDispatcher(this.router);

  final GoRouter router;

  @override
  Future<bool> invokeCallback(Future<bool> defaultValue) {
    final path = router.routeInformationProvider?.value.uri.path ?? '/';
    if (!router.canPop() && path != '/' && path.isNotEmpty) {
      router.go('/');
      return Future<bool>.value(true);
    }
    return super.invokeCallback(defaultValue);
  }
}

class SmartWrongNotebookApp extends ConsumerWidget {
  const SmartWrongNotebookApp({required this.routerConfig, super.key});

  final GoRouter routerConfig;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return MaterialApp.router(
      title: 'AI错题本',
      theme: buildLightTheme(),
      darkTheme: buildDarkTheme(),
      themeMode: ThemeMode.light,
      debugShowCheckedModeBanner: false,
      routeInformationProvider: routerConfig.routeInformationProvider,
      routeInformationParser: routerConfig.routeInformationParser,
      routerDelegate: routerConfig.routerDelegate,
      backButtonDispatcher: _AppBackButtonDispatcher(routerConfig),
    );
  }
}
