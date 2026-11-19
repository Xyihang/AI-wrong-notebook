import 'dart:async';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:smart_wrong_notebook/src/app/design/tokens.dart';
import 'package:smart_wrong_notebook/src/app/providers.dart';
import 'package:smart_wrong_notebook/src/common/widgets/app_card.dart';
import 'package:smart_wrong_notebook/src/features/glass/glass_top_bar.dart';
import 'package:smart_wrong_notebook/src/data/remote/ai/ai_analysis_service.dart';
import 'package:smart_wrong_notebook/src/data/services/question_analysis_coordinator.dart';
import 'package:smart_wrong_notebook/src/domain/models/question_record.dart';
import 'package:smart_wrong_notebook/src/features/glass/glass_overlays.dart';

class AnalysisLoadingScreen extends ConsumerStatefulWidget {
  const AnalysisLoadingScreen({super.key});

  @override
  ConsumerState<AnalysisLoadingScreen> createState() =>
      _AnalysisLoadingScreenState();
}

class _AnalysisLoadingScreenState extends ConsumerState<AnalysisLoadingScreen> {
  String? _errorMessage;
  String? _debugInfo;
  String? _progressText;
  bool _canContinueInBackground = false;

  @override
  void initState() {
    super.initState();
    // 每次进入加载页都从「读取图片」阶段开始。
    AiAnalysisService.analysisStage.value = 0;
    _runAnalysis();
  }

  Future<void> _runAnalysis() async {
    final current = ref.read(currentQuestionProvider);
    if (current == null) {
      if (mounted) context.go('/');
      return;
    }

    // 检查配置并显示调试信息
    final settingsRepo = ref.read(settingsRepositoryProvider);
    final config = await settingsRepo.getAiProviderConfig();

    String debugInfo = '配置状态:\n';
    debugInfo += '- 配置对象: ${config != null ? "存在" : "为空"}\n';
    if (config != null) {
      debugInfo +=
          '- baseUrl: ${config.baseUrl.isNotEmpty ? config.baseUrl : "(空)"}\n';
      debugInfo +=
          '- model: ${config.model.isNotEmpty ? config.model : "(空)"}\n';
      debugInfo +=
          '- apiKey: ${config.apiKey.isNotEmpty ? "[已设置(${config.apiKey.length}字符)]" : "(空)"}\n';
    } else {
      debugInfo += '\n请到设置中配置 AI 服务';
    }

    if (!mounted) return;
    setState(() => _debugInfo = debugInfo);

    try {
      final coordinator = ref.read(questionAnalysisCoordinatorProvider);
      final QuestionRecord updated;
      if (coordinator is BackgroundQuestionAnalysisCoordinator) {
        final handle = await coordinator.enqueue(current);
        if (mounted) {
          setState(() => _canContinueInBackground = true);
        }
        updated = await coordinator.waitForResult(handle);
      } else {
        updated = await coordinator.analyze(
          current,
          onProgress: (completed, total, {int failed = 0}) {
            if (!mounted) return;
            setState(() {
              if (completed == 0) {
                _progressText = '正在依次分析 $total 道题...';
                return;
              }
              final suffix = failed > 0 ? '（$failed题失败）' : '';
              _progressText = '已完成 $completed/$total题分析$suffix';
            });
          },
        );
      }
      if (!mounted) return;
      final activeQuestion = ref.read(currentQuestionProvider);
      if (activeQuestion?.id != current.id) return;
      ref.read(currentQuestionProvider.notifier).state = updated;
      // 分析可能消耗视觉识别额度，返回后刷新额度显示
      ref
          .read(visionQuotaRefreshProvider.notifier)
          .update((state) => state + 1);

      context.go('/analysis/result');
    } on AiAnalysisException catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = e.toString();
          _debugInfo = debugInfo;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: glassTopBar(context, 
        title: const Text('AI 解析'),
        leading: IconButton(
          icon: const Icon(CupertinoIcons.chevron_left),
          onPressed: () => context.go('/capture/correction'),
        ),
      ),
      body: _errorMessage != null
          ? _buildErrorView()
          : _LoadingView(
              progressText: _progressText,
              onContinueInBackground:
                  _canContinueInBackground ? () => context.go('/') : null,
            ),
    );
  }

  Widget _buildErrorView() {
    final t = context.tokens;
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(AppTokens.s6),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                color: t.warningSoft,
                borderRadius: BorderRadius.circular(32),
              ),
              child: Icon(
                CupertinoIcons.exclamationmark_circle,
                color: t.warning,
                size: 32,
              ),
            ),
            const SizedBox(height: AppTokens.s4),
            Text(
              _errorMessage!,
              textAlign: TextAlign.center,
              style: TextStyle(
                  fontSize: AppTokens.textSm, color: t.textPrimary),
            ),
            const SizedBox(height: AppTokens.s6),
            AppCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text('调试信息:',
                      style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: AppTokens.textXs,
                          color: t.textSecondary)),
                  const SizedBox(height: AppTokens.s2),
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Text(_debugInfo ?? '',
                        style: TextStyle(
                            fontSize: AppTokens.textXs,
                            fontFamily: 'monospace',
                            color: t.textTertiary)),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            FilledButton(
              onPressed: () {
                setState(() {
                  _errorMessage = null;
                  _progressText = null;
                  _canContinueInBackground = false;
                });
                AiAnalysisService.analysisStage.value = 0;
                _runAnalysis();
              },
              style: FilledButton.styleFrom(minimumSize: const Size(120, 40)),
              child: const Text('重试'),
            ),
          ],
        ),
      ),
    );
  }
}

