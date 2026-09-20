// نسخة المنصات الأصلية: قراءة النصوص هناك عبر google_mlkit
// (انظر services/_ocr_native.dart)، فلا حاجة لأي إجراء هنا.
import 'dart:typed_data';

import 'package:orderly_app/utils/web_text_ocr_state.dart';

/// على Android/iOS لا نحتاج محرّك قراءة داخل المتصفح.
Future<WebTextOcrResult> recognizeTextFromImage(
  Uint8List bytes, {
  String mimeType = 'image/jpeg',
  Duration timeout = const Duration(seconds: 25),
}) async {
  return const WebTextOcrResult(status: WebTextOcrStatus.notApplicable);
}
