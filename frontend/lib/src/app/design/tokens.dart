import 'package:flutter/material.dart';

/// 设计 Token（对应 `design/ui-beautify-demo.html`）。
///
/// 页面/组件一律通过 `context.tokens` 取色与尺寸，禁止再写字面量。
/// 浅色与深色各自一套；深色卡片使用不透明 `card` + 1px `cardBorder`（无阴影）。
@immutable
class AppTokens extends ThemeExtension<AppTokens> {
  const AppTokens({
    required this.primary,
    required this.primaryDark,
    required this.primarySoft,
    required this.secondary,
    required this.secondarySoft,
    required this.success,
    required this.successSoft,
    required this.warning,
    required this.warningSoft,
    required this.error,
    required this.errorSoft,
    required this.bg,
    required this.bgPage,
    required this.card,
    required this.cardBorder,
    required this.cardTranslucent,
    required this.textPrimary,
    required this.textSecondary,
    required this.textTertiary,
    required this.onPrimary,
    required this.formulaBg,
    required this.shadow1,
    required this.shadow2,
    required this.isDark,
  });

  // ---- 颜色 ----
  final Color primary;
  final Color primaryDark;
  final Color primarySoft;
  final Color secondary;
  final Color secondarySoft;
  final Color success;
  final Color successSoft;
  final Color warning;
  final Color warningSoft;
  final Color error;
  final Color errorSoft;
  final Color bg;
  final Color bgPage;
  final Color card;
  final Color cardBorder;

  /// 有页面背景图时的半透明卡片（可选使用，默认不启用）。
  final Color cardTranslucent;
  final Color textPrimary;
  final Color textSecondary;
  final Color textTertiary;
  final Color onPrimary;
  final Color formulaBg;
  final List<BoxShadow> shadow1;
  final List<BoxShadow> shadow2;
  final bool isDark;

  // ---- 字阶 ----
  static const double textXs = 12;
  static const double textSm = 14;
  static const double textBase = 16;
  static const double textLg = 20;
  static const double textXl = 24;
  static const double textXxl = 32;

  // ---- 间距（4px 栅格）----
  static const double s1 = 4;
  static const double s2 = 8;
  static const double s3 = 12;
  static const double s4 = 16;
  static const double s6 = 24;
  static const double s8 = 32;
  static const double s12 = 48;

  // ---- 圆角 ----
  static const double radiusSm = 6;
  static const double radiusMd = 8;
  static const double radiusLg = 12;

  /// 科目色（统一入口，避免各处硬编码）。
  Color subjectColor(String subject) {
    switch (subject) {
      case '语文':
        return success;
      case '数学':
        return primary;
      case '英语':
        return warning;
      case '物理':
        return secondary;
      case '化学':
        return const Color(0xFF7C3AED);
      case '生物':
        return const Color(0xFF0EA5E9);
      default:
        return textSecondary;
    }
  }

  /// 科目软底（标签背景）。
  ///
  /// 深色下一律用「科目色 18% 透明」叠在卡片上，避免固定浅底在深色里刺眼。
  Color subjectSoft(String subject) {
    if (isDark) return subjectColor(subject).withValues(alpha: 0.18);
    switch (subject) {
      case '语文':
        return successSoft;
      case '数学':
        return primarySoft;
      case '英语':
        return warningSoft;
      case '物理':
        return secondarySoft;
      case '化学':
        return const Color(0xFFF3E8FF);
      case '生物':
        return const Color(0xFFE0F2FE);
      default:
        return card;
    }
  }

  /// 难度色：较易 / 中等 / 较难。
  Color difficultyColor(String label) {
    if (label.contains('易')) return success;
    if (label.contains('中')) return warning;
    if (label.contains('难')) return error;
    return textSecondary;
  }

