// حالة قراءة النصوص من صورة ثابتة على الويب.
//
// محرّك القراءة (Tesseract.js) يُحمَّل من CDN عند أول استخدام فقط، وكل حالات
// الفشل معالَجة حتى لا يتوقف التطبيق أبداً.
enum WebTextOcrStatus {
  /// المنصة أصلية (Android/iOS) — القراءة هناك عبر ML Kit.
  notApplicable,

  /// تعذّر تحميل محرّك القراءة (لا إنترنت أو الشبكة تحجب الـ CDN).
  offline,

  /// فشلت القراءة أو لم تُرجِع المكتبة نصاً.
  failed,

  /// تمّت القراءة (النص قد يكون فارغاً إن لم تُوجد كتابة في الصورة).
  ok,
}

/// نتيجة قراءة النصوص من صورة.
class WebTextOcrResult {
  /// إنشاء النتيجة.
  const WebTextOcrResult({required this.status, this.text});

  /// حالة القراءة.
  final WebTextOcrStatus status;

  /// النص المقروء من الصورة (قد يكون فارغاً).
  final String? text;

  /// هل يوجد نص غير فارغ؟
  bool get hasText => (text ?? '').trim().isNotEmpty;
}
