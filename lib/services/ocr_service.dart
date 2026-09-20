import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' show Rect, Size;

import 'package:flutter/foundation.dart' show kIsWeb;

// ─── Conditional imports للمكتبات غير المتوافقة مع الويب ──────────────────
// على الويب (kIsWeb=true): يُستخدم _ocr_stub.dart (واجهة فارغة)
// على Android/iOS: يُستخدم _ocr_native.dart (google_mlkit الفعلي)
import 'package:orderly_app/services/_ocr_stub.dart'
    // ignore: uri_does_not_exist
    if (dart.library.io) 'package:orderly_app/services/_ocr_native.dart';

import 'package:orderly_app/utils/jpeg_info.dart';

/// بكسل أعلى يُستخدم لتجنّب نتائج خافتة أو أرقام غير واقعية.
const double maxReasonableAmount = 1000000;

/// أقصى عدد خانات مقبول لرقم الطلب أو الباركود المُستخرج من الصورة.
const int maxOrderNumberDigits = 14;

/// نتيجة قراءة صورة: النص الخام + المبالغ وأرقام الطلبات المكتشفة.
class OcrResult {
  /// نتيجة قراءة ناجحة.
  const OcrResult({
    required this.rawText,
    required this.amounts,
    this.orderNumbers = const <String>[],
  });

  /// نتيجة فارغة (لم يُعثر على أي رقم للطلب أو السعر).
  const OcrResult.empty()
    : rawText = '',
      amounts = const <double>[],
      orderNumbers = const <String>[];

  /// كل النص المقروء من الصورة (للأرشيف وللمراجعة).
  final String rawText;

  /// المبالغ المكتشفة من الصورة، مرتّبة تنازلياً وبلا تكرار.
  final List<double> amounts;

  /// أرقام الطلبات المكتشفة من الصورة (بلا تكرار، بترتيب الظهور).
  final List<String> orderNumbers;

  /// أفضل رقم مقترح لسعر الطلب (الأكبر عادةً هو الإجمالي في الفاتورة).
  double? get best => amounts.isEmpty ? null : amounts.first;

  /// أفضل رقم مقترح لرقم الطلب (أول رقم مرتبط بكلمة «طلب» أو `#`).
  String? get bestOrderNumber =>
      orderNumbers.isEmpty ? null : orderNumbers.first;

  /// هل عُثر على رقم طلب واضح في الصورة؟
  bool get hasOrderNumber => orderNumbers.isNotEmpty;

  /// هل لم يُعثر على أي رقم (سعر أو رقم طلب) في الصورة؟
  bool get isEmpty => amounts.isEmpty && orderNumbers.isEmpty;
}

/// خدمة التعرف على النصوص والأرقام من الصور.
///
/// تُستخدم مع شاشة الكاميرا: تُقرأ الصورة، ثم تُستخرج الأرقام من النص
/// لملء حقل سعر الطلب تلقائياً (ويبقى الإدخال اليدوي متاحاً دائماً).
///
/// **على الويب**: google_mlkit لا يدعم Flutter Web؛ وبدلاً منه يُستخدم
/// `web_text_ocr.dart` (Tesseract.js من CDN عبر `recognizeTextFromImage`)
/// كبديل متوافق تماماً لقراءة النصوص المطبوعة مباشرة من صورة ثابتة.
/// وكل حالات الفشل (لا إنترنت، موقع يحجب الـ CDN، أو لا يوجد نص) معالَجة
/// لتفادي توقف التطبيق؛ ويبقى **الإدخال اليدوي متاحاً دائماً** كخلفية
/// منبهة صحيحة بدلاً من رسائل فشل مضللة.
class OcrService {
  const OcrService._();

  /// هل تدعم هذه المنصة قراءة النصوص تلقائياً (OCR)؟
  ///
  /// * Android / iOS / كمبيوتر: `true` (عبر google_mlkit).
  /// * الويب: `true` — يُستخدم `web_text_ocr.dart` (Tesseract.js من CDN).
  ///   إن لم يتوفر المحرك (offline / CDN محظور) تُعرض رسالة ملائمة
  ///   مع إدخال يدوي بدلاً من إيقاف الشاشة.
  static const bool isSupported = true;

  /// نمط الأرقام: `1500` أو `1,500` أو `1.500` أو `12.5`.
  static final RegExp _numberPattern = RegExp(r'\d+(?:[.,]\d+)*');

  /// نمط رقم تُستخدم فيه النقطة أو الفاصلة كفاصل آلاف (مجموعات من 3 خانات).
  static final RegExp _thousandGroupsPattern = RegExp(r'^\d{1,3}(\.\d{3})+$');

  /// كلمات تدلّ على رقم الطلب أو الفاتورة أو الباركود متبوعة بالرقم مباشرة.
  static final RegExp _orderNumberLabelPattern = RegExp(
    r'(?:رقم\s*(?:الطلب|الأوردر|الاوردر|أوردر|اوردر|الفاتورة|الوصل|الباركود|الكود)|'
    r'الطلب|أوردر|اوردر|فاتورة|وصل|باركود|كود|order|invoice|bill|barcode|code|#)'
    r'\s*[:#.\-]?\s*(\d{1,14})(?!\d)',
    caseSensitive: false,
  );

