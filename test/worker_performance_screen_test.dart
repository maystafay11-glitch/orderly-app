// اختبارات شاشة «أداء العمال»: الحالة الفارغة، ملخص الأرقام، تنبيه العامل
// المقصّر وشارته، ترتيب القائمة تصاعدياً/تنازلياً، نسبة المساهمة، تصفير
// إحصائيات عامل واحد بشكل مستقل، والوصول إليها من الشاشة الرئيسية.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:orderly_app/models/driver.dart';
import 'package:orderly_app/screens/home_screen.dart';
import 'package:orderly_app/screens/worker_performance_screen.dart';
import 'package:orderly_app/services/driver_storage.dart';

/// لفّ الشاشة باتجاه RTL كما في التطبيق.
Widget wrap(Widget child) => MaterialApp(
  theme: ThemeData(useMaterial3: true),
  builder: (BuildContext context, Widget? widget) => Directionality(
    textDirection: TextDirection.rtl,
    child: widget ?? const SizedBox.shrink(),
  ),
  home: child,
);

/// عامل بعدد طلبات محدد (كل طلب بمبلغ 10000 وأجرة 1000 دينار).
Driver driverWith(String name, int ordersCount, {double amount = 10000}) {
  Driver driver = Driver(name: name);
  for (int i = 0; i < ordersCount; i++) {
    driver = driver.addOrder(amount, orderNumber: '${100 + i}');
  }
  return driver;
}

