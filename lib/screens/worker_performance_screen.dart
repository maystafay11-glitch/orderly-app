import 'package:flutter/material.dart';

import 'package:orderly_app/models/driver.dart';
import 'package:orderly_app/models/worker_performance.dart';
import 'package:orderly_app/services/driver_storage.dart';
import 'package:orderly_app/theme/app_theme.dart';
import 'package:orderly_app/utils/formatters.dart';

/// شاشة «أداء العمال»: تحليل وتقييم أداء كل عامل في الفترة الحالية.
///
/// تعرض لكل عامل عدد الطلبات التي أنجزها، وأجره المستحق، ونسبة مساهمته من
/// إجمالي طلبات المطعم، ومقارنته بمتوسط زملائه.
///
/// كما تُبرز تلقائياً **العامل المقصّر** (من أنجز أقل من 60% من متوسط الطلبات)
/// بشارة تحذير ولون مميز على بطاقته لتنبيه المدير (انظر
/// [PerformanceReport.underperformerThreshold]).
///
/// وتتيح ترتيب القائمة (الأكثر/الأقل نشاطاً، الأعلى أجوراً، الأعلى مساهمة)،
/// وتصفير إحصائيات أي عامل **بشكل مستقل** دون المساس ببقية العمال.
class WorkerPerformanceScreen extends StatefulWidget {
  const WorkerPerformanceScreen({super.key, this.showAppBar = true});

  /// هل يتم عرض شريط التطبيق العلوي (يُعطَّل عند تضمينها في التبويب السفلي).
  final bool showAppBar;

  /// عنوان الشاشة (يُستخدم في الاختبارات).
  static const String title = 'أداء العمال';

  @override
  State<WorkerPerformanceScreen> createState() =>
      WorkerPerformanceScreenState();
}

class WorkerPerformanceScreenState extends State<WorkerPerformanceScreen> {
  bool _isLoading = true;
  List<Driver> _drivers = <Driver>[];
  PerformanceReport _report = PerformanceReport.empty;
  PerformanceSort _sort = PerformanceSort.ordersDesc;

  /// إعادة تحميل بيانات أداء العمال وتحديث الشاشة فوراً.
  Future<void> reload() => _load();

  @override
  void initState() {
    super.initState();
    _load();
  }

