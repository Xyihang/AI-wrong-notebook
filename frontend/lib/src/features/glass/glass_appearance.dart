/// 玻璃外观偏好与设备档位。
///
/// 规格见 `docs/SPEC-LIQUID-GLASS.md`：
/// - 三档：低 / 中（默认）/ 高；
/// - 用户可在「设置 → 外观」里覆盖，或选择关闭。
enum GlassAppearance {
  /// 按设备自动判档（判档失败按中档）。
  auto('auto', '自动（推荐）'),

  /// 低档：轻量玻璃（底部栏 + 顶栏极轻模糊）。
  low('low', '低'),

  /// 中档：标准玻璃。
  mid('mid', '中'),

  /// 高档：完整玻璃效果。
  high('high', '高'),

  /// 关闭：完全使用原有 Material 外观。
  off('off', '关闭');

  const GlassAppearance(this.storageValue, this.label);

  final String storageValue;
  final String label;

  static GlassAppearance fromStorage(String? value) {
    if (value == null) return GlassAppearance.auto;
    for (final item in GlassAppearance.values) {
      if (item.storageValue == value) return item;
    }
    return GlassAppearance.auto;
  }
}

/// 设备性能档位。
enum GlassTier {
  low('低'),
  mid('中'),
  high('高');

  const GlassTier(this.label);

  final String label;
}
