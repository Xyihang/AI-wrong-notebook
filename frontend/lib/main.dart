import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:smart_wrong_notebook/src/app/providers.dart';
import 'package:smart_wrong_notebook/src/config/scroll_tint.dart';
import 'package:smart_wrong_notebook/src/common/widgets/app_fab.dart';
import 'package:smart_wrong_notebook/src/features/glass/glass_edge_fade.dart';
import 'package:smart_wrong_notebook/src/features/glass/glass_overlays.dart';
import 'package:smart_wrong_notebook/src/app/auth_controller.dart';
import 'package:smart_wrong_notebook/src/features/auth/presentation/login_screen.dart';
import 'package:smart_wrong_notebook/src/features/auth/presentation/register_screen.dart';
import 'package:smart_wrong_notebook/src/data/repositories/drift_settings_repository.dart';
import 'package:smart_wrong_notebook/src/data/repositories/drift_question_repository.dart';
import 'package:smart_wrong_notebook/src/data/repositories/syncing_question_repository.dart';
import 'package:smart_wrong_notebook/src/data/repositories/drift_ai_conversation_repository.dart';
import 'package:smart_wrong_notebook/src/data/repositories/drift_analysis_job_repository.dart';
import 'package:smart_wrong_notebook/src/data/local/app_database.dart';
import 'package:smart_wrong_notebook/src/data/remote/ai/ai_analysis_service.dart';
import 'package:smart_wrong_notebook/src/data/services/app_analysis_job_runner.dart';
import 'package:smart_wrong_notebook/src/data/services/ai_learning_task_coordinator.dart';
import 'package:smart_wrong_notebook/src/data/services/question_analysis_coordinator.dart';
import 'package:smart_wrong_notebook/src/domain/services/analysis_job_queue_executor.dart';
import 'package:smart_wrong_notebook/src/app/theme/app_theme.dart';
import 'package:smart_wrong_notebook/src/features/home/presentation/home_screen.dart';
import 'package:smart_wrong_notebook/src/features/notebook/presentation/notebook_screen.dart';
import 'package:smart_wrong_notebook/src/features/notebook/presentation/question_detail_screen.dart';
import 'package:smart_wrong_notebook/src/features/review/presentation/review_screen.dart';
import 'package:smart_wrong_notebook/src/features/onboarding/presentation/onboarding_screen.dart';
import 'package:smart_wrong_notebook/src/features/settings/presentation/settings_screen.dart';
import 'package:smart_wrong_notebook/src/features/settings/presentation/provider_config_screen.dart';
import 'package:smart_wrong_notebook/src/features/settings/presentation/subject_management_screen.dart';
import 'package:smart_wrong_notebook/src/features/settings/presentation/prompt_settings_screen.dart';
import 'package:smart_wrong_notebook/src/features/settings/presentation/data_management_screen.dart';
import 'package:smart_wrong_notebook/src/features/capture/presentation/question_correction_screen.dart';
import 'package:smart_wrong_notebook/src/features/capture/presentation/image_crop_screen.dart';
import 'package:smart_wrong_notebook/src/features/ocr/presentation/question_save_confirmation_screen.dart';
import 'package:smart_wrong_notebook/src/features/ocr/presentation/question_split_confirmation_screen.dart';
import 'package:smart_wrong_notebook/src/features/analysis/presentation/analysis_loading_screen.dart';
import 'package:smart_wrong_notebook/src/features/analysis/presentation/analysis_result_screen.dart';
import 'package:smart_wrong_notebook/src/features/analysis/presentation/question_text_correction_screen.dart';
import 'package:smart_wrong_notebook/src/features/analysis/presentation/exercise_practice_screen.dart';
import 'package:smart_wrong_notebook/src/features/review/presentation/review_history_screen.dart';
import 'package:smart_wrong_notebook/src/data/files/image_storage_service.dart';
import 'package:smart_wrong_notebook/src/shared/widgets/katex_math_view.dart';
import 'package:smart_wrong_notebook/src/features/splash/splash_screen.dart';
import 'package:smart_wrong_notebook/src/features/setup/setup_wizard_screen.dart';
import 'package:smart_wrong_notebook/src/features/achievements/presentation/achievements_screen.dart';
import 'package:smart_wrong_notebook/src/features/paper/presentation/paper_setup_screen.dart';
import 'package:smart_wrong_notebook/src/features/paper/presentation/paper_preview_screen.dart';
import 'package:smart_wrong_notebook/src/data/remote/config/backend_config_resolver.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';
import 'package:smart_wrong_notebook/src/features/glass/device_profile.dart';
import 'package:smart_wrong_notebook/src/features/glass/glass_appearance.dart';
import 'package:smart_wrong_notebook/src/features/glass/glass_providers.dart';
import 'package:smart_wrong_notebook/src/features/glass/page_background.dart';
import 'package:smart_wrong_notebook/src/features/glass/glass_warmup.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  KatexMathView.preload();

  // 先从远程配置仓库解析后端地址（失败静默降级为缓存/打包默认值）。
  // 这样以后换服务器只改配置仓库，无需重新打包 App。
  try {
    await BackendConfigResolver().resolve();
  } catch (_) {}

  final navigatorKey = GlobalKey<NavigatorState>();
  final db = AppDatabase();
  final settingsRepo = DriftSettingsRepository(db);

  // 玻璃外观：读取用户偏好 + 采集设备画像判档（默认中档）。
  var glassAppearance = GlassAppearance.auto;
  var deviceTier = GlassTier.mid;
  var backgroundSelection = BackgroundSelection(
    light: PageBackground.defaultFor(dark: false),
    dark: PageBackground.defaultFor(dark: true),
  );
  try {
    glassAppearance = GlassAppearance.fromStorage(
      await settingsRepo.getString(GlassAppearanceNotifier.key),
    );
    backgroundSelection = BackgroundSelection(
      light: PageBackground.fromStorage(
          await settingsRepo.getString(PageBackgroundNotifier.lightKey),
          dark: false),
      dark: PageBackground.fromStorage(
          await settingsRepo.getString(PageBackgroundNotifier.darkKey),
          dark: true),
    );
    final profile = await DeviceProfile.collect();
    deviceTier = profile.resolveTier();
    debugPrint('[Glass] tier=${deviceTier.name} '
        'cores=${profile.cores} ram=${profile.ramMb}MB '
        'hz=${profile.refreshHz.toStringAsFixed(0)} api=${profile.sdkInt} '
        'appearance=${glassAppearance.name}');
  } catch (_) {}
  // 开屏动画期间预热 shader（不阻塞启动）。
  startGlassWarmUp();

  final authController = AuthController(settingsRepo);
  final questionRepo = SyncingQuestionRepository(DriftQuestionRepository(db));
  final aiConversationRepo = DriftAiConversationRepository(db);
  final aiService = AiAnalysisService(
    settingsRepository: settingsRepo,
    largeTokenRetryNotifier: () async {
      // 大 token 重试前的提示弹窗（仅提示，不询问选择）。
      final ctx = navigatorKey.currentContext;
      if (ctx == null) return;
      await showAppDialog<void>(ctx,
        builder: (dialogCtx) => AlertDialog(
          title: const Text('题目较复杂'),
          content: const Text(
              '当前题目内容较复杂，AI 首次分析未返回完整结果。\n'
              '正在使用更大的输出额度（MAXTOKEN）自动重试一次，'
              '本次约多花费 ¥0.05 左右。'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogCtx).pop(),
              child: const Text('知道了'),
            ),
          ],
        ),
      );
    },
  );
  final analysisJobRepo = DriftAnalysisJobRepository(db);
  final analysisJobExecutor = AnalysisJobQueueExecutor(
    repository: analysisJobRepo,
    runner: AppAnalysisJobRunner(
      aiService,
      questionRepository: questionRepo,
      analysisJobRepository: analysisJobRepo,
    ),
  );
  final questionAnalysisCoordinator = QueuedQuestionAnalysisCoordinator(
    service: aiService,
    settingsRepository: settingsRepo,
    repository: analysisJobRepo,
    executor: analysisJobExecutor,
  );
  final aiLearningTaskCoordinator = QueuedAiLearningTaskCoordinator(
    settingsRepository: settingsRepo,
    repository: analysisJobRepo,
    executor: analysisJobExecutor,
    questionRepository: questionRepo,
  );

  final router = GoRouter(
    navigatorKey: navigatorKey,
    initialLocation: '/splash',
    refreshListenable: authController.refreshListenable,
    redirect: _authRedirect(authController),
    routes: [
      GoRoute(
          path: '/splash',
          builder: (context, state) => const SplashScreen()),
      GoRoute(
          path: '/setup',
          builder: (context, state) => const SetupWizardScreen()),
      GoRoute(
          path: '/login',
          builder: (context, state) => const LoginScreen()),
      GoRoute(
          path: '/register',
          builder: (context, state) => const RegisterScreen()),
      GoRoute(
          path: '/onboarding',
          builder: (context, state) => const OnboardingScreen()),
      StatefulShellRoute.indexedStack(
        builder: (BuildContext context, GoRouterState state,
            StatefulNavigationShell navigationShell) {
          return ScaffoldWithNavBar(navigationShell: navigationShell);
        },
        branches: <StatefulShellBranch>[
          StatefulShellBranch(routes: [
            GoRoute(path: '/', builder: (_, __) => const HomeScreen())
          ]),
          StatefulShellBranch(routes: [
            GoRoute(
                path: '/notebook', builder: (_, __) => const NotebookScreen())
          ]),
          StatefulShellBranch(routes: [
            GoRoute(path: '/review', builder: (_, __) => const ReviewScreen())
          ]),
          StatefulShellBranch(routes: [
            GoRoute(
              path: '/settings',
              builder: (_, __) => const SettingsScreen(),
              routes: [
                GoRoute(
                    path: 'provider',
                    builder: (_, __) => const ProviderConfigScreen()),
                GoRoute(
                    path: 'subjects',
                    builder: (_, __) => const SubjectManagementScreen()),
                GoRoute(
                    path: 'prompts',
                    builder: (_, __) => const PromptSettingsScreen()),
                GoRoute(
                    path: 'data',
                    builder: (_, __) => const DataManagementScreen()),
              ],
            ),
          ]),
        ],
      ),
      GoRoute(
          path: '/capture/crop',
          builder: (context, state) => const ImageCropScreen()),
      GoRoute(
          path: '/capture/correction',
          builder: (context, state) => const QuestionCorrectionScreen()),
      GoRoute(
          path: '/capture/save-confirmation',
          builder: (context, state) => const QuestionSaveConfirmationScreen()),
      GoRoute(
          path: '/capture/split-confirmation',
          builder: (context, state) => const QuestionSplitConfirmationScreen()),
      GoRoute(
          path: '/analysis/loading',
          builder: (context, state) => const AnalysisLoadingScreen()),
      GoRoute(
          path: '/analysis/result',
          builder: (context, state) => const AnalysisResultScreen()),
      GoRoute(
        path: '/analysis/text-correction',
        builder: (context, state) => const QuestionTextCorrectionScreen(),
      ),
      GoRoute(
          path: '/exercise/practice',
          builder: (context, state) => const ExercisePracticeScreen()),
      GoRoute(
          path: '/notebook/question/:id',
          builder: (context, state) => const QuestionDetailScreen()),
      GoRoute(
          path: '/review/history',
          builder: (context, state) => const ReviewHistoryScreen()),
      GoRoute(
          path: '/achievements',
          builder: (context, state) => const AchievementsScreen()),
      GoRoute(
          path: '/paper/setup',
          builder: (context, state) => const PaperSetupScreen()),
      GoRoute(
          path: '/paper/preview',
          builder: (context, state) => const PaperPreviewScreen()),
      // 游客模式的 AI 服务配置页（未登录也可进入）。
      GoRoute(
          path: '/guest/provider',
          builder: (context, state) => const ProviderConfigScreen()),
    ],
  );

  // 旧的 onboarding 自动跳转已废弃：首次启动路由由 SplashScreen 统一决定
  // （未完成配置向导 -> /setup，已完成 -> /）。此处不再自动跳转 /onboarding，
  // 避免与 /setup 冲突（首次启动被旧 onboarding 覆盖的问题）。
  // WidgetsBinding.instance.addPostFrameCallback((_) async {
  //   try {
  //     final onboardingDone = await settingsRepo.getString('onboarding_done');
  //     if (onboardingDone == null) {
  //       router.go('/onboarding');
  //     }
  //   } catch (_) {}
  // });

  runApp(
    LiquidGlassWidgets.wrap(
      brightnessResolver: Theme.maybeBrightnessOf,
      child: ProviderScope(
        overrides: [
          settingsRepositoryProvider.overrideWithValue(settingsRepo),
          authControllerProvider.overrideWith((ref) => authController),
          questionRepositoryProvider.overrideWithValue(questionRepo),
          aiConversationRepositoryProvider.overrideWithValue(aiConversationRepo),
          analysisJobRepositoryProvider.overrideWithValue(analysisJobRepo),
          aiAnalysisServiceProvider.overrideWithValue(aiService),
          questionAnalysisCoordinatorProvider
              .overrideWithValue(questionAnalysisCoordinator),
          aiLearningTaskCoordinatorProvider
              .overrideWithValue(aiLearningTaskCoordinator),
          imageStorageServiceProvider.overrideWithValue(ImageStorageService()),
          glassDeviceTierProvider.overrideWithValue(deviceTier),
          glassAppearanceProvider.overrideWith(
            (ref) => GlassAppearanceNotifier(settingsRepo, glassAppearance),
          ),
          pageBackgroundProvider.overrideWith(
            (ref) => PageBackgroundNotifier(settingsRepo, backgroundSelection),
          ),
        ],
        child: Consumer(
          builder: (context, ref, _) {
            // P3/C3：高档设备 + 玻璃开启时，页面切换使用玻璃转场
            // 用户要求：全部关闭页面转场动画
            // Android：淡入淡出；iOS：系统原生（保留侧滑返回手势）
            const appTransitions = PageTransitionsTheme(
              builders: <TargetPlatform, PageTransitionsBuilder>{
                TargetPlatform.android: AppFadeTransitionsBuilder(),
                TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
              },
            );
            final light = buildLightTheme();
            final dark = buildDarkTheme();
            return MaterialApp.router(
              title: 'AI错题本',
              theme: light.copyWith(pageTransitionsTheme: appTransitions),
              darkTheme: dark.copyWith(pageTransitionsTheme: appTransitions),
              themeMode: ref.watch(themeModeProvider),
              routerConfig: router,
              debugShowCheckedModeBanner: false,
              builder: (context, child) {
                // 背景始终铺（顶栏折射需要内容垫底）；
                // 档位只决定玻璃质量：低=minimal / 中=standard / 高=premium。
                final selection = ref.watch(pageBackgroundProvider);
                final theme = Theme.of(context);
                final bg = selection
                    .forDark(theme.brightness == Brightness.dark);
                if (child == null) return const SizedBox.shrink();
                return Theme(
                  // 让页面 Scaffold 透明，露出背景图（玻璃才能折射它）
                  data: theme.copyWith(
                      scaffoldBackgroundColor: Colors.transparent),
                  child: Stack(
                    fit: StackFit.expand,
                    children: <Widget>[
                      PageBackgroundLayer(
                        background: bg,
                        dark: theme.brightness == Brightness.dark,
                      ),
                      child,
                    ],
                  ),
                );
              },
            );
          },
        ),
      ),
    ),
  );

  unawaited(analysisJobExecutor.initialize());
}

