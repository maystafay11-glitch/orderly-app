/// شاشة أرشيف الأسابيع السابقة مع إشعار أسبوعي وزر أرشفة الأسبوع.
///
/// * تعرض جميع الأرشيفات المحفوظة (عدد الطلبات، الأجور، صافي المطعم، التواريخ).
/// * يُظهر إشعاراً أسبوعياً تلقائياً عندما ينقضي أكثر من 7 أيام على آخر أرشفة.
/// * يتيح أرشفة الأسبوع الحالي وتصفير الحسابات مع حفظ الملخص محلياً.
library;

import 'package:flutter/material.dart';

import 'package:orderly_app/models/delivery_order.dart';
import 'package:orderly_app/models/driver.dart';
import 'package:orderly_app/models/weekly_archive.dart';
import 'package:orderly_app/services/app_settings.dart';
import 'package:orderly_app/services/driver_storage.dart';
import 'package:orderly_app/theme/app_theme.dart';
import 'package:orderly_app/utils/formatters.dart';
import 'package:orderly_app/utils/whatsapp.dart';
import 'package:orderly_app/widgets/stat_tile.dart';

/// إجماليات الأسبوع من قائمة العمال.
class WeeklyTotals {
  WeeklyTotals({
    required this.drivers,
    required this.orders,
    required this.amount,
    required this.wage,
    required this.net,
  });

  factory WeeklyTotals.from(
    List<Driver> drivers, {
    List<DeliveryOrder> generalOrders = const <DeliveryOrder>[],
  }) {
    int orders = 0;
    double amount = 0;
    double wage = 0;
    for (final Driver driver in drivers) {
      orders += driver.ordersCount;
      amount += driver.totalOrdersAmount;
      wage += driver.wage;
    }
    final double generalAmount = generalOrders.fold<double>(
      0,
      (double sum, DeliveryOrder o) => sum + o.amount,
    );
    final double totalSales = amount + generalAmount;
    return WeeklyTotals(
      drivers: drivers.length,
      orders: orders + generalOrders.length,
      amount: totalSales,
      wage: wage,
      net: totalSales,
    );
  }

  final int drivers;
  final int orders;
  final double amount;
  final double wage;
  final double net;
}

class WeeklyArchiveScreen extends StatefulWidget {
  const WeeklyArchiveScreen({super.key});

  /// عنوان الشاشة (للاختبارات).
  static const String title = 'الملخص الأسبوعي';

  @override
  State<WeeklyArchiveScreen> createState() => _WeeklyArchiveScreenState();
}

class _WeeklyArchiveScreenState extends State<WeeklyArchiveScreen> {
  List<WeeklyArchive> _archives = <WeeklyArchive>[];
  List<Driver> _drivers = <Driver>[];
  bool _isLoading = true;
  bool _showNotice = false;

  @override
  void initState() {
    super.initState();
    _init();
  }

  /// تحميل الأرشيف + فحص ما إذا كان يجب إظهار التنبيه الأسبوعي.
  Future<void> _init() async {
    await _loadArchives();
    _drivers = await DriverStorage.loadDrivers();
    final bool shouldNotice = await _shouldShowWeeklyNotice();
    if (!mounted) return;
    setState(() => _showNotice = shouldNotice);
    if (shouldNotice) {
      await AppSettings.setLastWeeklyNotice(DateTime.now());
    }
  }

  Future<void> _loadArchives() async {
    final List<WeeklyArchive> archives = await AppSettings.loadArchives();
    if (!mounted) return;
    setState(() {
      _archives = archives;
      _isLoading = false;
    });
  }

  /// التنبيه يظهر مرة واحدة كل 7 أيام على الأقل.
  static Future<bool> _shouldShowWeeklyNotice() async {
    final DateTime now = DateTime.now();
    final DateTime last = await AppSettings.getLastWeeklyNotice();
    return now.difference(last) >= const Duration(days: 7);
  }

