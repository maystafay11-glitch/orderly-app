import 'dart:math' as math;
import 'dart:ui' show Rect, Size;

/// هندسة مربع المسح: تحويل المربع المعروض على شاشة الكاميرا إلى المنطقة
/// المقابلة له داخل الصورة الملتقطة، حتى تُقرأ الأرقام من داخل المربع فقط.
///
/// الحساب يبني على أن معاينة الكاميرا تُعرض بملء الشاشة مع الحفاظ على النسبة
/// (`BoxFit.cover`) وبمحاذاة مركزية (كما في `_CameraPreviewBox`)، لذلك:
/// * الجزء المرئي من الصورة هو مستطيل مركزي بالنسب [visibleFraction].
/// * أي مستطيل معروض على الشاشة يُحوَّل إلى نسب الصورة عبر [mapToImage].
class ScanGeometry {
  const ScanGeometry._();

  /// حجم الجزء **المرئي** من الصورة بالنسب (0..1) عند عرضها داخل [viewSize]
  /// بنمط `BoxFit.cover` ومحاذاة مركزية.
  ///
  /// القيمة 1 تعني أن كامل البُعد مرئي، والقيمة الأصغر تعني أن جزءاً من
  /// الصورة مقصوص (كما يحدث عند اختلاف نِسب الأبعاد).
  static Size visibleFraction({
    required Size viewSize,
    required Size imageSize,
  }) {
    if (_isInvalid(viewSize) || _isInvalid(imageSize)) {
      return const Size(1, 1);
    }
    final double scale = math.max(
      viewSize.width / imageSize.width,
      viewSize.height / imageSize.height,
    );
    final double fractionWidth = math.min(
      1,
      viewSize.width / (imageSize.width * scale),
    );
    final double fractionHeight = math.min(
      1,
      viewSize.height / (imageSize.height * scale),
    );
    return Size(fractionWidth, fractionHeight);
  }

  /// تحويل مستطيل معروض على الشاشة [scanBox] (بكسل) إلى منطقة داخل الصورة.
  ///
  /// تُرجع `null` إذا كانت الأبعاد غير صالحة.
  static Rect? mapToImage({
    required Rect scanBox,
    required Size viewSize,
    required Size imageSize,
  }) {
    final Rect? fraction = mapToImageFraction(
      scanBox: scanBox,
      viewSize: viewSize,
      imageSize: imageSize,
    );
    if (fraction == null) {
      return null;
    }
    return Rect.fromLTWH(
      fraction.left * imageSize.width,
      fraction.top * imageSize.height,
      fraction.width * imageSize.width,
      fraction.height * imageSize.height,
    );
  }

  /// تحويل مستطيل معروض على الشاشة [scanBox] إلى نسب (0..1) من أبعاد الصورة.
  ///
  /// تُرجع `null` إذا كانت الأبعاد غير صالحة.
  static Rect? mapToImageFraction({
    required Rect scanBox,
    required Size viewSize,
    required Size imageSize,
  }) {
    if (_isInvalid(viewSize) || _isInvalid(scanBox)) {
      return null;
    }
    final Rect boxFraction = _unitFraction(rect: scanBox, viewSize: viewSize);
    final Size visFrac = visibleFraction(viewSize: viewSize, imageSize: imageSize);
    return _mapFractionIntoView(boxFraction: boxFraction, visibleFraction: visFrac);
  }

  /// تحويل نسبة [boxFraction] (داخل النافذة الكاملة 0..1) إلى نسبة الصورة
  /// المرئية بعد تطبيق `BoxFit.cover` والحشو المركزي.
  static Rect _mapFractionIntoView({
    required Rect boxFraction,
    required Size visibleFraction,
  }) {
    final double viewW = 1.0;
    final double viewH = 1.0;
    final double imageW = visibleFraction.width;
    final double imageH = visibleFraction.height;

    // توحيد الصيغ: إذا كان العرض يُقصّذ (مقلوب الارتفاع يُظهر كامل الارتفاع).
    if (imageW >= imageH) {
      // الصورة تمتد أفقياً → يُقصّ الجانب الأفقي.
      final double scale = imageW;
      final double offsetX = (viewW - imageW) / 2;
      final double offsetY = (viewH - imageH) / 2;

      final double left = (boxFraction.left * viewW - offsetX) / scale;
      final double top = (boxFraction.top * viewH - offsetY) / scale;
      final double right = (boxFraction.right * viewW - offsetX) / scale;
      final double bottom = (boxFraction.bottom * viewH - offsetY) / scale;

      return Rect.fromLTRB(
        left.clamp(0.0, 1.0),
        top.clamp(0.0, 1.0),
        right.clamp(0.0, 1.0),
        bottom.clamp(0.0, 1.0),
      );
    } else {
      // الصورة تمتد عمودياً → يُقصّ الجانب العمودي.
      final double scale = imageH;
      final double offsetX = (viewW - imageW) / 2;
      final double offsetY = (viewH - imageH) / 2;

      final double left = (boxFraction.left * viewW - offsetX) / scale;
      final double top = (boxFraction.top * viewH - offsetY) / scale;
      final double right = (boxFraction.right * viewW - offsetX) / scale;
      final double bottom = (boxFraction.bottom * viewH - offsetY) / scale;

      return Rect.fromLTRB(
        left.clamp(0.0, 1.0),
        top.clamp(0.0, 1.0),
        right.clamp(0.0, 1.0),
        bottom.clamp(0.0, 1.0),
      );
    }
  }

  /// تحويل مستطيل [rect] (بكسل) إلى نسب (0..1) داخل [viewSize].
  static Rect _unitFraction({
    required Rect rect,
    required Size viewSize,
  }) {
    if (viewSize.width <= 0 || viewSize.height <= 0) {
      return Rect.zero;
    }
    return Rect.fromLTRB(
      rect.left / viewSize.width,
      rect.top / viewSize.height,
      rect.right / viewSize.width,
      rect.bottom / viewSize.height,
    );
  }

  /// يتحقق مما إذا كان المستطيل أو الحجم غير صالح (سلبي أو فارغ).
  static bool _isInvalid(dynamic value) {
    if (value is Size) {
      return value.width <= 0 || value.height <= 0;
    }
    if (value is Rect) {
      return value.isEmpty;
    }
    return true;
  }
}

