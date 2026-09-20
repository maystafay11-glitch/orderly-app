// تحليل حمولة الباركود/QR أثناء المسح التلقائي المباشر.
//
// هذه الطبقة تفصل «منطق التحليل» عن «واجهة الكاميرا»، فتصبح قابلة للاختبار
// بدون كاميرا أو متصفح، وتبقى خفيفة جداً على متصفحات الهواتف لأنها تعمل على
// نص الباركود فقط (بدون صور أو إطارات).
//
// الهدف: تحويل نص الباركود المقروء فوراً إلى سعر مقترح و/أو رقم طلب، مع رفض
// القيم غير المعقولة حتى لا تُملأ الحقول بأرقام خاطئة.
import 'package:orderly_app/services/ocr_service.dart';

/// الحقل المطلوب تعبئته من الباركود المقروء.
enum LiveScanTarget {
  /// اختيار تلقائي: رقم الطلب أولاً إن وُجد تصنيف صريح، وإلا المبلغ.
  auto,

  /// خطوة سعر الطلب: يُقبل المبلغ فقط (ورقم الطلب إن كان مكتوباً بتصنيف صريح).
  price,

  /// خطوة رقم الطلب: يُقبل الرقم فقط، ويكون أي تسلسل أرقام مقبولاً.
  orderNumber,
}

/// نتيجة تحليل حمولة باركود واحد.
class LiveScanPayload {
  /// إنشاء نتيجة تحليل.
  const LiveScanPayload({this.raw, this.amount, this.orderNumber});

  /// النص الخام للباركود بعد توحيد الأرقام العربية.
  final String? raw;

  /// المبلغ المقترح (إن كان الباركود يحمل مبلغاً معقولاً).
  final double? amount;

  /// رقم الطلب المقترح (إن وُجد).
  final String? orderNumber;

  /// هل لم يُستخرج أي قيمة صالحة من هذه الحمولة؟
  bool get isEmpty =>
      amount == null && (orderNumber == null || orderNumber!.isEmpty);

  /// أقل قيمة تُقبل كمبلغ من باركود (لتفادي الخلط بين السعر ورقم طلب صغير).
  static const double minAmount = 250;

  /// أعلى قيمة تُقبل كمبلغ (نفس حد OCR العام).
  static const double maxAmount = maxReasonableAmount;

  /// أطول رقم طلب مقبول (نفس حد OCR العام).
  static const int maxOrderDigits = maxOrderNumberDigits;

  /// رقم صريح فقط: `1500` أو `1,500` أو `12.5`.
  static final RegExp _plainNumber = RegExp(r'^\d+(?:[.,]\d+)*$');

  /// تحليل حمولة الباركود [rawValue] بحسب [target].
  static LiveScanPayload parse(
    String? rawValue, {
    LiveScanTarget target = LiveScanTarget.auto,
  }) {
    final String raw = OcrService.normalizeDigits((rawValue ?? '').trim());
    if (raw.isEmpty) {
      return const LiveScanPayload();
    }

    // 1) رقم طلب مكتوب بتصنيف صريح («رقم الطلب 12» أو «order:12» أو «#12»).
    final List<String> labeledNumbers = OcrService.extractOrderNumbers(raw);
    final String? labeled = labeledNumbers.isEmpty ? null : labeledNumbers.first;

    // 2) استبعاد الرقم المُصنَّف من حساب المبلغ، حتى لا يُقرأ رقم الطلب سعراً.
    final String withoutLabeled = labeled == null
        ? raw
        : raw.replaceFirst(labeled, ' ');

    final double? amount = _extractAmount(
      withoutLabeled,
      allowAmount: target != LiveScanTarget.orderNumber,
    );

    String? orderNumber;
    switch (target) {
      case LiveScanTarget.price:
        // في خطوة السعر: رقم الطلب يُقبل فقط إن كان مُصنَّفاً صراحةً.
        orderNumber = labeled;
      case LiveScanTarget.orderNumber:
        orderNumber = labeled ?? _digitsOnly(raw);
      case LiveScanTarget.auto:
        // الوضع التلقائي: يُبلّغ عن الرقم كرقم طلب أيضاً (تفويض القرار للمستدعي).
        orderNumber = labeled ?? _digitsOnly(raw);
    }

    return LiveScanPayload(
      raw: raw,
      amount: amount,
      orderNumber: orderNumber,
    );
  }

  /// استخراج مبلغ معقول من النص [text].
  static double? _extractAmount(String text, {required bool allowAmount}) {
    if (!allowAmount) {
      return null;
    }

    final String trimmed = text.trim();
    if (trimmed.isEmpty) {
      return null;
    }

    // رقم صريح بلا حروف: نقبله إن كان داخل المجال المعقول.
    if (_plainNumber.hasMatch(trimmed)) {
      final double? value = OcrService.parseNumberToken(trimmed);
      return _inAmountRange(value) ? value : null;
    }

    // نص يحتوي أرقاماً: نأخذ أكبر رقم داخل المجال المعقول.
    for (final double candidate in OcrService.extractAmounts(trimmed)) {
      if (_inAmountRange(candidate)) {
        return candidate;
      }
    }
    return null;
  }

  /// تسلسل الأرقام في [text] بشرط أن يكون بطول رقم طلب مقبول.
  static String? _digitsOnly(String text) {
    final String digits = text.replaceAll(RegExp('[^0-9]'), '');
    if (digits.isEmpty || digits.length > maxOrderDigits) {
      return null;
    }
    String value = digits;
    while (value.length > 1 && value.startsWith('0')) {
      value = value.substring(1);
    }
    return value;
  }

  /// هل القيمة [value] داخل مجال مبلغ معقول؟
  static bool _inAmountRange(double? value) =>
      value != null && value >= minAmount && value <= maxAmount;
}
