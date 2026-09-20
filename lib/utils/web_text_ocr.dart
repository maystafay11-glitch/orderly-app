// واجهة عامة لقراءة النصوص من صورة ثابتة.
//
//   * الويب: `_web_text_ocr_impl.dart` (Tesseract.js من CDN عند الحاجة).
//   * غير ذلك: `_web_text_ocr_stub.dart` (ML Kit يتولّى القراءة هناك).
import 'dart:typed_data';

import 'package:orderly_app/utils/_web_text_ocr_stub.dart'
    if (dart.library.js_interop) 'package:orderly_app/utils/_web_text_ocr_impl.dart'
    as impl;

import 'package:orderly_app/utils/web_text_ocr_state.dart';

export 'package:orderly_app/utils/web_text_ocr_state.dart';

/// يقرأ النصوص من الصورة [bytes] (JPEG/PNG).
///
/// لا يرمي أي استثناء أبداً: يعيد [WebTextOcrStatus.offline] عند تعذّر تحميل
/// المحرّك، و[WebTextOcrStatus.failed] عند أي خطأ آخر.
Future<WebTextOcrResult> recognizeTextFromImage(
  Uint8List bytes, {
  String mimeType = 'image/jpeg',
  Duration timeout = const Duration(seconds: 25),
}) => impl.recognizeTextFromImage(bytes, mimeType: mimeType, timeout: timeout);
