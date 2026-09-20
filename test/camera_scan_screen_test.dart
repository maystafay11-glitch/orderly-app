// اختبارات واجهة شاشة المسح بالكاميرا.
//
// تُشغَّل هذه الاختبارات بدون كاميرا حقيقية (لا توجد إضافات أصلية في بيئة
// الاختبار)، لذلك تتحقق من المسار الاحتياطي: رسالة واضحة + أزرار
// «إعادة المحاولة» و«الإدخال اليدوي»، وسلامة القيم المُمرَّرة للشاشة.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:orderly_app/screens/camera_scan_screen.dart';
import 'package:orderly_app/services/ocr_service.dart';

/// غلاف الشاشة بنفس نمط بقية اختبارات التطبيق (RTL + Material 3).
Widget wrapScanner({double? initialPrice, String? initialOrderNumber}) =>
    MaterialApp(
      theme: ThemeData(useMaterial3: true),
      builder: (BuildContext context, Widget? child) => Directionality(
        textDirection: TextDirection.rtl,
        child: child ?? const SizedBox.shrink(),
      ),
      home: CameraScanScreen(
        initialPrice: initialPrice,
        initialOrderNumber: initialOrderNumber,
      ),
    );

/// يمنح المهام غير المتزامنة (طلب الإذن + البحث عن الكاميرات) فرصة للانتهاء.
///
/// نستخدم [WidgetTester.runAsync] لأن وقت اختبارات الودجت وهمي، ونداءات
/// الإضافات الأصلية (permission_handler / camera) تحتاج وقتاً حقيقياً لتُكمل.
Future<void> settleCameraAttempt(WidgetTester tester) async {
  await tester.runAsync(() async {
    await Future<void>.delayed(const Duration(milliseconds: 250));
  });
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 50));
}

void main() {
  group('شاشة المسح بالكاميرا — المسار الاحتياطي عند تعذّر التشغيل', () {
    testWidgets('تعرض رسالة واضحة مع زر إعادة المحاولة وزر الإدخال اليدوي', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(wrapScanner());
      await settleCameraAttempt(tester);

      // لا تبقى الشاشة على مؤشر التحميل بلا نهاية.
      expect(find.byType(CircularProgressIndicator), findsNothing);

      // أزرار الإصلاح الاحتياطية.
      expect(find.text('إعادة المحاولة'), findsOneWidget);
      expect(
        find.byKey(const ValueKey<String>('camera-manual-entry-button')),
        findsOneWidget,
      );

      // زر إعادة تشغيل الكاميرا داخل الشريط العلوي.
      expect(
        find.byKey(const ValueKey<String>('camera-restart-button')),
        findsOneWidget,
      );
    });

    testWidgets('زر «إعادة المحاولة» لا يُغلق الشاشة ويُعيد المحاولة', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(wrapScanner());
      await settleCameraAttempt(tester);

      await tester.tap(find.text('إعادة المحاولة'));
      await settleCameraAttempt(tester);

      expect(tester.takeException(), isNull);
      expect(find.byType(CameraScanScreen), findsOneWidget);
    });

    testWidgets('زر إعادة تشغيل الكاميرا في الشريط العلوي يعمل دون أخطاء', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(wrapScanner());
      await settleCameraAttempt(tester);

      await tester.tap(
        find.byKey(const ValueKey<String>('camera-restart-button')),
      );
      await settleCameraAttempt(tester);

      expect(tester.takeException(), isNull);
      expect(find.byType(CameraScanScreen), findsOneWidget);
    });
  });

  group('شاشة المسح بالكاميرا — الخروج للإدخال اليدوي', () {
    testWidgets('الإدخال اليدوي يُرجع النتيجة مع الحفاظ على السعر المُمرَّر', (
      WidgetTester tester,
    ) async {
      OcrResult? captured;
      bool returned = false;

      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(useMaterial3: true),
          home: Builder(
            builder: (BuildContext context) => Scaffold(
              body: Center(
                child: ElevatedButton(
                  onPressed: () async {
                    captured = await Navigator.of(context).push<OcrResult>(
                      MaterialPageRoute<OcrResult>(
                        builder: (BuildContext _) =>
                            const CameraScanScreen(initialPrice: 12000),
                      ),
                    );
                    returned = true;
                  },
                  child: const Text('فتح الماسح'),
                ),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('فتح الماسح'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      await settleCameraAttempt(tester);

      await tester.tap(
        find.byKey(const ValueKey<String>('camera-manual-entry-button')),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pumpAndSettle();

      expect(returned, isTrue);
      expect(captured, isNotNull);
      // السعر المُمرَّر للشاشة يبقى محفوظاً عند الخروج للإدخال اليدوي.
      expect(captured!.amounts, contains(12000));
      expect(find.byType(CameraScanScreen), findsNothing);
    });
  });

  group('OcrService — توافق المنصة', () {
    test('قراءة النصوص مدعومة على المنصات الأصلية وغير مدعومة على الويب', () {
      // في بيئة الاختبار (VM) نتحقق أن العلم يعكس دعم google_mlkit.
      expect(OcrService.isSupported, isTrue);
    });
  });
}