/// 加载页：阶段进度（打勾）+ 不确定进度条 + 安抚文案轮播。
class _LoadingView extends ConsumerStatefulWidget {
  const _LoadingView({
    this.progressText,
    this.onContinueInBackground,
  });

  final String? progressText;
  final VoidCallback? onContinueInBackground;

  @override
  ConsumerState<_LoadingView> createState() => _LoadingViewState();
}

class _LoadingViewState extends ConsumerState<_LoadingView>
    with SingleTickerProviderStateMixin {
  static const List<String> _stages = <String>[
    '正在读取图片…',
    '正在识别题干…',
    '正在解题分析…',
    '正在整理知识点…',
  ];

  static const List<String> _comfort = <String>[
    '别急，AI 正在认真读题…',
    '手写也能认，稍等片刻…',
    '正在核对答案，马上就好…',
    '整理知识点中，先深呼吸一下…',
  ];

  late AnimationController _controller;
  Timer? _comfortTimer;
  int _comfortIndex = 0;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(seconds: 3),
      vsync: this,
    )..repeat();
    _comfortTimer = Timer.periodic(const Duration(seconds: 4), (_) {
      if (!mounted) return;
      setState(() => _comfortIndex = (_comfortIndex + 1) % _comfort.length);
    });
  }

  @override
  void dispose() {
    _comfortTimer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Stack(
      children: <Widget>[
        Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(28, 24, 28, 96),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Container(
                  width: 88,
                  height: 88,
                  decoration: BoxDecoration(
                    color: t.primarySoft,
                    borderRadius: BorderRadius.circular(44),
                  ),
                  child: AnimatedBuilder(
                    animation: _controller,
                    builder: (_, __) => Transform.rotate(
                      angle: _controller.value * 2 * 3.14159,
                      child: Icon(CupertinoIcons.smiley,
                          size: 44, color: t.primary),
                    ),
                  ),
                ),
                const SizedBox(height: 26),
                // 不确定进度条：开启玻璃时为玻璃进度条，否则 Material。
                appProgressBar(context, ref, height: 6),
                const SizedBox(height: 22),
                ValueListenableBuilder<int>(
                  valueListenable: AiAnalysisService.analysisStage,
                  builder: (_, stage, __) => Column(
                    children: <Widget>[
                      for (var i = 0; i < _stages.length; i++)
                        _StageRow(
                          label: _stages[i],
                          done: i < stage,
                          active: i == stage,
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 18),
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 400),
                  child: Text(
                    _comfort[_comfortIndex],
                    key: ValueKey<int>(_comfortIndex),
                    style: TextStyle(
                      fontSize: AppTokens.textSm,
                      color: t.textSecondary,
                    ),
                  ),
                ),
                if (widget.progressText != null) ...<Widget>[
                  const SizedBox(height: 8),
                  Text(
                    widget.progressText!,
                    style: TextStyle(
                        fontSize: AppTokens.textSm,
                        fontWeight: FontWeight.w500,
                        color: t.textPrimary),
                  ),
                ],
                if (widget.onContinueInBackground != null) ...<Widget>[
                  const SizedBox(height: 22),
                  OutlinedButton.icon(
                    onPressed: widget.onContinueInBackground,
                    icon: const Icon(CupertinoIcons.camera, size: 18),
                    label: const Text('继续录题'),
                  ),
                ],
              ],
            ),
          ),
        ),
        // 底部轮播小贴士
        Positioned(
          left: 16,
          right: 16,
          bottom: 20,
          child: const _TipsCarousel(),
        ),
      ],
    );
  }
}

