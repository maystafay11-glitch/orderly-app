import 'package:orderly_app/models/driver.dart';

/// طرق ترتيب قائمة أداء العمال في الواجهة.
///
/// يحمل كل خيار نصّه العربي الجاهز للعرض، ويُوفّر مُقارِناً يُستخدم في الفرز.
enum PerformanceSort {
  /// الأعلى عدداً في الطلبات (الأكثر نشاطاً).
  ordersDesc('الأكثر نشاطاً'),

  /// الأقل عدداً في الطلبات (الأقل نشاطاً).
  ordersAsc('الأقل نشاطاً'),

  /// الأعلى أجوراً مستحقة.
  wageDesc('الأعلى أجوراً'),

  /// الأعلى نسبة مساهمة من إجمالي الطلبات.
  shareDesc('الأعلى مساهمة'),

  /// حسب الاسم أبجدياً.
  nameAsc('الاسم');

  const PerformanceSort(this.label);

  /// النص العربي المعروض على زر الترتيب.
  final String label;

  /// المُقارِن المستخدم لترتيب القائمة، مع اعتماد الاسم كفاصل للتعادل
  /// حتى يكون الترتيب ثابتاً لا يتغيّر عشوائياً بين البناءات.
  int compare(WorkerPerformance a, WorkerPerformance b) {
    switch (this) {
      case PerformanceSort.ordersDesc:
        final int byOrders = b.ordersCount.compareTo(a.ordersCount);
        return byOrders != 0 ? byOrders : a.name.compareTo(b.name);
      case PerformanceSort.ordersAsc:
        final int byOrders = a.ordersCount.compareTo(b.ordersCount);
        return byOrders != 0 ? byOrders : a.name.compareTo(b.name);
      case PerformanceSort.wageDesc:
        final int byWage = b.wage.compareTo(a.wage);
        return byWage != 0 ? byWage : a.name.compareTo(b.name);
      case PerformanceSort.shareDesc:
        final int byShare = b.share.compareTo(a.share);
        return byShare != 0 ? byShare : a.name.compareTo(b.name);
      case PerformanceSort.nameAsc:
        return a.name.compareTo(b.name);
    }
  }
}

/// تقييم أداء عامل واحد مستخرَج من بياناته المسجَّلة.
class WorkerPerformance {
  const WorkerPerformance({
    required this.name,
    required this.ordersCount,
    required this.totalAmount,
    required this.wage,
    required this.share,
    required this.averageRatio,
    required this.activityRank,
    required this.isUnderperformer,
  });

  /// اسم العامل.
  final String name;

  /// عدد الطلبات التي أنجزها في الفترة الحالية.
  final int ordersCount;

  /// إجمالي مبالغ طلباته بالدينار.
  final double totalAmount;

  /// الأجرة المستحقة له عن الفترة الحالية.
  final double wage;

  /// نسبة مساهمته من إجمالي طلبات المطعم (0.0 .. 1.0).
  final double share;

  /// نسبة عدد طلباته إلى متوسط العمال (1.0 تعني مطابق للمتوسط).
  final double averageRatio;

  /// ترتيبه حسب النشاط (1 = الأعلى طلبات)، ولا يتأثر بطريقة عرض القائمة.
  final int activityRank;

  /// هل يُعدّ أداؤه منخفضاً بشكل ملحوظ مقارنة بالمتوسط؟
  final bool isUnderperformer;

  /// نسبة المساهمة مُقرَّبة للعرض: `42` تعني 42%.
  int get sharePercent => (share * 100).round();

  /// نسبة المساهمة محصورة بين 0 و1 (آمنة لشريط التقدّم).
  double get shareFraction => share.clamp(0.0, 1.0);

  /// هل لم يُسجّل أي طلب؟
  bool get isEmpty => ordersCount == 0;

  /// مقدار انخفاضه عن المتوسط بنقاط مئوية (تُستخدم في نص التنبيه).
  int get belowAveragePercent {
    final double percent = (1 - averageRatio) * 100;
    return percent < 0 ? 0 : percent.round();
  }

  /// هل أداؤه أعلى من متوسط زملائه؟
  bool get isAboveAverage => averageRatio > 1;

  @override
  String toString() =>
      'WorkerPerformance(name: $name, ordersCount: $ordersCount, '
      'wage: $wage, share: $sharePercent%, rank: $activityRank, '
      'isUnderperformer: $isUnderperformer)';
}

/// تقرير أداء كل العمال: الإجماليات ومتوسط الطلبات وقائمة العمال المقصّرين.
class PerformanceReport {
  const PerformanceReport._({
    required this.entries,
    required this.totalOrders,
    required this.totalAmount,
    required this.totalWage,
    required this.averageOrders,
  });

  /// حدّ اعتبار العامل مقصّراً: أدنى من هذه النسبة من المتوسط.
  ///
  /// القيمة 0.6 تعني أن من أنجز أقل من 60% من متوسط زملائه يُنبَّه عليه،
  /// وهو حدّ متوازن لا يُشعل التنبيه بسبب فروق صغيرة.
  static const double underperformerThreshold = 0.6;

