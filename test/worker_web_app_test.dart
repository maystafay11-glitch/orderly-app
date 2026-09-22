import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:orderly_app/models/delivery_order.dart';
import 'package:orderly_app/models/driver.dart';
import 'package:orderly_app/models/staff_member.dart';
import 'package:orderly_app/screens/home_screen.dart';
import 'package:orderly_app/screens/unified_login_screen.dart';
import 'package:orderly_app/services/worker_web_service.dart';
import 'package:orderly_app/worker_web_main.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  test('RestaurantSnapshot reads only the matching restaurant worker orders', () {
    final List<Driver> drivers = RestaurantSnapshot.readDrivers(
      <String, dynamic>{
        'restaurantId': 'RESTONE',
        'drivers': <Map<String, dynamic>>[
          <String, dynamic>{
            'name': 'أحمد',
            'pin': '1001',
            'orders': <Map<String, dynamic>>[
              <String, dynamic>{
                'id': 'ord_a',
                'orderNumber': '12',
                'amount': 5000,
                'status': 'preparing',
              },
            ],
          },
          <String, dynamic>{
            'name': 'علي',
            'pin': '1002',
            'orders': <Map<String, dynamic>>[
              <String, dynamic>{
                'id': 'ord_b',
                'orderNumber': '99',
                'amount': 8000,
                'status': 'pickedUp',
              },
            ],
          },
        ],
      },
    );

    expect(drivers, hasLength(2));
    final List<DeliveryOrder> forAhmed = RestaurantSnapshot.ordersForDriver(
      drivers,
      driverPin: '1001',
      driverName: 'أحمد',
    );
    expect(forAhmed, hasLength(1));
    expect(forAhmed.single.orderNumber, '12');

    final List<DeliveryOrder> byName = RestaurantSnapshot.ordersForDriver(
      drivers,
      driverPin: '',
      driverName: 'علي',
    );
    expect(byName.single.orderNumber, '99');
    expect(
      RestaurantSnapshot.indexOfDriver(
        drivers,
        driverPin: '1002',
        driverName: 'علي',
      ),
      1,
    );
  });

  test('staff restaurant ids stay isolated even with the same username', () {
    final String first = StaffMember.buildStaffId('CAFE1', 'ahmed');
    final String second = StaffMember.buildStaffId('CAFE2', 'ahmed');
    expect(first, isNot(equals(second)));
    expect(StaffMember.normalizeRestaurantId(' cafe1 '), 'CAFE1');
  });

  Future<void> pumpWorkerLogin(WidgetTester tester) async {
    await tester.pumpWidget(const WorkerWebApp());
    await tester.pump();
    await tester.pump(const Duration(seconds: 3));
  }

  testWidgets('worker web app never shows the manager console', (WidgetTester tester) async {
    await pumpWorkerLogin(tester);

    expect(find.byKey(const ValueKey<String>('worker-web-title')), findsOneWidget);
    expect(find.text('Restaurant ID'), findsOneWidget);
    expect(find.text('اسم المستخدم'), findsOneWidget);
    expect(find.text('كلمة المرور أو PIN'), findsOneWidget);
    expect(find.text('دخول العامل'), findsOneWidget);
    expect(find.text('تسجيل دخول المدير'), findsNothing);
    expect(find.byType(HomeScreen), findsNothing);
    expect(find.byType(UnifiedLoginScreen), findsNothing);
  });

  testWidgets('worker login rejects an invalid restaurant id locally',
      (WidgetTester tester) async {
    await pumpWorkerLogin(tester);

    await tester.enterText(
      find.byKey(const ValueKey<String>('worker-restaurant-id-field')),
      'ab',
    );
    await tester.tap(find.byKey(const ValueKey<String>('worker-login-btn')));
    await tester.pump();

    expect(
      find.textContaining('Restaurant ID صحيحاً'),
      findsOneWidget,
    );
  });
}
