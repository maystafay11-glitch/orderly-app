// نسخة المنصات الأصلية: قراءة الباركود من الصورة تتم هناك عبر ML Kit
// (انظر services/_ocr_native.dart)، فلا حاجة لأي إجراء هنا.
import 'dart:typed_data';

import 'package:orderly_app/utils/web_image_barcode_state.dart';

/// على Android/iOS لا يوجد `BarcodeDetector` للمتصفح.
Future<WebImageBarcodeResult> readBarcodesFromImage(
  Uint8List bytes, {
  String mimeType = 'image/jpeg',
}) async {
  return const WebImageBarcodeResult(
    status: WebImageBarcodeStatus.notApplicable,
  );
}
