import 'dart:io';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_cropper/image_cropper.dart';
import 'package:smart_wrong_notebook/src/app/providers.dart';
import 'package:smart_wrong_notebook/src/features/glass/glass_providers.dart';
import 'package:smart_wrong_notebook/src/features/glass/glass_top_bar.dart';
import 'package:smart_wrong_notebook/src/domain/models/content_status.dart';
import 'package:smart_wrong_notebook/src/domain/models/question_record.dart';

class ImageCropScreen extends ConsumerStatefulWidget {
  const ImageCropScreen({super.key});

  @override
  ConsumerState<ImageCropScreen> createState() => _ImageCropScreenState();
}

class _ImageCropScreenState extends ConsumerState<ImageCropScreen> {
  bool _cropping = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _startCrop();
    });
  }

  Future<void> _startCrop() async {
    final current = ref.read(currentQuestionProvider);
    if (current == null) {
      if (mounted) context.go('/');
      return;
    }

    setState(() => _cropping = true);

    try {
      final croppedFile = await ImageCropper().cropImage(
        sourcePath: current.imagePath,
        compressFormat: ImageCompressFormat.jpg,
        compressQuality: 82,
        uiSettings: [
          AndroidUiSettings(
            toolbarTitle: '框选题目',
            // 与 App 品牌色统一：靛蓝工具栏 + 深色裁剪区
            toolbarColor: const Color(0xFF6366F1),
            toolbarWidgetColor: Colors.white,
            statusBarColor: const Color(0xFF4F46E5),
            backgroundColor: const Color(0xFF0F172A),
            activeControlsWidgetColor: const Color(0xFF8B5CF6),
            cropFrameColor: Colors.white,
            cropGridColor: const Color(0x66FFFFFF),
            dimmedLayerColor: const Color(0xB3000000),
            // 去掉 uCrop 的 Logo/计数，减少“工具感”
            showCropGrid: true,
            // 自由缩放；比例预设精简为 原始/1:1/4:3
            initAspectRatio: CropAspectRatioPreset.original,
            lockAspectRatio: false,
            aspectRatioPresets: <CropAspectRatioPreset>[
              CropAspectRatioPreset.original,
              CropAspectRatioPreset.square,
              CropAspectRatioPreset.ratio4x3,
            ],
            hideBottomControls: false,
          ),
          IOSUiSettings(
            title: '框选题目',
            cancelButtonTitle: '取消',
            doneButtonTitle: '完成',
            aspectRatioLockEnabled: false,
            resetAspectRatioEnabled: true,
          ),
        ],
      );

      if (!mounted) return;

      if (croppedFile != null) {
        // 裁剪成功：保存裁剪图，更新当前题目，进入单题分析
        final storage = ref.read(imageStorageServiceProvider);
        final savedPath = await storage.saveImage(File(croppedFile.path));

        final newRecord = QuestionRecord.draft(
          id: current.id,
          imagePath: savedPath,
          subject: current.subject,
          recognizedText: '',
        ).copyWith(contentStatus: ContentStatus.processing);
        ref.read(currentQuestionProvider.notifier).state = newRecord;

        if (mounted) {
          context.go('/analysis/loading');
        }
      } else {
        // 用户取消裁剪：留在本页，可重新裁剪；不清理当前题目
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('已取消裁剪，可重新裁剪')),
          );
        }
      }
    } catch (e) {
      // 裁剪失败：留在本页可重试，不再跳转
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('裁剪失败: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _cropping = false);
    }
  }

  /// 退出裁剪页：清理当前拍照流程的残留状态后回首页。
  void _exitAndClear() {
    ref.read(currentQuestionProvider.notifier).state = null;
    if (mounted) context.go('/');
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      // 拦截系统返回键，统一走「清理 + 回首页」，避免残留状态或不可控后退
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        _exitAndClear();
      },
      child: Scaffold(
        extendBodyBehindAppBar: ref.watch(glassEnabledProvider),
        appBar: glassTopBar(
          context,
          title: const Text('框选题目'),
          leading: IconButton(
            icon: const Icon(CupertinoIcons.chevron_left),
            onPressed: _exitAndClear,
          ),
        ),
        body: DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: <Color>[
                Theme.of(context).colorScheme.surfaceContainerLow,
                Theme.of(context).colorScheme.surface,
              ],
            ),
          ),
          child: SafeArea(
            child: Center(
            child: _cropping
                ? const Column(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      CircularProgressIndicator(),
                      SizedBox(height: 16),
                      Text('正在打开裁剪工具...'),
                    ],
                  )
                : Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        const Text('准备裁剪...'),
                        const SizedBox(height: 16),
                        FilledButton(
                          onPressed: _startCrop,
                          child: const Text('重新裁剪'),
                        ),
                      ],
                    ),
                  ),
            ),
          ),
        ),
      ),
    );
  }
}