  /// رقم مكتوب بعده علامة `#` (مثل `1024#`).
  static final RegExp _orderNumberHashSuffixPattern = RegExp(
    r'(\d{1,14})(?!\d)\s*#',
  );

  /// قراءة أول [bytesLength] من الملف [imagePath] لاستخراج رأس JPEG.
  ///
  /// تُرجع `null` إذا لم يتم العثر على الملف أو كان فارغاً —
  /// يُعامل ذلك `readRegion` كصورة بلا دوران (توافق الاختبارات).
  /// **على الويب**: يُرجع `null` دائماً.
  static Future<Uint8List?> _peekJpegBytes(
    String imagePath, {
    int bytesLength = 64 * 1024,
  }) async {
    if (kIsWeb) return null;
    return OcrNativeHelper.peekJpegBytes(imagePath, bytesLength: bytesLength);
  }

  /// قراءة صورة من المسار [imagePath] واستخراج المبالغ وأرقام الطلبات منها.
  ///
  /// **على الويب**: يُرجع [OcrResult.empty] فوراً.
  static Future<OcrResult> recognizeAmounts(
    String imagePath, {
    dynamic script,
  }) async {
    if (kIsWeb) return const OcrResult.empty();
    return OcrNativeHelper.recognizeAmounts(imagePath, script: script);
  }

  /// قراءة مقيودة: تُعالج الصورة وتقرأ فقط الكلمات التي تقع **داخل**
  /// المنطقة [region] (بكسل في الصورة الأصلية)، متجاهلاً باقي الفاتورة.
  ///
  /// **على الويب**: يُرجع [OcrResult.empty] فوراً.
  static Future<OcrResult> readRegion(
    String imagePath, {
    required Rect region,
    dynamic script,
  }) async {
    if (kIsWeb) return const OcrResult.empty();
    return OcrNativeHelper.readRegion(
      imagePath,
      region: region,
      script: script,
    );
  }

  /// دمج النص في حالة قراءة مقيودة أو كاملة.
  ///
  /// تعتمد المبالغ وأرقام الطلبات على القراءة المقيودة أولاً (أدق عند تحديد
  /// مربع المسح)، وإلا تُستخدم القراءة الكاملة للصورة.
  static OcrResult combine(OcrResult? region, OcrResult? full) {
    final Set<double> amounts = <double>{};
    final List<String> orderNumbers = <String>[];
    String text = '';
    final OcrResult? preferred = (region != null && !region.isEmpty)
        ? region
        : full;
    if (preferred != null) {
      amounts.addAll(preferred.amounts);
      _collectOrderNumbers(preferred.rawText, orderNumbers);
      for (final String number in preferred.orderNumbers) {
        if (!orderNumbers.contains(number)) {
          orderNumbers.add(number);
        }
      }
      text = preferred.rawText;
    }
    final List<double> sorted = amounts.toList()
      ..sort((double a, double b) => b.compareTo(a));
    return OcrResult(
      rawText: text,
      amounts: sorted,
      orderNumbers: orderNumbers,
    );
  }

  /// [مساعد عام] تحليل نص OCR خام واستخراج نتيجة OcrResult.
  ///
  /// يُستخدم من قِبَل [_ocr_native.dart] لتجنب تكرار منطق الاستخراج.
  static OcrResult parseRecognizedText(String rawText) {
    return OcrResult(
      rawText: rawText,
      amounts: extractAmounts(rawText),
      orderNumbers: extractOrderNumbers(rawText),
    );
  }

  /// تحويل [region] (نسبي إلى الصورة المعلنة الأصلية) إلى مساحة
  /// التعرف التي يُرجعها ML Kit بعد تطبيق دوران [rotation] (0/90/180/270).
  static Rect toRecognizedSpaceRegion(
      Rect region, Size imageSize, int rotation) {
    if (imageSize.isEmpty || rotation == 0) {
      return region;
    }
    Size currentSize = imageSize;
    Rect current = region;
    for (int i = 0; i < (rotation ~/ 90) % 4; i++) {
      final double h = currentSize.height;
      final double left = h - current.bottom;
      final double top = current.left;
      final double right = h - current.top;
      final double bottom = current.right;
      current = Rect.fromLTRB(left, top, right, bottom);
      currentSize = Size(h, currentSize.width);
    }
    return current;
  }

