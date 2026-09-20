import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:orderly_app/models/delivery_order.dart';
import 'package:orderly_app/models/driver.dart';
import 'package:orderly_app/models/order_payment_type.dart';
import 'package:orderly_app/models/order_status.dart';
import 'package:orderly_app/models/shift_record.dart';
import 'package:orderly_app/services/driver_session_service.dart';
import 'package:orderly_app/services/driver_storage.dart';
import 'package:orderly_app/services/firebase_tracking_service.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  group('Driver PIN Codes (1001 إلى 1030)', () {
    test('توليد الرموز تسلسلياً يبدأ من 1001 ويصل إلى 1030', () {
      final List<Driver> drivers = <Driver>[];

      // أول سائق يأخذ 1001
      final String pin1 = Driver.findNextAvailablePin(drivers);
      expect(pin1, '1001');
      drivers.add(Driver(name: 'سائق 1', pin: pin1));

      // ثاني سائق يأخذ 1002
      final String pin2 = Driver.findNextAvailablePin(drivers);
      expect(pin2, '1002');
      drivers.add(Driver(name: 'سائق 2', pin: pin2));

      // ثالث سائق يأخذ 1003
      final String pin3 = Driver.findNextAvailablePin(drivers);
      expect(pin3, '1003');
    });

    test('إعادة استخدام الرموز الشاغرة عند حذف سائق', () {
      final List<Driver> drivers = <Driver>[
        const Driver(name: 'سائق 1', pin: '1001'),
        const Driver(name: 'سائق 3', pin: '1003'),
      ];

      // السائق التالي يأخذ 1002 لأنها شاغرة
      final String next = Driver.findNextAvailablePin(drivers);
      expect(next, '1002');
    });

    test('تسجيل دخول السائق بالرمز الخاص واسترجاع الجلسة', () async {
      await DriverStorage.saveDriver(const Driver(name: 'أحمد التوصيل', pin: '1005'));

      // تجربة رمز غير مسجل
      final Driver? fail = await DriverSessionService.loginWithPin('9999');
      expect(fail, isNull);
      expect(await DriverSessionService.isLoggedIn(), isFalse);

      // تجربة الرمز المسجل
      final Driver? success = await DriverSessionService.loginWithPin('1005');
      expect(success, isNotNull);
      expect(success!.name, 'أحمد التوصيل');
      expect(await DriverSessionService.isLoggedIn(), isTrue);

      // استرجاع السائق الحالي
      final Driver? active = await DriverSessionService.getLoggedInDriver();
      expect(active?.pin, '1005');

      // تسجيل الخروج
      await DriverSessionService.logout();
      expect(await DriverSessionService.isLoggedIn(), isFalse);
    });
  });

  group('تتبع مسار الطلب ومؤقت الرحلة واكتشاف التأخير (منع التسخيت)', () {
    test('الحالة الافتراضية للطلب الجديد هي قيد الإعداد', () {
      final DeliveryOrder order = DeliveryOrder(
        amount: 15000,
        orderNumber: 'A-101',
      );

      expect(order.status, OrderStatus.preparing);
      expect(order.status.isActive, isTrue);
      expect(order.pickedUpAt, isNull);
      expect(order.deliveredAt, isNull);
      expect(order.isDelayed, isFalse);
    });

    test('حساب مدة الرحلة بعد الاستلام واكتشاف التأخير بدقة', () {
      final DateTime now = DateTime.now();

      // طلب خرج قبل 10 دقائق (أقل من الوقت الطبيعي 25 دقيقة)
      final DeliveryOrder onTime = DeliveryOrder(
        amount: 12000,
        status: OrderStatus.pickedUp,
        pickedUpAt: now.subtract(const Duration(minutes: 10)),
        expectedDurationMinutes: 25,
      );

      expect(onTime.durationMinutes, greaterThanOrEqualTo(10));
      expect(onTime.isDelayed, isFalse);
      expect(onTime.delayMinutes, 0);

      // طلب خرج قبل 35 دقيقة (تجاوز الوقت الطبيعي 25 دقيقة)
      final DeliveryOrder delayed = DeliveryOrder(
        amount: 18000,
        status: OrderStatus.pickedUp,
        pickedUpAt: now.subtract(const Duration(minutes: 35)),
        expectedDurationMinutes: 25,
      );

      expect(delayed.durationMinutes, greaterThanOrEqualTo(35));
      expect(delayed.isDelayed, isTrue);
      expect(delayed.delayMinutes, greaterThanOrEqualTo(10));
    });

    test('تسجيل الخروج ثم التسليم عبر FirebaseTrackingService وتوثيق الوردية', () async {
      final Driver driver = const Driver(name: 'حيدر الكابتن', pin: '1010');
      final DeliveryOrder order = DeliveryOrder(
        id: 'ord_test_1',
        orderNumber: '99',
        amount: 20000,
        paymentType: OrderPaymentType.cash,
      );

      // إضافة الطلب للسائق
      await DriverStorage.saveDriver(driver.addDeliveryOrder(order));

      // 1. استلام الطلب من المطعم (بدء الطريق)
      final bool pickedUpSuccess = await FirebaseTrackingService.instance.markOrderPickedUp(
        orderId: 'ord_test_1',
      );
      expect(pickedUpSuccess, isTrue);

      Driver? refreshed = await DriverStorage.loadDriverByPin('1010');
      DeliveryOrder tracked = refreshed!.orders.firstWhere((DeliveryOrder o) => o.id == 'ord_test_1');
      expect(tracked.status, OrderStatus.pickedUp);
      expect(tracked.pickedUpAt, isNotNull);

      // 2. تسليم الطلب للزبون (اكتمال التوصيل)
      final bool deliveredSuccess = await FirebaseTrackingService.instance.markOrderDelivered(
        orderId: 'ord_test_1',
      );
      expect(deliveredSuccess, isTrue);

      refreshed = await DriverStorage.loadDriverByPin('1010');
      tracked = refreshed!.orders.firstWhere((DeliveryOrder o) => o.id == 'ord_test_1');
      expect(tracked.status, OrderStatus.delivered);
      expect(tracked.deliveredAt, isNotNull);

      // 3. التحقق من توثيق الرحلة في أرشيف الوردية اليومي (Shift History)
      final List<ShiftRecord> records = await DriverStorage.loadShiftRecords();
      expect(records.isNotEmpty, isTrue);
      final ShiftRecord shift = records.first;
      expect(shift.driverPin, '1010');
      expect(shift.completedOrdersCount, 1);
      expect(shift.totalCollectedCash, 20000);
      expect(shift.totalWagesEarned, 1000);
    });
  });
}
