// ملف native — يُستخدم على Android/iOS/Desktop فقط (dart.library.io متاح)
// يستورد google_mlkit ويُنفّذ OCR الفعلي
// ignore_for_file: avoid_classes_with_only_static_members

import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' show Rect, Size;

import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';

import 'package:orderly_app/services/ocr_service.dart';
import 'package:orderly_app/utils/jpeg_info.dart';

/// مساعد OCR الفعلي — يُستخدم فقط على المنصات الأصلية (Android/iOS/Desktop).
///
/// يُستورد شرطياً من [ocr_service.dart] عبر:
/// ```dart
/// import 'package:orderly_app/services/_ocr_stub.dart'
///     if (dart.library.io) 'package:orderly_app/services/_ocr_native.dart';
/// ```
class OcrNativeHelper {
  const OcrNativeHelper._();

  // ─── قراءة رأس JPEG ────────────────────────────────────────────────────────

  /// قراءة أول [bytesLength] من الملف لاستخراج رأس JPEG (Exif/orientation).
  static Future<Uint8List?> peekJpegBytes(
    String imagePath, {
    int bytesLength = 64 * 1024,
  }) async {
    final File file = File(imagePath);
    try {
      final RandomAccessFile raf = await file.open(mode: FileMode.read);
      try {
        final int length = await raf.length();
        if (length == 0) return null;
        final int toRead = math.min(bytesLength, length);
        final Uint8List bytes = await raf.read(toRead);
        return bytes.isNotEmpty ? bytes : null;
      } finally {
        await raf.close();
      }
    } catch (_) {
      return null;
    }
  }

  // ─── OCR كامل للصورة ────────────────────────────────────────────────────────

  /// قراءة الصورة كاملةً واستخراج المبالغ وأرقام الطلبات منها.
  static Future<OcrResult> recognizeAmounts(
    String imagePath, {
    dynamic script,
  }) async {
    final TextRecognitionScript recScript =
        (script is TextRecognitionScript) ? script : TextRecognitionScript.latin;
    final TextRecognizer recognizer = TextRecognizer(script: recScript);
    try {
      final InputImage image = InputImage.fromFilePath(imagePath);
      final RecognizedText recognized = await recognizer.processImage(image);
      return OcrService.parseRecognizedText(recognized.text);
    } finally {
      await recognizer.close();
    }
  }

  // ─── OCR مقيود بمنطقة ───────────────────────────────────────────────────────

  /// قراءة منطقة محددة فقط من الصورة.
  ///
  /// يُعيد تشكيل [region] بعد تصحيح اتجاه EXIF ثم يُرشّح النتائج.
  static Future<OcrResult> readRegion(
    String imagePath, {
    required Rect region,
    dynamic script,
  }) async {
    final TextRecognitionScript recScript =
        (script is TextRecognitionScript) ? script : TextRecognitionScript.latin;
    final TextRecognizer recognizer = TextRecognizer(script: recScript);
    try {
      final InputImage image = InputImage.fromFilePath(imagePath);
      final RecognizedText recognized = await recognizer.processImage(image);

      // قراءة أبعاد الصورة المعلنة واتجاهها من رأس JPEG
      final Uint8List? jpegBytes = await peekJpegBytes(imagePath);
      final JpegInfo? jpeg = jpegBytes != null ? JpegInfo.parse(jpegBytes) : null;
      final bool swapsAxes = jpeg?.swapsAxes ?? false;
      final int rotation = swapsAxes ? 90 : 0;
      final Size imageSize = jpeg?.displaySize ?? region.size;

      // تصحيح المنطقة لتطابق فضاء ML Kit (بعد تطبيق دوران EXIF).
      final Rect imageRegion =
          OcrService.toRecognizedSpaceRegion(region, imageSize, rotation);

      final StringBuffer buffer = StringBuffer();
      final Set<double> found = <double>{};
      final List<String> orderNumbers = <String>[];

      for (final TextBlock block in recognized.blocks) {
        for (final TextLine line in block.lines) {
          final List<TextElement> elementsInsideBox = line.elements
              .where((TextElement e) =>
                  OcrService.isInsideRegion(e.boundingBox, imageRegion))
              .toList();

          if (elementsInsideBox.isNotEmpty) {
            final String textInside =
                elementsInsideBox.map((TextElement e) => e.text).join(' ');
            if (buffer.isNotEmpty) buffer.write('\n');
            buffer.write(textInside);

            for (final String num
                in OcrService.extractOrderNumbers(textInside)) {
              if (!orderNumbers.contains(num)) orderNumbers.add(num);
            }

            for (final TextElement element in elementsInsideBox) {
              for (final double amount
                  in OcrService.extractAmounts(element.text)) {
                if (amount <= maxReasonableAmount) found.add(amount);
              }
              for (final String num
                  in OcrService.extractOrderNumbers(element.text)) {
                if (!orderNumbers.contains(num)) orderNumbers.add(num);
              }
            }
          }
        }
      }

      final List<double> amounts = found.toList()
        ..sort((double a, double b) => b.compareTo(a));
      return OcrResult(
        rawText: buffer.toString(),
        amounts: amounts,
        orderNumbers: orderNumbers,
      );
    } finally {
      await recognizer.close();
    }
  }
}