/// 认证路由守卫：未登录时只能访问公开页（splash/setup/onboarding/login/register/guest-provider），
/// 其余路由重定向到登录页；已登录/游客访问登录/注册页则回首页。
String? Function(BuildContext, GoRouterState) _authRedirect(
    AuthController authController) {
  bool isPublic(String path) {
    return path == '/splash' ||
        path == '/setup' ||
        path == '/onboarding' ||
        path == '/login' ||
        path == '/register' ||
        path == '/guest/provider';
  }

  return (context, state) {
    final auth = authController.currentState;
    final path = state.matchedLocation;
    // 启动中：交由 SplashScreen 决定（其会等待 auth 加载完成再跳转）
    if (auth is AuthChecking) return null;
    // 游客与正式登录都允许访问 App 内页面。
    final authed = auth is AuthAuthenticated || auth is AuthGuest;
    if (authed) {
      if (path == '/login' || path == '/register') return '/';
      return null;
    }
    // 未登录：仅放行公开页，其余跳登录
    return isPublic(path) ? null : '/login';
  };
}

class ScaffoldWithNavBar extends ConsumerWidget {
  const ScaffoldWithNavBar({required this.navigationShell, super.key});
  final StatefulNavigationShell navigationShell;

  static const List<GlassTab> _glassTabs = <GlassTab>[
    GlassTab(
      icon: Icon(CupertinoIcons.house),
      activeIcon: Icon(CupertinoIcons.house_fill),
      label: '首页',
    ),
    GlassTab(
      icon: Icon(CupertinoIcons.book),
      activeIcon: Icon(CupertinoIcons.book_fill),
      label: '错题本',
    ),
    GlassTab(
      icon: Icon(CupertinoIcons.arrow_2_circlepath),
      activeIcon: Icon(CupertinoIcons.arrow_2_circlepath),
      label: '复习',
    ),
    GlassTab(
      icon: Icon(CupertinoIcons.gear),
      activeIcon: Icon(CupertinoIcons.gear_solid),
      label: '设置',
    ),
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final glassEnabled = ref.watch(glassEnabledProvider);
    final quality = ref.watch(glassQualityProvider);
    // 所有 Tab 页统一处理「内容 ↔ 底部 Dock」连接处：
    // 与原来首页一致——28px 同色渐变（不做模糊，避免过度虚化）。
    const double dockFadeHeight = 28;
    return Scaffold(
      body: Stack(
        children: <Widget>[
          ScrollTintListener(child: navigationShell),
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            height: dockFadeHeight,
            child: const AppBottomFade(height: dockFadeHeight),
          ),
        ],
      ),
      bottomNavigationBar: glassEnabled
          ? GlassTabBar.bottom(
              tabs: _glassTabs,
              selectedIndex: navigationShell.currentIndex,
              onTabSelected: (int index) =>
                  navigationShell.goBranch(index),
              quality: quality,
            )
          : NavigationBar(
              selectedIndex: navigationShell.currentIndex,
              onDestinationSelected: (int index) =>
                  navigationShell.goBranch(index),
              destinations: const [
                NavigationDestination(
                  icon: Icon(CupertinoIcons.house),
                  selectedIcon: Icon(CupertinoIcons.house_fill),
                  label: '首页',
                ),
                NavigationDestination(
                  icon: Icon(CupertinoIcons.book),
                  selectedIcon: Icon(CupertinoIcons.book_fill),
                  label: '错题本',
                ),
                NavigationDestination(
                  icon: Icon(CupertinoIcons.arrow_2_circlepath),
                  selectedIcon: Icon(CupertinoIcons.arrow_2_circlepath),
                  label: '复习',
                ),
                NavigationDestination(
                  icon: Icon(CupertinoIcons.gear),
                  selectedIcon: Icon(CupertinoIcons.gear_solid),
                  label: '设置',
                ),
              ],
            ),
    );
  }
}


/// 淡入淡出转场（Android 用；iOS 保留原生 Cupertino 以支持侧滑返回）。
class AppFadeTransitionsBuilder extends PageTransitionsBuilder {
  const AppFadeTransitionsBuilder({
    this.duration = const Duration(milliseconds: 180),
  });

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
    return FadeTransition(
      opacity: CurvedAnimation(
        parent: animation,
        curve: Curves.easeOut,
        reverseCurve: Curves.easeOut,
      ),
      child: child,
    );
  }
}
