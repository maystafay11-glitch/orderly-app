import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:orderly_app/models/delivery_order.dart';
import 'package:orderly_app/models/driver.dart';
import 'package:orderly_app/models/order_status.dart';
import 'package:orderly_app/screens/driver_dashboard_screen.dart';
import 'package:orderly_app/screens/driver_login_screen.dart';
import 'package:orderly_app/screens/live_tracking_screen.dart';
import 'package:orderly_app/services/driver_session_service.dart';
import 'package:orderly_app/services/driver_storage.dart';
import 'package:orderly_app/theme/app_theme.dart';

Widget _buildTestWidget(Widget child) {
  return MaterialApp(
    theme: AppTheme.light(),
    builder: (BuildContext context, Widget? c) => Directionality(
      textDirection: TextDirection.rtl,
      child: c ?? const SizedBox.shrink(),
    ),
    home: child,
  );
}

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    await DriverSessionService.logout();
  });

  group('شاشات تطبيق السائق ولوحة التتبع الحية', () {
    testWidgets('شاشة تسجيل دخول السائق: النقر على بطاقة السائق السريعة والدخول',
        (WidgetTester tester) async {
      tester.view.physicalSize = const Size(800, 1200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await DriverStorage.saveDriver(const Driver(name: 'كرار', pin: '1002'));

      await tester.pumpWidget(_buildTestWidget(const DriverLoginScreen()));
      await tester.pumpAndSettle();

      // التحقق من ظهور شاشة الدخول
      expect(find.text('تسجيل دخول السائق'), findsOneWidget);
      expect(find.text('بوابة السائق السريعة'), findsOneWidget);

      // النقر على رقاقة السائق السريعة المتاحة للتجربة
      final Finder quickChip = find.widgetWithText(ActionChip, 'كرار (1002)');
      expect(quickChip, findsOneWidget);
      await tester.ensureVisible(quickChip);
      await tester.pumpAndSettle();
      await tester.tap(quickChip);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pumpAndSettle();

      // الانتقال بنجاح إلى شاشة السائق
      expect(find.byType(DriverDashboardScreen), findsOneWidget);
      expect(find.text('كرار'), findsOneWidget);
      expect(find.text('PIN: 1002'), findsOneWidget);
    });

    testWidgets('تطبيق السائق: حصر الواجهة على زري الاستلام والتسليم لمتابعة الحالة فوراً',
        (WidgetTester tester) async {
      final DeliveryOrder readyOrder = DeliveryOrder(
        id: 'ord_active_1',
        orderNumber: '55',
        amount: 14000,
        status: OrderStatus.preparing,
      );
      final Driver driver = Driver(
        name: 'سامر',
        pin: '1004',
        orders: <DeliveryOrder>[readyOrder],
      );
      await DriverStorage.saveDriver(driver);

      await tester.pumpWidget(_buildTestWidget(DriverDashboardScreen(driver: driver)));
      await tester.pumpAndSettle();

      // التحقق من ظهور إرشادات المتابعة اللحظية وحصر الواجهة على زري المتابعة
      expect(find.textContaining('واجهة السائق مقتصرة على زري متابعة الحالة فقط'), findsOneWidget);
      expect(find.text('طلب #55'), findsOneWidget);

      // ظهور الزرين التفاعليين معاً:
      // الزر 1: تم الاستلام من المطعم
      // الزر 2: تم التسليم للزبون
      expect(find.text('تم الاستلام من المطعم'), findsOneWidget);
      expect(find.text('تم التسليم للزبون (يتطلب الاستلام أولاً)'), findsOneWidget);

      // تجربة النقر على التسليم قبل الاستلام تظهر تنبيهاً إرشادياً
      await tester.tap(find.text('تم التسليم للزبون (يتطلب الاستلام أولاً)'));
      await tester.pumpAndSettle();
      expect(find.textContaining('يرجى الضغط على زر (تم الاستلام من المطعم) أولاً'), findsOneWidget);

      // الضغط على زر (تم الاستلام من المطعم)
      await tester.tap(find.text('تم الاستلام من المطعم'));
      await tester.pumpAndSettle();

      // تفعيل زر (تم التسليم للزبون) وبدء مؤقت الرحلة
      expect(find.text('تم التسليم للزبون'), findsOneWidget);
      expect(find.textContaining('وقت الرحلة على الطريق'), findsOneWidget);
      expect(find.textContaining('تم الاستلام من المطعم'), findsWidgets);
    });

    testWidgets('لوحة تحكم المطعم: عرض الحالات والمؤشرات والعدادات',
        (WidgetTester tester) async {
      final DeliveryOrder order = DeliveryOrder(
        id: 'ord_track_1',
        orderNumber: '77',
        amount: 25000,
        status: OrderStatus.pickedUp,
        driverName: 'علي',
        driverPin: '1001',
        pickedUpAt: DateTime.now().subtract(const Duration(minutes: 30)),
        expectedDurationMinutes: 25,
      );
      final Driver driver = Driver(
        name: 'علي',
        pin: '1001',
        orders: <DeliveryOrder>[order],
      );
      await DriverStorage.saveDriver(driver);

      await tester.pumpWidget(_buildTestWidget(const LiveTrackingScreen()));
      await tester.pumpAndSettle();

      // التحقق من ظهور مؤشرات الحالة
      expect(find.text(LiveTrackingScreen.title), findsOneWidget);
      expect(find.text('طلب #77'), findsOneWidget);
      expect(find.text('علي (1001)'), findsOneWidget);
      expect(find.text('مع السائق'), findsWidgets);
      // كشف التحذير الأحمر للتأخير
      expect(find.textContaining('تحذير تأخير'), findsOneWidget);
      expect(find.textContaining('تجاوز الوقت'), findsOneWidget);
    });
  });
}