  /// أرشفة الأسبوع وتصفير الحسابات.
  Future<void> _archiveWeek() async {
    final List<Driver> drivers = await DriverStorage.loadDrivers();
    final List<DeliveryOrder> generalOrders =
        await DriverStorage.loadGeneralOrders();
    final WeeklyTotals totals =
        WeeklyTotals.from(drivers, generalOrders: generalOrders);
    final DateTime now = DateTime.now();

    await AppSettings.archiveWeek(
      totalOrders: totals.orders,
      totalAmount: totals.amount,
      totalWage: totals.wage,
      netAmount: totals.net,
      periodStart: now.subtract(const Duration(days: 6)),
      periodEnd: now,
    );

    // تصفير الحسابات اليومية بعد الأرشاف.
    final List<Driver> cleared =
        drivers.map((Driver driver) => driver.resetDay()).toList();
    await DriverStorage.saveDrivers(cleared);
    await DriverStorage.clearGeneralOrders();

    if (!mounted) return;
    _drivers = cleared;
    await _loadArchives();
    _showMessage('تم أرشفة الملخص الأسبوعي وتصفير الحسابات.');
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(WeeklyArchiveScreen.title),
        leading: IconButton(
          key: const ValueKey<String>('archive-back'),
          icon: const Icon(Icons.arrow_back),
          tooltip: 'رجوع',
          onPressed: () => Navigator.of(context).pop(),
        ),
        actions: <Widget>[
          TextButton.icon(
            key: const ValueKey<String>('archive-week-button'),
            onPressed: _archiveWeek,
            icon: const Icon(Icons.archive_rounded, size: 18),
            label: const Text('أرشفة الأسبوع'),
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: <Widget>[
                if (_showNotice)
                  _WeeklyNoticeCard(
                    totals: _currentTotals,
                    onSendWhatsApp: _shareCurrentWeek,
                  ),
                if (_archives.isEmpty)
                  const Expanded(child: _EmptyArchiveView())
                else
                  Expanded(
                    child: ListView.separated(
                      padding:
                          const EdgeInsets.fromLTRB(16, 12, 16, 24),
                      itemCount: _archives.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 10),
                      itemBuilder: (BuildContext context, int index) {
                        final WeeklyArchive archive = _archives[index];
                        return _ArchiveRow(archive: archive);
                      },
                    ),
                  ),
              ],
            ),
    );
  }

  WeeklyTotals get _currentTotals => WeeklyTotals.from(_drivers);

  /// إرسال تقرير إجماليات الأسبوع الحالي مباشرة إلى واتساب المدير.
  Future<void> _shareCurrentWeek() async {
    final DateTime now = DateTime.now();
    final String message = WhatsAppLink.formatWeeklySummaryMessage(
      periodStart: now.subtract(const Duration(days: 6)),
      periodEnd: now,
      totalOrders: _currentTotals.orders,
      totalAmount: _currentTotals.amount,
      totalWage: _currentTotals.wage,
      netAmount: _currentTotals.net,
      drivers: _drivers,
    );
    final Uri? link = await WhatsAppLink.build(message: message);
    if (!mounted) {
      return;
    }
    if (link == null) {
      _showMessage('رجئًا حفظ رقم مديرك في «إعدادات المدير» قبل المشاركة.');
      return;
    }
    _showMessage('تم تحضير رسالة الواتساب لرقم: ${link.pathSegments.last}');
    await WhatsAppLink.launch(message: message);
  }
}

/// بطاقة تنبيه أسبوعي مُنسقة يُظهرها التطبيق أسبوعياً لتلخيص الأداء.
class _WeeklyNoticeCard extends StatelessWidget {
  const _WeeklyNoticeCard({
    required this.totals,
    this.onSendWhatsApp,
  });

  final WeeklyTotals totals;
  final VoidCallback? onSendWhatsApp;

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;

