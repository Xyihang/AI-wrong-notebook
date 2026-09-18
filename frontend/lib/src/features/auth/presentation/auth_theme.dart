import 'package:flutter/material.dart';

/// 认证页共用的应用 Logo（纯代码绘制，与启动页一致）。
class AuthLogo extends StatelessWidget {
  const AuthLogo({super.key});

  @override
  Widget build(BuildContext context) {
    const brandColor = Color(0xFF6366F1);
    return Container(
      width: 72,
      height: 72,
      decoration: BoxDecoration(
        color: brandColor,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: brandColor.withValues(alpha: 0.3),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: const Center(
        child: Icon(Icons.edit_note, color: Colors.white, size: 40),
      ),
    );
  }
}
