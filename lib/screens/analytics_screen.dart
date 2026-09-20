import 'dart:math' as math;
import 'package:flutter/material.dart';

import 'package:orderly_app/models/delivery_order.dart';
import 'package:orderly_app/models/driver.dart';
import 'package:orderly_app/models/order_payment_type.dart';
import 'package:orderly_app/models/weekly_archive.dart';
import 'package:orderly_app/services/app_settings.dart';
import 'package:orderly_app/services/driver_storage.dart';
import 'package:orderly_app/theme/app_theme.dart';
import 'package:orderly_app/utils/formatters.dart';

/// شاشة «الإحصائيات الذكية والرسوم البيانية» (Charts & Analytics Dashboard).
///
/// تعرض لوحة تحكم مرئية شاملة لأداء المطعم تحتوي على:
/// 1. بطاقات مؤشرات الأداء الرئيسية (KPIs): إجمالي المبيعات، الطلبات، صافي المطعم، وأجور العمال.
/// 2. مؤشر مقارنة المبيعات مع الأسبوع السابق ونسبة النمو / التراجع (±%).
/// 3. رسم بياني شريطي يوضح أكثر الأيام حركة ونشاطاً بناءً على عدد الطلبات ومبالغها.
/// 4. رسم بياني ونسب مئوية لتوزيع الطلبات: الكاش مقابل الماستر كارد والاستلام المباشر.
/// 5. مساهمة عمال التوصيل في المبيعات وحجم الطلبات.
class AnalyticsScreen extends StatefulWidget {
  const AnalyticsScreen({super.key, this.showAppBar = true});

  /// هل يتم عرض شريط التطبيق العلوي (يُعطَّل عند تضمينها في التبويب السفلي).
  final bool showAppBar;

  /// عنوان الشاشة الموحّد.
  static const String title = 'الإحصائيات والرسوم البيانية';

  @override
  State<AnalyticsScreen> createState() => AnalyticsScreenState();
}

class AnalyticsScreenState extends State<AnalyticsScreen> {
  bool _isLoading = true;
  List<Driver> _drivers = <Driver>[];
  List<WeeklyArchive> _archives = <WeeklyArchive>[];
  int? _selectedDayIndex;

  /// إعادة تحميل بيانات الإحصائيات فوراً.
  Future<void> reload() => _loadData();

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  /// تحميل بيانات العمال الحالية والأرشيفات السابقة.
  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    final List<Driver> drivers = await DriverStorage.loadDrivers();
    final List<WeeklyArchive> archives = await AppSettings.loadArchives();

    if (!mounted) {
      return;
    }