    return Container(
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.accent.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(16),
        border:
            Border.all(color: AppColors.accent.withValues(alpha: 0.30)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              const Icon(Icons.notifications_outlined,
                  color: AppColors.accent),
              const SizedBox(width: 8),
              Text(
                'ملخص أسبوعي',
                key: const ValueKey<String>('weekly-notice-title'),
                style: text.titleSmall?.copyWith(color: AppColors.accent),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'مرحباً! ينقضي أسبوع على أداء المطعم. لا تنسَ مراجعة '
            'الطلبات والأجور، وأرشف الأسبوع إذا رغبت في تصفير الحسابات '
            'وبدء أسبوع جديد.',
            style: text.bodySmall?.copyWith(height: 1.6),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 14,
            runSpacing: 8,
            children: <Widget>[
              StatTile(
                label: 'الطلبات',
                value: formatNumber(totals.orders),
                icon: Icons.receipt_long_outlined,
                color: AppColors.primary,
                compact: true,
              ),
              StatTile(
                label: 'الأجور',
                value: formatAmount(totals.wage),
                icon: Icons.savings_outlined,
                color: AppColors.accent,
                compact: true,
              ),
              StatTile(
                label: 'صافي المطعم',
                value: formatAmount(totals.net),
                icon: Icons.storefront_outlined,
                color: AppColors.success,
                compact: true,
              ),
            ],
          ),
          if (onSendWhatsApp != null) ...<Widget>[
            const SizedBox(height: 14),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                key: const ValueKey<String>('send-weekly-summary-whatsapp'),
                onPressed: onSendWhatsApp,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF25D366),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                icon: const Icon(Icons.send_rounded, size: 18),
                label: const Text(
                  'إرسال الملخص الأسبوعي عبر واتساب 📲',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// صندوق فارغ يُعرض عندما لا يوجد أي أرشيف مسجل.
class _EmptyArchiveView extends StatelessWidget {
  const _EmptyArchiveView();

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;

    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(
              Icons.inventory_2_outlined,
              size: 54,
              color: AppColors.textSecondary.withValues(alpha: 0.7),
            ),
            const SizedBox(height: 14),
            Text('لا يوجد أرشيف أسبوعي بعد', style: text.titleSmall),
            const SizedBox(height: 6),
            Text(
              'عند أرشاف الأسبوع يظهر ملخصه هنا، ويُحذف تلقائياً بعد '
              'مرور أسبوع لتوفير مساحة التخزين.',
              textAlign: TextAlign.center,
              style: text.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}

/// صف أرشيف أسبوعي واحد يعرض الإجماليات والتواريخ وزر المشاركة.
class _ArchiveRow extends StatelessWidget {
  const _ArchiveRow({required this.archive});

  final WeeklyArchive archive;

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;

    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 12, 8, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                const Icon(Icons.calendar_today_outlined,
                    size: 16, color: AppColors.textSecondary),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    'من ${formatDate(archive.periodStart)} إلى '
                    '${formatDate(archive.periodEnd)}',
                    style: text.bodySmall,
                  ),
                ),
                IconButton(
                  key: ValueKey<String>('share-archive-${archive.periodEnd}'),
                  tooltip: 'مشاركة عبر الواتساب',
                  icon: const Icon(Icons.share,
                      size: 22, color: Color(0xFF25D36F)),
                  onPressed: () => _shareWeek(context),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 12,
              runSpacing: 6,
              children: <Widget>[
                StatTile(
                  label: 'الطلبات',
                  value: formatNumber(archive.totalOrders),
                  icon: Icons.receipt_long_outlined,
                  color: AppColors.primary,
                  compact: true,
                ),
                StatTile(
                  label: 'الأجور',
                  value: formatAmount(archive.totalWage),
                  icon: Icons.savings_outlined,
                  color: AppColors.accent,
                  compact: true,
                ),
                StatTile(
                  label: 'صافي المطعم',
                  value: formatAmount(archive.netAmount),
                  icon: Icons.storefront_outlined,
                  color: AppColors.success,
                  compact: true,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
  /// بناء رسالة ملخص الأسبوع وتحضير رابط الواتساب لرقم المدير المحفوظ.
  ///
  /// الرقم يُقرأ من «إعدادات المدير» عبر [WhatsAppLink]، وربط الرابط بفتح
  /// تطبيق الواتساب يتم عبر url_launcher في الإصدار الإنتاجي.
  Future<void> _shareWeek(BuildContext context) async {
    final Uri? link = await WhatsAppLink.build(
      message: _buildWeekMessage(archive),
    );

    if (!context.mounted) {
      return;
    }
    if (link == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'رجئًا حفظ رقم مديرك في «إعدادات المدير» قبل المشاركة.',
          ),
        ),
      );
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'تم تحضير رسالة الواتساب لرقم: ${link.pathSegments.last}',
        ),
      ),
    );
    await WhatsAppLink.launch(message: _buildWeekMessage(archive));
  }
}

/// بناء نص رسالة مشاركة الأسبوع للواتساب (يقرأ الرقم المخزّن تلقافياً).
String _buildWeekMessage(WeeklyArchive archive) =>
    WhatsAppLink.formatWeeklySummaryMessage(
      periodStart: archive.periodStart,
      periodEnd: archive.periodEnd,
      totalOrders: archive.totalOrders,
      totalAmount: archive.totalAmount,
      totalWage: archive.totalWage,
      netAmount: archive.netAmount,
    );
