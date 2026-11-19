import 'package:flutter/material.dart';
import 'package:smart_wrong_notebook/src/domain/models/achievement.dart';
import 'package:smart_wrong_notebook/src/features/glass/glass_overlays.dart';

/// 新解锁徽章的「恭喜」弹层。每枚徽章显示 emoji + 名称。
Future<void> showAchievementCelebration(
  BuildContext context,
  List<Achievement> achievements,
) {
  if (achievements.isEmpty) return Future.value();
  final colorScheme = Theme.of(context).colorScheme;
  final isDark = Theme.of(context).brightness == Brightness.dark;

  return showAppDialog<void>(context,
    barrierDismissible: true,
    builder: (dialogContext) => Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 24, 24, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Text('🎉',
                style: TextStyle(fontSize: 48)),
            const SizedBox(height: 12),
            Text(
              achievements.length == 1 ? '解锁新徽章！' : '一口气解锁 ${achievements.length} 枚徽章！',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w700,
                color: colorScheme.onSurface,
              ),
            ),
            const SizedBox(height: 16),
            ...achievements.map((a) => Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Row(
                    children: <Widget>[
                      Container(
                        width: 48,
                        height: 48,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: isDark
                              ? const Color(0xFFF97316).withValues(alpha: 0.16)
                              : const Color(0xFFFFF7ED),
                          borderRadius: BorderRadius.circular(24),
                          border: Border.all(
                            color: const Color(0xFFFED7AA),
                            width: 1.2,
                          ),
                        ),
                        child: Text(a.icon, style: const TextStyle(fontSize: 24)),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            Text(a.name,
                                style: const TextStyle(
                                    fontSize: 15, fontWeight: FontWeight.w600)),
                            const SizedBox(height: 2),
                            Text(a.description,
                                style: TextStyle(
                                  fontSize: 12,
                                  color: colorScheme.onSurfaceVariant,
                                )),
                          ],
                        ),
                      ),
                    ],
                  ),
                )),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text('太棒了'),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}
