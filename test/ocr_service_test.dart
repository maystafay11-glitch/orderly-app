// اختبارات منطق التعرف على الأرقام من نصوص الصور (بدون كاميرا أو جهاز).
import 'package:flutter_test/flutter_test.dart';

import 'package:orderly_app/services/ocr_service.dart';

void main() {
  group('normalizeDigits - تحويل الأرقام العربية', () {
    test('يحوّل الأرقام العربية الهندية إلى لاتينية', () {
      expect(OcrService.normalizeDigits('١٥٠٠٠'), '15000');
    });

    test('يحوّل الأرقام الفارسية ويوحّد الفواصل العربية', () {
      expect(OcrService.normalizeDigits('۱۲٬۵۰۰'), '12,500');
      expect(OcrService.normalizeDigits('١٢٫٥'), '12.5');
    });

    test('يترك النصوص اللاتينية كما هي', () {
      expect(
        OcrService.normalizeDigits('Total 250,000 IQD'),
        'Total 250,000 IQD',
      );
    });
  });

  group('parseNumberToken - تحليل الرقم', () {
    test('يتعامل مع فاصلة الآلاف والنقطة العشرية', () {
      expect(OcrService.parseNumberToken('1,500'), 1500);
      expect(OcrService.parseNumberToken('12.500'), 12500);
      expect(OcrService.parseNumberToken('12.5'), 12.5);
      expect(OcrService.parseNumberToken('1500'), 1500);
    });

    test('يُرجع null للقيم غير الصالحة أو غير الموجبة', () {
      expect(OcrService.parseNumberToken(''), isNull);
      expect(OcrService.parseNumberToken('0'), isNull);
      expect(OcrService.parseNumberToken('abc'), isNull);
    });
  });

  group('extractAmounts - استخراج المبالغ', () {
    test('يستخرج الأرقام من فاتورة نصية مرتّبة تنازلياً بلا تكرار', () {
      const String text =
          'فاتورة مطعم رقم 7\nالمجموع: 250,000 د.ع\n'
          'التوصيل: 5000\nضريبة: 5,000';

      expect(OcrService.extractAmounts(text), <double>[250000, 5000, 7]);
    });

    test('يستخرج الأرقام العربية الهندية من صورة عربية', () {
      expect(OcrService.extractAmounts('سعر الطلب ٢٥٠٠٠ دينار'), <double>[
        25000,
      ]);
    });

    test('يُرجع قائمة فارغة عندما لا توجد أرقام', () {
      expect(OcrService.extractAmounts('لا توجد أرقام هنا'), isEmpty);
    });
  });

  group('OcrResult - أفضل رقم مقترح', () {
    test('أفضل رقم هو الأكبر (الإجمالي عادةً)', () {
      const OcrResult result = OcrResult(
        rawText: 'المجموع 250000 و 5000 توصيل',
        amounts: <double>[250000, 5000],
      );

      expect(result.best, 250000);
      expect(result.isEmpty, isFalse);
    });

    test('النتيجة الفارغة لا تحتوي على رقم مقترح', () {
      const OcrResult result = OcrResult.empty();

      expect(result.best, isNull);
      expect(result.isEmpty, isTrue);
    });
  });
}