  /// هل يقع العنصر أو السطر داخل منطقة المستطيل المحددة؟
  ///
  /// نتحقق من أن مركز العنصر يقع داخل المربع، أو أن نسبة التداخل بينهما
  /// تمثل أكثر من 40% من مساحة العنصر، لمنع قراءة النصوص الواقعة خارج المربع.
  static bool isInsideRegion(Rect elementBox, Rect region) {
    if (elementBox.isEmpty || region.isEmpty) {
      return false;
    }
    if (region.contains(elementBox.center)) {
      return true;
    }
    final Rect intersection = elementBox.intersect(region);
    if (intersection.width > 0 && intersection.height > 0) {
      final double elementArea = elementBox.width * elementBox.height;
      final double overlapArea = intersection.width * intersection.height;
      return elementArea > 0 && (overlapArea / elementArea) >= 0.40;
    }
    return false;
  }

  /// تحويل الأرقام العربية الهندية (٠١٢…) والفارسية (۰۱۲…) إلى أرقام لاتينية،
  /// مع توحيد الفواصل العربية `٫` و`٬`.
  static String normalizeDigits(String text) {
    final StringBuffer buffer = StringBuffer();
    for (final int rune in text.runes) {
      final String character = String.fromCharCode(rune);
      final int arabicIndex = _arabicIndicDigits.indexOf(character);
      if (arabicIndex != -1) {
        buffer.write(arabicIndex);
        continue;
      }
      final int persianIndex = _persianDigits.indexOf(character);
      if (persianIndex != -1) {
        buffer.write(persianIndex);
        continue;
      }
      switch (character) {
        case '٫':
          buffer.write('.');
        case '٬':
          buffer.write(',');
        default:
          buffer.write(character);
      }
    }
    return buffer.toString();
  }

  /// استخراج كل المبالغ من [text] مرتّبة تنازلياً وبلا تكرار.
  static List<double> extractAmounts(String text) {
    final String normalized = normalizeDigits(text);
    final Set<double> found = <double>{};
    for (final RegExpMatch match in _numberPattern.allMatches(normalized)) {
      final double? value = parseNumberToken(match.group(0)!);
      if (value != null) {
        found.add(value);
      }
    }
    final List<double> amounts = found.toList()
      ..sort((double a, double b) => b.compareTo(a));
    return amounts;
  }

  /// استخراج أرقام الطلبات من [text] بترتيب الظهور وبلا تكرار.
  ///
  /// يعتمد على كلمات دالة (مثل «رقم الطلب» أو «order») أو علامة `#` قبل
  /// الرقم، ويقبل الأرقام العربية الهندية/الفارسية، ويتجاهل أي رقم يزيد
  /// عن [maxOrderNumberDigits] خانة لتفادي اقتطاع أرقام طويلة خطأً.
  static List<String> extractOrderNumbers(String text) {
    final List<String> found = <String>[];
    _collectOrderNumbers(text, found);
    return found;
  }

  /// إضافة أرقام الطلبات المكتشفة في [text] إلى القائمة [into] (بلا تكرار).
  static void _collectOrderNumbers(String text, List<String> into) {
    if (text.trim().isEmpty) {
      return;
    }
    final String normalized = normalizeDigits(text);
    final Iterable<RegExpMatch> matches = <RegExpMatch>[
      ..._orderNumberLabelPattern.allMatches(normalized),
      ..._orderNumberHashSuffixPattern.allMatches(normalized),
    ];
    for (final RegExpMatch match in matches) {
      final String? number = _cleanOrderNumber(match.group(1));
      if (number != null && !into.contains(number)) {
        into.add(number);
      }
    }
  }

  /// تنظيف رقم الطلب: إزالة كل ما ليس رقماً والأصفار البادئة.
  ///
  /// تُرجع `null` إذا لم يتبقَّ رقم صالح أو تجاوز الحد المسموح.
  static String? _cleanOrderNumber(String? raw) {
    if (raw == null) {
      return null;
    }
    String value = raw.replaceAll(RegExp('[^0-9]'), '');
    if (value.isEmpty || value.length > maxOrderNumberDigits) {
      return null;
    }
    while (value.length > 1 && value.startsWith('0')) {
      value = value.substring(1);
    }
    return value;
  }

  /// تحليل رقم واحد من نص مثل `12,500` أو `12.500` أو `1500` أو `12.5`.
  ///
  /// تُرجع `null` إذا كان النص غير صالح أو قيمته صفر أو أقل.
  static double? parseNumberToken(String token) {
    final String cleaned = token.replaceAll(' ', '').trim();
    if (cleaned.isEmpty) {
      return null;
    }

    String value = cleaned;
    if (value.contains(',')) {
      value = value.replaceAll(',', '');
    } else if (_thousandGroupsPattern.hasMatch(value)) {
      value = value.replaceAll('.', '');
    }

    final double? parsed = double.tryParse(value);
    if (parsed == null || parsed <= 0) {
      return null;
    }
    return parsed;
  }

  /// أرقام عربية هندية (المستخدَمة في العراق ومصر والخليج).
  static const String _arabicIndicDigits = '٠١٢٣٤٥٦٧٨٩';

  /// أرقام فارسية/أوردو تُشبه العربية الهندية.
  static const String _persianDigits = '۰۱۲۳۴۵۶۷۸۹';
}
