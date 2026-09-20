/// دوال تنسيق الأرقام والمبالغ بالعربية، مكتوبة يدوياً بدون حزم إضافية.
library;

/// العملة المستخدمة في الواجهة.
const String kCurrency = 'د.ع';

/// تنسيق رقم بفواصل الآلاف: 250000 ⇒ `250,000`.
///
/// تُقرَّب الكسور إلى أقرب دينار، وتُدعم الأرقام السالبة (تُعرض بإشارة سالب).
String formatNumber(num value) {
  final bool isNegative = value < 0;
  final String digits = value.abs().round().toString();
  final StringBuffer buffer = StringBuffer();
  for (int i = 0; i < digits.length; i++) {
    if (i > 0 && (digits.length - i) % 3 == 0) {
      buffer.write(',');
    }
    buffer.write(digits[i]);
  }
  return isNegative ? '-$buffer' : buffer.toString();
}

/// تنسيق مبلغ بالدينار: `250000` ⇒ `250,000 د.ع`.
String formatAmount(num value) => '${formatNumber(value)} $kCurrency';

/// رقم من خانتين: `7` ⇒ `07`.
String _twoDigits(int value) => value.toString().padLeft(2, '0');

/// تنسيق الوقت بنظام 12 ساعة: `15:45` ⇒ `3:45 م`.
String formatTime(DateTime value) {
  final int hour = value.hour % 12 == 0 ? 12 : value.hour % 12;
  final String period = value.hour < 12 ? 'ص' : 'م';
  return '$hour:${_twoDigits(value.minute)} $period';
}

/// تنسيق التاريخ: `18/09/2026`.
String formatDate(DateTime value) =>
    '${_twoDigits(value.day)}/${_twoDigits(value.month)}/${value.year}';

/// تنسيق التاريخ والوقت معاً: `18/09/2026 — 3:45 م`.
String formatDateTime(DateTime value) =>
    '${formatDate(value)} — ${formatTime(value)}';

/// قراءة مبلغ من نص أدخله المستخدم (يتجاهل الفواصل والمسافات).
///
/// تُرجع `null` إذا كان النص غير صالح أو أقل من أو يساوي صفراً.
double? parseAmount(String? raw) {
  if (raw == null) {
    return null;
  }
  final String cleaned = raw.replaceAll(',', '').replaceAll(' ', '').trim();
  if (cleaned.isEmpty) {
    return null;
  }
  final double? value = double.tryParse(cleaned);
  if (value == null || value <= 0) {
    return null;
  }
  return value;
}
