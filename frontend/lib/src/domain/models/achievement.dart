/// 一枚成就徽章。
///
/// [unlockedAt] 为空表示尚未解锁；非空表示已解锁（持久化后不再回退）。
class Achievement {
  const Achievement({
    required this.id,
    required this.name,
    required this.icon,
    required this.description,
    this.unlockedAt,
  });

  /// 稳定唯一 id（用于持久化判定，不可随文案/顺序变化）。
  final String id;

  final String name;

  /// emoji 图标（简单可靠，跨平台无需资源）。
  final String icon;

  final String description;

  final DateTime? unlockedAt;

  bool get isUnlocked => unlockedAt != null;

  Achievement unlockAt(DateTime time) {
    return Achievement(
      id: id,
      name: name,
      icon: icon,
      description: description,
      unlockedAt: time,
    );
  }
}
