// اختبارات تحليل حمولة الباركود للمسح التلقائي المباشر.
//
// هذه الطبقة تعمل بلا كاميرا ولا متصفح، واختبارها يضمن أن المسح المباشر
// يملأ الحقول الصحيحة (سعر/رقم طلب) ولا يقبل قيماً خاطئة.
import 'package:flutter_test/flutter_test.dart';

import 'package:orderly_app/utils/live_scan_payload.dart';

void main() {
  group('LiveScanPayload — خطوة سعر الطلب', () {
    test('باركود يحمل مبلغاً صريحاً يُقرأ سعراً', () {
      final LiveScanPayload payload = LiveScanPayload.parse(
        '15000',
        target: LiveScanTarget.price,
      );

      expect(payload.amount, 15000);
      expect(payload.orderNumber, isNull);
      expect(payload.isEmpty, isFalse);
    });

    test('يقبل الأرقام العربية والفواصل ويوحّدها', () {
      expect(
        LiveScanPayload.parse(
          '١٥٬٠٠٠',
          target: LiveScanTarget.price,
        ).amount,
        15000,
      );
      expect(
        LiveScanPayload.parse(
          '15,000',
          target: LiveScanTarget.price,
        ).amount,
        15000,
      );
    });

    test('يرفض المبالغ الصغيرة جداً لتفادي الخلط برقم طلب', () {
      final LiveScanPayload payload = LiveScanPayload.parse(
        '42',
        target: LiveScanTarget.price,
      );

      expect(payload.amount, isNull);
      expect(payload.orderNumber, isNull);
      expect(payload.isEmpty, isTrue);
    });

    test('يرفض المبالغ الضخمة غير المعقولة', () {
      expect(
        LiveScanPayload.parse(
          '9999999',
          target: LiveScanTarget.price,
        ).amount,
        isNull,
      );
    });

    test('يستخرج المبلغ من نص يحتوي كلمات', () {
      expect(
        LiveScanPayload.parse(
          'TOTAL 25000 IQD',
          target: LiveScanTarget.price,
        ).amount,
        25000,
      );
    });

    test('رقم الطلب المُصنَّف صراحةً لا يُقرأ سعراً', () {
      final LiveScanPayload payload = LiveScanPayload.parse(
        'ORDER 5500',
        target: LiveScanTarget.price,
      );

      expect(payload.amount, isNull);
      expect(payload.orderNumber, '5500');
    });
  });

  group('LiveScanPayload — خطوة رقم الطلب', () {
    test('باركود رقمي بحت يُقرأ رقم طلب', () {
      final LiveScanPayload payload = LiveScanPayload.parse(
        '123456',
        target: LiveScanTarget.orderNumber,
      );

      expect(payload.orderNumber, '123456');
      expect(payload.amount, isNull);
    });

    test('يقبل الرقم بعد # أو بعد كلمة «رقم الطلب»', () {
      expect(
        LiveScanPayload.parse(
          '#1024',
          target: LiveScanTarget.orderNumber,
        ).orderNumber,
        '1024',
      );
      expect(
        LiveScanPayload.parse(
          'رقم الطلب ٥٥٠٠',
          target: LiveScanTarget.orderNumber,
        ).orderNumber,
        '5500',
      );
    });

    test('يستخرج الأرقام من نص أو رابط', () {
      expect(
        LiveScanPayload.parse(
          'https://orderly.app/o/98765',
          target: LiveScanTarget.orderNumber,
        ).orderNumber,
        '98765',
      );
    });

    test('يرفض الأرقام الأطول من حد رقم الطلب', () {
      expect(
        LiveScanPayload.parse(
          '12345678901234567890',
          target: LiveScanTarget.orderNumber,
        ).orderNumber,
        isNull,
      );
    });

    test('يزيل الأصفار البادئة', () {
      expect(
        LiveScanPayload.parse(
          '000123',
          target: LiveScanTarget.orderNumber,
        ).orderNumber,
        '123',
      );
    });
  });

  group('LiveScanPayload — نصوص مقروءة من صورة (OCR)', () {
    test('يستخرج السعر الأكبر من نص فاتورة', () {
      const String text =
          'فاتورة رقم 7\nالمجموع: 250,000 د.ع\nالتوصيل: 5000';

      final LiveScanPayload payload = LiveScanPayload.parse(
        text,
        target: LiveScanTarget.price,
      );

      expect(payload.amount, 250000);
    });

    test('يستخرج رقم الطلب من نص فيه تصنيف صريح', () {
      const String text = 'رقم الطلب ١٢٣٤٥\nالسعر 15000';

      final LiveScanPayload payload = LiveScanPayload.parse(
        text,
        target: LiveScanTarget.orderNumber,
      );

      expect(payload.orderNumber, '12345');
    });

    test('يرفض النص الذي لا يحتوي أي أرقام', () {
      final LiveScanPayload payload = LiveScanPayload.parse(
        'لا يوجد شيء هنا',
        target: LiveScanTarget.price,
      );

      expect(payload.isEmpty, isTrue);
    });
  });

  group('LiveScanPayload — حالات عامة', () {
    test('الحمولة الفارغة أو بلا أرقام تُرجع نتيجة فارغة', () {
      expect(LiveScanPayload.parse(null).isEmpty, isTrue);
      expect(LiveScanPayload.parse('   ').isEmpty, isTrue);
      expect(LiveScanPayload.parse('BARCODE-ONLY').isEmpty, isTrue);
    });

    test('الوضع التلقائي يُبلّغ عن الرقم كرقم طلب أيضاً', () {
      final LiveScanPayload payload = LiveScanPayload.parse('98765');

      expect(payload.orderNumber, '98765');
      expect(payload.amount, 98765);
    });

    test('يوحّد الأرقام العربية في النص الخام', () {
      expect(LiveScanPayload.parse('١٢٣').raw, '123');
    });
  });
}
