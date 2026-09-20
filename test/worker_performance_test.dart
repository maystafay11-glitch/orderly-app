// اختبارات تحليل أداء العمال: الإجماليات، متوسط الطلبات، نسبة المساهمة،
// تمييز العامل المقصّر مقارنة بالمتوسط، وطرق الترتيب المختلفة.
import 'package:flutter_test/flutter_test.dart';

import 'package:orderly_app/models/driver.dart';
import 'package:orderly_app/models/worker_performance.dart';

/// عامل بعدد طلبات محدد (كل طلب بمبلغ [amount] وأجرة 1000 دينار).
Driver driverWith(String name, int ordersCount, {double amount = 10000}) {
  Driver driver = Driver(name: name);
  for (int i = 0; i < ordersCount; i++) {
    driver = driver.addOrder(amount, orderNumber: '${100 + i}');
  }
  return driver;
}

/// البحث عن تقييم عامل بالاسم.
WorkerPerformance entryOf(PerformanceReport report, String name) =>
    report.entries.firstWhere((WorkerPerformance e) => e.name == name);

void main() {
  group('التقرير الفارغ', () {
    test('قائمة بلا عمال تُنتج تقريراً فارغاً بلا تنبيهات', () {
      final PerformanceReport report = PerformanceReport.of(const <Driver>[]);

      expect(report.isEmpty, isTrue);
      expect(report.workersCount, 0);
      expect(report.totalOrders, 0);
      expect(report.totalAmount, 0);
      expect(report.totalWage, 0);
      expect(report.averageOrders, 0);
      expect(report.hasUnderperformers, isFalse);
      expect(report.topPerformer, isNull);
      expect(report.sorted(PerformanceSort.ordersDesc), isEmpty);
    });
  });

  group('الإجماليات والمتوسط', () {
    test('تجمع الطلبات والمبالغ والأجور وتحسب المتوسط', () {
      final PerformanceReport report = PerformanceReport.of(<Driver>[
        driverWith('أحمد', 5, amount: 20000),
        driverWith('سعد', 3),
        driverWith('علي', 2),
      ]);

      expect(report.workersCount, 3);
      expect(report.totalOrders, 10);
      expect(report.totalAmount, 5 * 20000 + 3 * 10000 + 2 * 10000);
      expect(report.totalWage, 10 * 1000);
      expect(report.averageOrders, closeTo(10 / 3, 0.0001));
    });

    test('تُحتسب الطلبات المُرحَّلة من إصدار سابق داخل الأرقام', () {
      const Driver legacy = Driver(
        name: 'قديم',
        legacyOrdersCount: 4,
        legacyOrdersAmount: 60000,
      );
      final PerformanceReport report = PerformanceReport.of(<Driver>[
        legacy,
        driverWith('جديد', 2),
      ]);

      expect(report.totalOrders, 6);
      expect(report.totalAmount, 60000 + 20000);
      expect(entryOf(report, 'قديم').ordersCount, 4);
      expect(entryOf(report, 'قديم').wage, 4000);
    });
  });

  group('نسبة المساهمة', () {
    test('تُحسب من إجمالي الطلبات وتُقرَّب للعرض', () {
      final PerformanceReport report = PerformanceReport.of(<Driver>[
        driverWith('أحمد', 3),
        driverWith('سعد', 1),
      ]);

      expect(entryOf(report, 'أحمد').share, closeTo(0.75, 0.0001));
      expect(entryOf(report, 'أحمد').sharePercent, 75);
      expect(entryOf(report, 'سعد').sharePercent, 25);
      expect(entryOf(report, 'أحمد').shareFraction, closeTo(0.75, 0.0001));
    });

    test('المساهمة صفر عندما لا توجد طلبات إطلاقاً', () {
      final PerformanceReport report = PerformanceReport.of(<Driver>[
        driverWith('أحمد', 0),
        driverWith('سعد', 0),
      ]);

      expect(report.totalOrders, 0);
      expect(entryOf(report, 'أحمد').share, 0);
      expect(entryOf(report, 'أحمد').sharePercent, 0);
      expect(report.hasUnderperformers, isFalse);
    });
  });

  group('تمييز العامل المقصّر', () {
    test('من أنجز أقل من 60% من المتوسط يُنبَّه عليه', () {
      final PerformanceReport report = PerformanceReport.of(<Driver>[
        driverWith('أحمد', 4),
        driverWith('سعد', 4),
        driverWith('علي', 1),
      ]);

      // المتوسط 3 والحد 1.8 ⇒ علي (1) مقصّر والبقية لا.
      expect(report.averageOrders, 3);
      expect(entryOf(report, 'علي').isUnderperformer, isTrue);
      expect(entryOf(report, 'أحمد').isUnderperformer, isFalse);
      expect(report.hasUnderperformers, isTrue);
      expect(report.underperformers, hasLength(1));
      expect(report.underperformers.single.name, 'علي');
    });

    test('عامل بلا أي طلب يُعدّ مقصّراً عندما يعمل زملاؤه', () {
      final PerformanceReport report = PerformanceReport.of(<Driver>[
        driverWith('أحمد', 10),
        driverWith('علي', 0),
      ]);

      // المتوسط 5 والحد 3 ⇒ صفر أقل من 3.
      expect(entryOf(report, 'علي').isUnderperformer, isTrue);
      expect(entryOf(report, 'علي').belowAveragePercent, 100);
      expect(entryOf(report, 'علي').isEmpty, isTrue);
    });

    test('لا مقارنة مع عامل واحد فقط حتى لو لم يسجّل طلبات', () {
      final PerformanceReport report = PerformanceReport.of(<Driver>[
        driverWith('أحمد', 0),
      ]);

      expect(report.hasUnderperformers, isFalse);
      expect(entryOf(report, 'أحمد').isUnderperformer, isFalse);
    });

    test('لا تنبيه عندما يتساوى أداء كل العمال', () {
      final PerformanceReport report = PerformanceReport.of(<Driver>[
        driverWith('أحمد', 3),
        driverWith('سعد', 3),
      ]);

      expect(report.hasUnderperformers, isFalse);
      expect(entryOf(report, 'أحمد').averageRatio, 1);
      expect(entryOf(report, 'أحمد').isAboveAverage, isFalse);
    });

    test('الحد المخصّص يغيّر من يُعتبر مقصّراً', () {
      final List<Driver> drivers = <Driver>[
        driverWith('أحمد', 4),
        driverWith('سعد', 4),
        driverWith('علي', 3),
      ];

      // بحد 0.9: المتوسط 11/3 ≈ 3.67 والحد 3.3 ⇒ علي مقصّر.
      expect(
        entryOf(
          PerformanceReport.of(drivers, threshold: 0.9),
          'علي',
        ).isUnderperformer,
        isTrue,
      );
      // بحد 0.2: الحد ≈ 0.73 ⇒ لا أحد مقصّر.
      expect(
        PerformanceReport.of(drivers, threshold: 0.2).hasUnderperformers,
        isFalse,
      );
    });

    test('حد غير صالح يعود إلى القيمة الافتراضية', () {
      final List<Driver> drivers = <Driver>[
        driverWith('أحمد', 4),
        driverWith('علي', 1),
      ];

      expect(
        PerformanceReport.of(drivers, threshold: 0).hasUnderperformers,
        isTrue,
      );
      expect(
        PerformanceReport.of(drivers, threshold: 5).hasUnderperformers,
        isTrue,
      );
    });

    test('وصف الانخفاض والمقارنة بالمتوسط', () {
      final PerformanceReport report = PerformanceReport.of(<Driver>[
        driverWith('أحمد', 6),
        driverWith('علي', 2),
      ]);

      final WorkerPerformance top = entryOf(report, 'أحمد');
      final WorkerPerformance low = entryOf(report, 'علي');

      expect(top.averageRatio, closeTo(1.5, 0.0001));
      expect(top.isAboveAverage, isTrue);
      expect(top.belowAveragePercent, 0);
      expect(low.averageRatio, closeTo(0.5, 0.0001));
      expect(low.isAboveAverage, isFalse);
      expect(low.belowAveragePercent, 50);
    });
  });

  group('الترتيب', () {
    test('التقييمات مرتّبة أصلاً حسب النشاط مع ترقيم صحيح', () {
      final PerformanceReport report = PerformanceReport.of(<Driver>[
        driverWith('علي', 1),
        driverWith('أحمد', 5),
        driverWith('سعد', 3),
      ]);

      expect(
        report.entries.map((WorkerPerformance e) => e.name).toList(),
        <String>['أحمد', 'سعد', 'علي'],
      );
      expect(
        report.entries.map((WorkerPerformance e) => e.activityRank).toList(),
        <int>[1, 2, 3],
      );
      expect(report.topPerformer?.name, 'أحمد');
    });

    test('الأكثر نشاطاً والأقل نشاطاً', () {
      final PerformanceReport report = PerformanceReport.of(<Driver>[
        driverWith('أحمد', 5),
        driverWith('سعد', 1),
        driverWith('علي', 3),
      ]);

      expect(
        report
            .sorted(PerformanceSort.ordersDesc)
            .map((WorkerPerformance e) => e.ordersCount)
            .toList(),
        <int>[5, 3, 1],
      );
      expect(
        report
            .sorted(PerformanceSort.ordersAsc)
            .map((WorkerPerformance e) => e.ordersCount)
            .toList(),
        <int>[1, 3, 5],
      );
    });

    test('الأعلى أجوراً يعتمد على الأجرة لا على عدد الطلبات', () {
      // أحمد: طلب واحد بأجرة 5000، سعد: ثلاثة طلبات بأجرة 1000.
      final PerformanceReport report = PerformanceReport.of(<Driver>[
        Driver(name: 'أحمد', wagePerOrder: 5000).addOrder(10000),
        driverWith('سعد', 3),
      ]);

      expect(
        report
            .sorted(PerformanceSort.wageDesc)
            .map((WorkerPerformance e) => e.name)
            .toList(),
        <String>['أحمد', 'سعد'],
      );
      expect(
        report
            .sorted(PerformanceSort.ordersDesc)
            .map((WorkerPerformance e) => e.name)
            .toList(),
        <String>['سعد', 'أحمد'],
      );
    });

    test('الأعلى مساهمة وحسب الاسم', () {
      final PerformanceReport report = PerformanceReport.of(<Driver>[
        driverWith('سعد', 1),
        driverWith('أحمد', 4),
        driverWith('بشار', 2),
      ]);

      expect(
        report
            .sorted(PerformanceSort.shareDesc)
            .map((WorkerPerformance e) => e.share)
            .toList(),
        <double>[4 / 7, 2 / 7, 1 / 7],
      );
      expect(
        report
            .sorted(PerformanceSort.nameAsc)
            .map((WorkerPerformance e) => e.name)
            .toList(),
        <String>['أحمد', 'بشار', 'سعد'],
      );
    });

    test('الفرز لا يُعدّل التقييمات الأصلية في التقرير', () {
      final PerformanceReport report = PerformanceReport.of(<Driver>[
        driverWith('أحمد', 5),
        driverWith('سعد', 1),
      ]);

      expect(report.sorted(PerformanceSort.ordersAsc).first.name, 'سعد');
      expect(report.entries.first.name, 'أحمد');
    });

    test('لكل طريقة ترتيب نص عربي للعرض', () {
      for (final PerformanceSort sort in PerformanceSort.values) {
        expect(sort.label, isNotEmpty);
      }
    });
  });
}