  @override
  AppTokens copyWith({
    Color? primary,
    Color? primaryDark,
    Color? primarySoft,
    Color? secondary,
    Color? secondarySoft,
    Color? success,
    Color? successSoft,
    Color? warning,
    Color? warningSoft,
    Color? error,
    Color? errorSoft,
    Color? bg,
    Color? bgPage,
    Color? card,
    Color? cardBorder,
    Color? cardTranslucent,
    Color? textPrimary,
    Color? textSecondary,
    Color? textTertiary,
    Color? onPrimary,
    Color? formulaBg,
    List<BoxShadow>? shadow1,
    List<BoxShadow>? shadow2,
    bool? isDark,
  }) {
    return AppTokens(
      primary: primary ?? this.primary,
      primaryDark: primaryDark ?? this.primaryDark,
      primarySoft: primarySoft ?? this.primarySoft,
      secondary: secondary ?? this.secondary,
      secondarySoft: secondarySoft ?? this.secondarySoft,
      success: success ?? this.success,
      successSoft: successSoft ?? this.successSoft,
      warning: warning ?? this.warning,
      warningSoft: warningSoft ?? this.warningSoft,
      error: error ?? this.error,
      errorSoft: errorSoft ?? this.errorSoft,
      bg: bg ?? this.bg,
      bgPage: bgPage ?? this.bgPage,
      card: card ?? this.card,
      cardBorder: cardBorder ?? this.cardBorder,
      cardTranslucent: cardTranslucent ?? this.cardTranslucent,
      textPrimary: textPrimary ?? this.textPrimary,
      textSecondary: textSecondary ?? this.textSecondary,
      textTertiary: textTertiary ?? this.textTertiary,
      onPrimary: onPrimary ?? this.onPrimary,
      formulaBg: formulaBg ?? this.formulaBg,
      shadow1: shadow1 ?? this.shadow1,
      shadow2: shadow2 ?? this.shadow2,
      isDark: isDark ?? this.isDark,
    );
  }

  @override
  AppTokens lerp(covariant AppTokens? other, double t) {
    if (other == null) return this;
    Color c(Color a, Color b) => Color.lerp(a, b, t)!;
    return AppTokens(
      primary: c(primary, other.primary),
      primaryDark: c(primaryDark, other.primaryDark),
      primarySoft: c(primarySoft, other.primarySoft),
      secondary: c(secondary, other.secondary),
      secondarySoft: c(secondarySoft, other.secondarySoft),
      success: c(success, other.success),
      successSoft: c(successSoft, other.successSoft),
      warning: c(warning, other.warning),
      warningSoft: c(warningSoft, other.warningSoft),
      error: c(error, other.error),
      errorSoft: c(errorSoft, other.errorSoft),
      bg: c(bg, other.bg),
      bgPage: c(bgPage, other.bgPage),
      card: c(card, other.card),
      cardBorder: c(cardBorder, other.cardBorder),
      cardTranslucent: c(cardTranslucent, other.cardTranslucent),
      textPrimary: c(textPrimary, other.textPrimary),
      textSecondary: c(textSecondary, other.textSecondary),
      textTertiary: c(textTertiary, other.textTertiary),
      onPrimary: c(onPrimary, other.onPrimary),
      formulaBg: c(formulaBg, other.formulaBg),
      shadow1: t < 0.5 ? shadow1 : other.shadow1,
      shadow2: t < 0.5 ? shadow2 : other.shadow2,
      isDark: t < 0.5 ? isDark : other.isDark,
    );
  }

  static const AppTokens light = AppTokens(
    primary: Color(0xFF4F46E5),
    primaryDark: Color(0xFF4338CA),
    primarySoft: Color(0xFFEEF2FF),
    secondary: Color(0xFF0D9488),
    secondarySoft: Color(0xFFF0FDFA),
    success: Color(0xFF16A34A),
    successSoft: Color(0xFFF0FDF4),
    warning: Color(0xFFD97706),
    warningSoft: Color(0xFFFFFBEB),
    error: Color(0xFFDC2626),
    errorSoft: Color(0xFFFEF2F2),
    bg: Color(0xFFFFFFFF),
    bgPage: Color(0xFFF8F9FA),
    card: Color(0xFFFFFFFF),
    cardBorder: Color(0xFFE5E7EB),
    cardTranslucent: Color(0xB8FFFFFF),
    textPrimary: Color(0xFF111827),
    textSecondary: Color(0xFF6B7280),
    textTertiary: Color(0xFF9CA3AF),
    onPrimary: Color(0xFFFFFFFF),
    formulaBg: Color(0xFFF3F4F6),
    shadow1: <BoxShadow>[
      BoxShadow(color: Color(0x14000000), blurRadius: 3, offset: Offset(0, 1)),
    ],
    shadow2: <BoxShadow>[
      BoxShadow(color: Color(0x1A000000), blurRadius: 12, offset: Offset(0, 4)),
    ],
    isDark: false,
  );

