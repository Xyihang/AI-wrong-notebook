import 'package:flutter/foundation.dart';

import 'package:smart_wrong_notebook/src/data/remote/backend/backend_client.dart';

/// OCR service — 委托云端后端识别。
///
/// 端侧不做 OCR：手机拍照后上传图片到云端后端，由后端
/// RapidOCR（本地 OCR）+ 视觉大模型兜底识别文字。
/// 这样手机端不依赖 Google 服务 / ML Kit，跨 Android/iOS 稳定。
class OcrService {
  OcrService({BackendClient? backendClient})
      : _backendClient = backendClient ?? BackendClient();

  final BackendClient _backendClient;

  Future<String> recognizeImage(String imagePath) async {
    try {
      final ocrText = await _backendClient.recognizeImage(imagePath);
      if (ocrText.trim().isEmpty) {
        debugPrint('[OcrService] 后端返回空 OCR 文本');
      }
      return ocrText;
    } catch (e) {
      debugPrint('[OcrService] recognizeImage failed: $e');
      rethrow;
    }
  }

  void dispose() {}
}