/// مفتاح بطاقة عامل.
ValueKey<String> cardKey(String name) => ValueKey<String>('worker-card-$name');

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  /// تكبير مساحة الاختبار حتى تُبنى كل البطاقات (القائمة قابلة للتمرير).
  Future<void> useTallSurface(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(620, 1800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
  }

  testWidgets('تعرض حالة فارغة عند عدم وجود عمال', (WidgetTester tester) async {
    await tester.pumpWidget(wrap(const WorkerPerformanceScreen()));
    await tester.pumpAndSettle();

    expect(find.text(WorkerPerformanceScreen.title), findsOneWidget);
    expect(
      find.byKey(const ValueKey<String>('performance-empty')),
      findsOneWidget,
    );
    expect(find.text('لا يوجد عمال لتحليل أدائهم بعد'), findsOneWidget);
    expect(
      find.byKey(const ValueKey<String>('underperformer-banner')),
      findsNothing,
    );
  });

  testWidgets('تعرض ملخص الأرقام: العمال والطلبات والمتوسط والأجور', (
    WidgetTester tester,
  ) async {
    await useTallSurface(tester);
    await DriverStorage.saveDrivers(<Driver>[
      driverWith('أحمد', 5),
      driverWith('سعد', 3),
      driverWith('علي', 2),
    ]);

    await tester.pumpWidget(wrap(const WorkerPerformanceScreen()));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey<String>('report-workers-count')),
      findsOneWidget,
    );
    expect(
      tester
          .widget<Text>(
            find.byKey(const ValueKey<String>('report-workers-count')),
          )
          .data,
      '3',
    );
    expect(
      tester
          .widget<Text>(
            find.byKey(const ValueKey<String>('report-total-orders')),
          )
          .data,
      '10',
    );
    // المتوسط 10/3 = 3.3 بخانة عشرية واحدة.
    expect(
      tester
          .widget<Text>(
            find.byKey(const ValueKey<String>('report-average-orders')),
          )
          .data,
      '3.3',
    );
    expect(
      tester
          .widget<Text>(find.byKey(const ValueKey<String>('report-total-wage')))
          .data,
      '10,000 د.ع',
    );
  });

  testWidgets('تُبرز العامل المقصّر بشارة تحذير ولافتة تنبيه', (
    WidgetTester tester,
  ) async {
    await useTallSurface(tester);
    await DriverStorage.saveDrivers(<Driver>[
      driverWith('أحمد', 4),
      driverWith('سعد', 4),
      driverWith('علي', 1),
    ]);

    await tester.pumpWidget(wrap(const WorkerPerformanceScreen()));
    await tester.pumpAndSettle();

    // لافتة التنبيه مع اسم العامل المقصّر.
    expect(
      find.byKey(const ValueKey<String>('underperformer-banner')),
      findsOneWidget,
    );
    expect(find.text('أداؤهم أقل من متوسط الفريق: علي'), findsOneWidget);

    // شارة التحذير على بطاقة علي فقط.
    expect(
      find.byKey(const ValueKey<String>('worker-warning-علي')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey<String>('worker-warning-أحمد')),
      findsNothing,
    );
    expect(find.text('أداء منخفض'), findsOneWidget);

    // وصف المقارنة بالمعدّل.
    expect(
      tester
          .widget<Text>(
            find.byKey(const ValueKey<String>('worker-comparison-علي')),
          )
          .data,
      'أقل من المتوسط بـ 67%',
    );
  });

  testWidgets('لا تظهر لافتة التنبيه عندما يتساوى أداء العمال', (
    WidgetTester tester,
  ) async {
    await useTallSurface(tester);
    await DriverStorage.saveDrivers(<Driver>[
      driverWith('أحمد', 3),
      driverWith('سعد', 3),
    ]);

    await tester.pumpWidget(wrap(const WorkerPerformanceScreen()));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey<String>('underperformer-banner')),
      findsNothing,
    );
    expect(find.text('أداء منخفض'), findsNothing);
    expect(
      tester
          .widget<Text>(
            find.byKey(const ValueKey<String>('worker-comparison-أحمد')),
          )
          .data,
      'مطابق لمتوسط الفريق',
    );
  });

  testWidgets('تعرض نسبة مساهمة كل عامل من إجمالي الطلبات', (
    WidgetTester tester,
  ) async {
    await useTallSurface(tester);
    await DriverStorage.saveDrivers(<Driver>[
      driverWith('أحمد', 3),
      driverWith('سعد', 1),
    ]);

    await tester.pumpWidget(wrap(const WorkerPerformanceScreen()));
    await tester.pumpAndSettle();

    expect(
      tester
          .widget<Text>(find.byKey(const ValueKey<String>('worker-share-أحمد')))
          .data,
      '75% من إجمالي الطلبات',
    );
    expect(
      tester
          .widget<Text>(find.byKey(const ValueKey<String>('worker-share-سعد')))
          .data,
      '25% من إجمالي الطلبات',
    );
    // شريط التقدّم يعكس نسبة المساهمة نفسها.
    expect(
      tester
          .widget<LinearProgressIndicator>(
            find.byKey(const ValueKey<String>('worker-contribution-أحمد')),
          )
          .value,
      closeTo(0.75, 0.0001),
    );
  });

  testWidgets('ترتيب القائمة يتغيّر بين الأكثر والأقل نشاطاً وحسب الاسم', (
    WidgetTester tester,
  ) async {
    await useTallSurface(tester);
    await DriverStorage.saveDrivers(<Driver>[
      driverWith('أحمد', 1),
      driverWith('بشار', 5),
      driverWith('تمام', 3),
    ]);

    await tester.pumpWidget(wrap(const WorkerPerformanceScreen()));
    await tester.pumpAndSettle();

    double topOf(String name) =>
        tester.getTopLeft(find.byKey(cardKey(name))).dy;

    // الافتراضي: الأكثر نشاطاً أولاً (بشار 5 ثم تمام 3 ثم أحمد 1).
    expect(topOf('بشار'), lessThan(topOf('تمام')));
    expect(topOf('تمام'), lessThan(topOf('أحمد')));

    // الترتيب التصاعدي: الأقل نشاطاً أولاً.
    await tester.ensureVisible(
      find.byKey(const ValueKey<String>('sort-ordersAsc')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey<String>('sort-ordersAsc')));
    await tester.pumpAndSettle();
    expect(topOf('أحمد'), lessThan(topOf('تمام')));
    expect(topOf('تمام'), lessThan(topOf('بشار')));

    // الترتيب حسب الاسم: أحمد ثم بشار ثم تمام (يختلف عن ترتيب النشاط).
    // يُمرَّر شريط الأزرار أفقياً أولاً لأن الخيار الأخير خارج الشاشة.
    await tester.ensureVisible(
      find.byKey(const ValueKey<String>('sort-nameAsc')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey<String>('sort-nameAsc')));
    await tester.pumpAndSettle();
    expect(topOf('أحمد'), lessThan(topOf('بشار')));
    expect(topOf('بشار'), lessThan(topOf('تمام')));
  });

  testWidgets('تصفير إحصائيات عامل واحد لا يمسّ بقية العمال', (
    WidgetTester tester,
  ) async {
    await useTallSurface(tester);
    await DriverStorage.saveDrivers(<Driver>[
      driverWith('أحمد', 4),
      driverWith('سعد', 4),
      driverWith('علي', 1),
    ]);

    await tester.pumpWidget(wrap(const WorkerPerformanceScreen()));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey<String>('worker-reset-علي')));
    await tester.pumpAndSettle();

    expect(find.text('تصفير إحصائيات العامل'), findsOneWidget);
    expect(
      find.textContaining('سيتم تصفير أرقام العامل «علي»'),
      findsOneWidget,
    );

    await tester.tap(
      find.byKey(const ValueKey<String>('confirm-worker-reset-button')),
    );
    await tester.pumpAndSettle();

    // العامل المحدَّد فقط تُصفَّر أرقامه.
    final List<Driver> drivers = await DriverStorage.loadDrivers();
    expect(drivers, hasLength(3));
    Driver byName(String name) =>
        drivers.firstWhere((Driver driver) => driver.name == name);
    expect(byName('علي').ordersCount, 0);
    expect(byName('علي').wage, 0);
    expect(byName('أحمد').ordersCount, 4);
    expect(byName('سعد').ordersCount, 4);

    // الشاشة أُعيد تحميلها بالأرقام الجديدة (4 + 4 = 8).
    expect(
      tester
          .widget<Text>(
            find.byKey(const ValueKey<String>('report-total-orders')),
          )
          .data,
      '8',
    );
    expect(find.text('تم تصفير إحصائيات العامل علي.'), findsOneWidget);
  });

  testWidgets('إلغاء التصفير لا يغيّر أي إحصائية', (WidgetTester tester) async {
    await useTallSurface(tester);
    await DriverStorage.saveDrivers(<Driver>[
      driverWith('أحمد', 2),
      driverWith('سعد', 2),
    ]);

    await tester.pumpWidget(wrap(const WorkerPerformanceScreen()));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey<String>('worker-reset-أحمد')));
    await tester.pumpAndSettle();

    await tester.tap(find.text('إلغاء'));
    await tester.pumpAndSettle();

    final List<Driver> drivers = await DriverStorage.loadDrivers();
    expect(
      drivers.firstWhere((Driver driver) => driver.name == 'أحمد').ordersCount,
      2,
    );
    expect(find.text('تصفير إحصائيات العامل'), findsNothing);
  });

  testWidgets('يمكن فتح شاشة أداء العمال من الشاشة الرئيسية', (
    WidgetTester tester,
  ) async {
    await useTallSurface(tester);
    await DriverStorage.saveDrivers(<Driver>[driverWith('أحمد', 2)]);

    await tester.pumpWidget(wrap(const HomeScreen()));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey<String>('performance-button')));
    await tester.pumpAndSettle();

    expect(
      find.descendant(
        of: find.byType(AppBar),
        matching: find.text(WorkerPerformanceScreen.title),
      ),
      findsOneWidget,
    );
    expect(
      tester
          .widget<Text>(
            find.byKey(const ValueKey<String>('report-total-orders')),
          )
          .data,
      '2',
    );
  });
}
