// نتيجة قراءة الباركود/QR من **صورة ثابتة** (Snapshot).
//
// على الويب لا نفتح أي بث فيديو مباشر، بل نقرأ الباركود من الصورة الملتقطة
// عبر واجهة المتصفح الأصلية `BarcodeDetector` إن كانت مدعومة.
enum WebImageBarcodeStatus {
  /// المنصة أصلية (Android/iOS) — القراءة تتم عبر ML Kit هناك.
  notApplicable,

  /// المتصفح لا يدعم `BarcodeDetector` (مثل Firefox) → نعتمد على قراءة النص.
  unsupported,

  /// فشلت القراءة (صورة غير صالحة أو خطأ غير متوقع).
  failed,

  /// تمّت القراءة (قد تكون النتيجة بلا باركود، انظر [WebImageBarcodeResult.payloads]).
  ok,
}

/// حمولات الباركود المقروءة من الصورة.
class WebImageBarcodeResult {
  /// إنشاء نتيجة القراءة.
  const WebImageBarcodeResult({
    required this.status,
    this.payloads = const <String>[],
  });

  /// حالة القراءة.
  final WebImageBarcodeStatus status;

  /// نصوص الباركود المكتشفة (بترتيب الظهور، بلا تكرار).
  final List<String> payloads;

  /// هل لم يُعثر على أي باركود في الصورة؟
  bool get isEmpty => payloads.isEmpty;
}