  static const AppTokens dark = AppTokens(
    primary: Color(0xFF818CF8),
    primaryDark: Color(0xFF6366F1),
    primarySoft: Color(0xFF312E81),
    secondary: Color(0xFF2DD4BF),
    secondarySoft: Color(0xFF134E4A),
    success: Color(0xFF4ADE80),
    successSoft: Color(0xFF14532D),
    warning: Color(0xFFFBBF24),
    warningSoft: Color(0xFF451A03),
    error: Color(0xFFF87171),
    errorSoft: Color(0xFF450A0A),
    bg: Color(0xFF0F172A),
    bgPage: Color(0xFF0F172A),
    card: Color(0xFF1E293B),
    cardBorder: Color(0xFF334155),
    cardTranslucent: Color(0xD11E293B),
    textPrimary: Color(0xFFE2E8F0),
    textSecondary: Color(0xFF94A3B8),
    textTertiary: Color(0xFF64748B),
    onPrimary: Color(0xFFFFFFFF),
    formulaBg: Color(0xFF0F172A),
    shadow1: <BoxShadow>[],
    shadow2: <BoxShadow>[],
    isDark: true,
  );
}

/// 便捷访问：`context.tokens.primary`。
extension AppTokensX on BuildContext {
  AppTokens get tokens =>
      Theme.of(this).extension<AppTokens>() ??
      (Theme.of(this).brightness == Brightness.dark
          ? AppTokens.dark
          : AppTokens.light);
}


/// 补齐的设计缺口（不属于主题切换字段，但设计稿需要）。
///
/// 用法：`AppPalette.accentViolet(context.tokens.isDark)` 等。
class AppPalette {
  const AppPalette._();

  /// 强调紫（候选卡、难度=提高）。
  static Color accentViolet(bool dark) =>
      dark ? const Color(0xFFA78BFA) : const Color(0xFF7C3AED);

  /// 橙红档（答错 / 待复习，介于 warning 与 error 之间）。
  static Color orange(bool dark) =>
      dark ? const Color(0xFFFB923C) : const Color(0xFFEA580C);

  /// 软底上的深色前景（保证彩色底上的对比度）。
  static Color onSoft(Color softForeground, bool dark) => dark
      ? softForeground
      : Color.lerp(softForeground, const Color(0xFF000000), 0.35)!;

  /// 中性最浅底（「今日新增」类卡片）。
  static Color bgSubtle(bool dark) =>
      dark ? const Color(0xFF0F172A) : const Color(0xFFF9FAFB);

  /// 反向表面（tooltip / 深色提示条）。
  static Color inverseSurface(bool dark) =>
      dark ? const Color(0xFFE2E8F0) : const Color(0xFF1E293B);

  /// 反向表面上的文字。
  static Color onInverseSurface(bool dark) =>
      dark ? const Color(0xFF0F172A) : const Color(0xFFFFFFFF);

  /// 图表数据系列色（3 条）。
  static List<Color> chartSeries(bool dark) => dark
      ? const <Color>[
          Color(0xFF4ADE80),
          Color(0xFFFBBF24),
          Color(0xFF64748B),
        ]
      : const <Color>[
          Color(0xFF16A34A),
          Color(0xFFD97706),
          Color(0xFF9CA3AF),
        ];

  /// 极小字（图片角标等，设计稿 10px）。
  static const double textXxs = 10;

  /// 全圆角。
  static const double radiusFull = 999;
}
