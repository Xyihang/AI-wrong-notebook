import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:smart_wrong_notebook/src/app/providers.dart';
import 'package:smart_wrong_notebook/src/data/repositories/settings_repository.dart';

/// 页面背景图（衬托玻璃质感）。
///
/// 玻璃页面的顶栏/底栏/弹层会折射这张图。浅色模式只用浅色背景，
/// 深色模式只用深色背景；两套选择各自记忆。
enum PageBackground {
  lavender,
  mint,
  sand,
  indigo,
  violet,
  teal;

  String get storageValue => name;

  String get label => switch (this) {
        PageBackground.lavender => '紫雾',
        PageBackground.mint => '薄荷',
        PageBackground.sand => '暖沙',
        PageBackground.indigo => '午夜靛蓝',
        PageBackground.violet => '深空紫',
        PageBackground.teal => '墨绿夜',
      };

  String get asset => switch (this) {
        PageBackground.lavender => 'assets/backgrounds/bg_light_1_lavender.jpg',
        PageBackground.mint => 'assets/backgrounds/bg_light_2_mint.jpg',
        PageBackground.sand => 'assets/backgrounds/bg_light_3_sand.jpg',
        PageBackground.indigo => 'assets/backgrounds/bg_dark_1_indigo.jpg',
        PageBackground.violet => 'assets/backgrounds/bg_dark_2_violet.jpg',
        PageBackground.teal => 'assets/backgrounds/bg_dark_3_teal.jpg',
      };

  /// 是否为深色模式专属背景。
  bool get isDark =>
      this == PageBackground.indigo ||
      this == PageBackground.violet ||
      this == PageBackground.teal;

  /// 浅色默认「薄荷」，深色默认「午夜靛蓝」。
  static PageBackground defaultFor({required bool dark}) =>
      dark ? PageBackground.indigo : PageBackground.mint;

  /// 解析存储值：非法值或跨模式的旧值一律回落到该模式默认背景。
  static PageBackground fromStorage(String? value, {required bool dark}) {
    for (final item in PageBackground.values) {
      if (item.storageValue == value) {
        return item.isDark == dark ? item : defaultFor(dark: dark);
      }
    }
    return defaultFor(dark: dark);
  }
}

/// 浅色/深色两套背景选择。
class BackgroundSelection {
  const BackgroundSelection({required this.light, required this.dark});

  final PageBackground light;
  final PageBackground dark;

  BackgroundSelection copyWith({PageBackground? light, PageBackground? dark}) =>
      BackgroundSelection(
        light: light ?? this.light,
        dark: dark ?? this.dark,
      );

  PageBackground forDark(bool isDark) => isDark ? dark : light;
}

class PageBackgroundNotifier extends StateNotifier<BackgroundSelection> {
  PageBackgroundNotifier(this._repo, BackgroundSelection initial)
      : super(initial);

  final SettingsRepository _repo;

  static const String lightKey = 'page_background_light';
  static const String darkKey = 'page_background_dark';

  /// 保存到当前模式对应的槽位（跨模式写入被拒绝）。
  Future<void> set(PageBackground background, {required bool dark}) async {
    if (background.isDark != dark) return;
    if (state.forDark(dark) == background) return;
    state = dark
        ? state.copyWith(dark: background)
        : state.copyWith(light: background);
    try {
      await _repo.setString(dark ? darkKey : lightKey, background.storageValue);
    } catch (_) {}
  }
}

final pageBackgroundProvider =
    StateNotifierProvider<PageBackgroundNotifier, BackgroundSelection>(
  (ref) => PageBackgroundNotifier(
    ref.watch(settingsRepositoryProvider),
    BackgroundSelection(
      light: PageBackground.defaultFor(dark: false),
      dark: PageBackground.defaultFor(dark: true),
    ),
  ),
);

/// 背景图 + 蒙层（提升文字对比度）。
class PageBackgroundLayer extends StatelessWidget {
  const PageBackgroundLayer({
    required this.background,
    required this.dark,
    super.key,
  });

  final PageBackground background;
  final bool dark;

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: <Widget>[
        Image.asset(background.asset, fit: BoxFit.cover),
        // 浅色提亮、深色压暗，保证内容可读性
        ColoredBox(
          color: dark
              ? Colors.black.withValues(alpha: 0.32)
              : Colors.white.withValues(alpha: 0.34),
        ),
      ],
    );
  }
}
