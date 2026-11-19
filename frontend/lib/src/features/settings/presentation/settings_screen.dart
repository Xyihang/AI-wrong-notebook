import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:smart_wrong_notebook/src/app/auth_controller.dart';
import 'package:smart_wrong_notebook/src/app/design/tokens.dart';
import 'package:smart_wrong_notebook/src/app/providers.dart';
import 'package:smart_wrong_notebook/src/common/widgets/app_button.dart';
import 'package:smart_wrong_notebook/src/common/widgets/app_card.dart';
import 'package:smart_wrong_notebook/src/core/constants/app_config.dart';
import 'package:smart_wrong_notebook/src/features/glass/glass_appearance.dart';
import 'package:smart_wrong_notebook/src/features/glass/glass_overlays.dart';
import 'package:smart_wrong_notebook/src/features/glass/glass_providers.dart';
import 'package:smart_wrong_notebook/src/features/glass/glass_top_bar.dart';
import 'package:smart_wrong_notebook/src/features/glass/page_background.dart';

/// 设置页（对应 SPEC T7）。
///
/// 分组：外观 / 学习 / 数据；条目统一「图标 32×32 + 标题(+描述) + 右侧值/箭头」三段式。
/// 危险项（退出登录）用 error 色 + errorSoft 图标底。
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
    final glassEnabled = ref.watch(glassEnabledProvider);
    final pageBg = ref
        .watch(pageBackgroundProvider)
        .forDark(Theme.of(context).brightness == Brightness.dark);
    final glassAppearance = ref.watch(glassAppearanceProvider);
    final glassTier = ref.watch(glassTierProvider);

    final accountName = auth is AuthAuthenticated
        ? (auth.session.displayName.isNotEmpty
            ? auth.session.displayName
            : auth.session.username)
        : auth is AuthGuest
            ? '游客模式'
            : '未登录';
    final accountDesc = auth is AuthAuthenticated
        ? '@${auth.session.username}'
        : auth is AuthGuest
            ? '数据仅存本机，登录后可云端同步'
            : '登录后错题按账号隔离';
    final canLogout = auth is AuthAuthenticated || auth is AuthGuest;

    return Scaffold(
      extendBodyBehindAppBar: glassEnabled,
      appBar: glassTopBar(context, title: const Text('设置')),
      body: ListView(
        padding: EdgeInsets.fromLTRB(
          AppTokens.s4,
          AppTokens.s4 + (glassEnabled ? glassTopInset(context) : 0),
          AppTokens.s4,
          AppTokens.s6 + MediaQuery.paddingOf(context).bottom,
        ),
        children: <Widget>[
          // ---- 外观 ----
          const _GroupTitle('外观'),
          _SettingsGroup(
            children: <Widget>[
              _appearanceModeTile(context, ref, themeMode),
              _SettingsTile(
                icon: CupertinoIcons.square_on_square,
                title: '玻璃外观',
                subtitle: '${glassAppearance.label} · 设备档位：${glassTier.label}',
                onTap: () => _pickGlassAppearance(context, ref),
              ),
              _SettingsTile(
                icon: CupertinoIcons.photo,
                title: '页面背景',
                subtitle: '衬托玻璃的背景图',
                value: pageBg.label,
                onTap: () => _pickPageBackground(context, ref),
              ),
            ],
          ),
          const SizedBox(height: AppTokens.s4),
          // ---- 学习 ----
          const _GroupTitle('学习'),
          _SettingsGroup(
            children: <Widget>[
              _SettingsTile(
                icon: CupertinoIcons.bell,
                title: '复习提醒',
                subtitle: '发送待复习错题通知',
                trailing: AppButton(
                  label: '发送',
                  kind: AppButtonKind.outline,
                  expand: false,
                  height: 32,
                  fontSize: AppTokens.textXs,
                  onPressed: () async {
                    final service = ref.read(notificationServiceProvider);
                    await service.checkAndNotify();
                    if (context.mounted) {
                      showAppToast(context, '已发送复习提醒');
                    }
                  },
                ),
              ),
              _SettingsTile(
                icon: CupertinoIcons.sparkles,
                title: 'AI 服务商配置',
                subtitle: '模型 / 接口地址 / Key',
                onTap: () => context.go('/settings/provider'),
              ),
              _SettingsTile(
                icon: CupertinoIcons.pencil,
                title: '提示词设置',
                subtitle: '解析风格与输出约束',
                onTap: () => context.go('/settings/prompts'),
              ),
              _SettingsTile(
                icon: CupertinoIcons.folder,
                title: '科目管理',
                onTap: () => context.go('/settings/subjects'),
              ),
              _SettingsTile(
                icon: CupertinoIcons.star,
                title: '成就徽章',
                subtitle: '学习连击 & 徽章收藏',
                onTap: () => context.push('/achievements'),
              ),
            ],
          ),
          const SizedBox(height: AppTokens.s4),
          // ---- 数据 ----
          const _GroupTitle('数据'),
          _SettingsGroup(
            children: <Widget>[
              _SettingsTile(
                icon: CupertinoIcons.person_crop_circle,
                title: accountName,
                subtitle: accountDesc,
              ),
              _SettingsTile(
                icon: CupertinoIcons.tray,
                title: '数据管理',
                subtitle: '导入 / 导出 / 清空',
                onTap: () => context.go('/settings/data'),
              ),
              _SettingsTile(
                icon: CupertinoIcons.link,
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
              if (canLogout)
                _SettingsTile(
                  icon: CupertinoIcons.square_arrow_right,
                  title: auth is AuthGuest ? '退出游客模式' : '退出登录',
                  danger: true,
                  onTap: () async {
                    await ref.read(authControllerProvider.notifier).logout();
                    if (context.mounted) context.go('/login');
                  },
                ),
            ],
          ),
        ],
      ),
    );
  }

  /// 外观模式（跟随系统 / 浅色 / 深色）：三段式条目 + 三个按钮。
  Widget _appearanceModeTile(
    BuildContext context,
    WidgetRef ref,
    ThemeMode mode,
  ) {
    final t = context.tokens;
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppTokens.s4,
        vertical: AppTokens.s3,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              const _SettingsIconBox(
                icon: CupertinoIcons.circle_lefthalf_fill,
              ),
              const SizedBox(width: AppTokens.s3),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      '外观模式',
                      style: TextStyle(
                        fontSize: AppTokens.textSm,
                        fontWeight: FontWeight.w500,
                        color: t.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '跟随系统 / 固定浅色 / 固定深色',
                      style: TextStyle(
                        fontSize: AppTokens.textXs,
                        color: t.textTertiary,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: AppTokens.s3),
          Row(
            children: <Widget>[
              _ThemeButton(
                label: '系统',
                icon: CupertinoIcons.device_phone_portrait,
                isSelected: mode == ThemeMode.system,
                onTap: () =>
                    ref.read(themeModeProvider.notifier).setMode(ThemeMode.system),
              ),
              const SizedBox(width: AppTokens.s2),
              _ThemeButton(
                label: '浅色',
                icon: CupertinoIcons.sun_max,
                isSelected: mode == ThemeMode.light,
                onTap: () =>
                    ref.read(themeModeProvider.notifier).setMode(ThemeMode.light),
              ),
              const SizedBox(width: AppTokens.s2),
              _ThemeButton(
                label: '深色',
                icon: CupertinoIcons.moon,
                isSelected: mode == ThemeMode.dark,
                onTap: () =>
                    ref.read(themeModeProvider.notifier).setMode(ThemeMode.dark),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// 分组标题（demo `.group-title`）。
class _GroupTitle extends StatelessWidget {
  const _GroupTitle(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Padding(
      padding: const EdgeInsets.only(
        left: AppTokens.s1,
        bottom: AppTokens.s2,
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: AppTokens.textXs,
          fontWeight: FontWeight.w500,
          color: t.textTertiary,
        ),
      ),
    );
  }
}

/// 分组卡片：AppCard + 1px 分隔线（浅色 neutral-100 / 深色 #0F172A）。
class _SettingsGroup extends StatelessWidget {
  const _SettingsGroup({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return AppCard(
      padding: EdgeInsets.zero,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(AppTokens.radiusLg),
        child: Column(
          children: <Widget>[
            for (var i = 0; i < children.length; i++) ...<Widget>[
              if (i > 0) Divider(height: 1, thickness: 1, color: t.formulaBg),
              children[i],
            ],
          ],
        ),
      ),
    );
  }
}

/// 图标底：32×32 + `radiusMd` + 中立底（危险项用 error/errorSoft）。
class _SettingsIconBox extends StatelessWidget {
  const _SettingsIconBox({required this.icon, this.danger = false});

  final IconData icon;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Container(
      width: 32,
      height: 32,
      decoration: BoxDecoration(
        color: danger ? t.errorSoft : t.formulaBg,
        borderRadius: BorderRadius.circular(AppTokens.radiusMd),
      ),
      child: Icon(
        icon,
        size: 16,
        color: danger ? t.error : t.textSecondary,
      ),
    );
  }
}

/// 三段式设置条目：图标 + 标题(+描述) + 右侧（值 / 自定义尾随 / 箭头）。
class _SettingsTile extends StatelessWidget {
  const _SettingsTile({
    required this.icon,
    required this.title,
    this.subtitle,
    this.value,
    this.trailing,
    this.onTap,
    this.danger = false,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final String? value;
  final Widget? trailing;
  final VoidCallback? onTap;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final content = Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppTokens.s4,
        vertical: AppTokens.s3,
      ),
      child: Row(
        children: <Widget>[
          _SettingsIconBox(icon: icon, danger: danger),
          const SizedBox(width: AppTokens.s3),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  title,
                  style: TextStyle(
                    fontSize: AppTokens.textSm,
                    fontWeight: FontWeight.w500,
                    color: danger ? t.error : t.textPrimary,
                  ),
                ),
                if (subtitle != null) ...<Widget>[
                  const SizedBox(height: 2),
                  Text(
                    subtitle!,
                    style: TextStyle(
                      fontSize: AppTokens.textXs,
                      color: t.textTertiary,
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (value != null) ...<Widget>[
            const SizedBox(width: AppTokens.s2),
            Text(
              value!,
              style: TextStyle(
                fontSize: AppTokens.textXs,
                color: t.textTertiary,
              ),
            ),
          ],
          if (trailing != null) ...<Widget>[
            const SizedBox(width: AppTokens.s2),
            trailing!,
          ],
          if (onTap != null && trailing == null) ...<Widget>[
            const SizedBox(width: AppTokens.s2),
            Icon(
              CupertinoIcons.chevron_forward,
              size: 16,
              color: t.textTertiary,
            ),
          ],
        ],
      ),
    );

    if (onTap == null) return content;
    // 透明 Material 让水波纹画在卡片底色之上（否则会被 AppCard 底色盖住）
    return Material(
      type: MaterialType.transparency,
      child: InkWell(onTap: onTap, child: content),
    );
  }
}

/// 外观模式三选一按钮。
class _ThemeButton extends StatelessWidget {
  const _ThemeButton({
    required this.label,
    required this.icon,
    required this.isSelected,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final fg = isSelected ? t.onPrimary : t.textSecondary;
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: AppTokens.s2 + 2),
          decoration: BoxDecoration(
            color: isSelected ? t.primary : t.formulaBg,
            borderRadius: BorderRadius.circular(AppTokens.radiusMd),
            border: Border.all(
              color: isSelected ? t.primary : t.cardBorder,
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Icon(icon, size: 20, color: fg),
              const SizedBox(height: AppTokens.s1),
              Text(
                label,
                style: TextStyle(fontSize: AppTokens.textXs, color: fg),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
