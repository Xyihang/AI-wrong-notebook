import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:smart_wrong_notebook/src/app/auth_controller.dart';
import 'package:smart_wrong_notebook/src/app/providers.dart';
import 'package:smart_wrong_notebook/src/core/constants/app_config.dart';
import 'package:smart_wrong_notebook/src/features/glass/glass_appearance.dart';
import 'package:smart_wrong_notebook/src/features/glass/glass_overlays.dart';
import 'package:smart_wrong_notebook/src/features/glass/glass_providers.dart';
import 'package:smart_wrong_notebook/src/features/glass/glass_top_bar.dart';
import 'package:smart_wrong_notebook/src/features/glass/page_background.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  /// 选择玻璃外观（自动/低/中/高/关闭）。
  Future<void> _pickGlassAppearance(
    BuildContext context,
    WidgetRef ref,
  ) async {
    final current = ref.read(glassAppearanceProvider);
    // 统一弹层门面：玻璃开启时玻璃弹层，关闭时回退 Material
    final selected = await showAppSheet<GlassAppearance>(
      context,
      // 与拍照弹层一致：底部留 20，避开悬浮 Dock
      bottomInset: 20,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 4, 20, 8),
              child: Text(
                '玻璃外观',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
              ),
            ),
            for (final item in GlassAppearance.values)
              RadioListTile<GlassAppearance>(
                value: item,
                // ignore: deprecated_member_use
                groupValue: current,
                title: Text(item.label),
                subtitle: item == GlassAppearance.auto
                    ? const Text('按设备性能自动选择，判档失败按「中」')
                    : null,
                // ignore: deprecated_member_use
                onChanged: (value) => Navigator.pop(ctx, value),
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (selected != null) {
      await ref.read(glassAppearanceProvider.notifier).set(selected);
    }
  }

  /// 选择页面背景（衬托玻璃）。
  Future<void> _pickPageBackground(
    BuildContext context,
    WidgetRef ref,
  ) async {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final selection = ref.read(pageBackgroundProvider);
    final current = selection.forDark(isDark);
    // 只列当前模式可用的背景：深色模式只给深色背景，浅色模式只给浅色背景
    final options =
        PageBackground.values.where((e) => e.isDark == isDark).toList();
    final selected = await showAppSheet<PageBackground>(
      context,
      bottomInset: 20,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 4, 20, 8),
              child: Text(
                '页面背景',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
              ),
            ),
            for (final item in options)
              RadioListTile<PageBackground>(
                value: item,
                // ignore: deprecated_member_use
                groupValue: current,
                secondary: ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Image.asset(
                    item.asset,
                    width: 34,
                    height: 54,
                    fit: BoxFit.cover,
                  ),
                ),
                title: Text(item.label),
                // ignore: deprecated_member_use
                onChanged: (value) => Navigator.pop(ctx, value),
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (selected != null) {
      await ref
          .read(pageBackgroundProvider.notifier)
          .set(selected, dark: isDark);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themeMode = ref.watch(themeModeProvider);
    final auth = ref.watch(authControllerProvider);

    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final glassEnabled = ref.watch(glassEnabledProvider);
    final pageBg = ref
        .watch(pageBackgroundProvider)
        .forDark(Theme.of(context).brightness == Brightness.dark);

    return Scaffold(
      extendBodyBehindAppBar: glassEnabled,
      appBar: glassTopBar(context, title: const Text('设置')),
      body: Stack(
        children: <Widget>[
          ListView(
        padding: EdgeInsets.fromLTRB(
          24,
          24 + (glassEnabled ? glassTopInset(context) : 0),
          24,
          24,
        ),
        children: <Widget>[
          // Account
          Text('账号',
              style: theme.textTheme.titleMedium
                  ?.copyWith(fontWeight: FontWeight.w600)),
          const SizedBox(height: 12),
          _SettingsSection(
            child: Column(
              children: <Widget>[
                ListTile(
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                  leading: const _SettingsIcon(
                    icon: CupertinoIcons.person_crop_circle,
                    iconColor: Color(0xFF6366F1),
                    lightBg: Color(0xFFEEF2FF),
                  ),
                  title: Text(
                    auth is AuthAuthenticated
                        ? (auth.session.displayName.isNotEmpty
                            ? auth.session.displayName
                            : auth.session.username)
                        : auth is AuthGuest
                            ? '游客模式'
                            : '未登录',
                    style: const TextStyle(fontSize: 14),
                  ),
                  subtitle: Text(
                    auth is AuthAuthenticated
                        ? '@${auth.session.username}'
                        : auth is AuthGuest
                            ? '数据仅存本机，登录后可云端同步'
                            : '登录后错题按账号隔离',
                    style: const TextStyle(fontSize: 12),
                  ),
                ),
                if (auth is AuthAuthenticated || auth is AuthGuest) ...<Widget>[
                  const Divider(
                      height: 1,
                      indent: 56,
                      color: Color(0xFFE5E7EB)),
                  ListTile(
                    contentPadding:
                        const EdgeInsets.symmetric(horizontal: 16),
                    leading: const _SettingsIcon(
                      icon: CupertinoIcons.square_arrow_right,
                      iconColor: Color(0xFFDC2626),
                      lightBg: Color(0xFFFEF2F2),
                    ),
                    title: Text(
                        auth is AuthGuest ? '退出游客模式' : '退出登录',
                        style: TextStyle(
                            fontSize: 14, color: colorScheme.error)),
                    onTap: () async {
                      await ref
                          .read(authControllerProvider.notifier)
                          .logout();
                      if (context.mounted) context.go('/login');
                    },
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 24),
          // Appearance
          Text('外观',
              style: theme.textTheme.titleMedium
                  ?.copyWith(fontWeight: FontWeight.w600)),
          const SizedBox(height: 12),
          Row(
            children: <Widget>[
              _ThemeButton(
                  label: '系统',
                  icon: CupertinoIcons.device_phone_portrait,
                  isSelected: themeMode == ThemeMode.system,
                  onTap: () => ref
                      .read(themeModeProvider.notifier)
                      .setMode(ThemeMode.system)),
              const SizedBox(width: 8),
              _ThemeButton(
                  label: '浅色',
                  icon: CupertinoIcons.sun_max,
                  isSelected: themeMode == ThemeMode.light,
                  onTap: () => ref
                      .read(themeModeProvider.notifier)
                      .setMode(ThemeMode.light)),
              const SizedBox(width: 8),
              _ThemeButton(
                  label: '深色',
                  icon: CupertinoIcons.moon,
                  isSelected: themeMode == ThemeMode.dark,
                  onTap: () => ref
                      .read(themeModeProvider.notifier)
                      .setMode(ThemeMode.dark)),
            ],
          ),
          const SizedBox(height: 12),
          // 液态玻璃外观：自动/低/中/高/关闭（详见 docs/SPEC-LIQUID-GLASS.md）
          _SettingsSection(
            child: Column(
              children: <Widget>[
                _SettingsListItem(
                  icon: CupertinoIcons.square_on_square,
                  iconColor: const Color(0xFF8B5CF6),
                  lightIconBg: const Color(0xFFF5F3FF),
                  title: '玻璃外观',
                  subtitle: '${ref.watch(glassAppearanceProvider).label} · '
                      '设备档位：${ref.watch(glassTierProvider).label}',
                  onTap: () => _pickGlassAppearance(context, ref),
                ),
                Divider(
                    height: 1, indent: 56, color: colorScheme.outlineVariant),
                _SettingsListItem(
                  icon: CupertinoIcons.photo,
                  iconColor: const Color(0xFF0EA5E9),
                  lightIconBg: const Color(0xFFE0F2FE),
                  title: '页面背景',
                  subtitle: pageBg.label,
                  onTap: () => _pickPageBackground(context, ref),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          // Notifications
          Text('提醒',
              style: theme.textTheme.titleMedium
                  ?.copyWith(fontWeight: FontWeight.w600)),
          const SizedBox(height: 12),
          _SettingsSection(
            child: ListTile(
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              leading: const _SettingsIcon(
                icon: CupertinoIcons.bell,
                iconColor: Color(0xFFF97316),
                lightBg: Color(0xFFFFF7ED),
              ),
              title: Text('复习提醒',
                  style: TextStyle(fontSize: 14, color: colorScheme.onSurface)),
              subtitle: Text('发送待复习错题通知',
                  style: TextStyle(
                      fontSize: 12, color: colorScheme.onSurfaceVariant)),
              trailing: FilledButton.tonal(
                onPressed: () async {
                  final svc = ref.read(notificationServiceProvider);
                  await svc.checkAndNotify();
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('已发送复习提醒')),
                    );
                  }
                },
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  minimumSize: const Size(0, 32),
                ),
                child: const Text('发送', style: TextStyle(fontSize: 12)),
              ),
            ),
          ),
          const SizedBox(height: 24),
          // AI Service
          Text('AI 服务',
              style: theme.textTheme.titleMedium
                  ?.copyWith(fontWeight: FontWeight.w600)),
          const SizedBox(height: 12),
          _SettingsSection(
            child: Column(
              children: <Widget>[
                _SettingsListItem(
                  icon: CupertinoIcons.sparkles,
                  iconColor: const Color(0xFF6366F1),
                  lightIconBg: const Color(0xFFEEF2FF),
                  title: 'AI 服务商配置',
                  onTap: () => context.go('/settings/provider'),
                ),
                Divider(
                    height: 1, indent: 56, color: colorScheme.outlineVariant),
                _SettingsListItem(
                  icon: CupertinoIcons.pencil,
                  iconColor: const Color(0xFFD97706),
                  lightIconBg: const Color(0xFFFFFBEB),
                  title: '提示词设置',
                  onTap: () => context.go('/settings/prompts'),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          // Content
          Text('内容',
              style: theme.textTheme.titleMedium
                  ?.copyWith(fontWeight: FontWeight.w600)),
          const SizedBox(height: 12),
          _SettingsSection(
            child: Column(
              children: <Widget>[
                _SettingsListItem(
                  icon: CupertinoIcons.folder,
                  iconColor: const Color(0xFF16A34A),
                  lightIconBg: const Color(0xFFF0FDF4),
                  title: '科目管理',
                  onTap: () => context.go('/settings/subjects'),
                ),
                Divider(
                    height: 1, indent: 56, color: colorScheme.outlineVariant),
                _SettingsListItem(
                  icon: CupertinoIcons.tray,
                  iconColor: const Color(0xFFEA580C),
                  lightIconBg: const Color(0xFFFFF7ED),
                  title: '数据管理',
                  subtitle: '导入 / 导出 / 清空',
                  onTap: () => context.go('/settings/data'),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          // Growth / Gamification
          Text('成长',
              style: theme.textTheme.titleMedium
                  ?.copyWith(fontWeight: FontWeight.w600)),
          const SizedBox(height: 12),
          _SettingsSection(
            child: Column(
              children: <Widget>[
                _SettingsListItem(
                  icon: CupertinoIcons.star,
                  iconColor: const Color(0xFFF97316),
                  lightIconBg: const Color(0xFFFFF7ED),
                  title: '成就徽章',
                  subtitle: '学习连击 & 徽章收藏',
                  onTap: () => context.push('/achievements'),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          // 诊断：当前实际使用的后端地址（换服务器排查用）
          Text('诊断',
              style: theme.textTheme.titleMedium
                  ?.copyWith(fontWeight: FontWeight.w600)),
          const SizedBox(height: 12),
          _SettingsSection(
            child: _SettingsListItem(
              icon: CupertinoIcons.link,
              iconColor: const Color(0xFF0EA5E9),
              lightIconBg: const Color(0xFFF0F9FF),
              title: '后端地址',
              subtitle: AppConfig.currentBaseUrl,
              onTap: () async {
                await Clipboard.setData(
                  ClipboardData(text: AppConfig.currentBaseUrl),
                );
                if (context.mounted) {
                  showAppToast(context, '后端地址已复制');
                }
              },
            ),
          ),
        ],
      ),
        ],
      ),
    );
  }
}

class _SettingsSection extends StatelessWidget {
  const _SettingsSection({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: colorScheme.outlineVariant),
      ),
      child: child,
    );
  }
}

class _SettingsIcon extends StatelessWidget {
  const _SettingsIcon({
    required this.icon,
    required this.iconColor,
    required this.lightBg,
  });

  final IconData icon;
  final Color iconColor;
  final Color lightBg;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      width: 36,
      height: 36,
      decoration: BoxDecoration(
        color: isDark ? iconColor.withValues(alpha: 0.16) : lightBg,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Icon(icon, size: 18, color: iconColor),
    );
  }
}

class _SettingsListItem extends StatelessWidget {
  const _SettingsListItem({
    required this.icon,
    required this.iconColor,
    required this.lightIconBg,
    required this.title,
    this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final Color iconColor;
  final Color lightIconBg;
  final String title;
  final String? subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: <Widget>[
            _SettingsIcon(
              icon: icon,
              iconColor: iconColor,
              lightBg: lightIconBg,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(title,
                      style: TextStyle(
                          fontSize: 14, color: colorScheme.onSurface)),
                  if (subtitle != null) ...<Widget>[
                    const SizedBox(height: 2),
                    Text(subtitle!,
                        style: TextStyle(
                            fontSize: 12, color: colorScheme.onSurfaceVariant)),
                  ],
                ],
              ),
            ),
            Icon(CupertinoIcons.chevron_right,
                size: 22,
                color: colorScheme.onSurfaceVariant.withValues(alpha: 0.5)),
          ],
        ),
      ),
    );
  }
}

class _ThemeButton extends StatelessWidget {
  const _ThemeButton(
      {required this.label,
      required this.icon,
      required this.isSelected,
      required this.onTap});

  final String label;
  final IconData icon;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            color: isSelected
                ? colorScheme.primary
                : colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
                color: isSelected
                    ? colorScheme.primary
                    : colorScheme.outlineVariant),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Icon(icon,
                  size: 20,
                  color: isSelected
                      ? colorScheme.onPrimary
                      : colorScheme.onSurfaceVariant),
              const SizedBox(height: 4),
              Text(label,
                  style: TextStyle(
                      fontSize: 12,
                      color: isSelected
                          ? colorScheme.onPrimary
                          : colorScheme.onSurfaceVariant)),
            ],
          ),
        ),
      ),
    );
  }
}
