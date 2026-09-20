// اختبارات شاشة «الملخص الأسبوعي»: التنبيه الأسبوعي، أرشفة الأسبوع وتصفير
// الحسابات، عرض الأرشيف المحفوظ، زر المشاركة عبر الواتساب، والوصول إليها
// من القائمة الجانبية (Drawer) في الشاشة الرئيسية.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:orderly_app/models/driver.dart';
import 'package:orderly_app/models/weekly_archive.dart';
import 'package:orderly_app/screens/home_screen.dart';
import 'package:orderly_app/screens/weekly_archive_screen.dart';
import 'package:orderly_app/services/app_settings.dart';
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

/// عامل بطلبات محددة (كل طلب بأجرة 1000 دينار).
Driver driverWith(String name, List<double> amounts) {
  Driver driver = Driver(name: name);
  for (int i = 0; i < amounts.length; i++) {
    driver = driver.addOrder(amounts[i], orderNumber: '${100 + i}');
  }
  return driver;
}

/// أرشيف محفوظ بفترة وتاريخ أرشفة محددين.
WeeklyArchive savedArchive({DateTime? createdAt}) => WeeklyArchive(
  totalOrders: 2,
  totalAmount: 250000,
  totalWage: 2000,
  netAmount: 248000,
  periodStart: DateTime(2026, 9, 12, 8),
  periodEnd: DateTime(2026, 9, 18, 20),
  createdAt: createdAt ?? DateTime.now(),
);

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  testWidgets('تعرض الحالة الفارغة والتنبيه الأسبوعي بإجماليات الفترة', (
    WidgetTester tester,
  ) async {
    await DriverStorage.saveDrivers(<Driver>[
      driverWith('أحمد', <double>[150000, 100000]),
    ]);

    await tester.pumpWidget(wrap(const WeeklyArchiveScreen()));
    await tester.pumpAndSettle();

    expect(find.text(WeeklyArchiveScreen.title), findsOneWidget);
    expect(find.text('لا يوجد أرشيف أسبوعي بعد'), findsOneWidget);
    expect(
      find.byKey(const ValueKey<String>('weekly-notice-title')),
      findsOneWidget,
    );
    // التنبيه يعرض إجماليات الفترة الحالية: أجور 2,000 وصافي 250,000.
    expect(find.text('2,000 د.ع'), findsOneWidget);
    expect(find.text('250,000 د.ع'), findsOneWidget);

    // يُسجَّل وقت العرض حتى لا يتكرر التنبيه قبل أسبوع.
    expect(
      DateTime.now().difference(await AppSettings.getLastWeeklyNotice()),
      lessThan(const Duration(days: 7)),
    );
  });

  testWidgets('لا يظهر التنبيه الأسبوعي إذا عُرض خلال الأسبوع نفسه', (
    WidgetTester tester,
  ) async {
    await AppSettings.setLastWeeklyNotice(DateTime.now());

    await tester.pumpWidget(wrap(const WeeklyArchiveScreen()));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey<String>('weekly-notice-title')),
      findsNothing,
    );
  });

  testWidgets('أرشفة الأسبوع تحفظ الملخص وتصفّر حسابات العمال', (
    WidgetTester tester,
  ) async {
    await DriverStorage.saveDrivers(<Driver>[
      driverWith('أحمد', <double>[150000, 100000]),
    ]);

    await tester.pumpWidget(wrap(const WeeklyArchiveScreen()));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey<String>('archive-week-button')));
    await tester.pumpAndSettle();

    // الملخص محفوظ بأرقام الفترة.
    final List<WeeklyArchive> archives = await AppSettings.loadArchives();
    expect(archives, hasLength(1));
    expect(archives.single.totalOrders, 2);
    expect(archives.single.totalAmount, 250000);
    expect(archives.single.totalWage, 2000);
    expect(archives.single.netAmount, 250000);

    // الحسابات مصفّرة مع الاحتفاظ باسم العامل.
    final List<Driver> drivers = await DriverStorage.loadDrivers();
    expect(drivers, hasLength(1));
    expect(drivers.single.name, 'أحمد');
    expect(drivers.single.ordersCount, 0);
    expect(drivers.single.netAmountToRestaurant, 0);

    expect(
      find.text('تم أرشفة الملخص الأسبوعي وتصفير الحسابات.'),
      findsOneWidget,
    );
    // صف الأرشيف يظهر بالأرقام المحفوظة.
    expect(find.text('250,000 د.ع'), findsOneWidget);
    expect(find.text('لا يوجد أرشيف أسبوعي بعد'), findsNothing);

    await tester.pump(const Duration(seconds: 5));
  });

  testWidgets('زر المشاركة يطلب حفظ رقم المدير عند عدم وجود رقم', (
    WidgetTester tester,
  ) async {
    await AppSettings.saveArchives(<WeeklyArchive>[savedArchive()]);

    await tester.pumpWidget(wrap(const WeeklyArchiveScreen()));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('مشاركة عبر الواتساب'));
    await tester.pumpAndSettle();

    expect(
      find.text('رجئًا حفظ رقم مديرك في «إعدادات المدير» قبل المشاركة.'),
      findsOneWidget,
    );

    await tester.pump(const Duration(seconds: 5));
  });

  testWidgets('زر المشاركة يحضّر رسالة الواتساب للرقم المحفوظ', (
    WidgetTester tester,
  ) async {
    await AppSettings.setWhatsAppPhone('+964 770 123 4567');
    await AppSettings.saveArchives(<WeeklyArchive>[savedArchive()]);

    await tester.pumpWidget(wrap(const WeeklyArchiveScreen()));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('مشاركة عبر الواتساب'));
    await tester.pumpAndSettle();

    expect(
      find.text('تم تحضير رسالة الواتساب لرقم: 9647701234567'),
      findsOneWidget,
    );

    await tester.pump(const Duration(seconds: 5));
  });

  testWidgets('أيقونة الملخص الأسبوعي في القائمة الجانبية تفتح الأرشيف', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(wrap(const HomeScreen()));
    await tester.pump();

    await tester.tap(find.byKey(const ValueKey<String>('drawer-button')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey<String>('archive-button')));
    await tester.pumpAndSettle();

    expect(find.text(WeeklyArchiveScreen.title), findsOneWidget);
    expect(find.text('لا يوجد أرشيف أسبوعي بعد'), findsOneWidget);
  });
}