    setState(() {
      _drivers = drivers;
      _archives = archives;
      _isLoading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: widget.showAppBar
          ? AppBar(
              title: const Text(AnalyticsScreen.title),
              actions: <Widget>[
                IconButton(
                  tooltip: 'تحديث البيانات',
                  icon: const Icon(Icons.refresh_rounded),
                  onPressed: _loadData,
                ),
              ],
            )
          : null,
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _loadData,
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    _buildHeaderBanner(theme),
                    const SizedBox(height: 16),
                    _buildKpiOverview(theme),
                    const SizedBox(height: 16),
                    _buildWeeklyComparisonCard(theme),
                    const SizedBox(height: 16),
                    _buildDailyActivityChart(theme),
                    const SizedBox(height: 16),
                    _buildPaymentBreakdownCard(theme),
                    const SizedBox(height: 16),
                    if (_drivers.isNotEmpty) ...<Widget>[
                      _buildDriverContributionsCard(theme),
                      const SizedBox(height: 24),
                    ],
                  ],
                ),
              ),
            ),
    );
  }

  // ===========================================================================
  // 1. ترويسة الشاشة التعريفية
  // ===========================================================================
  Widget _buildHeaderBanner(ThemeData theme) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: <Color>[AppColors.primaryDark, AppColors.primary],
          begin: Alignment.topRight,
          end: Alignment.bottomLeft,
        ),
        borderRadius: BorderRadius.circular(16),
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: AppColors.primary.withValues(alpha: 0.25),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: <Widget>[
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.15),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.auto_graph_rounded,
              color: Colors.white,
              size: 28,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  'لوحة التحليل الذكي للأداء',
                  style: theme.textTheme.titleMedium?.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'ملخص بصري فوري للمبيعات، نشاط الأيام، ونسب الدفع',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: Colors.white.withValues(alpha: 0.9),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ===========================================================================
  // 2. بطاقات مؤشرات الأداء الرئيسية (KPIs Overview)
  // ===========================================================================
  Widget _buildKpiOverview(ThemeData theme) {
    final double totalSales = _drivers.fold(
      0.0,
      (double sum, Driver d) => sum + d.totalOrdersAmount,
    );
    final int totalOrders = _drivers.fold(
      0,
      (int sum, Driver d) => sum + d.ordersCount,
    );
    final double netProfit = _drivers.fold(
      0.0,
      (double sum, Driver d) => sum + d.netAmountToRestaurant,
    );
    final double totalWages = _drivers.fold(
      0.0,
      (double sum, Driver d) => sum + d.wage,
    );

    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final double itemWidth = (constraints.maxWidth - 12) / 2;
        return Wrap(
          spacing: 12,
          runSpacing: 12,
          children: <Widget>[
            SizedBox(
              width: itemWidth,
              child: _buildKpiCard(
                title: 'إجمالي المبيعات',
                value: formatAmount(totalSales),
                icon: Icons.point_of_sale_rounded,
                color: AppColors.primary,
                backgroundColor: AppColors.primary.withValues(alpha: 0.08),
                theme: theme,
              ),
            ),
            SizedBox(
              width: itemWidth,
              child: _buildKpiCard(
                title: 'عدد الطلبات',
                value: '${formatNumber(totalOrders)} طلب',
                icon: Icons.receipt_long_rounded,
                color: const Color(0xFF2563EB),
                backgroundColor: const Color(0xFF2563EB).withValues(alpha: 0.08),
                theme: theme,
              ),
            ),
            SizedBox(
              width: itemWidth,
              child: _buildKpiCard(
                title: 'صافي المطعم',
                value: formatAmount(netProfit),
                icon: Icons.account_balance_wallet_rounded,
                color: AppColors.success,
                backgroundColor: AppColors.success.withValues(alpha: 0.08),
                theme: theme,
              ),
            ),
            SizedBox(
              width: itemWidth,
              child: _buildKpiCard(
                title: 'أجور التوصيل',
                value: formatAmount(totalWages),
                icon: Icons.two_wheeler_rounded,
                color: AppColors.accent,
                backgroundColor: AppColors.accent.withValues(alpha: 0.08),
                theme: theme,
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildKpiCard({
    required String title,
    required String value,
    required IconData icon,
    required Color color,
    required Color backgroundColor,
    required ThemeData theme,
  }) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: backgroundColor,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(icon, size: 18, color: color),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  title,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: AppColors.textSecondary,
                    fontWeight: FontWeight.w600,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            value,
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w800,
              fontSize: 16,
              color: color,
            ),
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }

  // ===========================================================================
  // 3. مؤشر مقارنة المبيعات مع الأسبوع السابق
  // ===========================================================================
  Widget _buildWeeklyComparisonCard(ThemeData theme) {
    final double currentSales = _drivers.fold(
      0.0,
      (double sum, Driver d) => sum + d.totalOrdersAmount,
    );

    final WeeklyArchive? previousArchive =
        _archives.isNotEmpty ? _archives.first : null;
    final double previousSales = previousArchive?.totalAmount ?? 0.0;

    final bool hasHistory = previousArchive != null;
    final double difference = currentSales - previousSales;
    final double percentChange = (hasHistory && previousSales > 0)
        ? ((currentSales - previousSales) / previousSales) * 100
        : (currentSales > 0 ? 100.0 : 0.0);

    final bool isPositive = difference >= 0;
    final Color trendColor = isPositive ? AppColors.success : AppColors.danger;
    final IconData trendIcon =
        isPositive ? Icons.trending_up_rounded : Icons.trending_down_rounded;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.02),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(
                  Icons.compare_arrows_rounded,
                  color: AppColors.primary,
                  size: 20,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      'مقارنة المبيعات مع الأسبوع السابق',
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Text(
                      hasHistory
                          ? 'الفترة السابقة: ${formatDate(previousArchive.periodStart)} إلى ${formatDate(previousArchive.periodEnd)}'
                          : 'لا يوجد أرشيف سابق مسجّل حتى الآن',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: AppColors.textSecondary,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ),
              if (hasHistory)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: trendColor.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      Icon(trendIcon, size: 16, color: trendColor),
                      const SizedBox(width: 4),
                      Text(
                        '${isPositive ? '+' : ''}${percentChange.toStringAsFixed(1)}%',
                        style: TextStyle(
                          color: trendColor,
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
          const SizedBox(height: 16),
          // مقارنة بصرية بالأشرطة الملونة
          _buildSalesComparisonBars(
            currentSales: currentSales,
            previousSales: previousSales,
            theme: theme,
          ),
          const SizedBox(height: 14),
          // تفاصيل المبالغ والفرق
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.field,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: <Widget>[
                _buildComparisonStat(
                  label: 'الأسبوع الحالي',
                  amount: formatAmount(currentSales),
                  color: AppColors.primary,
                  theme: theme,
                ),
                Container(
                  height: 28,
                  width: 1,
                  color: AppColors.border,
                ),
                _buildComparisonStat(
                  label: 'الأسبوع السابق',
                  amount: hasHistory ? formatAmount(previousSales) : '0 د.ع',
                  color: AppColors.textSecondary,
                  theme: theme,
                ),
                Container(
                  height: 28,
                  width: 1,
                  color: AppColors.border,
                ),
                _buildComparisonStat(
                  label: isPositive ? 'فارق الزيادة' : 'فارق النقصان',
                  amount:
                      '${isPositive ? '+' : ''}${formatAmount(difference.abs())}',
                  color: trendColor,
                  theme: theme,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSalesComparisonBars({
    required double currentSales,
    required double previousSales,
    required ThemeData theme,
  }) {
    final double maxVal = math.max(currentSales, previousSales);
    final double safeMax = maxVal <= 0 ? 1.0 : maxVal;

    final double currentRatio = (currentSales / safeMax).clamp(0.05, 1.0);
    final double prevRatio = (previousSales / safeMax).clamp(0.05, 1.0);

    return Column(
      children: <Widget>[
        // شريط الأسبوع الحالي
        Row(
          children: <Widget>[
            SizedBox(
              width: 80,
              child: Text(
                'الحالي',
                style: theme.textTheme.bodySmall?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: AppColors.primary,
                ),
              ),
            ),
            Expanded(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: LinearProgressIndicator(
                  value: currentRatio,
                  minHeight: 12,
                  backgroundColor: AppColors.border,
                  valueColor: const AlwaysStoppedAnimation<Color>(AppColors.primary),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        // شريط الأسبوع السابق
        Row(
          children: <Widget>[
            SizedBox(
              width: 80,
              child: Text(
                'السابق',
                style: theme.textTheme.bodySmall?.copyWith(
                  fontWeight: FontWeight.w600,
                  color: AppColors.textSecondary,
                ),
              ),
            ),
            Expanded(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: LinearProgressIndicator(
                  value: previousSales > 0 ? prevRatio : 0.0,
                  minHeight: 12,
                  backgroundColor: AppColors.border,
                  valueColor: AlwaysStoppedAnimation<Color>(
                    AppColors.textSecondary.withValues(alpha: 0.5),
                  ),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildComparisonStat({
    required String label,
    required String amount,
    required Color color,
    required ThemeData theme,
  }) {
    return Column(
      children: <Widget>[
        Text(
          label,
          style: theme.textTheme.bodySmall?.copyWith(
            fontSize: 11,
            color: AppColors.textSecondary,
          ),
        ),
        const SizedBox(height: 3),
        Text(
          amount,
          style: theme.textTheme.bodyMedium?.copyWith(
            fontWeight: FontWeight.bold,
            color: color,
            fontSize: 12,
          ),
        ),
      ],
    );
  }

  // ===========================================================================
  // 4. رسم بياني لأكثر الأيام حركة ونشاطاً (Daily Activity Chart)
  // ===========================================================================
  Widget _buildDailyActivityChart(ThemeData theme) {
    // تجميع طلبات كل العمال
    final List<DeliveryOrder> allOrders =
        _drivers.expand((Driver d) => d.orders).toList();

    // تعريف أيام الأسبوع بترتيب البداية (السبت)
    final List<_DayActivity> days = <_DayActivity>[
      _DayActivity(dayName: 'السبت', shortName: 'سبت', weekday: DateTime.saturday),
      _DayActivity(dayName: 'الأحد', shortName: 'أحد', weekday: DateTime.sunday),
      _DayActivity(dayName: 'الإثنين', shortName: 'إثن', weekday: DateTime.monday),
      _DayActivity(dayName: 'الثلاثاء', shortName: 'ثلا', weekday: DateTime.tuesday),
      _DayActivity(dayName: 'الأربعاء', shortName: 'أرب', weekday: DateTime.wednesday),
      _DayActivity(dayName: 'الخميس', shortName: 'خمي', weekday: DateTime.thursday),
      _DayActivity(dayName: 'الجمعة', shortName: 'جمع', weekday: DateTime.friday),
    ];

    // حساب الطلبات والمبالغ لكل يوم
    for (final DeliveryOrder order in allOrders) {
      final int orderWeekday = order.addedAt.weekday;
      for (final _DayActivity day in days) {
        if (day.weekday == orderWeekday) {
          day.orderCount += 1;
          day.totalSales += order.amount;
          break;
        }
      }
    }

    // إيجاد اليوم الأكثر نشاطاً
    int maxOrders = 0;
    _DayActivity? peakDay;
    for (final _DayActivity day in days) {
      if (day.orderCount > maxOrders) {
        maxOrders = day.orderCount;
        peakDay = day;
      }
    }

    // اليوم المختار حالياً للتفاصيل
    final _DayActivity selectedDay = (_selectedDayIndex != null &&
            _selectedDayIndex! >= 0 &&
            _selectedDayIndex! < days.length)
        ? days[_selectedDayIndex!]
        : (peakDay ?? days.first);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.02),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppColors.accent.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(
                  Icons.bar_chart_rounded,
                  color: AppColors.accent,
                  size: 20,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      'أكثر الأيام نشاطاً وحركة',
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Text(
                      'توزيع الطلبات بحسب أيام الأسبوع',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: AppColors.textSecondary,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ),
              if (peakDay != null && maxOrders > 0)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: AppColors.accent.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppColors.accent.withValues(alpha: 0.4)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      const Icon(Icons.star_rounded,
                          size: 14, color: AppColors.accent),
                      const SizedBox(width: 4),
                      Text(
                        'الأعلى: ${peakDay.dayName}',
                        style: const TextStyle(
                          color: AppColors.accent,
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
          const SizedBox(height: 20),

          // الرسم البياني الشريطي
          SizedBox(
            height: 180,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: <Widget>[
                for (int i = 0; i < days.length; i++) ...<Widget>[
                  Expanded(
                    child: _buildDayBar(
                      day: days[i],
                      index: i,
                      maxOrders: maxOrders,
                      isPeak: days[i] == peakDay && maxOrders > 0,
                      isSelected: _selectedDayIndex == i ||
                          (_selectedDayIndex == null && days[i] == peakDay),
                      theme: theme,
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 14),

          // تفاصيل اليوم المحدّد
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: AppColors.field,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.border),
            ),
            child: Row(
              children: <Widget>[
                Icon(
                  Icons.calendar_today_rounded,
                  size: 16,
                  color: AppColors.primary,
                ),
                const SizedBox(width: 8),
                Text(
                  'تفاصيل يوم ${selectedDay.dayName}:',
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: AppColors.textPrimary,
                  ),
                ),
                const Spacer(),
                Text(
                  '${formatNumber(selectedDay.orderCount)} طلب',
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: AppColors.primary,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  '•  ${formatAmount(selectedDay.totalSales)}',
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: AppColors.success,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDayBar({
    required _DayActivity day,
    required int index,
    required int maxOrders,
    required bool isPeak,
    required bool isSelected,
    required ThemeData theme,
  }) {
    final double ratio = maxOrders > 0 ? (day.orderCount / maxOrders) : 0.0;
    final double barHeight = (ratio * 110).clamp(6.0, 110.0);

    final Color barColor = isPeak
        ? AppColors.accent
        : (isSelected ? AppColors.primary : AppColors.primary.withValues(alpha: 0.35));

    return InkWell(
      onTap: () {
        setState(() {
          _selectedDayIndex = index;
        });
      },
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 2),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.end,
          children: <Widget>[
            // عدد الطلبات أعلى العمود
            Text(
              day.orderCount > 0 ? formatNumber(day.orderCount) : '0',
              style: TextStyle(
                fontSize: 10,
                fontWeight: isPeak ? FontWeight.bold : FontWeight.w500,
                color: isPeak ? AppColors.accent : AppColors.textSecondary,
              ),
            ),
            const SizedBox(height: 4),

            // العمود نفسه
            AnimatedContainer(
              duration: const Duration(milliseconds: 300),
              height: barHeight,
              width: 22,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: <Color>[
                    barColor,
                    barColor.withValues(alpha: 0.7),
                  ],
                ),
                borderRadius: const BorderRadius.vertical(top: Radius.circular(6)),
                boxShadow: isPeak
                    ? <BoxShadow>[
                        BoxShadow(
                          color: AppColors.accent.withValues(alpha: 0.3),
                          blurRadius: 6,
                          offset: const Offset(0, 2),
                        ),
                      ]
                    : null,
              ),
            ),
            const SizedBox(height: 6),

            // اسم اليوم
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
              decoration: isSelected
                  ? BoxDecoration(
                      color: AppColors.primary.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(4),
                    )
                  : null,
              child: Text(
                day.shortName,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                  color: isSelected ? AppColors.primary : AppColors.textSecondary,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ===========================================================================
  // 5. نسبة مئوية ورسم توضيحي: الكاش مقابل الماستر كارد والاستلام المباشر
  // ===========================================================================
  Widget _buildPaymentBreakdownCard(ThemeData theme) {
    final List<DeliveryOrder> allOrders =
        _drivers.expand((Driver d) => d.orders).toList();

    // حساب الطلبات لكل نوع مع دعم الطلبات المرحّلة (legacy)
    int cashCount = 0;
    double cashAmount = 0.0;

    int masterCardCount = 0;
    double masterCardAmount = 0.0;

    int directReceiveCount = 0;
    double directReceiveAmount = 0.0;

    int otherSpecialCount = 0;
    double otherSpecialAmount = 0.0;

    for (final DeliveryOrder order in allOrders) {
      switch (order.paymentType) {
        case OrderPaymentType.cash:
          cashCount++;
          cashAmount += order.amount;
        case OrderPaymentType.masterCard:
          masterCardCount++;
          masterCardAmount += order.amount;
        case OrderPaymentType.directReceive:
          directReceiveCount++;
          directReceiveAmount += order.amount;
        case OrderPaymentType.otherSpecial:
          otherSpecialCount++;
          otherSpecialAmount += order.amount;
      }
    }

    // إضافة الطلبات القديمة الموروثة ككاش
    for (final Driver d in _drivers) {
      cashCount += d.legacyOrdersCount;
      cashAmount += d.legacyOrdersAmount;
    }

    final int totalCount =
        cashCount + masterCardCount + directReceiveCount + otherSpecialCount;
    final double safeTotal = totalCount <= 0 ? 1.0 : totalCount.toDouble();

    final double cashPercent = (cashCount / safeTotal) * 100;
    final double masterCardPercent = (masterCardCount / safeTotal) * 100;
    final double directPercent = (directReceiveCount / safeTotal) * 100;
    final double otherSpecialPercent = (otherSpecialCount / safeTotal) * 100;

    // تجميع الاستلام المباشر والحالات الخاصة للعرض
    final int directAndSpecialCount = directReceiveCount + otherSpecialCount;
    final double directAndSpecialAmount =
        directReceiveAmount + otherSpecialAmount;
    final double directAndSpecialPercent =
        directPercent + otherSpecialPercent;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.02),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: const Color(0xFF2563EB).withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(
                  Icons.donut_large_rounded,
                  color: Color(0xFF2563EB),
                  size: 20,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      'نسب طرق الدفع (كاش مقابل ماستر كارد)',
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Text(
                      'توزيع الطلبات حسب وسيلة السداد وأثرها على أجر العامل',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: AppColors.textSecondary,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),

          // الرسم الدائري (Donut Chart) + شريط المقارنة
          Row(
            children: <Widget>[
              // الرسم الدائري المخصص
              SizedBox(
                width: 110,
                height: 110,
                child: CustomPaint(
                  painter: _PaymentDonutChartPainter(
                    cashRatio: cashPercent / 100,
                    masterCardRatio: masterCardPercent / 100,
                    directRatio: directAndSpecialPercent / 100,
                  ),
                  child: Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        Text(
                          '${cashPercent.toStringAsFixed(0)}%',
                          style: const TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w900,
                            color: AppColors.success,
                          ),
                        ),
                        const Text(
                          'كاش',
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 16),

              // الأرقام والنسب بجانب الرسم الدائري
              Expanded(
                child: Column(
                  children: <Widget>[
                    _buildPaymentTypeRow(
                      title: 'نقداً (كاش)',
                      badge: 'أجرة كاملة',
                      count: cashCount,
                      amount: cashAmount,
                      percentage: cashPercent,
                      color: AppColors.success,
                      icon: Icons.payments_outlined,
                      theme: theme,
                    ),
                    const Divider(height: 14),
                    _buildPaymentTypeRow(
                      title: 'ماستر كارد',
                      badge: 'بدون أجر',
                      count: masterCardCount,
                      amount: masterCardAmount,
                      percentage: masterCardPercent,
                      color: const Color(0xFF2563EB),
                      icon: Icons.credit_card_outlined,
                      theme: theme,
                    ),
                    if (directAndSpecialCount > 0) ...<Widget>[
                      const Divider(height: 14),
                      _buildPaymentTypeRow(
                        title: 'استلام مباشر / خاص',
                        badge: 'أجر صفر',
                        count: directAndSpecialCount,
                        amount: directAndSpecialAmount,
                        percentage: directAndSpecialPercent,
                        color: const Color(0xFF7C3AED),
                        icon: Icons.storefront_outlined,
                        theme: theme,
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // شريط مقسم خطي (Segmented Bar)
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: SizedBox(
              height: 14,
              child: Row(
                children: <Widget>[
                  if (cashPercent > 0)
                    Expanded(
                      flex: (cashPercent * 10).round(),
                      child: Container(color: AppColors.success),
                    ),
                  if (masterCardPercent > 0)
                    Expanded(
                      flex: (masterCardPercent * 10).round(),
                      child: Container(color: const Color(0xFF2563EB)),
                    ),
                  if (directAndSpecialPercent > 0)
                    Expanded(
                      flex: (directAndSpecialPercent * 10).round(),
                      child: Container(color: const Color(0xFF7C3AED)),
                    ),
                  if (totalCount == 0)
                    Expanded(
                      child: Container(color: AppColors.border),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPaymentTypeRow({
    required String title,
    required String badge,
    required int count,
    required double amount,
    required double percentage,
    required Color color,
    required IconData icon,
    required ThemeData theme,
  }) {
    return Row(
      children: <Widget>[
        Container(
          padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Icon(icon, size: 14, color: color),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Row(
                children: <Widget>[
                  Text(
                    title,
                    style: theme.textTheme.bodySmall?.copyWith(
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      badge,
                      style: TextStyle(
                        fontSize: 9,
                        fontWeight: FontWeight.w600,
                        color: color,
                      ),
                    ),
                  ),
                ],
              ),
              Text(
                '${formatNumber(count)} طلب (${percentage.toStringAsFixed(1)}%)',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: AppColors.textSecondary,
                  fontSize: 11,
                ),
              ),
            ],
          ),
        ),
        Text(
          formatAmount(amount),
          style: theme.textTheme.bodySmall?.copyWith(
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
      ],
    );
  }

  // ===========================================================================
  // 6. مساهمة عمال التوصيل في المبيعات والطلبات
  // ===========================================================================
  Widget _buildDriverContributionsCard(ThemeData theme) {
    final int totalOrders = _drivers.fold(
      0,
      (int sum, Driver d) => sum + d.ordersCount,
    );
    final double safeTotal = totalOrders <= 0 ? 1.0 : totalOrders.toDouble();

    // ترتيب العمال تنازلياً حسب عدد الطلبات
    final List<Driver> sorted = List<Driver>.from(_drivers)
      ..sort((Driver a, Driver b) => b.ordersCount.compareTo(a.ordersCount));

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.02),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(
                  Icons.groups_rounded,
                  color: AppColors.primary,
                  size: 20,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'مساهمة العمال في حجم الطلبات',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          for (final Driver driver in sorted) ...<Widget>[
            _buildDriverShareRow(
              driver: driver,
              totalOrders: safeTotal,
              theme: theme,
            ),
            const SizedBox(height: 10),
          ],
        ],
      ),
    );
  }

  Widget _buildDriverShareRow({
    required Driver driver,
    required double totalOrders,
    required ThemeData theme,
  }) {
    final double sharePercent = (driver.ordersCount / totalOrders) * 100;
    final double ratio = (driver.ordersCount / totalOrders).clamp(0.0, 1.0);

    return Column(
      children: <Widget>[
        Row(
          children: <Widget>[
            Expanded(
              child: Text(
                driver.name,
                style: theme.textTheme.bodySmall?.copyWith(
                  fontWeight: FontWeight.w600,
                  fontSize: 12,
                ),
              ),
            ),
            Text(
              '${formatNumber(driver.ordersCount)} طلب  (${sharePercent.toStringAsFixed(1)}%)',
              style: theme.textTheme.bodySmall?.copyWith(
                fontWeight: FontWeight.bold,
                color: AppColors.textSecondary,
                fontSize: 11,
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: ratio,
            minHeight: 6,
            backgroundColor: AppColors.field,
            valueColor: const AlwaysStoppedAnimation<Color>(AppColors.primary),
          ),
        ),
      ],
    );
  }
}

// =============================================================================
// مساعدات الرسم والتصنيف
// =============================================================================

class _DayActivity {
  _DayActivity({
    required this.dayName,
    required this.shortName,
    required this.weekday,
  })  : orderCount = 0,
        totalSales = 0.0;

  final String dayName;
  final String shortName;
  final int weekday;
  int orderCount;
  double totalSales;
}

/// رسّام مخصص لرسم المخطط الدائري المجوف (Donut Chart) لطرق الدفع.
class _PaymentDonutChartPainter extends CustomPainter {
  const _PaymentDonutChartPainter({
    required this.cashRatio,
    required this.masterCardRatio,
    required this.directRatio,
  });

  final double cashRatio;
  final double masterCardRatio;
  final double directRatio;

  @override
  void paint(Canvas canvas, Size size) {
    final Offset center = Offset(size.width / 2, size.height / 2);
    final double radius = (math.min(size.width, size.height) / 2) - 8;
    const double strokeWidth = 14;

    final Paint backgroundPaint = Paint()
      ..color = AppColors.border
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth;

    canvas.drawCircle(center, radius, backgroundPaint);

    final double totalRatio = cashRatio + masterCardRatio + directRatio;
    if (totalRatio <= 0) {
      return;
    }

    double startAngle = -math.pi / 2;

    void drawSegment(double ratio, Color color) {
      if (ratio <= 0) return;
      final double sweepAngle = ratio * 2 * math.pi;
      final Paint paint = Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth
        ..strokeCap = StrokeCap.round;

      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        startAngle,
        sweepAngle,
        false,
        paint,
      );
      startAngle += sweepAngle;
    }

    drawSegment(cashRatio, AppColors.success);
    drawSegment(masterCardRatio, const Color(0xFF2563EB));
    drawSegment(directRatio, const Color(0xFF7C3AED));
  }

  @override
  bool shouldRepaint(covariant _PaymentDonutChartPainter oldDelegate) {
    return oldDelegate.cashRatio != cashRatio ||
        oldDelegate.masterCardRatio != masterCardRatio ||
        oldDelegate.directRatio != directRatio;
  }
}
