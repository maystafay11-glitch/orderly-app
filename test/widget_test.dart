// اختبارات واجهة الشاشة الرعدية: بطاقات العمال، حوار تسجيل الطلب برقم الطلب + السعر،
// سجل الطلبات وحذف طلب محدد، والحفظ التلقائي في التخزين المحلي.
//
// تُستخدم حزمة Material الافتراضية (بدون GoogleFonts) لتفادي جلب الخطوط أثناء
// الاختبار، مع فرض اتجاه RTL كما في التطبيق.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:orderly_app/models/delivery_order.dart';
import 'package:orderly_app/models/driver.dart';
import 'package:orderly_app/screens/home_screen.dart';
import 'package:orderly_app/screens/manage_drivers_screen.dart';
import 'package:orderly_app/services/driver_storage.dart';

/// وقت ثابت لكل الطلبات في الاختبارات (لاختبار عرض وقت الإضافة).
final DateTime testTime = DateTime(2026, 9, 18, 15, 45);

/// طلب بوقت ثابت: الرقم + السعر + الوقت نفسه لكل مرة.
DeliveryOrder order(String number, double amount) =>
    DeliveryOrder(orderNumber: number, amount: amount, addedAt: testTime);

/// عامل لديه سجل طلبات محدد.
Driver driverWith(String name, List<DeliveryOrder> orders) =>
    Driver(name: name, orders: orders);

