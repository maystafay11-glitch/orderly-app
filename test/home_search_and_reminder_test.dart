import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:orderly_app/models/delivery_order.dart';
import 'package:orderly_app/models/driver.dart';
import 'package:orderly_app/screens/home_screen.dart';
import 'package:orderly_app/services/app_settings.dart';
import 'package:orderly_app/services/driver_storage.dart';

Widget wrapHomeScreen() => MaterialApp(
  theme: ThemeData(useMaterial3: true),
  builder: (BuildContext context, Widget? child) => Directionality(
    textDirection: TextDirection.rtl,
    child: child ?? const SizedBox.shrink(),
  ),
  home: const HomeScreen(),
);

void useTallScreen(WidgetTester tester) {
  tester.view.physicalSize = const Size(1080, 2600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  group('خانة البحث في صفحة أجور العمال', () {
    testWidgets('تصفية قائمة العمال بالاسم في الوقت الفعلي مع تسوية العربية', (
      WidgetTester tester,
    ) async {
      await DriverStorage.saveDrivers(<Driver>[
        const Driver(name: 'أحمد'),
        const Driver(name: 'علي'),
        const Driver(name: 'حيدر'),
      ]);

      useTallScreen(tester);
      await tester.pumpWidget(wrapHomeScreen());
      await tester.pumpAndSettle();

      // التحقق من ظهور جميع العمال وحقل البحث
      expect(find.byKey(const ValueKey<String>('driver-search-field')), findsOneWidget);
      expect(find.text('أحمد'), findsOneWidget);
      expect(find.text('علي'), findsOneWidget);
      expect(find.text('حيدر'), findsOneWidget);

      // البحث بدون همزة 'احمد' يجب أن يطابق 'أحمد'
      await tester.enterText(
        find.byKey(const ValueKey<String>('driver-search-field')),
        'احمد',
      );
      await tester.pump();

      expect(find.text('أحمد'), findsOneWidget);
      expect(find.text('علي'), findsNothing);
      expect(find.text('حيدر'), findsNothing);

      // مسح البحث عبر زر المسح
      expect(find.byKey(const ValueKey<String>('clear-driver-search-button')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey<String>('clear-driver-search-button')));
      await tester.pump();

      expect(find.text('أحمد'), findsOneWidget);
      expect(find.text('علي'), findsOneWidget);
      expect(find.text('حيدر'), findsOneWidget);

      // البحث عن اسم غير موجود يظهر رسالة فارغة
      await tester.enterText(
        find.byKey(const ValueKey<String>('driver-search-field')),
        'عمر',
      );
      await tester.pump();

      expect(find.byKey(const ValueKey<String>('empty-search-results')), findsOneWidget);
      expect(find.text('أحمد'), findsNothing);
    });
  });

  group('إشعار التذكير الأسبوعي وزر الواتساب في الشاشة الرئيسية', () {
    testWidgets('يظهر إشعار التذكير الأسبوعي وزر الواتساب عند مرور 7 أيام مع وجود عمال', (
      WidgetTester tester,
    ) async {
      await DriverStorage.saveDrivers(<Driver>[
        Driver(name: 'أحمد', orders: <DeliveryOrder>[
          DeliveryOrder(orderNumber: '1', amount: 15000),
        ]),
      ]);
      await AppSettings.setWhatsAppPhone('9647701234567');
      await AppSettings.setLastWeeklyNotice(
        DateTime.now().subtract(const Duration(days: 8)),
      );

      useTallScreen(tester);
      await tester.pumpWidget(wrapHomeScreen());
      await tester.pumpAndSettle();

      // ظهور شريط التذكير
      expect(find.byKey(const ValueKey<String>('weekly-reminder-banner')), findsOneWidget);
      expect(find.text('تذكير أسبوعي: إرسال ملخص الأسبوع'), findsOneWidget);
      expect(
        find.byKey(const ValueKey<String>('send-weekly-summary-whatsapp-home')),
        findsOneWidget,
      );

      // الضغط على زر إرسال الملخص الأسبوعي
      await tester.tap(find.byKey(const ValueKey<String>('send-weekly-summary-whatsapp-home')));
      await tester.pump();

      expect(find.textContaining('تم تحضير رسالة الواتساب'), findsOneWidget);

      // إغلاق التذكير بعد الإرسال
      expect(find.byKey(const ValueKey<String>('weekly-reminder-banner')), findsNothing);
    });
  });
}