  /// أدنى عدد عمال مطلوب لتشغيل آلية المقارنة (المقارنة تحتاج زميلاً واحداً).
  static const int minWorkersForComparison = 2;

  /// تقرير فارغ (لا يوجد عمال بعد).
  static const PerformanceReport empty = PerformanceReport._(
    entries: <WorkerPerformance>[],
    totalOrders: 0,
    totalAmount: 0,
    totalWage: 0,
    averageOrders: 0,
  );

  /// بناء التقرير من قائمة العمال المحفوظين.
  ///
  /// [threshold] نسبة من المتوسط يُعتبر ما دونها أداءً منخفضاً؛ وأي قيمة
  /// خارج المجال (0, 1] تُستبدل بالقيمة الافتراضية [underperformerThreshold]
  /// حمايةً من مدخلات غير صالحة.
  factory PerformanceReport.of(
    List<Driver> drivers, {
    double threshold = underperformerThreshold,
  }) {
    final double safeThreshold = (threshold > 0 && threshold <= 1)
        ? threshold
        : underperformerThreshold;

    if (drivers.isEmpty) {
      return empty;
    }

    final int totalOrders = drivers.fold<int>(
      0,
      (int sum, Driver driver) => sum + driver.ordersCount,
    );
    final double totalAmount = drivers.fold<double>(
      0,
      (double sum, Driver driver) => sum + driver.totalOrdersAmount,
    );
    final double totalWage = drivers.fold<double>(
      0,
      (double sum, Driver driver) => sum + driver.wage,
    );
    final double averageOrders = totalOrders / drivers.length;

    // الترتيب حسب النشاط (عدد الطلبات تنازلياً) مع الاسم كفاصل للتعادل.
    final List<Driver> ranked = List<Driver>.of(drivers)
      ..sort((Driver a, Driver b) {
        final int byOrders = b.ordersCount.compareTo(a.ordersCount);
        return byOrders != 0 ? byOrders : a.name.compareTo(b.name);
      });

    final bool canCompare =
        drivers.length >= minWorkersForComparison && averageOrders > 0;
    final double lowLimit = averageOrders * safeThreshold;

    final List<WorkerPerformance> entries = <WorkerPerformance>[];
    for (int i = 0; i < ranked.length; i++) {
      final Driver driver = ranked[i];
      entries.add(
        WorkerPerformance(
          name: driver.name,
          ordersCount: driver.ordersCount,
          totalAmount: driver.totalOrdersAmount,
          wage: driver.wage,
          share: totalOrders == 0 ? 0 : driver.ordersCount / totalOrders,
          averageRatio: averageOrders == 0
              ? 1
              : driver.ordersCount / averageOrders,
          activityRank: i + 1,
          isUnderperformer: canCompare && driver.ordersCount < lowLimit,
        ),
      );
    }

    return PerformanceReport._(
      entries: List<WorkerPerformance>.unmodifiable(entries),
      totalOrders: totalOrders,
      totalAmount: totalAmount,
      totalWage: totalWage,
      averageOrders: averageOrders,
    );
  }

  /// تقييم كل العمال مرتّبين حسب النشاط (الأعلى أولاً).
  final List<WorkerPerformance> entries;

  /// إجمالي الطلبات المنفّذة من كل العمال.
  final int totalOrders;

  /// إجمالي مبالغ الطلبات كلها بالدينار.
  final double totalAmount;

  /// إجمالي الأجور المستحقة لكل العمال.
  final double totalWage;

  /// متوسط عدد الطلبات لكل عامل.
  final double averageOrders;

  /// عدد العمال المشمولين في التقرير.
  int get workersCount => entries.length;

  /// هل لا يوجد عمال بعد؟
  bool get isEmpty => entries.isEmpty;

  /// العمال ذوو الأداء المنخفض مقارنة بالمتوسط.
  List<WorkerPerformance> get underperformers => entries
      .where((WorkerPerformance entry) => entry.isUnderperformer)
      .toList();

  /// هل يوجد عامل واحد على الأقل يحتاج متابعة؟
  bool get hasUnderperformers => underperformers.isNotEmpty;

  /// أقوى عامل من حيث عدد الطلبات (أول الترتيب)، أو `null` بلا عمال.
  WorkerPerformance? get topPerformer => entries.isEmpty ? null : entries.first;

  /// نسخة مرتّبة حسب [sort] للعرض في الواجهة (لا تُعدّل التقرير نفسه).
  List<WorkerPerformance> sorted(PerformanceSort sort) =>
      List<WorkerPerformance>.of(entries)..sort(sort.compare);

  @override
  String toString() =>
      'PerformanceReport(workersCount: $workersCount, '
      'totalOrders: $totalOrders, averageOrders: $averageOrders, '
      'underperformers: ${underperformers.length})';
}