Widget wrapHomeScreen() => MaterialApp(
  theme: ThemeData(useMaterial3: true),
  builder: (BuildContext context, Widget? child) => Directionality(
    textDirection: TextDirection.rtl,
    child: child ?? const SizedBox.shrink(),
  ),
  home: const HomeScreen(),
);

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  testWidgets('تعرض حالة عدم وجود عمال عند عدم وجود بيانات محفوظة', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(wrapHomeScreen());
    await tester.pump();

    expect(find.text(HomeScreen.title), findsOneWidget);
    expect(find.text('لا يوجد عمال بعد'), findsOneWidget);
    expect(
      find.byKey(const ValueKey<String>('empty-add-driver-button')),
      findsOneWidget,
    );
  });

  testWidgets('تعرض بطاقة العامل بالأرقام المحسوبة من سجل طلباته', (
    WidgetTester tester,
  ) async {
    await DriverStorage.saveDrivers(<Driver>[
      driverWith('أحمد', <DeliveryOrder>[
        order('1001', 150000),
        order('1002', 100000),
      ]),
    ]);

    useTallScreen(tester);
    await tester.pumpWidget(wrapHomeScreen());
    await tester.pump();

    expect(find.text('أحمد'), findsOneWidget);
    expect(_valueOf(tester, 'card-orders-أحمد'), '2');
    expect(_valueOf(tester, 'card-total-أحمد'), '250,000 د.ع');
    // أجرة العامل = 2 × 1000
    expect(_valueOf(tester, 'card-wage-أحمد'), '2,000 د.ع');
    // صافي المطعم = 250,000 دون خصم الأجور
    expect(_valueOf(tester, 'card-net-أحمد'), '250,000 د.ع');

    // بطاقة الملخص أسفل الشاشة تعرض الإجماليات الكلية.
    expect(_valueOf(tester, 'summary-orders'), '2');
    expect(_valueOf(tester, 'summary-total'), '250,000 د.ع');
    expect(_valueOf(tester, 'summary-wage'), '2,000 د.ع');
    expect(_valueOf(tester, 'summary-net'), '250,000 د.ع');
  });

  testWidgets('زر «تسجيل طلب» يفتح الحوار بحقل رقم الطلب ويحفظ الطلب محلياً', (
    WidgetTester tester,
  ) async {
    await DriverStorage.saveDrivers(<Driver>[
      driverWith('أحمد', <DeliveryOrder>[
        order('1001', 150000),
        order('1002', 100000),
      ]),
    ]);

    useTallScreen(tester);
    await tester.pumpWidget(wrapHomeScreen());
    await tester.pump();

    // زر «تسجيل طلب» داخل البطاقة يفتح حوار الإدخال.
    await tester.tap(find.byKey(const ValueKey<String>('register-order-أحمد')));
    await tester.pumpAndSettle();

    expect(find.text('تسجيل طلب جديد'), findsOneWidget);
    expect(find.text('رقم الطلب'), findsOneWidget);
    expect(find.text('سعر الطلب'), findsOneWidget);
    expect(_valueOf(tester, 'dialog-orders'), '2');
    expect(_valueOf(tester, 'dialog-total'), '250,000 د.ع');
    expect(_valueOf(tester, 'dialog-wage'), '2,000 د.ع');
    expect(_valueOf(tester, 'dialog-net'), '250,000 د.ع');

    // رقم الطلب مقترح تلقائياً (أكبر رقم مسجّل + 1) ويمكن تعديله.
    expect(_fieldText(tester, 'order-number-field'), '1003');

    await tester.enterText(
      find.byKey(const ValueKey<String>('order-number-field')),
      '1003',
    );
    await tester.enterText(
      find.byKey(const ValueKey<String>('order-price-field')),
      '5000',
    );
    await tester.pump();

    // معاينة فورية للطلب الجديد والأرقام بعده.
    expect(_valueOf(tester, 'dialog-preview-new-order'), '1003 • 5,000 د.ع');
    expect(_valueOf(tester, 'dialog-preview-orders'), '3');
    expect(_valueOf(tester, 'dialog-preview-total'), '255,000 د.ع');
    expect(_valueOf(tester, 'dialog-preview-wage'), '3,000 د.ع');
    expect(_valueOf(tester, 'dialog-preview-net'), '255,000 د.ع');

    await tester.tap(find.byKey(const ValueKey<String>('order-submit-button')));
    await tester.pumpAndSettle();

    expect(find.text('تسجيل طلب جديد'), findsNothing);
    expect(_valueOf(tester, 'card-orders-أحمد'), '3');
    expect(_valueOf(tester, 'card-total-أحمد'), '255,000 د.ع');
    expect(_valueOf(tester, 'card-net-أحمد'), '255,000 د.ع');
    expect(_valueOf(tester, 'summary-orders'), '3');

    // التحقق من الحفظ التلقائي: رقم الطلب وسعره ووقت إضافته.
    final Driver? saved = await DriverStorage.loadDriver('أحمد');
    expect(saved, isNotNull);
    expect(saved!.orders.length, 3);
    expect(saved.orders.last.orderNumber, '1003');
    expect(saved.orders.last.amount, 5000);
    expect(saved.totalOrdersAmount, 255000);
    expect(saved.wage, 3000);
    expect(saved.netAmountToRestaurant, 255000);
    expect(
      saved.orders.last.addedAt.difference(DateTime.now()).abs(),
      lessThan(const Duration(minutes: 1)),
    );

    // ترك مهلة شريط التنبيه (SnackBar) لينتهي قبل إغلاق الاختبار.
    await tester.pump(const Duration(seconds: 5));
  });

  testWidgets('النقر على البطاقة يفتح سجل الطلبات، وحذف طلب يخصم قيمته فوراً', (
    WidgetTester tester,
  ) async {
    await DriverStorage.saveDrivers(<Driver>[
      driverWith('أحمد', <DeliveryOrder>[
        order('1001', 150000),
        order('1002', 100000),
      ]),
    ]);

    useTallScreen(tester);
    await tester.pumpWidget(wrapHomeScreen());
    await tester.pump();

    // النقر على البطاقة يفتح قائمة الطلبات بأرقامها وأسعارها وأوقاتها.
    await tester.tap(find.text('أحمد'));
    await tester.pumpAndSettle();

            expect(find.text('سجل الطلبات'), findsOneWidget);
    expect(find.byKey(const ValueKey<String>('order-row-0')), findsOneWidget);
    expect(find.byKey(const ValueKey<String>('order-row-1')), findsOneWidget);
    // رقم الطلب + السعر مدمجان في الصف (وقت إضافة الطلب).
        expect(find.text('1001'), findsOneWidget);
    expect(find.text('1002'), findsOneWidget);
    // السعر + وقت الإضافة مدمجان في الصف (ونتحقّق من كل منهما منفرداً).
    expect(
      find.textContaining('150,000 د.ع'),
      findsWidgets,
    );
    expect(
      find.textContaining('100,000 د.ع'),
      findsWidgets,
    );
    expect(find.textContaining('3:45 م'), findsWidgets);
    expect(_valueOf(tester, 'history-orders'), '2');
    expect(_valueOf(tester, 'history-total'), '250,000 د.ع');
    expect(_valueOf(tester, 'history-wage'), '2,000 د.ع');
    expect(_valueOf(tester, 'history-net'), '250,000 د.ع');

    // حذف الطلب رقم 1001 (150,000 د.ع) بزر الحذف الخاص به فقط.
    await tester.tap(find.byKey(const ValueKey<String>('delete-order-0')));
    await tester.pumpAndSettle();

    expect(find.text('حذف الطلب'), findsOneWidget);
    expect(find.textContaining('مع رقم الطلب: 1001'), findsOneWidget);

    // الإلغاء أولاً ⇒ لا يُحذف شيء.
    await tester.tap(find.text('إلغاء'));
    await tester.pumpAndSettle();
    expect(_valueOf(tester, 'history-orders'), '2');
    expect((await DriverStorage.loadDriver('أحمد'))!.ordersCount, 2);

    // التأكيد ⇒ يُحذف الطلب المحدد ويُحدَّث السجل والأرقام فوراً.
    await tester.tap(find.byKey(const ValueKey<String>('delete-order-0')));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey<String>('confirm-delete-order-button')),
    );
    await tester.pumpAndSettle();

    expect(find.text('1001'), findsNothing);
    expect(find.text('1002'), findsOneWidget);
    expect(_valueOf(tester, 'history-orders'), '1');
    expect(_valueOf(tester, 'history-total'), '100,000 د.ع');
    expect(_valueOf(tester, 'history-wage'), '1,000 د.ع');
    expect(_valueOf(tester, 'history-net'), '100,000 د.ع');

    // الحفظ المحلي: القيمة خُصمت والعدد نقص واحداً.
    final Driver? saved = await DriverStorage.loadDriver('أحمد');
    expect(saved, isNotNull);
    expect(saved!.ordersCount, 1);
    expect(saved.totalOrdersAmount, 100000);
    expect(saved.wage, 1000);
    expect(saved.netAmountToRestaurant, 100000);
    expect(saved.orders.single.orderNumber, '1002');

        // الرجوع للشاشة الرئيسية ⇒ بطاقة العامل والإجماليات محدَّثة تلقائياً.
    await tester.tap(find.byKey(const ValueKey<String>('order-history-close')));
    await tester.pumpAndSettle();

    expect(_valueOf(tester, 'card-orders-أحمد'), '1');
    expect(_valueOf(tester, 'card-total-أحمد'), '100,000 د.ع');
    expect(_valueOf(tester, 'card-net-أحمد'), '100,000 د.ع');
    expect(_valueOf(tester, 'summary-orders'), '1');

    await tester.pump(const Duration(seconds: 5));
  });

  testWidgets('حذف الطلب الأخير يجعل السجل فارغاً مع بقاء العامل', (
    WidgetTester tester,
  ) async {
    await DriverStorage.saveDrivers(<Driver>[
      driverWith('أحمد', <DeliveryOrder>[order('1001', 150000)]),
    ]);

    useTallScreen(tester);
    await tester.pumpWidget(wrapHomeScreen());
    await tester.pump();

    await tester.tap(find.text('أحمد'));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey<String>('delete-order-0')));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey<String>('confirm-delete-order-button')),
    );
    await tester.pumpAndSettle();

        expect(find.text('لا توجد طلبات مسجّلة بالتفصيل بعد.'), findsOneWidget);
    expect(_valueOf(tester, 'history-orders'), '0');
    expect(_valueOf(tester, 'history-net'), '0 د.ع');

    final Driver? saved = await DriverStorage.loadDriver('أحمد');
    expect(saved, isNotNull);
    expect(saved!.orders, isEmpty);
    expect(saved.ordersCount, 0);
    expect(saved.netAmountToRestaurant, 0);

    await tester.pump(const Duration(seconds: 5));
  });

  testWidgets(
    'إدارة العمال: إضافة عامل ثم حذفه بتأكيد وتحديث الشاشة الرئيسية',
    (WidgetTester tester) async {
      await DriverStorage.saveDrivers(<Driver>[
        driverWith('أحمد', <DeliveryOrder>[order('1', 30000)]),
      ]);

      useTallScreen(tester);
      await tester.pumpWidget(wrapHomeScreen());
      await tester.pump();

      // فتح نافذة الإدارة من خيار «إدارة أسماء العمال» في القائمة الجانبية.
      await tester.tap(find.byKey(const ValueKey<String>('drawer-button')));
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey<String>('manage-drivers-button')),
      );
      await tester.pumpAndSettle();
      expect(find.text(ManageDriversScreen.title), findsOneWidget);

      // إضافة عامل جديد من الحقل + زر «إضافة».
      await tester.enterText(
        find.byKey(const ValueKey<String>('manage-driver-name-field')),
        'علي',
      );
      await tester.tap(
        find.byKey(const ValueKey<String>('manage-add-driver-button')),
      );
      await tester.pumpAndSettle();

      expect(find.text('علي'), findsOneWidget);
      expect(await DriverStorage.loadDriver('علي'), isNotNull);

      // منع تكرار الاسم.
      await tester.enterText(
        find.byKey(const ValueKey<String>('manage-driver-name-field')),
        'علي',
      );
      await tester.tap(
        find.byKey(const ValueKey<String>('manage-add-driver-button')),
      );
      await tester.pumpAndSettle();
      expect(find.text('هذا الاسم مسجّل مسبقاً'), findsOneWidget);
      expect((await DriverStorage.loadDrivers()).length, 2);

      // الحذف: الإلغاء أولاً ⇒ لا يُحذف شيء.
      await tester.tap(
        find.byKey(const ValueKey<String>('delete-driver-أحمد')),
      );
      await tester.pumpAndSettle();
      expect(find.text('حذف العامل'), findsOneWidget);

      await tester.tap(find.text('إلغاء'));
      await tester.pumpAndSettle();
      expect(await DriverStorage.loadDriver('أحمد'), isNotNull);

      // التأكيد ⇒ يُحذف العامل وبياناته فوراً.
      await tester.tap(
        find.byKey(const ValueKey<String>('delete-driver-أحمد')),
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey<String>('confirm-delete-driver-button')),
      );
      await tester.pumpAndSettle();

      expect(await DriverStorage.loadDriver('أحمد'), isNull);
      expect(find.text('أحمد'), findsNothing);
      expect(find.text('لا يوجد عمال مسجّلون'), findsNothing);

          // الرجوع للشاشة الرئيسية ⇒ تُحدَّث القائمة والإجماليات تلقائياً.
    await tester.tap(find.byKey(const ValueKey<String>('manage-back')));
    await tester.pumpAndSettle();

      expect(find.text('أحمد'), findsNothing);
      expect(find.text('علي'), findsOneWidget);
      expect(_valueOf(tester, 'summary-orders'), '0');
      expect(_valueOf(tester, 'summary-net'), '0 د.ع');

      await tester.pump(const Duration(seconds: 5));
    },
  );

  testWidgets('تصفير حسابات اليوم يصفير الأرقام ويحتفظ بالعمال', (
    WidgetTester tester,
  ) async {
    await DriverStorage.saveDrivers(<Driver>[
      driverWith('أحمد', <DeliveryOrder>[
        order('1', 150000),
        order('2', 100000),
      ]),
      driverWith('علي', <DeliveryOrder>[order('1', 45000)]),
    ]);

    useTallScreen(tester);
    await tester.pumpWidget(wrapHomeScreen());
    await tester.pump();

    // الإجماليات: 3 طلبات، 295,000 د.ع، أجور 3,000، صافي 295,000.
    expect(_valueOf(tester, 'summary-orders'), '3');
    expect(_valueOf(tester, 'summary-total'), '295,000 د.ع');
    expect(_valueOf(tester, 'summary-wage'), '3,000 د.ع');
    expect(_valueOf(tester, 'summary-net'), '295,000 د.ع');

    // (1) الإلغاء في نافذة التأكيد ⇒ لا يُصفَّر أي شيء.
    await tester.tap(find.byKey(const ValueKey<String>('drawer-button')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey<String>('reset-day-button')));
    await tester.pumpAndSettle();
    expect(find.text('تصفير حسابات اليوم'), findsOneWidget);

    await tester.tap(find.text('إلغاء'));
    await tester.pumpAndSettle();

    expect((await DriverStorage.loadDriver('أحمد'))!.ordersCount, 2);
    expect(_valueOf(tester, 'summary-orders'), '3');

    // (2) التأكيد ⇒ تصفر الأرقام وتبقى أسماء العمال محفوظة.
    await tester.tap(find.byKey(const ValueKey<String>('drawer-button')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey<String>('reset-day-button')));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey<String>('confirm-reset-button')),
    );
    await tester.pumpAndSettle();

    expect(_valueOf(tester, 'summary-orders'), '0');
    expect(_valueOf(tester, 'summary-total'), '0 د.ع');
    expect(_valueOf(tester, 'summary-wage'), '0 د.ع');
    expect(_valueOf(tester, 'summary-net'), '0 د.ع');

    final List<Driver> cleared = await DriverStorage.loadDrivers();
    expect(cleared.length, 2);
    expect(cleared.map((Driver driver) => driver.name), <String>[
      'أحمد',
      'علي',
    ]);
    expect(cleared.every((Driver driver) => driver.ordersCount == 0), isTrue);
    expect(
      cleared.every((Driver driver) => driver.totalOrdersAmount == 0),
      isTrue,
    );
    expect(cleared.every((Driver driver) => driver.wage == 0), isTrue);
    expect(
      cleared.every((Driver driver) => driver.netAmountToRestaurant == 0),
      isTrue,
    );

        await tester.pump(const Duration(seconds: 5));
  });
}

/// تكبير مساحة الاختبار ليظهر كامل محتوى الشاشة (بما فيه بطاقة الملخص السفلية)
/// دون الحاجة إلى تمرير.
void useTallScreen(WidgetTester tester) {
  tester.view.physicalSize = const Size(1080, 2600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

/// قراءة نص الرقم المعروض داخل مفتاح معيّن.
String _valueOf(WidgetTester tester, String key) =>
    tester.widget<Text>(find.byKey(ValueKey<String>(key))).data!;

/// قراءة نص الحقل المدخل المرتبط بمفتاح TextEditingController.
String _fieldText(WidgetTester tester, String key) =>
    tester.widget<TextField>(find.byKey(ValueKey<String>(key))).controller
        ?.text ??
    '';