  /// تحميل بيانات العمال ثم إعادة حساب تقرير الأداء.
  Future<void> _load() async {
    final List<Driver> drivers = await DriverStorage.loadDrivers();
    if (!mounted) {
      return;
    }
    setState(() {
      _drivers = drivers;
      _report = PerformanceReport.of(_drivers);
      _isLoading = false;
    });
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  /// تصفير إحصائيات عامل واحد فقط بعد تأكيد المدير.
  ///
  /// يُصفَّر هذا العامل وحده (تُحذف طلباته وأرقامه) ويبقى أداء بقية العمال
  /// كما هو، ثم تُحفظ القائمة وتُعاد قراءة التقرير.
  Future<void> _resetWorker(WorkerPerformance entry) async {
    final bool? confirmed = await _confirmReset(entry);
    if (confirmed != true || !mounted) {
      return;
    }

    final List<Driver> stored = await DriverStorage.loadDrivers();
    final List<Driver> updated = stored
        .map(
          (Driver driver) =>
              driver.name == entry.name ? driver.resetDay() : driver,
        )
        .toList();
    await DriverStorage.saveDrivers(updated);
    await _load();

    if (!mounted) {
      return;
    }
    _showMessage('تم تصفير إحصائيات العامل ${entry.name}.');
  }

  /// حوار تأكيد التصفير المستقل لعامل واحد.
  Future<bool?> _confirmReset(WorkerPerformance entry) {
    final TextTheme text = Theme.of(context).textTheme;

    return showDialog<bool>(
      context: context,
      builder: (BuildContext dialogContext) => AlertDialog(
        title: const Text('تصفير إحصائيات العامل'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              'سيتم تصفير أرقام العامل «${entry.name}» فقط '
              'دون بقية العمال:',
              style: text.bodyMedium?.copyWith(height: 1.6),
            ),
            const SizedBox(height: 12),
            _ResetRow(
              label: 'عدد الطلبات',
              value: formatNumber(entry.ordersCount),
            ),
            _ResetRow(
              label: 'إجمالي المبالغ',
              value: formatAmount(entry.totalAmount),
            ),
            _ResetRow(
              label: 'الأجرة المستحقة',
              value: formatAmount(entry.wage),
            ),
          ],
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('إلغاء'),
          ),
          FilledButton.icon(
            key: const ValueKey<String>('confirm-worker-reset-button'),
            style: FilledButton.styleFrom(backgroundColor: AppColors.warning),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            icon: const Icon(Icons.restart_alt, size: 18),
            label: const Text('تصفير'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: widget.showAppBar
          ? AppBar(
              title: const Text(WorkerPerformanceScreen.title),
              actions: <Widget>[
                IconButton(
                  key: const ValueKey<String>('performance-appbar-refresh'),
                  tooltip: 'تحديث البيانات',
                  icon: const Icon(Icons.refresh_rounded),
                  onPressed: _load,
                ),
              ],
            )
          : null,
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_report.isEmpty) {
      return RefreshIndicator(
        onRefresh: _load,
        color: AppColors.primary,
        child: _EmptyPerformance(onRefresh: _load),
      );
    }

    final List<WorkerPerformance> workers = _report.sorted(_sort);

    return RefreshIndicator(
      onRefresh: _load,
      color: AppColors.primary,
      child: ListView(
        key: const ValueKey<String>('worker-performance-list'),
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
        children: <Widget>[
          _ReportSummary(report: _report, onRefresh: _load),
          if (_report.hasUnderperformers) ...<Widget>[
            const SizedBox(height: 14),
            _UnderperformerBanner(report: _report),
          ],
          const SizedBox(height: 16),
          _SortBar(
            selected: _sort,
            onChanged: (PerformanceSort sort) => setState(() => _sort = sort),
          ),
          const SizedBox(height: 12),
          for (final WorkerPerformance worker in workers) ...<Widget>[
            _WorkerPerformanceCard(
              entry: worker,
              onReset: () => _resetWorker(worker),
            ),
            const SizedBox(height: 12),
          ],
        ],
      ),
    );
  }
}

/// حالة عدم وجود عمال بعد.
class _EmptyPerformance extends StatelessWidget {
  const _EmptyPerformance({this.onRefresh});

  final VoidCallback? onRefresh;

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;

    return Center(
      key: const ValueKey<String>('performance-empty'),
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.10),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.insights_outlined,
                size: 44,
                color: AppColors.primary,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'لا يوجد عمال لتحليل أدائهم بعد',
              textAlign: TextAlign.center,
              style: text.titleSmall?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              'أضف عمالاً من الشاشة الرئيسية وسجّل طلباتهم، '
              'لتظهر هنا إحصائيات أداء كل عامل بدقة.',
              textAlign: TextAlign.center,
              style: text.bodySmall?.copyWith(height: 1.6),
            ),
            const SizedBox(height: 20),
            if (onRefresh != null)
              ElevatedButton.icon(
                key: const ValueKey<String>('performance-refresh-button'),
                onPressed: onRefresh,
                icon: const Icon(Icons.refresh_rounded, size: 18),
                label: const Text('تحديث بيانات الأداء'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 12,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// بطاقة ملخص التقرير: عدد العمال والطلبات والمتوسط وإجمالي الأجور.
class _ReportSummary extends StatelessWidget {
  const _ReportSummary({required this.report, this.onRefresh});

  final PerformanceReport report;
  final VoidCallback? onRefresh;

  /// عرض المتوسط: بلا كسور إن كان صحيحاً، وبخانة عشرية واحدة إن كان كسرياً.
  static String formatAverage(double value) => value == value.roundToDouble()
      ? formatNumber(value)
      : value.toStringAsFixed(1);

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                const Icon(
                  Icons.leaderboard_outlined,
                  size: 20,
                  color: AppColors.primary,
                ),
                const SizedBox(width: 8),
                Expanded(child: Text('ملخص الأداء', style: text.titleSmall)),
                if (onRefresh != null)
                  IconButton(
                    key: const ValueKey<String>('performance-summary-refresh'),
                    icon: const Icon(Icons.refresh_rounded, size: 20),
                    tooltip: 'تحديث بيانات الأداء',
                    onPressed: onRefresh,
                  ),
              ],
            ),
            const SizedBox(height: 14),
            Row(
              children: <Widget>[
                _SummaryTile(
                  label: 'عدد العمال',
                  value: formatNumber(report.workersCount),
                  valueKey: const ValueKey<String>('report-workers-count'),
                ),
                _SummaryTile(
                  label: 'إجمالي الطلبات',
                  value: formatNumber(report.totalOrders),
                  valueKey: const ValueKey<String>('report-total-orders'),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: <Widget>[
                _SummaryTile(
                  label: 'متوسط الطلبات',
                  value: formatAverage(report.averageOrders),
                  valueKey: const ValueKey<String>('report-average-orders'),
                ),
                _SummaryTile(
                  label: 'إجمالي الأجور',
                  value: formatAmount(report.totalWage),
                  valueKey: const ValueKey<String>('report-total-wage'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// خانة واحدة داخل ملخص الأداء (عنوان + قيمة).
class _SummaryTile extends StatelessWidget {
  const _SummaryTile({
    required this.label,
    required this.value,
    required this.valueKey,
  });

  final String label;
  final String value;
  final Key valueKey;

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;

    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(label, style: text.bodySmall),
          const SizedBox(height: 4),
          Text(
            value,
            key: valueKey,
            style: text.titleSmall?.copyWith(color: AppColors.primary),
          ),
        ],
      ),
    );
  }
}

/// لافتة تنبيه بارزة تُظهر العمال ذوي الأداء المنخفض مقارنة بالمتوسط.
class _UnderperformerBanner extends StatelessWidget {
  const _UnderperformerBanner({required this.report});

  final PerformanceReport report;

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    final List<WorkerPerformance> low = report.underperformers;
    final String names = low
        .map((WorkerPerformance entry) => entry.name)
        .join('، ');

    return Container(
      key: const ValueKey<String>('underperformer-banner'),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.warningSurface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.warning.withValues(alpha: 0.45)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const Icon(
            Icons.warning_amber_rounded,
            color: AppColors.warning,
            size: 22,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  'تنبيه: ${formatNumber(low.length)} عامل بحاجة إلى متابعة',
                  key: const ValueKey<String>('underperformer-banner-title'),
                  style: text.titleSmall?.copyWith(color: AppColors.warning),
                ),
                const SizedBox(height: 6),
                Text(
                  'أداؤهم أقل من متوسط الفريق: $names',
                  style: text.bodySmall?.copyWith(height: 1.6),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// شريط أزرار ترتيب القائمة (الأكثر نشاطاً، الأقل، الأعلى أجوراً…).
class _SortBar extends StatelessWidget {
  const _SortBar({required this.selected, required this.onChanged});

  final PerformanceSort selected;
  final ValueChanged<PerformanceSort> onChanged;

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text('ترتيب حسب', style: text.bodySmall),
        const SizedBox(height: 8),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: <Widget>[
              for (final PerformanceSort sort
                  in PerformanceSort.values) ...<Widget>[
                ChoiceChip(
                  key: ValueKey<String>('sort-${sort.name}'),
                  label: Text(sort.label),
                  selected: sort == selected,
                  showCheckmark: false,
                  onSelected: (_) => onChanged(sort),
                  selectedColor: AppColors.primary,
                  backgroundColor: AppColors.surface,
                  side: BorderSide(
                    color: sort == selected
                        ? AppColors.primary
                        : AppColors.border,
                  ),
                  labelStyle: text.bodySmall?.copyWith(
                    color: sort == selected
                        ? Colors.white
                        : AppColors.textPrimary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(width: 8),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

/// بطاقة أداء عامل واحد: الترتيب، الإحصائيات، نسبة المساهمة، وزر التصفير.
class _WorkerPerformanceCard extends StatelessWidget {
  const _WorkerPerformanceCard({required this.entry, required this.onReset});

  final WorkerPerformance entry;
  final VoidCallback onReset;

  /// وصف مقارنة العامل بمتوسط زملائه.
  static String comparisonLabel(WorkerPerformance entry) {
    if (entry.ordersCount == 0) {
      return 'لا توجد طلبات مسجّلة بعد';
    }
    if (entry.isAboveAverage) {
      final int percent = ((entry.averageRatio - 1) * 100).round();
      return 'أعلى من المتوسط بـ $percent%';
    }
    if (entry.averageRatio < 1) {
      return 'أقل من المتوسط بـ ${entry.belowAveragePercent}%';
    }
    return 'مطابق لمتوسط الفريق';
  }

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    final bool isLow = entry.isUnderperformer;

    return Card(
      key: ValueKey<String>('worker-card-${entry.name}'),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(
          color: isLow ? AppColors.warning : AppColors.border,
          width: isLow ? 1.6 : 1,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                _RankBadge(
                  rank: entry.activityRank,
                  isTop: entry.activityRank == 1 && entry.ordersCount > 0,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(entry.name, style: text.titleSmall),
                      const SizedBox(height: 3),
                      Text(
                        comparisonLabel(entry),
                        key: ValueKey<String>(
                          'worker-comparison-${entry.name}',
                        ),
                        style: text.bodySmall?.copyWith(
                          color: isLow
                              ? AppColors.warning
                              : AppColors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
                if (isLow) _UnderperformerBadge(name: entry.name),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: <Widget>[
                _MetricBox(
                  label: 'عدد الطلبات',
                  value: formatNumber(entry.ordersCount),
                  valueKey: ValueKey<String>('worker-orders-${entry.name}'),
                ),
                const SizedBox(width: 10),
                _MetricBox(
                  label: 'الأجرة المستحقة',
                  value: formatAmount(entry.wage),
                  valueKey: ValueKey<String>('worker-wage-${entry.name}'),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: <Widget>[
                Expanded(child: Text('نسبة المساهمة', style: text.bodySmall)),
                Text(
                  '${entry.sharePercent}% من إجمالي الطلبات',
                  key: ValueKey<String>('worker-share-${entry.name}'),
                  style: text.bodySmall?.copyWith(
                    color: AppColors.textPrimary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: LinearProgressIndicator(
                key: ValueKey<String>('worker-contribution-${entry.name}'),
                value: entry.shareFraction,
                minHeight: 7,
                backgroundColor: AppColors.border,
                color: isLow ? AppColors.warning : AppColors.primary,
              ),
            ),
            const SizedBox(height: 10),
            Align(
              alignment: Alignment.centerLeft,
              child: OutlinedButton.icon(
                key: ValueKey<String>('worker-reset-${entry.name}'),
                onPressed: onReset,
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.warning,
                  backgroundColor: AppColors.warningSurface,
                  side: BorderSide(
                    color: AppColors.warning.withValues(alpha: 0.45),
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  textStyle: text.labelLarge,
                ),
                icon: const Icon(Icons.restart_alt, size: 18),
                label: const Text('تصفير إحصائياته'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// شارة تحذير بارزة تُوضَع على بطاقة العامل المقصّر.
class _UnderperformerBadge extends StatelessWidget {
  const _UnderperformerBadge({required this.name});

  final String name;

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;

    return Container(
      key: ValueKey<String>('worker-warning-$name'),
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: AppColors.warning,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          const Icon(
            Icons.warning_amber_rounded,
            size: 15,
            color: Colors.white,
          ),
          const SizedBox(width: 4),
          Text(
            'أداء منخفض',
            style: text.bodySmall?.copyWith(
              color: Colors.white,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

/// شارة ترتيب العامل حسب النشاط (#1، #2…).
class _RankBadge extends StatelessWidget {
  const _RankBadge({required this.rank, required this.isTop});

  final int rank;
  final bool isTop;

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;

    return Container(
      width: 34,
      height: 34,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: isTop ? AppColors.accent : AppColors.field,
        shape: BoxShape.circle,
        border: Border.all(color: isTop ? AppColors.accent : AppColors.border),
      ),
      child: Text(
        '#$rank',
        style: text.bodySmall?.copyWith(
          fontWeight: FontWeight.w700,
          color: isTop ? Colors.white : AppColors.textSecondary,
        ),
      ),
    );
  }
}

/// صندوق إحصائية واحدة (عنوان صغير + قيمة بارزة).
class _MetricBox extends StatelessWidget {
  const _MetricBox({
    required this.label,
    required this.value,
    required this.valueKey,
  });

  final String label;
  final String value;
  final Key valueKey;

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;

    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: AppColors.field,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(label, style: text.bodySmall),
            const SizedBox(height: 3),
            Text(
              value,
              key: valueKey,
              style: text.titleSmall?.copyWith(color: AppColors.textPrimary),
            ),
          ],
        ),
      ),
    );
  }
}

/// سطر (عنوان + قيمة) داخل حوار تأكيد تصفير عامل واحد.
class _ResetRow extends StatelessWidget {
  const _ResetRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: <Widget>[
          Expanded(child: Text(label, style: text.bodySmall)),
          const SizedBox(width: 10),
          Text(
            value,
            style: text.titleSmall?.copyWith(color: AppColors.warning),
          ),
        ],
      ),
    );
  }
}
