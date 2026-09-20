// اختبارات نموذج الطلب DeliveryOrder ونموذج العامل Driver، وحفظ/استرجاع
// بيانات العوامل (بما فيها سجل الطلبات) عبر shared_preferences.
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:orderly_app/models/delivery_order.dart';
import 'package:orderly_app/models/driver.dart';
import 'package:orderly_app/services/driver_storage.dart';

/// وقت ثابت لاختبارات وقت الإضافة (بدل الاعتماد على الوقت الحالي).
final DateTime testTime = DateTime(2026, 9, 18, 15, 45);

/// بناء عامل لديه طلبات بمبالغ محددة (رقم كل طلب = ترتيبه).
Driver driverWithOrders(
  String name,
  List<double> amounts, {
  int wagePerOrder = Driver.defaultWagePerOrder,
}) {
  Driver driver = Driver(name: name, wagePerOrder: wagePerOrder);
  for (int i = 0; i < amounts.length; i++) {
    driver = driver.addOrder(
      amounts[i],
      orderNumber: '${100 + i}',
      addedAt: testTime,
    );
  }
  return driver;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    // مخزن وهمي فارغ لكل اختبار.
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  group('DeliveryOrder - بيانات الطلب الواحد', () {
    test('يحفظ رقم الطلب وسعره ووقت إضافته', () {
      final DeliveryOrder order = DeliveryOrder(
        orderNumber: '1024',
        amount: 15000,
        addedAt: testTime,
      );

      expect(order.orderNumber, '1024');
      expect(order.amount, 15000);
      expect(order.addedAt, testTime);
      expect(order.displayNumber, '1024');
    });

    test('يستخدم وقت الإضافة الحالي عند عدم تمريره', () {
      final DateTime before = DateTime.now();
      final DeliveryOrder order = DeliveryOrder(amount: 5000);

      expect(order.addedAt.isBefore(before), isFalse);
      expect(order.orderNumber, '');
      // بدون رقم ⇒ عرض واضح في السجل.
      expect(order.displayNumber, 'بدون رقم');
    });

    test('toJson ثم fromJson يعيدان نفس الطلب', () {
      final DeliveryOrder order = DeliveryOrder(
        orderNumber: 'A-15',
        amount: 7500.5,
        addedAt: testTime,
      );

      expect(DeliveryOrder.fromJson(order.toJson()), order);
    });

    test('fromJson يتعامل مع القيم الناقصة أو التالفة دون خطأ', () {
      final DeliveryOrder order = DeliveryOrder.fromJson(<String, dynamic>{
        DeliveryOrder.keyOrderNumber: '  7  ',
        DeliveryOrder.keyAmount: 'غير رقم',
      });

      expect(order.orderNumber, '7');
      expect(order.amount, 0);
    });

    test('fromJson يقرأ المبلغ المكتوب بفواصل نصية', () {
      final DeliveryOrder order = DeliveryOrder.fromJson(<String, dynamic>{
        DeliveryOrder.keyAmount: '12,500',
      });

      expect(order.amount, 12500);
    });
  });

  group('Driver - الحساب التلقائي من سجل الطلبات', () {
    test('الأجرة = عدد الطلبات × 1000 دينار', () {
      final Driver driver = driverWithOrders('أحمد', <double>[
        20000,
        15000,
        10000,
      ]);

      expect(driver.ordersCount, 3);
      expect(driver.totalOrdersAmount, 45000);
      expect(driver.wage, 3000);
      expect(driver.netAmountToRestaurant, 45000);
    });

    test('يمكن تغيير أجرة الطلب الواحد', () {
      final Driver driver = driverWithOrders(
        'أحمد',
        <double>[20000, 30000],
        wagePerOrder: 750,
      );

      expect(driver.wage, 1500);
      expect(driver.netAmountToRestaurant, 50000);
    });

    test('عامل بدون طلبات: أجرة صفر والصافي صفر', () {
      const Driver driver = Driver(name: 'أحمد');

      expect(driver.ordersCount, 0);
      expect(driver.totalOrdersAmount, 0);
      expect(driver.wage, 0);
      expect(driver.netAmountToRestaurant, 0);
      expect(driver.hasLegacyOrders, isFalse);
    });

    test('addOrder يخزّن رقم الطلب وسعره ووقت الإضافة', () {
      final Driver driver = const Driver(
        name: 'أحمد',
      ).addOrder(15000, orderNumber: ' 1024 ', addedAt: testTime);

      expect(driver.orders.length, 1);
      expect(driver.orders.single.orderNumber, '1024');
      expect(driver.orders.single.amount, 15000);
      expect(driver.orders.single.addedAt, testTime);
      expect(driver.ordersCount, 1);
      expect(driver.totalOrdersAmount, 15000);
      expect(driver.wage, 1000);
      expect(driver.netAmountToRestaurant, 15000);
    });

    test('removeOrderAt يخصم القيمة ويُنقص العدد ويُعيد حساب الأجرة والصافي', () {
      final Driver driver = driverWithOrders('أحمد', <double>[
        20000,
        15000,
        10000,
      ]);

      final Driver after = driver.removeOrderAt(1);

      expect(after.orders.length, 2);
      expect(after.ordersCount, 2);
      expect(after.totalOrdersAmount, 30000);
      expect(after.wage, 2000);
      expect(after.netAmountToRestaurant, 30000);
      // الطلب المحذوف هو الطلب ذو الرقم 101 فقط.
      expect(
        after.orders.map((DeliveryOrder order) => order.orderNumber),
        <String>['100', '102'],
      );
    });

    test('removeOrder يحذف الطلب المحدد بعينه لا غيره', () {
      final Driver driver = driverWithOrders('أحمد', <double>[20000, 15000]);
      final DeliveryOrder target = driver.orders.first;

      final Driver after = driver.removeOrder(target);

      expect(after.orders.single.orderNumber, '101');
      expect(after.totalOrdersAmount, 15000);
    });

    test('الحذف بترتيب غير موجود لا يغيّر شيئاً', () {
      final Driver driver = driverWithOrders('أحمد', <double>[20000]);

      expect(driver.removeOrderAt(5), driver);
      expect(driver.removeOrderAt(-1), driver);
    });

    test('resetDay يحذف كل الطلبات والأرقام المُرحَّلة ويحتفظ بالاسم', () {
      final Driver driver = driverWithOrders('أحمد', <double>[20000, 5000]);

      final Driver cleared = driver.resetDay();

      expect(cleared.name, 'أحمد');
      expect(cleared.orders, isEmpty);
      expect(cleared.ordersCount, 0);
      expect(cleared.totalOrdersAmount, 0);
      expect(cleared.wage, 0);
      expect(cleared.netAmountToRestaurant, 0);
    });

    test('suggestedOrderNumber يقترح الرقم التالي بعد أكبر رقم مسجّل', () {
      final Driver driver = const Driver(name: 'أحمد')
          .addOrder(5000, orderNumber: '7')
          .addOrder(5000, orderNumber: '15');

      expect(driver.suggestedOrderNumber, '16');
      expect(const Driver(name: 'أحمد').suggestedOrderNumber, '1');
    });
  });

  group('Driver - الترميز JSON والترحيل', () {
    test('toJson ثم fromJson يعيدان نفس البيانات مع سجل الطلبات', () {
      final Driver driver = driverWithOrders('أحمد', <double>[45000, 20000]);

      final Driver restored = Driver.fromJson(driver.toJson());

      expect(restored, driver);
      expect(restored.orders.length, 2);
      expect(restored.orders.last.amount, 20000);
      expect(restored.orders.last.addedAt, testTime);
      expect(restored.ordersCount, 2);
      expect(restored.totalOrdersAmount, 65000);
    });

    test('fromJson يقرأ الأرقام المحفوظة بالصيغة السابقة (ترحيل)', () {
      final Driver driver = Driver.fromJson(<String, dynamic>{
        Driver.keyName: 'أحمد',
        Driver.keyOrdersCount: '7',
        Driver.keyTotalOrdersAmount: '12,500',
      });

      expect(driver.orders, isEmpty);
      expect(driver.hasLegacyOrders, isTrue);
      expect(driver.legacyOrdersCount, 7);
      expect(driver.legacyOrdersAmount, 12500);
      expect(driver.ordersCount, 7);
      expect(driver.wagePerOrder, Driver.defaultWagePerOrder);
      expect(driver.wage, 7000);
      expect(driver.netAmountToRestaurant, 12500);
    });

    test('الطلبات الجديدة تُضاف فوق الأرقام المُرحَّلة', () {
      final Driver legacy = Driver.fromJson(<String, dynamic>{
        Driver.keyOrdersCount: 2,
        Driver.keyTotalOrdersAmount: 30000,
      });

      final Driver updated = legacy.addOrder(10000, orderNumber: '3');

      expect(updated.ordersCount, 3);
      expect(updated.totalOrdersAmount, 40000);
      expect(updated.wage, 3000);
    });

    test('fromJson يتعامل مع القيم الناقصة أو التالفة دون خطأ', () {
      final Driver driver = Driver.fromJson(<String, dynamic>{
        Driver.keyOrders: 'ليست قائمة',
        Driver.keyOrdersCount: null,
        Driver.keyTotalOrdersAmount: 'غير رقم',
      });

      expect(driver.name, '');
      expect(driver.orders, isEmpty);
      expect(driver.ordersCount, 0);
      expect(driver.totalOrdersAmount, 0);
    });

    test('fromJson يتجاهل عناصر الطلبات غير الصالحة', () {
      final Driver driver = Driver.fromJson(<String, dynamic>{
        Driver.keyOrders: <Object?>[
          <String, dynamic>{
            DeliveryOrder.keyOrderNumber: '5',
            DeliveryOrder.keyAmount: 9000,
          },
          'قيمة غير صالحة',
        ],
      });

      expect(driver.orders.length, 1);
      expect(driver.totalOrdersAmount, 9000);
    });
  });

  group('DriverStorage - الحفظ والاسترجاع', () {
    test('لا يوجد محفوظ ⇒ قائمة فارغة', () async {
      expect(await DriverStorage.loadDrivers(), isEmpty);
      expect(await DriverStorage.hasSavedDrivers(), isFalse);
    });

    test('حفظ واسترجاع قائمة العوامل مع سجل الطلبات', () async {
      final List<Driver> drivers = <Driver>[
        driverWithOrders('أحمد', <double>[150000, 100000]),
        driverWithOrders('علي', <double>[60000]),
      ];

      await DriverStorage.saveDrivers(drivers);
      final List<Driver> loaded = await DriverStorage.loadDrivers();

      expect(loaded, drivers);
      expect(loaded.first.ordersCount, 2);
      expect(loaded.first.totalOrdersAmount, 250000);
      expect(loaded.first.orders.last.orderNumber, '101');
      expect(loaded.first.orders.last.addedAt, testTime);
      expect(await DriverStorage.hasSavedDrivers(), isTrue);
    });

    test('saveDriver يضيف عاملاً ثم يحدّثه بدل تكراره', () async {
      await DriverStorage.saveDriver(const Driver(name: 'أحمد'));
      await DriverStorage.saveDriver(
        const Driver(
          name: 'أحمد',
        ).addOrder(75000, orderNumber: '1', addedAt: testTime).addOrder(
          20000,
          orderNumber: '2',
          addedAt: testTime,
        ),
      );
      await DriverStorage.saveDriver(const Driver(name: 'علي'));

      final List<Driver> loaded = await DriverStorage.loadDrivers();
      expect(loaded.length, 2);
      expect(await DriverStorage.loadDriver('أحمد'), loaded.first);
      expect(loaded.first.ordersCount, 2);
      expect(loaded.first.totalOrdersAmount, 95000);
      expect(loaded.first.netAmountToRestaurant, 95000);
    });

    test('driver.save() يحفظ العامل مباشرة', () async {
      final Driver driver = const Driver(
        name: 'أحمد',
      ).addOrder(30000, orderNumber: '12', addedAt: testTime);
      await driver.save();

      final Driver? loaded = await DriverStorage.loadDriver('أحمد');
      expect(loaded, driver);
      expect(loaded!.orders.single.orderNumber, '12');
      expect(loaded.wage, 1000);
      expect(loaded.netAmountToRestaurant, 30000);
    });

    test('حذف طلب ثم الحفظ: تُخصم القيمة ويُحدَّث المحفوظ محلياً', () async {
      final Driver driver = driverWithOrders('أحمد', <double>[
        150000,
        100000,
      ]);
      await driver.save();

      // حذف الطلب الأول (150,000) ثم الحفظ كما يفعل حوار سجل الطلبات.
      final Driver afterDelete = driver.removeOrderAt(0);
      await afterDelete.save();

      final Driver? loaded = await DriverStorage.loadDriver('أحمد');
      expect(loaded, isNotNull);
      expect(loaded!.ordersCount, 1);
      expect(loaded.totalOrdersAmount, 100000);
      expect(loaded.wage, 1000);
      expect(loaded.netAmountToRestaurant, 100000);
      expect(loaded.orders.single.orderNumber, '101');
    });

    test('loadOrCreate يسترجع المحفوظ أو ينشئ ويحفظ الجديد', () async {
      final Driver created = await DriverStorage.loadOrCreate('أحمد');
      expect(created.ordersCount, 0);
      expect(await DriverStorage.loadDriver('أحمد'), created);

      await created.addOrder(20000, orderNumber: '1').save();
      final Driver reloaded = await DriverStorage.loadOrCreate('أحمد');

      expect(reloaded.ordersCount, 1);
      expect(reloaded.totalOrdersAmount, 20000);
      expect(reloaded.netAmountToRestaurant, 20000);
    });

    test('deleteDriver / driver.delete() يحذفان عاملاً بعينه', () async {
      await DriverStorage.saveDrivers(const <Driver>[
        Driver(name: 'أحمد'),
        Driver(name: 'علي'),
      ]);

      expect(await DriverStorage.deleteDriver('أحمد'), isTrue);
      expect(await DriverStorage.deleteDriver('غير موجود'), isFalse);

      final List<Driver> loaded = await DriverStorage.loadDrivers();
      expect(loaded.length, 1);
      expect(await loaded.single.delete(), isTrue);
      expect(await DriverStorage.loadDrivers(), isEmpty);
    });

    test('clear يحذف كل البيانات', () async {
      await DriverStorage.saveDrivers(const <Driver>[Driver(name: 'أحمد')]);

      await DriverStorage.clear();

      expect(await DriverStorage.loadDrivers(), isEmpty);
    });

    test('البيانات التالفة لا تُسقط التطبيق', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        DriverStorage.driversKey: 'ليست بيانات JSON',
      });

      expect(await DriverStorage.loadDrivers(), isEmpty);
    });
  });
}