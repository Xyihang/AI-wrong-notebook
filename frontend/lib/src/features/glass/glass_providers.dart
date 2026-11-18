import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';
import 'package:smart_wrong_notebook/src/app/providers.dart';
import 'package:smart_wrong_notebook/src/data/repositories/settings_repository.dart';
import 'package:smart_wrong_notebook/src/features/glass/glass_appearance.dart';

/// 设备判档结果（在 `main()` 中采集后 override，默认中档）。
final glassDeviceTierProvider = Provider<GlassTier>(
  (ref) => GlassTier.mid,
);

/// 用户的玻璃外观偏好（持久化到设置仓库）。
class GlassAppearanceNotifier extends StateNotifier<GlassAppearance> {
  GlassAppearanceNotifier(this._repo, GlassAppearance initial)
      : super(initial);

  final SettingsRepository _repo;

  static const String key = 'glass_appearance';

  Future<void> set(GlassAppearance appearance) async {
    if (state == appearance) return;
    state = appearance;
    try {
      await _repo.setString(key, appearance.storageValue);
    } catch (_) {}
  }
}

final glassAppearanceProvider =
    StateNotifierProvider<GlassAppearanceNotifier, GlassAppearance>(
  (ref) => GlassAppearanceNotifier(
    ref.watch(settingsRepositoryProvider),
    GlassAppearance.auto,
  ),
);

/// 最终生效档位：用户覆盖优先，自动则用设备判档。
final glassTierProvider = Provider<GlassTier>((ref) {
  final appearance = ref.watch(glassAppearanceProvider);
  final deviceTier = ref.watch(glassDeviceTierProvider);
  return switch (appearance) {
    GlassAppearance.auto => deviceTier,
    GlassAppearance.low => GlassTier.low,
    GlassAppearance.mid => GlassTier.mid,
    GlassAppearance.high => GlassTier.high,
    GlassAppearance.off => deviceTier,
  };
});

/// 是否启用玻璃外观（总开关）。
final glassEnabledProvider = Provider<bool>(
  (ref) => ref.watch(glassAppearanceProvider) != GlassAppearance.off,
);

/// 档位 → 玻璃质量映射。
final glassQualityProvider = Provider<GlassQuality>((ref) {
  return switch (ref.watch(glassTierProvider)) {
    GlassTier.low => GlassQuality.minimal,
    GlassTier.mid => GlassQuality.standard,
    GlassTier.high => GlassQuality.premium,
  };
});
