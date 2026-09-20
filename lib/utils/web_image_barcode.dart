// واجهة عامة لقراءة الباركود من صورة ثابتة.
//
//   * الويب: `_web_image_barcode_impl.dart` (واجهة BarcodeDetector الأصلية).
//   * غير ذلك: `_web_image_barcode_stub.dart` (لا يُستخدم؛ ML Kit يتولّى الأمر).
import 'dart:typed_data';

import 'package:orderly_app/utils/_web_image_barcode_stub.dart'
    if (dart.library.js_interop)
        'package:orderly_app/utils/_web_image_barcode_impl.dart' as impl;

import 'package:orderly_app/utils/web_image_barcode_state.dart';

export 'package:orderly_app/utils/web_image_barcode_state.dart';

/// يقرأ الباركود/QR من صورة ثابتة [bytes] (JPEG/PNG).
///
/// آمن على كل المنصات: على الأجهزة الأصلية يُرجع
/// [WebImageBarcodeStatus.notApplicable] بدل رمي أي خطأ.
Future<WebImageBarcodeResult> readBarcodesFromImage(
  Uint8List bytes, {
  String mimeType = 'image/jpeg',
}) => impl.readBarcodesFromImage(bytes, mimeType: mimeType);
