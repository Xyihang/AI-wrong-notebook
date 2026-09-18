import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:smart_wrong_notebook/src/app/providers.dart';

/// 视觉识别额度卡片。
///
/// 显示当前用户（按 IP）的视觉识别剩余额度：
/// - 有 Key 用户：每日剩余（如 47/50）
/// - 无 Key 用户：累计剩余（如 8/10）
/// 数据来自后端 GET /api/settings/vision-quota，通过 [visionQuotaProvider]
/// 管理；配置 Key 后 / 拍照后调用 [refreshVisionQuota] 即可刷新。
class VisionQuotaCard extends ConsumerWidget {
  const VisionQuotaCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final quotaAsync = ref.watch(visionQuotaProvider);
    return quotaAsync.when(
      loading: () => const Padding(
        padding: EdgeInsets.symmetric(vertical: 4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            SizedBox(width: 8),
            Text('正在加载识别额度...', style: TextStyle(fontSize: 12)),
          ],
        ),
      ),
      error: (e, _) => const SizedBox.shrink(),
      data: (quota) => _QuotaCardBody(quota: quota),
    );
  }
}

/// 刷新视觉额度（配置 Key 后 / 拍照后调用）。
void refreshVisionQuota(WidgetRef ref) {
  ref
      .read(visionQuotaRefreshProvider.notifier)
      .update((state) => state + 1);
}

class _QuotaCardBody extends StatelessWidget {
  const _QuotaCardBody({required this.quota});

  final Map<String, dynamic> quota;

  @override
  Widget build(BuildContext context) {
    final remaining = (quota['remaining'] as num?)?.toInt() ?? 0;
    final limit = (quota['limit'] as num?)?.toInt() ?? 0;
    final mode = (quota['mode'] as String?) ?? 'no_key';
    // 三档：no_key（无Key）/ vision_key（有Key+视觉模式）/ vision_key_no_mode（有Key未开视觉模式）
    final isNoKey = mode == 'no_key';
    final isNoMode = mode == 'vision_key_no_mode';
    final ratio = limit > 0 ? (remaining / limit).clamp(0.0, 1.0) : 0.0;
    final Color barColor = ratio > 0.3
        ? const Color(0xFF16A34A)
        : (ratio > 0.05 ? const Color(0xFFF59E0B) : const Color(0xFFDC2626));

    final title = isNoKey ? '系统识别额度' : '视觉识别额度';
    final subtitle = isNoKey
        ? '累计剩余 $remaining / $limit 次（配置 Key 可升级）'
        : '今日剩余 $remaining / $limit 次';
    // 按当前配置区分提示：
    // - 无 Key：仅本地 OCR 效果差、自动启用云端视觉兜底时才扣减；
    // - 有 Key + 视觉模式：优先用你的 Key 直连，仅 Key 失效回退云端时才扣减；
    // - 有 Key 未开视觉模式：降为每天 20 次且消耗云端额度，醒目提醒开启视觉模式。
    final String hint;
    if (isNoKey) {
      hint = '未配置 Key：仅当本地 OCR 效果差、自动改用云端视觉兜底时才扣减；配置 Key 可升级额度';
    } else if (isNoMode) {
      hint = '你已配置 Key 但未启用视觉模式：每天仅 $limit 次且消耗云端额度，'
          '建议开启视觉模式用你的 Key 直连（不扣云端额度、升级到 50 次/天）';
    } else {
      hint = '已配置 Key：识别优先用你的 Key 直连读图，仅 Key 失效回退云端时才扣减；纯 OCR 不扣';
    }
    // 未开视觉模式时用橙色醒目提醒
    final hintColor = isNoMode
        ? const Color(0xFFB45309)
        : const Color(0xFF9CA3AF);
    final hintIconColor = isNoMode
        ? const Color(0xFFF59E0B)
        : const Color(0xFF9CA3AF);

    return Container(
      margin: const EdgeInsets.only(top: 12, bottom: 4),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: isNoMode ? const Color(0xFFFFFBEB) : const Color(0xFFF3F4F6),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isNoMode ? const Color(0xFFFDE68A) : const Color(0xFFE5E7EB),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                isNoKey ? CupertinoIcons.sparkles : CupertinoIcons.eye,
                size: 16,
                color: barColor,
              ),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF1F2937),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            subtitle,
            style: const TextStyle(fontSize: 12, color: Color(0xFF6B7280)),
          ),
          const SizedBox(height: 6),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 1.5),
                child: Icon(
                  CupertinoIcons.info_circle,
                  size: 12,
                  color: hintIconColor,
                ),
              ),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  hint,
                  style: TextStyle(
                      fontSize: 11, color: hintColor, height: 1.3),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: ratio,
              minHeight: 6,
              backgroundColor: const Color(0xFFE5E7EB),
              valueColor: AlwaysStoppedAnimation<Color>(barColor),
            ),
          ),
        ],
      ),
    );
  }
}
