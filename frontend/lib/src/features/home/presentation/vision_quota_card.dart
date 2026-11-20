import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:smart_wrong_notebook/src/app/design/tokens.dart';
import 'package:smart_wrong_notebook/src/app/providers.dart';
import 'package:smart_wrong_notebook/src/common/widgets/app_card.dart';

/// 视觉识别额度卡片（Token 版，已适配深色）。
class VisionQuotaCard extends ConsumerWidget {
  const VisionQuotaCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final quotaAsync = ref.watch(visionQuotaProvider);
    return quotaAsync.when(
      loading: () => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            const SizedBox(
                width: 14, height: 14,
                child: CircularProgressIndicator(strokeWidth: 2)),
            const SizedBox(width: 8),
            Text('正在加载识别额度...',
                style: TextStyle(
                    fontSize: AppTokens.textXs,
                    color: context.tokens.textSecondary)),
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
  ref.read(visionQuotaRefreshProvider.notifier).update((state) => state + 1);
}

class _QuotaCardBody extends StatelessWidget {
  const _QuotaCardBody({required this.quota});

  final Map<String, dynamic> quota;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final remaining = (quota['remaining'] as num?)?.toInt() ?? 0;
    final limit = (quota['limit'] as num?)?.toInt() ?? 0;
    final mode = (quota['mode'] as String?) ?? 'no_key';
    final isNoKey = mode == 'no_key';
    final isNoMode = mode == 'vision_key_no_mode';
    final ratio = limit > 0 ? (remaining / limit).clamp(0.0, 1.0) : 0.0;
    final Color barColor = ratio > 0.3
        ? t.success
        : (ratio > 0.05 ? t.warning : t.error);

    final title = isNoKey ? '系统识别额度' : '视觉识别额度';
    final subtitle = isNoKey
        ? '累计剩余 $remaining / $limit 次（配置 Key 可升级）'
        : '今日剩余 $remaining / $limit 次';

    final String hint;
    if (isNoKey) {
      hint = '未配置 Key：仅当本地 OCR 效果差、自动改用云端视觉兜底时才扣减；配置 Key 可升级额度';
    } else if (isNoMode) {
      hint = '你已配置 Key 但未启用视觉模式：每天仅 $limit 次且消耗云端额度，'
          '建议开启视觉模式用你的 Key 直连（不扣云端额度、升级到 50 次/天）';
    } else {
      hint = '已配置 Key：识别优先用你的 Key 直连读图，仅 Key 失效回退云端时才扣减；纯 OCR 不扣';
    }

    return Padding(
      padding: const EdgeInsets.only(top: AppTokens.s3, bottom: AppTokens.s1),
      child: AppCard(
        padding: const EdgeInsets.symmetric(
            horizontal: AppTokens.s3, vertical: AppTokens.s2 + 2),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                Icon(isNoKey ? CupertinoIcons.sparkles : CupertinoIcons.eye,
                    size: 16, color: barColor),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          fontSize: AppTokens.textSm,
                          fontWeight: FontWeight.w600,
                          color: t.textPrimary)),
                ),
              ],
            ),
            const SizedBox(height: AppTokens.s1),
            Text(subtitle,
                style: TextStyle(
                    fontSize: AppTokens.textXs, color: t.textSecondary)),
            const SizedBox(height: 6),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Padding(
                  padding: const EdgeInsets.only(top: 1.5),
                  child: Icon(CupertinoIcons.info_circle,
                      size: 12,
                      color: isNoMode ? t.warning : t.textTertiary),
                ),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(hint,
                      style: TextStyle(
                          fontSize: 11,
                          height: 1.3,
                          color: isNoMode ? t.warning : t.textTertiary)),
                ),
              ],
            ),
            const SizedBox(height: AppTokens.s2),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: ratio,
                minHeight: 6,
                backgroundColor: t.formulaBg,
                valueColor: AlwaysStoppedAnimation<Color>(barColor),
              ),
            ),
            const SizedBox(height: AppTokens.s1),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: <Widget>[
                Text('$remaining / $limit',
                    style: TextStyle(
                        fontSize: AppTokens.textXs, color: t.textTertiary)),
                if (isNoMode)
                  Text('未启用视觉模式',
                      style: TextStyle(fontSize: 11, color: t.warning)),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
