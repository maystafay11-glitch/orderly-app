// اختبارات الأرشيف الأسبوعي: نموذج WeeklyArchive، وإعدادات التطبيق
// (رقم واتساب المدير + الأرشيف + التنبيه الأسبوعي) عبر shared_preferences،
// ورابط الواتساب المبني من الرقم المحفوظ، وإجماليات الأسبوع.
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:orderly_app/models/driver.dart';
import 'package:orderly_app/models/weekly_archive.dart';
import 'package:orderly_app/screens/weekly_archive_screen.dart';
import 'package:orderly_app/services/app_settings.dart';
import 'package:orderly_app/utils/whatsapp.dart';

/// وقت ثابت للفترات المخزَّنة في الاختبارات.
final DateTime testStart = DateTime(2026, 9, 12, 8);
final DateTime testEnd = DateTime(2026, 9, 18, 20);

/// أرشيف بفترة ثابتة (وقت الأرشفة = نهاية الفترة إلا إذا مُرِّر غير ذلك).
WeeklyArchive archiveWith({
  int orders = 3,
  double amount = 100000,
  double wage = 3000,
  double net = 97000,
  DateTime? createdAt,
  DateTime? periodEnd,
}) => WeeklyArchive(
  totalOrders: orders,
  totalAmount: amount,
  totalWage: wage,
  netAmount: net,
  periodStart: testStart,
  periodEnd: periodEnd ?? testEnd,
  createdAt: createdAt ?? testEnd,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    // مخزن وهمي فارغ لكل اختبار.
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });
  group('WeeklyArchive - التخزين والاسترجاع', () {
    test('toJson ثم fromJson يعيدان نفس الملخص', () {
      final WeeklyArchive archive = archiveWith();

      final WeeklyArchive restored = WeeklyArchive.fromJson(archive.toJson());

      expect(restored, archive);
      expect(restored.createdAt, archive.createdAt);
      expect(restored.totalOrders, 3);
      expect(restored.totalAmount, 100000);
      expect(restored.totalWage, 3000);
      expect(restored.netAmount, 97000);
      expect(restored.periodStart, testStart);
      expect(restored.periodEnd, testEnd);
    });

    test('createdAt الافتراضي هو وقت الإنشاء', () {
      final DateTime before = DateTime.now();
      final WeeklyArchive archive = WeeklyArchive(
        totalOrders: 0,
        totalAmount: 0,
        totalWage: 0,
        netAmount: 0,
        periodStart: testStart,
        periodEnd: testEnd,
      );

      expect(archive.createdAt.isBefore(before), isFalse);
    });

    test('fromJson يتحمّل القيم الناقصة أو التالفة دون خطأ', () {
      final WeeklyArchive archive = WeeklyArchive.fromJson(<String, dynamic>{
        'totalOrders': 'غير رقم',
        'totalAmount': '12,500',
        'totalWage': null,
      });

      expect(archive.totalOrders, 0);
      expect(archive.totalAmount, 12500);
      expect(archive.totalWage, 0);
      expect(archive.netAmount, 0);
    });

    test('fromJson يقرأ التواريخ الرقمية والنصية', () {
      final WeeklyArchive archive = WeeklyArchive.fromJson(<String, dynamic>{
        'totalOrders': 5,
        'periodStart': testStart.millisecondsSinceEpoch,
        'periodEnd': testEnd.toIso8601String(),
        'createdAt': testEnd.millisecondsSinceEpoch,
      });

      expect(archive.totalOrders, 5);
      expect(archive.periodStart, testStart);
      expect(archive.periodEnd, testEnd);
      expect(archive.createdAt, testEnd);
    });
  });

  group('AppSettings - رقم واتساب المدير', () {
    test('يرجع نصاً فارغاً عند عدم حفظ رقم', () async {
      expect(await AppSettings.getWhatsAppPhone(), '');
    });

    test('يحفظ الرقم ويقرأه بعد إزالة الفراغات', () async {
      await AppSettings.setWhatsAppPhone('  9647701234567  ');

      expect(await AppSettings.getWhatsAppPhone(), '9647701234567');
    });

    test('تحديث الرقم يستبدل القيمة السابقة', () async {
      await AppSettings.setWhatsAppPhone('9647701234567');
      await AppSettings.setWhatsAppPhone('971501234567');

      expect(await AppSettings.getWhatsAppPhone(), '971501234567');
    });
  });

  group('AppSettings - الأرشيف الأسبوعي', () {
    test('يرجع قائمة فارغة عند عدم وجود أرشيف', () async {
      expect(await AppSettings.loadArchives(), isEmpty);
    });

    test('حفظ الأرشيفات ثم قراءتها مرتّبة من الأحدث للأقدم', () async {
      await AppSettings.saveArchives(<WeeklyArchive>[
        archiveWith(orders: 1, periodEnd: DateTime(2026, 9, 10)),
        archiveWith(orders: 2, periodEnd: DateTime(2026, 9, 18)),
        archiveWith(orders: 3, periodEnd: DateTime(2026, 9, 14)),
      ]);

      final List<WeeklyArchive> loaded = await AppSettings.loadArchives();

      expect(loaded.length, 3);
      expect(
        loaded.map((WeeklyArchive a) => a.totalOrders).toList(),
        <int>[2, 3, 1],
      );
    });

    test('archiveWeek يضيف ملخصاً جديداً ويحتفظ بالسابق', () async {
      await AppSettings.archiveWeek(
        totalOrders: 4,
        totalAmount: 80000,
        totalWage: 4000,
        netAmount: 76000,
        periodStart: testStart,
        periodEnd: testEnd,
      );
      await AppSettings.archiveWeek(
        totalOrders: 6,
        totalAmount: 120000,
        totalWage: 6000,
        netAmount: 114000,
        periodStart: testStart,
        periodEnd: testEnd.add(const Duration(days: 1)),
      );

      final List<WeeklyArchive> loaded = await AppSettings.loadArchives();

      expect(loaded.length, 2);
      expect(loaded.first.totalOrders, 6);
      expect(loaded.last.totalOrders, 4);
    });

    test('pruneOldArchives يحذف ما مرّ عليه أكثر من 7 أيام', () async {
      final DateTime now = DateTime.now();
      await AppSettings.saveArchives(<WeeklyArchive>[
        archiveWith(orders: 1, createdAt: now.subtract(const Duration(days: 8))),
        archiveWith(
          orders: 2,
          periodEnd: DateTime(2026, 9, 17),
          createdAt: now.subtract(const Duration(days: 6)),
        ),
        archiveWith(
          orders: 3,
          periodEnd: DateTime(2026, 9, 18),
          createdAt: now,
        ),
      ]);

      await AppSettings.pruneOldArchives();

      final List<WeeklyArchive> loaded = await AppSettings.loadArchives();
      expect(
        loaded.map((WeeklyArchive a) => a.totalOrders).toList(),
        <int>[3, 2],
      );
    });

    test('archiveWeek ينقّي الأرشيفات القديمة تلقائياً', () async {
      final DateTime now = DateTime.now();
      await AppSettings.saveArchives(<WeeklyArchive>[
        archiveWith(orders: 9, createdAt: now.subtract(const Duration(days: 9))),
      ]);

      await AppSettings.archiveWeek(
        totalOrders: 2,
        totalAmount: 20000,
        totalWage: 2000,
        netAmount: 18000,
        periodStart: testStart,
        periodEnd: testEnd,
      );

      final List<WeeklyArchive> loaded = await AppSettings.loadArchives();
      expect(loaded.length, 1);
      expect(loaded.single.totalOrders, 2);
    });

    test('حفظ قائمة فارغة يمسح الأرشيف المخزَّن', () async {
      await AppSettings.saveArchives(<WeeklyArchive>[archiveWith()]);
      expect(await AppSettings.loadArchives(), hasLength(1));

      await AppSettings.saveArchives(<WeeklyArchive>[]);

      expect(await AppSettings.loadArchives(), isEmpty);
    });

    test('البيانات التالفة لا تُسقط التطبيق', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        AppSettings.archivesKey: 'ليست بيانات JSON',
      });

      expect(await AppSettings.loadArchives(), isEmpty);
    });
  });

  group('AppSettings - التنبيه الأسبوعي', () {
    test('تاريخ افتراضي بعيد عند عدم عرض التنبيه سابقاً', () async {
      final DateTime last = await AppSettings.getLastWeeklyNotice();

      expect(last, DateTime(2000));
      expect(
        DateTime.now().difference(last) >= const Duration(days: 7),
        isTrue,
      );
    });

    test('حفظ وقت العرض ثم قراءته', () async {
      await AppSettings.setLastWeeklyNotice(testEnd);

      expect(await AppSettings.getLastWeeklyNotice(), testEnd);
      expect(
        DateTime.now().difference(testEnd) >= const Duration(days: 7),
        isFalse,
      );
    });

    test('clearAll يمسح الرقم والأرشيف وتاريخ التنبيه', () async {
      await AppSettings.setWhatsAppPhone('9647701234567');
      await AppSettings.setLastWeeklyNotice(testEnd);
      await AppSettings.saveArchives(<WeeklyArchive>[archiveWith()]);

      await AppSettings.clearAll();

      expect(await AppSettings.getWhatsAppPhone(), '');
      expect(await AppSettings.loadArchives(), isEmpty);
      expect(await AppSettings.getLastWeeklyNotice(), DateTime(2000));
    });
  });

  group('WhatsAppLink - بناء رابط wa.me من الرقم المحفوظ', () {
    test('يرجع null عند عدم حفظ رقم', () async {
      expect(await WhatsAppLink.build(message: 'ملخص'), isNull);
    });

    test('يرجع null عند رقم بلا أرقام', () async {
      await AppSettings.setWhatsAppPhone('+ - ()');

      expect(await WhatsAppLink.build(message: 'ملخص'), isNull);
    });

    test('يبني رابطاً بالرقم مجرّداً من الرموز', () async {
      await AppSettings.setWhatsAppPhone('+964 770 123 4567');

      final Uri? link = await WhatsAppLink.build(message: 'ملخص الأسبوع');

      expect(link, isNotNull);
      expect(link!.scheme, 'https');
      expect(link.host, 'wa.me');
      expect(link.path, '/9647701234567');
      expect(link.query, contains('text='));
    });
  });

  group('WeeklyTotals - إجماليات الأسبوع', () {
    test('تحسب الطلبات والمبالغ والأجور والصافي', () {
      final WeeklyTotals totals = WeeklyTotals.from(<Driver>[
        const Driver(name: 'أحمد').addOrder(150000, orderNumber: '1'),
        const Driver(name: 'علي').addOrder(50000, orderNumber: '2'),
      ]);

      expect(totals.drivers, 2);
      expect(totals.orders, 2);
      expect(totals.amount, 200000);
      expect(totals.wage, 2000);
      expect(totals.net, 200000);
    });

    test('قائمة فارغة تعطي أصفاراً', () {
      final WeeklyTotals totals = WeeklyTotals.from(<Driver>[]);

      expect(totals.drivers, 0);
      expect(totals.orders, 0);
      expect(totals.amount, 0);
      expect(totals.wage, 0);
      expect(totals.net, 0);
    });
  });
}