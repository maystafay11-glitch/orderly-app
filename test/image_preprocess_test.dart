// اختبارات تجهيز الصورة الملتقطة قبل القراءة (قصّ + تكبير + تباين).
//
// هذه الطبقة Dart خالصة، لذا تُختبر بلا كاميرا ولا متصفح، وتضمن أن الصورة
// التي يقرأها محرّك القراءة فعلاً هي **منطقة إطار المسح** وواضحة بما يكفي.
import 'dart:typed_data';
import 'dart:ui' show Rect;

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

import 'package:orderly_app/utils/image_preprocess.dart';

/// ينشئ صورة JPEG اختبارية بمقاس محدّد مع مستطيل داكن (لإبراز التباين).
Uint8List makeTestJpeg(int width, int height) {
  final img.Image image = img.Image(width: width, height: height);
  img.fill(image, color: img.ColorRgb8(240, 240, 240));
  img.fillRect(
    image,
    x1: width ~/ 4,
    y1: height ~/ 4,
    x2: width ~/ 2,
    y2: height ~/ 2,
    color: img.ColorRgb8(20, 20, 20),
  );
  return Uint8List.fromList(img.encodeJpg(image, quality: 95));
}

void main() {
  group('ScanImagePreprocessor — مدخلات غير صالحة', () {
    test('البايتات الفارغة تُرجع null', () {
      expect(ScanImagePreprocessor.prepare(Uint8List(0)), isNull);
      expect(ScanImagePreprocessor.dimensionsOf(Uint8List(0)), isNull);
    });

    test('البايتات غير الصورة تُرجع null', () {
      final Uint8List garbage = Uint8List.fromList(<int>[1, 2, 3, 4, 5, 6]);
      expect(ScanImagePreprocessor.prepare(garbage), isNull);
      expect(ScanImagePreprocessor.dimensionsOf(garbage), isNull);
    });
  });

  group('ScanImagePreprocessor — الأبعاد والقصّ', () {
    test('يقرأ أبعاد الصورة الأصلية', () {
      final ({int width, int height})? size =
          ScanImagePreprocessor.dimensionsOf(makeTestJpeg(1600, 1200));

      expect(size, isNotNull);
      expect(size!.width, 1600);
      expect(size.height, 1200);
    });

    test('يقصّ منطقة إطار المسح ويُبلّغ عن القصّ والتكبير', () {
      final Uint8List source = makeTestJpeg(1600, 1200);
      final PreparedScanImage? prepared = ScanImagePreprocessor.prepare(
        source,
        region: const Rect.fromLTWH(400, 300, 800, 600),
      );

      expect(prepared, isNotNull);
      expect(prepared!.cropped, isTrue);
      expect(prepared.sourceWidth, 1600);
      expect(prepared.sourceHeight, 1200);
      expect(prepared.regionUsed.left, 400);
      expect(prepared.regionUsed.top, 300);
      // منطقة 800 بكسل أضيق من الحد الأدنى (900) → يجب تكبيرها.
      expect(prepared.width, ScanImagePreprocessor.minOutputWidth);
      expect(prepared.upscaled, isTrue);
      expect(prepared.scaleFactor, greaterThan(1));
      expect(prepared.bytes, isNotEmpty);
    });

    test('يحدّ العرض الأعلى للصورة المعالجة', () {
      final PreparedScanImage? prepared = ScanImagePreprocessor.prepare(
        makeTestJpeg(4000, 3000),
      );

      expect(prepared, isNotNull);
      expect(prepared!.width, ScanImagePreprocessor.maxOutputWidth);
      expect(prepared.cropped, isFalse);
      expect(prepared.upscaled, isFalse);
      expect(prepared.scaleFactor, lessThan(1));
    });

    test('يتجاهل المنطقة الصغيرة جداً ويستخدم الصورة كاملة', () {
      final PreparedScanImage? prepared = ScanImagePreprocessor.prepare(
        makeTestJpeg(1200, 900),
        region: const Rect.fromLTWH(10, 10, 12, 12),
      );

      expect(prepared, isNotNull);
      expect(prepared!.cropped, isFalse);
    });

    test('يضبط منطقة خارج حدود الصورة إلى كامل الصورة', () {
      final PreparedScanImage? prepared = ScanImagePreprocessor.prepare(
        makeTestJpeg(800, 600),
        region: const Rect.fromLTWH(900, 900, 400, 400),
      );

      expect(prepared, isNotNull);
      expect(prepared!.cropped, isFalse);
      expect(prepared.width, ScanImagePreprocessor.minOutputWidth);
    });
  });

  group('ScanImagePreprocessor — تحسين الصورة', () {
    test('الناتج صورة رمادية عالية التباين', () {
      final PreparedScanImage? prepared = ScanImagePreprocessor.prepare(
        makeTestJpeg(1200, 900),
      );

      expect(prepared, isNotNull);

      final img.Image? decoded = img.decodeImage(prepared!.bytes);
      expect(decoded, isNotNull);

      // نتحقق من بكسل داخل المستطيل الداكن: يجب أن تكون القنوات متساوية (رمادي).
      final img.Pixel pixel = decoded!.getPixel(
        decoded.width ~/ 3,
        decoded.height ~/ 3,
      );
      expect(pixel.r, pixel.g);
      expect(pixel.g, pixel.b);
    });
  });
}
