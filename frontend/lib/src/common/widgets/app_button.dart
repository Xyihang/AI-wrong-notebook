import 'package:flutter/material.dart';
import 'package:smart_wrong_notebook/src/app/design/tokens.dart';

/// 按钮语义（对应 demo `.btn-*`）。
enum AppButtonKind { primary, outline, success, warning, error }

/// 统一按钮（demo `.btn`）：高 40，圆角 `radiusMd`，图标 16 + 文字 `textSm`。
class AppButton extends StatelessWidget {
  const AppButton({
    required this.label,
    required this.onPressed,
    this.kind = AppButtonKind.primary,
    this.icon,
    this.expand = true,
    this.height = 40,
    this.fontSize,
    super.key,
  });

  final String label;
  final VoidCallback? onPressed;
  final AppButtonKind kind;
  final IconData? icon;
  final bool expand;
  final double height;
  final double? fontSize;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    late final Color bg;
    late final Color fg;
    BorderSide? side;
    switch (kind) {
      case AppButtonKind.primary:
        bg = t.primary;
        fg = t.onPrimary;
      case AppButtonKind.outline:
        bg = Colors.transparent;
        fg = t.textSecondary;
        side = BorderSide(color: t.cardBorder);
      case AppButtonKind.success:
        bg = t.successSoft;
        fg = t.success;
      case AppButtonKind.warning:
        bg = t.warningSoft;
        fg = t.warning;
      case AppButtonKind.error:
        bg = t.errorSoft;
        fg = t.error;
    }
    final disabled = onPressed == null;
    final child = Row(
      mainAxisAlignment: MainAxisAlignment.center,
      mainAxisSize: expand ? MainAxisSize.max : MainAxisSize.min,
      children: <Widget>[
        if (icon != null) ...<Widget>[
          Icon(icon, size: 16, color: disabled ? t.textTertiary : fg),
          const SizedBox(width: AppTokens.s2),
        ],
        Text(
          label,
          style: TextStyle(
            fontSize: fontSize ?? AppTokens.textSm,
            fontWeight: FontWeight.w500,
            color: disabled ? t.textTertiary : fg,
          ),
        ),
      ],
    );

    final style = FilledButton.styleFrom(
      backgroundColor: bg,
      foregroundColor: fg,
      disabledBackgroundColor: t.card,
      disabledForegroundColor: t.textTertiary,
      elevation: 0,
      minimumSize: Size(expand ? double.infinity : 0, height),
      padding: const EdgeInsets.symmetric(horizontal: AppTokens.s4),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppTokens.radiusMd),
        side: side ?? BorderSide.none,
      ),
      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
    );

    return FilledButton(
      onPressed: onPressed,
      style: style,
      child: child,
    );
  }
}
