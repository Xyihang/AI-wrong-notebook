import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:smart_wrong_notebook/src/features/glass/glass_appearance.dart';

/// 设备能力画像（用于分档，不引入额外插件）。
class DeviceProfile {
  const DeviceProfile({
    required this.cores,
    required this.ramMb,
    required this.refreshHz,
    required this.sdkInt,
  });

  /// CPU 核心数。
  final int cores;

  /// 运行内存（MB）；读取失败为 0（视为未知）。
  final int ramMb;

  /// 屏幕刷新率（Hz）；读取失败为 60。
  final double refreshHz;

  /// Android API Level；无法解析时为 0（视为未知，不因此降档）。
  final int sdkInt;

  /// 采集设备信息。可在 `runApp` 之前调用（不依赖 BuildContext）。
  static Future<DeviceProfile> collect() async {
    final cores = Platform.numberOfProcessors;
    var ramMb = 0;
    var refreshHz = 60.0;
    var sdkInt = 0;

    try {
      if (Platform.isAndroid || Platform.isLinux) {
        final meminfo = await File('/proc/meminfo').readAsString();
        final match = RegExp(r'MemTotal:\s*(\d+)\s*kB').firstMatch(meminfo);
        if (match != null) {
          ramMb = (int.parse(match.group(1)!) / 1024).round();
        }
      }
    } catch (_) {}

    try {
      final displays =
          WidgetsBinding.instance.platformDispatcher.displays;
      if (displays.isNotEmpty) {
        final rate = displays.first.refreshRate;
        if (rate > 0) refreshHz = rate;
      }
    } catch (_) {}

    try {
      if (Platform.isAndroid) {
        final version = Platform.operatingSystemVersion;
        final api = RegExp(r'SDK\s*(\d+)').firstMatch(version) ??
            RegExp(r'API\s*(\d+)').firstMatch(version);
        if (api != null) sdkInt = int.parse(api.group(1)!);
      } else if (Platform.isIOS) {
        sdkInt = 0;
      }
    } catch (_) {}

    return DeviceProfile(
      cores: cores,
      ramMb: ramMb,
      refreshHz: refreshHz,
      sdkInt: sdkInt,
    );
  }

  /// 按规格分档：
  /// - 高：核心 ≥8、运行内存 ≥10GB、刷新率 ≥90Hz、Android API ≥31（未知 API 不阻塞）；
  /// - 中（默认）：核心 ≥6、运行内存 ≥6GB；
  /// - 低：其余。
  GlassTier resolveTier() {
    final highApiOk = sdkInt == 0 || sdkInt >= 31;
    if (cores >= 8 &&
        ramMb >= 10 * 1024 &&
        refreshHz >= 90 &&
        highApiOk) {
      return GlassTier.high;
    }
    if (cores >= 6 && ramMb >= 6 * 1024) {
      return GlassTier.mid;
    }
    return GlassTier.low;
  }
}
