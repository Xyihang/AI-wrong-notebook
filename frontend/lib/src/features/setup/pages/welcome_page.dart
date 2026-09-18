import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:smart_wrong_notebook/src/features/setup/setup_controller.dart';

/// 向导第 1 步：欢迎页。介绍应用与向导流程，引导用户开始配置。
class WelcomePage extends StatefulWidget {
  const WelcomePage({super.key});

  @override
  State<WelcomePage> createState() => WelcomePageState();
}

class WelcomePageState extends State<WelcomePage>
    implements SetupWizardStepValidator {
  @override
  Future<String?> validateAndCommit() async => null;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;

    return ListView(
      padding: const EdgeInsets.fromLTRB(32, 12, 32, 24),
      children: <Widget>[
        const SizedBox(height: 8),
        Center(
          child: Container(
            width: 96,
            height: 96,
            decoration: BoxDecoration(
              color: isDark
                  ? const Color(0xFF6366F1).withValues(alpha: 0.16)
                  : const Color(0xFFEEF2FF),
              borderRadius: BorderRadius.circular(48),
            ),
            child: const Icon(CupertinoIcons.book,
                size: 48, color: Color(0xFF6366F1)),
          ),
        ),
        const SizedBox(height: 20),
        Center(
          child: Text(
            '欢迎使用 AI错题本',
            textAlign: TextAlign.center,
            style: theme.textTheme.headlineSmall
                ?.copyWith(fontWeight: FontWeight.bold),
          ),
        ),
        const SizedBox(height: 8),
        Center(
          child: Text(
            '拍照录题 · AI 智能解析 · 举一反三',
            style: theme.textTheme.bodyMedium
                ?.copyWith(color: colorScheme.onSurfaceVariant),
          ),
        ),
        const SizedBox(height: 32),
        const _FeatureRow(
          icon: CupertinoIcons.camera,
          color: Color(0xFF6366F1),
          background: Color(0xFFEEF2FF),
          title: '拍照录题',
          description: '快速拍照，智能识别题目',
        ),
        const SizedBox(height: 16),
        const _FeatureRow(
          icon: CupertinoIcons.sparkles,
          color: Color(0xFFD97706),
          background: Color(0xFFFFFBEB),
          title: 'AI 解析',
          description: '深入分析，精准诊断薄弱点',
        ),
        const SizedBox(height: 16),
        const _FeatureRow(
          icon: CupertinoIcons.pencil,
          color: Color(0xFF16A34A),
          background: Color(0xFFF0FDF4),
          title: '举一反三',
          description: '针对性练习，巩固知识点',
        ),
        const SizedBox(height: 28),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: colorScheme.surface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: colorScheme.outlineVariant),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Row(
                children: <Widget>[
                  Icon(CupertinoIcons.sparkles,
                      size: 16, color: colorScheme.primary),
                  const SizedBox(width: 8),
                  Text('首次使用，先完成 3 步配置', style: theme.textTheme.titleSmall),
                ],
              ),
              const SizedBox(height: 10),
              const _StepRow(index: 1, text: '配置 AI 服务商与 API Key'),
              const SizedBox(height: 2),
              const _StepRow(index: 2, text: '选择识别模式'),
              const SizedBox(height: 2),
              const _StepRow(index: 3, text: '完成设置，开始使用'),
            ],
          ),
        ),
        const SizedBox(height: 16),
        Text(
          '配置信息仅保存在本机，可随时在「设置」中修改。',
          textAlign: TextAlign.center,
          style: theme.textTheme.bodySmall
              ?.copyWith(color: colorScheme.onSurfaceVariant),
        ),
      ],
    );
  }
}

class _FeatureRow extends StatelessWidget {
  const _FeatureRow({
    required this.icon,
    required this.color,
    required this.background,
    required this.title,
    required this.description,
  });

  final IconData icon;
  final Color color;
  final Color background;
  final String title;
  final String description;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;

    return Row(
      children: <Widget>[
        Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: isDark ? color.withValues(alpha: 0.16) : background,
            borderRadius: BorderRadius.circular(22),
          ),
          child: Icon(icon, size: 22, color: color),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(title,
                  style: theme.textTheme.titleSmall
                      ?.copyWith(fontWeight: FontWeight.w600)),
              const SizedBox(height: 2),
              Text(description,
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: colorScheme.onSurfaceVariant)),
            ],
          ),
        ),
      ],
    );
  }
}

class _StepRow extends StatelessWidget {
  const _StepRow({required this.index, required this.text});

  final int index;
  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: <Widget>[
          Container(
            width: 22,
            height: 22,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: colorScheme.primaryContainer,
              shape: BoxShape.circle,
            ),
            child: Text(
              '$index',
              style: theme.textTheme.labelSmall?.copyWith(
                color: colorScheme.onPrimaryContainer,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(child: Text(text, style: theme.textTheme.bodyMedium)),
        ],
      ),
    );
  }
}
