// ملف stub للويب — يُستخدم عند تجميع Flutter Web
// يُوفّر واجهة فارغة متوافقة مع OcrNativeHelper دون استيراد google_mlkit أو dart:io
// ignore_for_file: avoid_classes_with_only_static_members

import 'dart:typed_data';
import 'dart:ui' show Rect;

import 'package:orderly_app/services/ocr_service.dart';

/// نسخة وهمية (stub) من مساعد OCR — تُستخدم على Flutter Web.
///
/// جميع المنصات ستستخدم هذا الملف إلا إذا وُجدت dart.library.io
/// (أي نظامي Android/iOS/Desktop).
class OcrNativeHelper {
  const OcrNativeHelper._();

  /// على الويب: إرجاع null — لا يوجد نظام ملفات مباشر.
  static Future<Uint8List?> peekJpegBytes(
    String imagePath, {
    int bytesLength = 64 * 1024,
  }) async {
    return null;
  }

  /// على الويب: إرجاع نتيجة فارغة — OCR غير مدعوم.
  static Future<OcrResult> recognizeAmounts(
    String imagePath, {
    dynamic script,
  }) async {
    return const OcrResult.empty();
  }

  /// على الويب: إرجاع نتيجة فارغة — OCR غير مدعوم.
  static Future<OcrResult> readRegion(
    String imagePath, {
    required Rect region,
    dynamic script,
  }) async {
    return const OcrResult.empty();
  }
}