/// 单行阶段：已完成打勾、进行中高亮、未开始灰色。
class _StageRow extends StatelessWidget {
  const _StageRow({
    required this.label,
    required this.done,
    required this.active,
  });

  final String label;
  final bool done;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final color = done
        ? t.success
        : active
            ? t.primary
            : t.textTertiary;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: <Widget>[
          Icon(
            done
                ? CupertinoIcons.check_mark_circled_solid
                : active
                    ? CupertinoIcons.arrow_right_circle_fill
                    : CupertinoIcons.circle,
            size: 18,
            color: color,
          ),
          const SizedBox(width: 10),
          Text(
            label,
            style: TextStyle(
              fontSize: AppTokens.textSm,
              height: 1.3,
              color: color,
              fontWeight: active ? FontWeight.w600 : FontWeight.w400,
            ),
          ),
        ],
      ),
    );
  }
}

/// 底部轮播小贴士：等待时循环展示使用技巧。
class _TipsCarousel extends StatefulWidget {
  const _TipsCarousel();

  @override
  State<_TipsCarousel> createState() => _TipsCarouselState();
}

class _TipsCarouselState extends State<_TipsCarousel> {
  static const List<String> _tips = <String>[
    '你知道吗？识别完成后，还可以让 AI 帮你举一反三、巩固知识点哦',
    '小技巧：拍题时保持光线充足、纸面平整，识别更准确',
    '一页多题可以先裁剪出单道题，再让 AI 逐题解析',
    '错题会按科目自动归档，复习时可按掌握程度筛选',
    '在「设置 → 数据管理」可以导出错题备份，换机不丢失',
    '标记掌握程度后，复习页会自动帮你安排巩固提醒',
    '公式识别不准时，试试印刷体更清晰或调整拍摄角度',
  ];

  int _index = 0;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 3), (_) {
      if (!mounted) return;
      setState(() {
        _index = (_index + 1) % _tips.length;
      });
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: t.primarySoft,
        borderRadius: BorderRadius.circular(AppTokens.radiusLg),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.only(top: 1),
            child: Icon(CupertinoIcons.lightbulb_fill,
                size: 15, color: t.primary),
          ),
          const SizedBox(width: AppTokens.s2),
          Expanded(
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 400),
              child: Text(
                _tips[_index],
                key: ValueKey<int>(_index),
                style: TextStyle(
                    fontSize: AppTokens.textXs,
                    height: 1.4,
                    color: t.textPrimary),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
