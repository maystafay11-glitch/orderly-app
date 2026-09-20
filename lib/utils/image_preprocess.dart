// تجهيز الصورة الملتقطة قبل القراءة (Snapshot Pipeline).
//
// لماذا هذه الطبقة؟
// * قصّ **منطقة إطار المسح** فقط يجعل القراءة أدق ويمنع التقاط أرقام أخرى
//   من الفاتورة.
// * تكبير منطقة صغيرة يرفع دقة التعرّف على الأرقام في الصور الملتقطة من بعيد.
// * التحويل إلى تدرّج رمادي مع رفع التباين يحسّن تمييز الأرقام عن الخلفية
//   ويقلّل حجم الصورة المُرسلة لمحرّك القراءة.
//
// Dart خالص (بدون كاميرا أو متصفح) لذلك يمكن اختبارها مباشرة.
import 'dart:typed_data';
import 'dart:ui' show Rect;

import 'package:image/image.dart' as img;

/// صورة جاهزة للقراءة (بعد القصّ والتكبير والتحسين).
class PreparedScanImage {
  /// إنشاء نتيجة التجهيز.
  const PreparedScanImage({
    required this.bytes,
    required this.width,
    required this.height,
    required this.sourceWidth,
    required this.sourceHeight,
    required this.regionUsed,
    required this.scaleFactor,
  });

  /// بايتات الصورة النهائية (JPEG محسّن للقراءة).
  final Uint8List bytes;

  /// عرض/ارتفاع الصورة النهائية بالبكسل.
  final int width;
  final int height;

  /// أبعاد الصورة الأصلية قبل المعالجة.
  final int sourceWidth;
  final int sourceHeight;

  /// المنطقة المستخدمة من الصورة الأصلية (بالبكسل).
  final Rect regionUsed;

  /// معامل القياس المُطبَّق على العرض:
  /// أكبر من 1 = تكبير، أصغر من 1 = تصغير، و1 = بلا تغيير.
  final double scaleFactor;

  /// هل جرى تكبير الصورة (لمصلحة دقة القراءة)؟
  bool get upscaled => scaleFactor > 1;

  /// هل تمّ قصّ جزء من الصورة؟
  bool get cropped =>
      regionUsed.width < sourceWidth || regionUsed.height < sourceHeight;
}

/// معالج الصور: يجهّز الصورة الملتقطة لقراءة الأرقام.
final class ScanImagePreprocessor {
  const ScanImagePreprocessor._();

  /// أقل عرض مقبول للصورة المعالجة (التكبير يرفع دقة الأرقام الصغيرة).
  static const int minOutputWidth = 900;

  /// أعلى عرض للصورة المعالجة (حماية من بطء القراءة على الهواتف).
  static const int maxOutputWidth = 2200;

  /// جودة JPEG النهائية.
  static const int jpegQuality = 92;

  /// أقل مقاس منطقة يُسمح بقصّها (تجاهل المناطق الصغيرة جداً).
  static const double minRegionSide = 32;

  /// يجهّز الصورة [source] ويقصّ منها المنطقة [region] إن أُعطيت.
  ///
  /// تُرجع `null` إذا كانت البايتات فارغة أو غير قابلة للفك كصورة.
  static PreparedScanImage? prepare(Uint8List source, {Rect? region}) {
    if (source.isEmpty) {
      return null;
    }

    final img.Image? decoded = img.decodeImage(source);
    if (decoded == null || decoded.width == 0 || decoded.height == 0) {
      return null;
    }

    final Rect full = Rect.fromLTWH(
      0,
      0,
      decoded.width.toDouble(),
      decoded.height.toDouble(),
    );
    final Rect clipped = _clip(region ?? full, decoded.width, decoded.height);

    img.Image working = decoded;
    Rect usedRegion = full;

    // 1) القصّ: فقط إذا كانت المنطقة أصغر من الصورة وبمقاس معقول.
    if (clipped.width >= minRegionSide &&
        clipped.height >= minRegionSide &&
        (clipped.width < decoded.width || clipped.height < decoded.height)) {
      working = img.copyCrop(
        decoded,
        x: clipped.left.round(),
        y: clipped.top.round(),
        width: clipped.width.round(),
        height: clipped.height.round(),
      );
      usedRegion = clipped;
    }

    // 2) ضبط العرض: تكبير الصور الصغيرة (أدق للأرقام) وتصغير الضخمة (أسرع).
    final int targetWidth = working.width < minOutputWidth
        ? minOutputWidth
        : (working.width > maxOutputWidth ? maxOutputWidth : working.width);
    final double scaleFactor = working.width == 0
        ? 1
        : targetWidth / working.width;
    if (targetWidth != working.width) {
      working = img.copyResize(
        working,
        width: targetWidth,
        interpolation: img.Interpolation.cubic,
      );
    }

    // 3) تدرّج رمادي + تباين أعلى: يفصل الأرقام عن خلفية الفاتورة.
    working = img.grayscale(working);
    working = img.adjustColor(working, contrast: 1.25);

    final Uint8List bytes = img.encodeJpg(working, quality: jpegQuality);

    return PreparedScanImage(
      bytes: bytes,
      width: working.width,
      height: working.height,
      sourceWidth: decoded.width,
      sourceHeight: decoded.height,
      regionUsed: usedRegion,
      scaleFactor: scaleFactor,
    );
  }

  /// قراءة أبعاد صورة (بالبكسل) بدون معالجة إضافية.
  ///
  /// تُرجع `null` إذا لم تكن البايتات صورة صالحة.
  static ({int width, int height})? dimensionsOf(Uint8List source) {
    if (source.isEmpty) {
      return null;
    }
    final img.Image? decoded = img.decodeImage(source);
    if (decoded == null || decoded.width == 0 || decoded.height == 0) {
      return null;
    }
    return (width: decoded.width, height: decoded.height);
  }

  /// حصر المستطيل داخل حدود الصورة.
  static Rect _clip(Rect rect, int width, int height) {
    final double left = rect.left.clamp(0.0, width.toDouble());
    final double top = rect.top.clamp(0.0, height.toDouble());
    final double right = rect.right.clamp(0.0, width.toDouble());
    final double bottom = rect.bottom.clamp(0.0, height.toDouble());
    if (right <= left || bottom <= top) {
      return Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble());
    }
    return Rect.fromLTRB(left, top, right, bottom);
  }
}
