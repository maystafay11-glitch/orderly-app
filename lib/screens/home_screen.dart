import 'package:flutter/material.dart';

import 'package:orderly_app/models/delivery_order.dart';
import 'package:orderly_app/models/driver.dart';
import 'package:orderly_app/models/order_payment_type.dart';
import 'package:orderly_app/screens/analytics_screen.dart';
import 'package:orderly_app/screens/camera_scan_screen.dart';
import 'package:orderly_app/screens/driver_login_screen.dart';
import 'package:orderly_app/screens/driver_shift_history_screen.dart';
import 'package:orderly_app/screens/live_tracking_screen.dart';
import 'package:orderly_app/screens/manage_drivers_screen.dart';
import 'package:orderly_app/screens/miswak_screen.dart';
import 'package:orderly_app/screens/settings_screen.dart';
import 'package:orderly_app/screens/unified_login_screen.dart';
import 'package:orderly_app/screens/weekly_archive_screen.dart';
import 'package:orderly_app/screens/worker_performance_screen.dart';
import 'package:orderly_app/services/app_settings.dart';
import 'package:orderly_app/services/auth_session_service.dart';
import 'package:orderly_app/services/driver_storage.dart';
import 'package:orderly_app/services/ocr_service.dart';
import 'package:orderly_app/theme/app_theme.dart';
import 'package:orderly_app/utils/formatters.dart';
import 'package:orderly_app/utils/whatsapp.dart';
import 'package:orderly_app/widgets/add_driver_dialog.dart';
import 'package:orderly_app/widgets/driver_card.dart';
import 'package:orderly_app/widgets/general_order_dialog.dart';
import 'package:orderly_app/widgets/order_history_dialog.dart';
import 'package:orderly_app/widgets/order_price_dialog.dart';

/// الشاشة الرئيسية: قائمة عمال التوصيل مع عدد الطلبات وإجمالي المبالغ
/// وأجرة العامل (1000 دينار لكل طلب) وصافي المبلغ للمطعم.
///
/// * النقر على بطاقة العامل ⇒ **سجل الطلبات**: كل طلب برقمه وسعره ووقته،
///   وبجانب كل طلب زر حذف (🗑️) يحذف تلك الطلبية ويُعيد حساب الأرقام فوراً.
/// * زر «تسجيل طلب» داخل البطاقة ⇒ حوار إدخال رقم الطلب وسعره (أو مسحه
///   بالكاميرا).
/// * الضغط المطوّل على البطاقة ⇒ شاشة إدارة أسماء العمال.
/// * كل تعديل يُحفظ تلقائياً في التخزين المحلي عبر [DriverStorage].
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  /// نص العنوان كما يظهر في الشريط العلوي (يُستخدم في الاختبارات).
  static const String title = 'أجور العمال';

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  bool _isLoading = true;
  List<Driver> _drivers = <Driver>[];
  List<DeliveryOrder> _generalOrders = <DeliveryOrder>[];
  int _selectedTabIndex = 0;
  String _driverSearchQuery = '';
  final TextEditingController _driverSearchController = TextEditingController();
  bool _showWeeklyReminder = false;

  final GlobalKey<AnalyticsScreenState> _analyticsKey =
      GlobalKey<AnalyticsScreenState>();
  final GlobalKey<MiswakScreenState> _miswakKey =
      GlobalKey<MiswakScreenState>();
  final GlobalKey<WorkerPerformanceScreenState> _performanceKey =
      GlobalKey<WorkerPerformanceScreenState>();

  @override
  void dispose() {
    _driverSearchController.dispose();
    super.dispose();
  }

  /// التحقق من وجوب عرض التنبيه الأسبوعي داخل التطبيق (كل 7 أيام).
  Future<void> _checkWeeklyReminder() async {
    final DateTime last = await AppSettings.getLastWeeklyNotice();
    final bool hasData = _drivers.isNotEmpty || _generalOrders.isNotEmpty;
    final bool isDue =
        DateTime.now().difference(last) >= const Duration(days: 7);
    if (mounted) {
      setState(() {
        _showWeeklyReminder = hasData && isDue;
      });
    }
  }

  /// إرسال الملخص الأسبوعي المنظّم عبر واتساب للمدير.
  Future<void> _sendWeeklySummaryWhatsApp() async {
    final DateTime now = DateTime.now();
    final _DailyTotals totals = _DailyTotals.from(
      _drivers,
      generalOrders: _generalOrders,
    );
    final String message = WhatsAppLink.formatWeeklySummaryMessage(
      periodStart: now.subtract(const Duration(days: 6)),
      periodEnd: now,
      totalOrders: totals.orders,
      totalAmount: totals.amounts,
      totalWage: totals.wages,
      netAmount: totals.net,
      drivers: _drivers,
    );

    final Uri? link = await WhatsAppLink.build(message: message);
    if (!mounted) {
      return;
    }
    if (link == null) {
      _showMessage('يرجى حفظ رقم مديرك في «إعدادات المدير» قبل المشاركة.');
      return;
    }
    await AppSettings.setLastWeeklyNotice(now);
    setState(() => _showWeeklyReminder = false);
    _showMessage('تم تحضير رسالة الواتساب لرقم: ${link.pathSegments.last}');
    await WhatsAppLink.launch(message: message);
  }

  /// تسوية النصوص العربية للبحث المرن (تجاهل الهمزات والتاء المربوطة والألف المقصورة والتشكيل).
  static String _normalizeArabic(String text) {
    return text
        .replaceAll(RegExp(r'[\u064B-\u065F\u0670]'), '')
        .replaceAll(RegExp(r'[إأآا]'), 'ا')
        .replaceAll('ة', 'ه')
        .replaceAll('ى', 'ي')
        .replaceAll('ؤ', 'و')
        .replaceAll('ئ', 'ي')
        .trim()
        .toLowerCase();
  }

  /// قائمة العمال بعد تطبيق تصفية البحث بالاسم.
  List<Driver> get _filteredDrivers {
    final String query = _normalizeArabic(_driverSearchQuery);
    if (query.isEmpty) {
      return _drivers;
    }
    return _drivers.where((Driver driver) {
      return _normalizeArabic(driver.name).contains(query);
    }).toList();
  }

  @override
  void initState() {
    super.initState();
    _loadDrivers();
  }

  /// استرجاع العمال والطلبات العامة المحفوظة محلياً.
  Future<void> _loadDrivers() async {
    final List<Driver> drivers = await DriverStorage.loadDrivers();
    final List<DeliveryOrder> generalOrders =
        await DriverStorage.loadGeneralOrders();
    if (!mounted) {
      return;
    }
    setState(() {
      _drivers = drivers;
      _generalOrders = generalOrders;
      _isLoading = false;
    });
    _performanceKey.currentState?.reload();
    _analyticsKey.currentState?.reload();
    await AppSettings.pruneOldArchives();
    await _checkWeeklyReminder();
  }

  /// التنقل بين التبويبات مع إعادة تحديث بيانات التبويب المختار فوراً.
  void _selectTab(int index) {
    setState(() => _selectedTabIndex = index);
    if (index == 0) {
      _loadDrivers();
    } else if (index == 1) {
      _analyticsKey.currentState?.reload();
    } else if (index == 2) {
      _miswakKey.currentState?.reload();
    } else if (index == 3) {
      _performanceKey.currentState?.reload();
    }
  }

  /// حفظ القائمة كاملة ثم تحديث الشاشة.
  Future<void> _persistDrivers(List<Driver> drivers) async {
    await DriverStorage.saveDrivers(drivers);
    await _loadDrivers();
  }

  /// تسجيل طلب عام / سفري مستقل بدون عامل ديليفري.
  Future<void> _registerGeneralOrder({
    double? initialPrice,
    String? initialOrderNumber,
  }) async {
    final DeliveryOrder? order = await showGeneralOrderDialog(
      context,
      initialPrice: initialPrice,
      initialOrderNumber: initialOrderNumber,
    );
    if (order == null || !mounted) {
      return;
    }
    await DriverStorage.addGeneralOrder(order);
    await _loadDrivers();
    if (!mounted) {
      return;
    }
    _showMessage(
      'تم تسجيل طلب سفري بمبلغ ${formatAmount(order.amount)} (صافي 100% للمطعم)',
    );
  }

  /// مسح الفاتورة أو الباركود بالكاميرا مباشرة وتسجيل طلب سفري سريع.
  Future<void> _scanGeneralOrderWithCamera() async {
    final OcrResult? result = await Navigator.of(context).push<OcrResult>(
      MaterialPageRoute<OcrResult>(
        builder: (BuildContext _) => const CameraScanScreen(),
      ),
    );
    if (!mounted || result == null) {
      return;
    }
    await _registerGeneralOrder(
      initialPrice: result.best,
      initialOrderNumber: result.bestOrderNumber,
    );
  }

  /// عرض سجل طلبات السفري لليوم مع إمكانية حذف أي طلب مسجل بالخطأ.
  void _showGeneralOrdersHistory() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (BuildContext sheetContext) {
        return StatefulBuilder(
          builder: (BuildContext context, StateSetter setSheetState) {
            final TextTheme text = Theme.of(context).textTheme;
            final double total = _generalOrders.fold<double>(
              0,
              (double sum, DeliveryOrder o) => sum + o.amount,
            );

            return Container(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
              constraints: BoxConstraints(
                maxHeight: MediaQuery.of(context).size.height * 0.75,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  Center(
                    child: Container(
                      width: 44,
                      height: 4,
                      decoration: BoxDecoration(
                        color: Colors.grey.shade300,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: <Widget>[
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: const Color(0xFFEA580C).withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Icon(
                          Icons.takeout_dining_rounded,
                          color: Color(0xFFEA580C),
                          size: 24,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            Text('سجل الطلبات العامة والسفري', style: text.titleMedium),
                            const SizedBox(height: 2),
                            Text(
                              '${formatNumber(_generalOrders.length)} طلبات • إجمالي: ${formatAmount(total)} (أجرة التوصيل: 0 د.ع)',
                              style: text.bodySmall?.copyWith(
                                color: AppColors.success,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const Divider(height: 24),
                  if (_generalOrders.isEmpty)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 32),
                      child: Center(
                        child: Text(
                          'لا توجد طلبات عامة أو سفري مسجلة اليوم',
                          style: TextStyle(color: AppColors.textSecondary),
                        ),
                      ),
                    )
                  else
                    Flexible(
                      child: ListView.separated(
                        shrinkWrap: true,
                        itemCount: _generalOrders.length,
                        separatorBuilder: (_, __) => const Divider(height: 1),
                        itemBuilder: (BuildContext _, int index) {
                          final DeliveryOrder order = _generalOrders[index];
                          return ListTile(
                            contentPadding: EdgeInsets.zero,
                            leading: Container(
                              width: 38,
                              height: 38,
                              decoration: BoxDecoration(
                                color: AppColors.primary.withValues(alpha: 0.08),
                                shape: BoxShape.circle,
                              ),
                              child: Center(
                                child: Text(
                                  '#${index + 1}',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 12,
                                    color: AppColors.primary,
                                  ),
                                ),
                              ),
                            ),
                            title: Row(
                              children: <Widget>[
                                Text(
                                  formatAmount(order.amount),
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 15,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 2,
                                  ),
                                  decoration: BoxDecoration(
                                    color: order.paymentType == OrderPaymentType.masterCard
                                        ? Colors.purple.withValues(alpha: 0.12)
                                        : (order.paymentType == OrderPaymentType.directReceive
                                            ? Colors.teal.withValues(alpha: 0.12)
                                            : AppColors.primary.withValues(alpha: 0.12)),
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: Text(
                                    order.displayPayment,
                                    style: TextStyle(
                                      fontSize: 10,
                                      fontWeight: FontWeight.w600,
                                      color: order.paymentType == OrderPaymentType.masterCard
                                          ? Colors.purple
                                          : (order.paymentType == OrderPaymentType.directReceive
                                              ? Colors.teal
                                              : AppColors.primary),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            subtitle: Text(
                              order.orderNumber.isNotEmpty
                                  ? 'رقم: ${order.orderNumber} • ${formatTime(order.addedAt)}'
                                  : formatTime(order.addedAt),
                              style: text.bodySmall?.copyWith(fontSize: 11),
                            ),
                            trailing: IconButton(
                              icon: const Icon(
                                Icons.delete_outline,
                                color: AppColors.danger,
                                size: 20,
                              ),
                              tooltip: 'حذف هذا الطلب',
                              onPressed: () async {
                                await DriverStorage.removeGeneralOrderAt(index);
                                await _loadDrivers();
                                setSheetState(() {});
                                if (!mounted) return;
                                Navigator.pop(sheetContext);
                                _showMessage('تم حذف الطلب العام');
                              },
                            ),
                          );
                        },
                      ),
                    ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  /// إضافة عامل جديد بالاسم.
  Future<void> _addDriver() async {
    final String? name = await showAddDriverDialog(
      context,
      existingNames: _drivers.map((Driver driver) => driver.name).toList(),
    );
    if (name == null) {
      return;
    }
    final String nextPin = Driver.findNextAvailablePin(_drivers);
    await _persistDrivers(<Driver>[..._drivers, Driver(name: name, pin: nextPin)]);
    if (!mounted) {
      return;
    }
    _showMessage('تمت إضافة العامل $name برمز دخول ($nextPin)');
  }

  void _openLiveTracking() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (BuildContext _) => const LiveTrackingScreen(),
      ),
    ).then((_) => _loadDrivers());
  }

  void _openDriverApp() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (BuildContext _) => const DriverLoginScreen(),
      ),
    ).then((_) => _loadDrivers());
  }

  void _openShiftHistory() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (BuildContext _) => const DriverShiftHistoryScreen(),
      ),
    );
  }

  /// تسجيل طلب جديد: يفتح حوار (رقم الطلب + السعر) ثم يضيفه ويحفظ فوراً.
  Future<void> _registerOrder(Driver driver) async {
    final DeliveryOrder? order = await showOrderPriceDialog(
      context,
      driver: driver,
    );
    if (order == null || !mounted) {
      return;
    }
    final Driver updated = driver.addDeliveryOrder(order);
    final bool saved = await _applyDriver(updated);
    if (!mounted) {
      return;
    }
    if (!saved) {
      _showMessage('تعذّر حفظ الطلب، حاول مرة أخرى.');
      return;
    }
    _showMessage(
      'تمت إضافة الطلب ${order.displayNumber} — '
      'الأجرة: ${formatAmount(updated.wage)} | '
      'صافي المطعم: ${formatAmount(updated.netAmountToRestaurant)}',
    );
  }

  /// حفظ نسخة مُحدَّثة من العامل في التخزين المحلي وتحديث الشاشة.
  ///
  /// تُستخدم في حوار سجل الطلبات (إضافة/حذف طلب)، وتُرجع `true` عند نجاح
  /// الحفظ و`false` إذا فشل حتى يبقى العرض مطابقاً للبيانات المحفوظة.
  Future<bool> _applyDriver(Driver updated) async {
    final List<Driver> drivers = <Driver>[
      for (final Driver driver in _drivers)
        if (driver.name == updated.name) updated else driver,
    ];
    try {
      await _persistDrivers(drivers);
      return true;
    } on Exception {
      return false;
    }
  }

  /// فتح سجل طلبات العامل: عرض الطلبات برقمها وسعرها ووقتها مع إمكانية
  /// حذف أي طلبية محددة (يُخصم مبلغها وتُحدَّث الأرقام وتُحفظ فوراً).
  Future<void> _openOrderHistory(Driver driver) async {
    await showOrderHistoryDialog(
      context,
      driver: driver,
      onDriverChanged: _applyDriver,
    );
  }

  /// فتح شاشة إدارة أسماء العمال من أيقونة الإعدادات، ثم تحديث القائمة
  /// تلقائياً بعد الرجوع (لأن الإضافة/الحذف تُحفظ فوراً هناك).
  Future<void> _openManageDrivers() async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (BuildContext _) => const ManageDriversScreen(),
      ),
    );
    if (!mounted) {
      return;
    }
    await _loadDrivers();
  }

  /// تصفير حسابات اليوم: يطلب تأكيداً أولاً لمنع الحذف بالخطأ.
  ///
  /// تُصفَّر أرقام العمال (عدد الطلبات ومجموع المبالغ) مع **الاحتفاظ بأسمائهم**،
  /// فالأجرة وصافي المطعم يُعاد حسابهما تلقائياً من الأرقام الجديدة.
  Future<void> _confirmResetDay() async {
    final TextTheme text = Theme.of(context).textTheme;
    final _DailyTotals totals = _DailyTotals.from(
      _drivers,
      generalOrders: _generalOrders,
    );

    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext dialogContext) => AlertDialog(
        titlePadding: const EdgeInsets.fromLTRB(20, 20, 20, 10),
        contentPadding: const EdgeInsets.fromLTRB(20, 0, 20, 10),
        actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        title: Row(
          children: <Widget>[
            Container(
              width: 42,
              height: 42,
              decoration: const BoxDecoration(
                color: AppColors.warningSurface,
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.restart_alt, color: AppColors.warning),
            ),
            const SizedBox(width: 12),
            Expanded(child: Text('تصفير حسابات اليوم')),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                'سيتم تصفير الأرقام التالية والبدء بيوم جديد:',
                style: text.bodyMedium,
              ),
              const SizedBox(height: 12),
              _ResetPreviewRow(
                label: 'إجمالي الطلبات الكلي',
                value: formatNumber(totals.orders),
              ),
              _ResetPreviewRow(
                label: 'إجمالي المبالغ الكلية',
                value: formatAmount(totals.amounts),
              ),
              _ResetPreviewRow(
                label: 'إجمالي أجور العمال',
                value: formatAmount(totals.wages),
              ),
              _ResetPreviewRow(
                label: 'إجمالي صافي المطعم',
                value: formatAmount(totals.net),
              ),
              if (totals.generalOrders > 0)
                _ResetPreviewRow(
                  label: 'طلبات سفري عامة (${totals.generalOrders})',
                  value: formatAmount(totals.generalAmounts),
                ),
              const SizedBox(height: 14),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: AppColors.warningSurface,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: <Widget>[
                    const Icon(
                      Icons.info_outline,
                      size: 16,
                      color: AppColors.warning,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'تُصفَّر أرقام ${formatNumber(totals.drivers)} عمال '
                        'وطلبات السفري مع الاحتفاظ بأسماء العمال، ولا يمكن التراجع.',
                        style: text.bodySmall?.copyWith(height: 1.5),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('إلغاء'),
          ),
          FilledButton.icon(
            key: const ValueKey<String>('confirm-reset-button'),
            style: FilledButton.styleFrom(backgroundColor: AppColors.warning),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            icon: const Icon(Icons.restart_alt, size: 18),
            label: const Text('تصفير الحسابات'),
          ),
        ],
      ),
    );

    if (confirmed != true) {
      return;
    }
    await _resetDay();
  }

  /// تنفيذ التصفير: صفر لكل الأرقام ثم حفظ فوري في التخزين المحلي.
  ///
  /// يُحذف سجل الطلبات التفصيلي بالكامل (فتُصفَّر الأرقام والأجور والصافي)
  /// مع الاحتفاظ بأسماء العمال، وتُصفَّر أيضاً الطلبات العامة والسفري.
  Future<void> _resetDay() async {
    final List<Driver> cleared = _drivers
        .map((Driver driver) => driver.resetDay())
        .toList();

    await _persistDrivers(cleared);
    await DriverStorage.clearGeneralOrders();
    await _loadDrivers();
    if (!mounted) {
      return;
    }
    _showMessage('تم تصفير حسابات اليوم، وبدأ يوم جديد.');
  }

  /// فتح شاشة إعدادات رقم واتساب المدير.
  void _openSettings() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (BuildContext context) => const SettingsScreen(),
      ),
    );
  }

  /// فتح شاشة أرشيف الأسابيع السابقة.
  void _openWeeklyArchive() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (BuildContext context) => const WeeklyArchiveScreen(),
      ),
    );
  }

  /// تسجيل الخروج من لوحة تحكم المدير والعودة لشاشة الدخول الموحدة.
  Future<void> _logout() async {
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext ctx) => AlertDialog(
        title: const Row(
          children: <Widget>[
            Icon(Icons.logout_rounded, color: AppColors.danger),
            SizedBox(width: 8),
            Text('تسجيل الخروج'),
          ],
        ),
        content: const Text('هل ترغب بتسجيل الخروج من لوحة المدير والعودة لبوابة الدخول بالرمز؟'),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('إلغاء'),
          ),
          FilledButton.icon(
            key: const ValueKey<String>('confirm-drawer-logout-button'),
            style: FilledButton.styleFrom(backgroundColor: AppColors.danger),
            onPressed: () => Navigator.pop(ctx, true),
            icon: const Icon(Icons.logout),
            label: const Text('تسجيل الخروج'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await AuthSessionService.logout();
      if (!mounted) return;
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute<void>(builder: (BuildContext _) => const UnifiedLoginScreen()),
        (Route<dynamic> route) => false,
      );
    }
  }

  /// عنوان التبويب الحالي المعروض في الشريط العلوي.
  String get _currentTabTitle {
    switch (_selectedTabIndex) {
      case 0:
        return HomeScreen.title;
      case 1:
        return AnalyticsScreen.title;
      case 2:
        return MiswakScreen.title;
      case 3:
        return WorkerPerformanceScreen.title;
      default:
        return HomeScreen.title;
    }
  }

  /// بناء القائمة الجانبية المنسدلة (Navigation Drawer) بأناقة واحترافية.
  Widget _buildDrawer(BuildContext context) {

    return Drawer(
      child: SafeArea(
        top: false,
        child: Column(
          children: <Widget>[
            // ترويسة القائمة الجانبية
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(16, 48, 16, 16),
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  colors: <Color>[Color(0xFF060E1E), Color(0xFF0B1E3A)],
                  begin: Alignment.topRight,
                  end: Alignment.bottomLeft,
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Container(
                    width: 46,
                    height: 46,
                    decoration: BoxDecoration(
                      gradient: AppColors.primaryGradient,
                      borderRadius: BorderRadius.circular(14),
                      boxShadow: <BoxShadow>[
                        BoxShadow(
                          color: AppColors.primary.withValues(alpha: 0.4),
                          blurRadius: 12,
                        ),
                      ],
                    ),
                    child: const Icon(Icons.storefront_rounded, color: Colors.white, size: 24),
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'Orderly',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w900,
                      fontSize: 20,
                      letterSpacing: 1,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'نظام إدارة التوصيل الذكي',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.65),
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),

            // قائمة الأقسام والعناصر
            Expanded(
              child: ListView(
                padding: const EdgeInsets.symmetric(vertical: 4),
                children: <Widget>[
                  // 1. الإدارة والعمليات
                  _buildDrawerSectionHeader('الإدارة والإعدادات'),
                  _DrawerItem(
                    key: const ValueKey<String>('manage-drivers-button'),
                    icon: Icons.groups_2_outlined,
                    iconColor: AppColors.primary,
                    title: 'إدارة أسماء العمال',
                    onTap: () {
                      Navigator.pop(context);
                      _openManageDrivers();
                    },
                  ),
                  _DrawerItem(
                    key: const ValueKey<String>('archive-button'),
                    icon: Icons.history_rounded,
                    iconColor: AppColors.accent,
                    title: 'الملخص الأرشيفي الأسبوعي',
                    onTap: () {
                      Navigator.pop(context);
                      _openWeeklyArchive();
                    },
                  ),
                  _DrawerItem(
                    key: const ValueKey<String>('settings-button'),
                    icon: Icons.settings_outlined,
                    iconColor: AppColors.textSecondary,
                    title: 'إعدادات المدير (واتساب)',
                    onTap: () {
                      Navigator.pop(context);
                      _openSettings();
                    },
                  ),
                  _DrawerItem(
                    key: const ValueKey<String>('reset-day-button'),
                    icon: Icons.restart_alt_rounded,
                    iconColor: AppColors.warning,
                    title: 'تصفير حسابات اليوم',
                    onTap: () {
                      Navigator.pop(context);
                      _confirmResetDay();
                    },
                  ),

                  const Divider(height: 8, indent: 16, endIndent: 16),

                  // نظام تتبع السائقين وتطبيق السائق (Firebase)
                  _buildDrawerSectionHeader('نظام تتبع السائقين (Firebase)'),
                  _DrawerItem(
                    key: const ValueKey<String>('live-tracking-button'),
                    icon: Icons.radar_rounded,
                    iconColor: const Color(0xFF2563EB),
                    title: 'تتبع السائقين والطلبات (مباشر)',
                    onTap: () {
                      Navigator.pop(context);
                      _openLiveTracking();
                    },
                  ),
                  _DrawerItem(
                    key: const ValueKey<String>('driver-app-button'),
                    icon: Icons.two_wheeler_rounded,
                    iconColor: AppColors.primary,
                    title: 'تطبيق السائق (بوابة PIN)',
                    onTap: () {
                      Navigator.pop(context);
                      _openDriverApp();
                    },
                  ),
                  _DrawerItem(
                    key: const ValueKey<String>('shift-history-button'),
                    icon: Icons.route_rounded,
                    iconColor: AppColors.success,
                    title: 'سجل مسار التوصيل اليومي',
                    onTap: () {
                      Navigator.pop(context);
                      _openShiftHistory();
                    },
                  ),

                  const Divider(height: 8, indent: 16, endIndent: 16),

                  // 2. الواجهات الرئيسية
                  _buildDrawerSectionHeader('الواجهات الرئيسية'),
                  _DrawerItem(
                    icon: Icons.two_wheeler_rounded,
                    title: 'العمال والطلبات (الرئيسية)',
                    isSelected: _selectedTabIndex == 0,
                    onTap: () {
                      Navigator.pop(context);
                      _selectTab(0);
                    },
                  ),
                  _DrawerItem(
                    key: const ValueKey<String>('analytics-button'),
                    icon: Icons.analytics_rounded,
                    title: 'الإحصائيات والرسوم البيانية',
                    isSelected: _selectedTabIndex == 1,
                    onTap: () {
                      Navigator.pop(context);
                      _selectTab(1);
                    },
                  ),
                  _DrawerItem(
                    key: const ValueKey<String>('miswak-button'),
                    icon: Icons.inventory_2_rounded,
                    title: 'حساب المسواگ والأرباح',
                    isSelected: _selectedTabIndex == 2,
                    onTap: () {
                      Navigator.pop(context);
                      _selectTab(2);
                    },
                  ),
                  _DrawerItem(
                    icon: Icons.insights_rounded,
                    title: 'تحليل وتقييم أداء العمال',
                    isSelected: _selectedTabIndex == 3,
                    onTap: () {
                      Navigator.pop(context);
                      _selectTab(3);
                    },
                  ),

                  const Divider(height: 8, indent: 16, endIndent: 16),

                  _DrawerItem(
                    key: const ValueKey<String>('drawer-logout-button'),
                    icon: Icons.logout_rounded,
                    iconColor: AppColors.danger,
                    title: 'تسجيل الخروج من لوحة المدير',
                    onTap: () {
                      Navigator.pop(context);
                      _logout();
                    },
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDrawerSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 4),
      child: Text(
        title.toUpperCase(),
        style: const TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w800,
          color: AppColors.textMuted,
          letterSpacing: 1.2,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.surface,
        title: Row(
          children: <Widget>[
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                gradient: AppColors.primaryGradient,
                borderRadius: BorderRadius.circular(9),
              ),
              child: const Icon(Icons.storefront_rounded, color: Colors.white, size: 18),
            ),
            const SizedBox(width: 10),
            Text(
              _currentTabTitle,
              style: const TextStyle(
                color: AppColors.textPrimary,
                fontWeight: FontWeight.w800,
                fontSize: 17,
              ),
            ),
          ],
        ),
        leading: Builder(
          builder: (BuildContext ctx) => IconButton(
            key: const ValueKey<String>('drawer-button'),
            icon: const Icon(Icons.menu_rounded, color: AppColors.textPrimary),
            tooltip: 'القائمة الجانبية',
            onPressed: () => Scaffold.of(ctx).openDrawer(),
          ),
        ),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(height: 1, color: AppColors.border),
        ),
        actions: <Widget>[
          IconButton(
            key: const ValueKey<String>('live-tracking-appbar-button'),
            icon: const Icon(Icons.radar_rounded, color: AppColors.info),
            tooltip: 'تتبع السائقين المباشر',
            onPressed: _openLiveTracking,
          ),
          IconButton(
            key: const ValueKey<String>('refresh-button'),
            onPressed: _isLoading
                ? null
                : () {
                    if (_selectedTabIndex == 0) {
                      _loadDrivers();
                    } else if (_selectedTabIndex == 1) {
                      _analyticsKey.currentState?.reload();
                    } else if (_selectedTabIndex == 2) {
                      _miswakKey.currentState?.reload();
                    } else if (_selectedTabIndex == 3) {
                      _performanceKey.currentState?.reload();
                    }
                  },
            tooltip: 'تحديث البيانات',
            icon: const Icon(Icons.refresh_rounded, color: AppColors.textSecondary),
          ),
          const SizedBox(width: 4),
        ],
      ),
      drawer: _buildDrawer(context),
      floatingActionButton: _selectedTabIndex == 0 && !_isLoading
          ? Container(
              decoration: BoxDecoration(
                gradient: AppColors.primaryGradient,
                borderRadius: BorderRadius.circular(18),
                boxShadow: <BoxShadow>[
                  BoxShadow(
                    color: AppColors.primary.withValues(alpha: 0.4),
                    blurRadius: 16,
                    offset: const Offset(0, 6),
                  ),
                ],
              ),
              child: Material(
                color: Colors.transparent,
                borderRadius: BorderRadius.circular(18),
                child: InkWell(
                  key: const ValueKey<String>('add-driver-fab'),
                  onTap: _addDriver,
                  borderRadius: BorderRadius.circular(18),
                  child: const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        Icon(Icons.person_add_alt_1_rounded, color: Colors.white, size: 20),
                        SizedBox(width: 8),
                        Text(
                          'إضافة عامل',
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w700,
                            fontSize: 14,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            )
          : null,
      bottomNavigationBar: Container(
        decoration: const BoxDecoration(
          color: AppColors.surface,
          border: Border(top: BorderSide(color: AppColors.border)),
        ),
        child: NavigationBar(
          selectedIndex: _selectedTabIndex,
          onDestinationSelected: _selectTab,
          backgroundColor: Colors.transparent,
          elevation: 0,
          indicatorColor: AppColors.primary.withValues(alpha: 0.15),
          labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
          destinations: const <NavigationDestination>[
            NavigationDestination(
              key: ValueKey<String>('drivers-tab-button'),
              icon: Icon(Icons.two_wheeler_outlined, color: AppColors.textMuted),
              selectedIcon: Icon(Icons.two_wheeler_rounded, color: AppColors.primary),
              label: 'العمال',
            ),
            NavigationDestination(
              key: ValueKey<String>('analytics-tab-button'),
              icon: Icon(Icons.analytics_outlined, color: AppColors.textMuted),
              selectedIcon: Icon(Icons.analytics_rounded, color: AppColors.primary),
              label: 'الإحصائيات',
            ),
            NavigationDestination(
              key: ValueKey<String>('miswak-tab-button'),
              icon: Icon(Icons.inventory_2_outlined, color: AppColors.textMuted),
              selectedIcon: Icon(Icons.inventory_2_rounded, color: AppColors.primary),
              label: 'المسواگ',
            ),
            NavigationDestination(
              key: ValueKey<String>('performance-button'),
              icon: Icon(Icons.insights_outlined, color: AppColors.textMuted),
              selectedIcon: Icon(Icons.insights_rounded, color: AppColors.primary),
              label: 'أداء العمال',
            ),
          ],
        ),
      ),
      body: IndexedStack(
        index: _selectedTabIndex,
        children: <Widget>[
          _buildBody(),
          AnalyticsScreen(key: _analyticsKey, showAppBar: false),
          MiswakScreen(key: _miswakKey, showAppBar: false),
          WorkerPerformanceScreen(key: _performanceKey, showAppBar: false),
        ],
      ),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_drivers.isEmpty) {
      return RefreshIndicator(
        onRefresh: _loadDrivers,
        color: AppColors.primary,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
          children: <Widget>[
            if (_showWeeklyReminder) _buildWeeklyReminderBanner(),
            _GeneralTakeawayCard(
              generalOrders: _generalOrders,
              onRegister: _registerGeneralOrder,
              onScanCamera: _scanGeneralOrderWithCamera,
              onViewHistory: _showGeneralOrdersHistory,
            ),
            if (_generalOrders.isNotEmpty) ...<Widget>[
              const SizedBox(height: 8),
              _DailySummaryCard(
                drivers: _drivers,
                generalOrders: _generalOrders,
              ),
              const SizedBox(height: 14),
              _ResetDayButton(
                onPressed: _confirmResetDay,
                enabled: true,
              ),
              const SizedBox(height: 20),
            ],
            _EmptyState(onAdd: _addDriver),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadDrivers,
      color: AppColors.primary,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
        children: <Widget>[
          if (_showWeeklyReminder) _buildWeeklyReminderBanner(),
          _GeneralTakeawayCard(
            generalOrders: _generalOrders,
            onRegister: _registerGeneralOrder,
            onScanCamera: _scanGeneralOrderWithCamera,
            onViewHistory: _showGeneralOrdersHistory,
          ),
          const SizedBox(height: 8),
          _buildDriverSearchBar(),
          _DriversHeader(
            drivers: _filteredDrivers,
            totalCount: _drivers.length,
          ),
          if (_filteredDrivers.isEmpty)
            _buildEmptySearchResults()
          else
            for (final Driver driver in _filteredDrivers) ...<Widget>[
              const SizedBox(height: 12),
              DriverCard(
                driver: driver,
                onTap: () => _openOrderHistory(driver),
                onRegisterOrder: () => _registerOrder(driver),
                onLongPress: _openManageDrivers,
              ),
            ],
          const SizedBox(height: 22),
          _DailySummaryCard(
            drivers: _drivers,
            generalOrders: _generalOrders,
          ),
          const SizedBox(height: 14),
          _ResetDayButton(
            onPressed: _confirmResetDay,
            enabled: _hasNumbersToReset(_drivers, _generalOrders),
          ),
        ],
      ),
    );
  }

  /// بطاقة إشعار التنبيه الأسبوعي لإرسال الملخص المنظّم عبر واتساب.
  Widget _buildWeeklyReminderBanner() {
    return Container(
      key: const ValueKey<String>('weekly-reminder-banner'),
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF25D366).withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: const Color(0xFF25D366).withValues(alpha: 0.35),
          width: 1.2,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: const Color(0xFF25D366),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(
                  Icons.notifications_active_rounded,
                  color: Colors.white,
                  size: 18,
                ),
              ),
              const SizedBox(width: 10),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      'تذكير أسبوعي: إرسال ملخص الأسبوع',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    SizedBox(height: 2),
                    Text(
                      'مرّ أسبوع على الحسابات. شارك الملخص الأسبوعي المنظّم مع الإدارة عبر الواتساب.',
                      style: TextStyle(
                        fontSize: 11,
                        color: AppColors.textSecondary,
                        height: 1.3,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                key: const ValueKey<String>('dismiss-weekly-reminder-button'),
                icon: const Icon(Icons.close_rounded, size: 18),
                tooltip: 'إغلاق التذكير',
                onPressed: () async {
                  await AppSettings.setLastWeeklyNotice(DateTime.now());
                  if (mounted) {
                    setState(() => _showWeeklyReminder = false);
                  }
                },
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: <Widget>[
              Expanded(
                child: ElevatedButton.icon(
                  key: const ValueKey<String>('send-weekly-summary-whatsapp-home'),
                  onPressed: _sendWeeklySummaryWhatsApp,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF25D366),
                    foregroundColor: Colors.white,
                    elevation: 0,
                    padding: const EdgeInsets.symmetric(
                      vertical: 10,
                      horizontal: 10,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  icon: const Icon(Icons.send_rounded, size: 16),
                  label: const Text(
                    'إرسال الملخص الأسبوعي عبر واتساب 📲',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              OutlinedButton(
                key: const ValueKey<String>('open-weekly-archive-from-banner'),
                onPressed: _openWeeklyArchive,
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(
                    vertical: 10,
                    horizontal: 12,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                child: const Text('الأرشيف', style: TextStyle(fontSize: 11)),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// حقل البحث عن عامل بالاسم لتسهيل الوصول إليه فوراً.
  Widget _buildDriverSearchBar() {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextField(
        key: const ValueKey<String>('driver-search-field'),
        controller: _driverSearchController,
        decoration: InputDecoration(
          hintText: 'بحث عن عامل بالاسم...',
          hintStyle: const TextStyle(
            fontSize: 13,
            color: AppColors.textSecondary,
          ),
          prefixIcon: const Icon(
            Icons.search_rounded,
            color: AppColors.primary,
            size: 20,
          ),
          suffixIcon: _driverSearchQuery.isNotEmpty
              ? IconButton(
                  key: const ValueKey<String>('clear-driver-search-button'),
                  icon: const Icon(Icons.clear_rounded, size: 18),
                  tooltip: 'مسح البحث',
                  onPressed: () {
                    _driverSearchController.clear();
                    setState(() => _driverSearchQuery = '');
                  },
                )
              : null,
          filled: true,
          fillColor: AppColors.surface,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 14,
            vertical: 10,
          ),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: Colors.grey.shade300),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: Colors.grey.shade300),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: AppColors.primary, width: 1.5),
          ),
        ),
        onChanged: (String value) {
          setState(() => _driverSearchQuery = value);
        },
      ),
    );
  }

  /// عرض تنبيه عند عدم العثور على أي عامل يطابق البحث.
  Widget _buildEmptySearchResults() {
    return Container(
      key: const ValueKey<String>('empty-search-results'),
      padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
      margin: const EdgeInsets.only(top: 8),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        children: <Widget>[
          Icon(
            Icons.person_search_outlined,
            size: 36,
            color: Colors.grey.shade400,
          ),
          const SizedBox(height: 8),
          Text(
            'لم يتم العثور على أي عامل يطابق «$_driverSearchQuery»',
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontWeight: FontWeight.w600,
              fontSize: 13,
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: 10),
          TextButton.icon(
            onPressed: () {
              _driverSearchController.clear();
              setState(() => _driverSearchQuery = '');
            },
            icon: const Icon(Icons.clear_rounded, size: 16),
            label: const Text('مسح البحث وعرض الكل'),
          ),
        ],
      ),
    );
  }

  /// هل توجد أرقام فعلياً لتصفيرها؟ (لمنع التصفير عند عدم وجود بيانات)
  bool _hasNumbersToReset(
    List<Driver> drivers,
    List<DeliveryOrder> generalOrders,
  ) =>
      generalOrders.isNotEmpty ||
      drivers.any(
        (Driver driver) =>
            driver.ordersCount > 0 || driver.totalOrdersAmount > 0,
      );
}

/// حالة عدم وجود أي عامل محفوظ.
class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.onAdd});

  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;

    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            Container(
              width: 96,
              height: 96,
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.10),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.delivery_dining_outlined,
                size: 46,
                color: AppColors.primary,
              ),
            ),
            const SizedBox(height: 20),
            Text('لا يوجد عمال بعد', style: text.titleMedium),
            const SizedBox(height: 8),
            Text(
              'أضف عامل التوصيل الأول لتبدأ بتسجيل طلباته وحساب أجره '
              'وصافي المبلغ المطلوب تسليمه للمطعم.',
              textAlign: TextAlign.center,
              style: text.bodySmall?.copyWith(height: 1.7),
            ),
            const SizedBox(height: 22),
            FilledButton.icon(
              key: const ValueKey<String>('empty-add-driver-button'),
              onPressed: onAdd,
              icon: const Icon(Icons.person_add_alt_1_outlined, size: 18),
              label: const Text('إضافة عامل'),
            ),
          ],
        ),
      ),
    );
  }
}

/// ترويسة قائمة العمال: عدد العمال وإرشاد سريع للاستخدام.
class _DriversHeader extends StatelessWidget {
  const _DriversHeader({
    required this.drivers,
    this.totalCount,
  });

  final List<Driver> drivers;
  final int? totalCount;

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    final bool isFiltering = totalCount != null && totalCount != drivers.length;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Container(
          width: 38,
          height: 38,
          decoration: BoxDecoration(
            color: AppColors.primary.withValues(alpha: 0.10),
            borderRadius: BorderRadius.circular(12),
          ),
          child: const Icon(
            Icons.groups_2_outlined,
            size: 20,
            color: AppColors.primary,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                isFiltering
                    ? 'نتائج البحث (${formatNumber(drivers.length)} من ${formatNumber(totalCount!)})'
                    : 'عمال التوصيل (${formatNumber(drivers.length)})',
                key: const ValueKey<String>('summary-drivers'),
                style: text.titleSmall,
              ),
              const SizedBox(height: 3),
              Text(
                'اضغط على البطاقة لتسجيل طلب جديد، أو استخدم أيقونة إدارة العمال '
                'لإدارة الأسماء.',
                style: text.bodySmall?.copyWith(height: 1.6),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// إجماليات اليوم المحسوبة من كل العمال والطلبات العامة.
///
/// تُستخدم في بطاقة الملخص وفي نافذة تأكيد التصفير (تتجاوز مع نصوصها
/// للحالة النهائية الصحيحة من النموذج `Driver`).
class _DailyTotals {
  const _DailyTotals({
    required this.drivers,
    required this.orders,
    required this.amounts,
    required this.wages,
    required this.net,
    this.generalOrders = 0,
    this.generalAmounts = 0,
  });

  /// حساب الإجماليات من قائمة العمال والطلبات العامة.
  factory _DailyTotals.from(
    List<Driver> drivers, {
    List<DeliveryOrder> generalOrders = const <DeliveryOrder>[],
  }) {
    int orders = 0;
    double amounts = 0;
    double wages = 0;
    double net = 0;
    for (final Driver driver in drivers) {
      orders += driver.ordersCount;
      amounts += driver.totalOrdersAmount;
      wages += driver.wage;
      net += driver.netAmountToRestaurant;
    }

    final double genAmounts = generalOrders.fold<double>(
      0,
      (double sum, DeliveryOrder o) => sum + o.amount,
    );
    orders += generalOrders.length;
    amounts += genAmounts;
    // أجرة التوصيل للطلبات العامة = 0 د.ع
    net += genAmounts; // كامل مبالغ السفري تذهب مباشرة لصافي المطعم

    return _DailyTotals(
      drivers: drivers.length,
      orders: orders,
      amounts: amounts,
      wages: wages,
      net: net,
      generalOrders: generalOrders.length,
      generalAmounts: genAmounts,
    );
  }

  /// عدد العمال.
  final int drivers;

  /// إجمالي عدد الطلبات الكلي (عمال + سفري).
  final int orders;

  /// إجمالي المبالغ الكلية.
  final double amounts;

  /// إجمالي أجور جميع العمال التي يجب دفعها.
  final double wages;

  /// إجمالي صافي المطعم (بما فيها صافي الطلبات العامة 100%).
  final double net;

  /// عدد الطلبات العامة / سفري.
  final int generalOrders;

  /// إجمالي مبالغ الطلبات العامة / سفري.
  final double generalAmounts;
}

/// بطاقة أنيقة تعرض إجماليات اليوم لكل العمال والطلبات العامة (الطلبات، المبالغ، الأجور، الصافي).
class _DailySummaryCard extends StatelessWidget {
  const _DailySummaryCard({
    required this.drivers,
    this.generalOrders = const <DeliveryOrder>[],
  });

  final List<Driver> drivers;
  final List<DeliveryOrder> generalOrders;

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    final _DailyTotals totals = _DailyTotals.from(
      drivers,
      generalOrders: generalOrders,
    );

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.border),
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: AppColors.primary.withValues(alpha: 0.08),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    begin: Alignment.topRight,
                    end: Alignment.bottomLeft,
                    colors: <Color>[AppColors.primary, AppColors.primaryDark],
                  ),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  Icons.summarize_outlined,
                  size: 19,
                  color: Colors.white,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text('ملخص اليوم', style: text.titleSmall),
                    const SizedBox(height: 2),
                    Text('إجماليات المبيعات والصافي', style: text.bodySmall),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(30),
                ),
                child: Text(
                  '${formatNumber(totals.drivers)} عمال'
                  '${totals.generalOrders > 0 ? ' • ${formatNumber(totals.generalOrders)} سفري' : ''}',
                  style: text.bodySmall?.copyWith(
                    color: AppColors.primary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          const Divider(height: 1),
          const SizedBox(height: 6),
          _SummaryRow(
            label: 'إجمالي الطلبات الكلي',
            value: formatNumber(totals.orders),
            icon: Icons.receipt_long_outlined,
            color: AppColors.primary,
            valueKey: const ValueKey<String>('summary-orders'),
          ),
          _SummaryRow(
            label: 'إجمالي المبالغ الكلية',
            value: formatAmount(totals.amounts),
            icon: Icons.payments_outlined,
            color: const Color(0xFF2563EB),
            valueKey: const ValueKey<String>('summary-total'),
          ),
          _SummaryRow(
            label: 'إجمالي أجور العمال',
            value: formatAmount(totals.wages),
            icon: Icons.savings_outlined,
            color: AppColors.accent,
            valueKey: const ValueKey<String>('summary-wage'),
          ),
          if (totals.generalOrders > 0)
            _SummaryRow(
              label: 'طلبات سفري عامة (أجر 0)',
              value: '${formatNumber(totals.generalOrders)} • ${formatAmount(totals.generalAmounts)}',
              icon: Icons.takeout_dining_outlined,
              color: const Color(0xFFEA580C),
              valueKey: const ValueKey<String>('summary-general'),
            ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topRight,
                end: Alignment.bottomLeft,
                colors: <Color>[
                  AppColors.success.withValues(alpha: 0.14),
                  AppColors.success.withValues(alpha: 0.05),
                ],
              ),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: AppColors.success.withValues(alpha: 0.25),
              ),
            ),
            child: Row(
              children: <Widget>[
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: AppColors.success.withValues(alpha: 0.16),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.storefront_outlined,
                    size: 20,
                    color: AppColors.success,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text('إجمالي الصافي للمطعم', style: text.bodySmall),
                      const SizedBox(height: 4),
                      Text(
                        formatAmount(totals.net),
                        key: const ValueKey<String>('summary-net'),
                        style: text.titleLarge?.copyWith(
                          fontSize: 19,
                          color: AppColors.success,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// سطر داخل بطاقة الملخص (أيقونة + عنوان + قيمة).
class _SummaryRow extends StatelessWidget {
  const _SummaryRow({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
    required this.valueKey,
  });

  final String label;
  final String value;
  final IconData icon;
  final Color color;
  final Key valueKey;

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Row(
        children: <Widget>[
          Icon(icon, size: 17, color: color),
          const SizedBox(width: 8),
          Expanded(child: Text(label, style: text.bodyMedium)),
          const SizedBox(width: 10),
          Text(
            value,
            key: valueKey,
            style: text.titleSmall?.copyWith(color: AppColors.textPrimary),
          ),
        ],
      ),
    );
  }
}

/// زر تصفير الحسابات بلون تحذيري هادئ.
///
/// يُعطَّل الزر تلقائياً عندما لا توجد أرقام لتصفيرها.
class _ResetDayButton extends StatelessWidget {
  const _ResetDayButton({required this.onPressed, required this.enabled});

  /// يُستدعى عند الضغط (يفتح نافذة التأكيد).
  final VoidCallback onPressed;

  /// هل يمكن التصفير؟ (يوجد طلبات أو مبالغ مسجّلة)
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;

    return Column(
      children: <Widget>[
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            key: const ValueKey<String>('summary-reset-day-button'),
            onPressed: enabled ? onPressed : null,
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.warning,
              backgroundColor: enabled
                  ? AppColors.warningSurface
                  : AppColors.warningSurface.withValues(alpha: 0.45),
              minimumSize: const Size.fromHeight(52),
              side: BorderSide(
                color: AppColors.warning.withValues(
                  alpha: enabled ? 0.45 : 0.20,
                ),
              ),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              textStyle: text.labelLarge,
            ),
            icon: const Icon(Icons.restart_alt, size: 20),
            label: const Text('تصفير الحسابات (يوم جديد)'),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          enabled
              ? 'تُصفَّر أرقام الطلبات والمبالغ لجميع العمال مع الاحتفاظ بأسمائهم.'
              : 'لا توجد أرقام مسجّلة لتصفيرها.',
          textAlign: TextAlign.center,
          style: text.bodySmall?.copyWith(height: 1.6),
        ),
      ],
    );
  }
}

/// سطر في نافذة تأكيد التصفير (عنوان + قيمة سيتم تصفيرها).
class _ResetPreviewRow extends StatelessWidget {
  const _ResetPreviewRow({required this.label, required this.value});

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

/// عنصر تفاعلي داخل القائمة الجانبية (Navigation Drawer).
class _DrawerItem extends StatelessWidget {
  const _DrawerItem({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle,
    this.iconColor,
    this.isSelected = false,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final Color? iconColor;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
      decoration: BoxDecoration(
        color: isSelected
            ? AppColors.primary.withValues(alpha: 0.10)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(10),
      ),
      child: ListTile(
        dense: true,
        visualDensity: VisualDensity.compact,
        contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 0),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        leading: Icon(
          icon,
          color: isSelected
              ? AppColors.primary
              : (iconColor ?? AppColors.textPrimary),
          size: 22,
        ),
        title: Text(
          title,
          style: TextStyle(
            fontWeight: isSelected ? FontWeight.bold : FontWeight.w600,
            color: isSelected ? AppColors.primary : AppColors.textPrimary,
            fontSize: 13,
          ),
        ),
        subtitle: subtitle != null
            ? Text(
                subtitle!,
                style: const TextStyle(
                  fontSize: 11,
                  color: AppColors.textSecondary,
                ),
              )
            : null,
        onTap: onTap,
      ),
    );
  }
}

/// بطاقة بارزة ومستقلة لتسجيل الطلبات العامة والسفري (منفصلة عن بطاقات عمال الديليفري).
class _GeneralTakeawayCard extends StatelessWidget {
  const _GeneralTakeawayCard({
    required this.generalOrders,
    required this.onRegister,
    required this.onScanCamera,
    required this.onViewHistory,
  });

  final List<DeliveryOrder> generalOrders;
  final VoidCallback onRegister;
  final VoidCallback onScanCamera;
  final VoidCallback onViewHistory;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final TextTheme text = theme.textTheme;
    final int count = generalOrders.length;
    final double totalAmount = generalOrders.fold<double>(
      0,
      (double sum, DeliveryOrder o) => sum + o.amount,
    );

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: const Color(0xFFEA580C).withValues(alpha: 0.25),
          width: 1.2,
        ),
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: const Color(0xFFEA580C).withValues(alpha: 0.08),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: <Color>[Color(0xFFEA580C), Color(0xFFC2410C)],
                    begin: Alignment.topRight,
                    end: Alignment.bottomLeft,
                  ),
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: <BoxShadow>[
                    BoxShadow(
                      color: const Color(0xFFEA580C).withValues(alpha: 0.3),
                      blurRadius: 8,
                      offset: const Offset(0, 3),
                    ),
                  ],
                ),
                child: const Icon(
                  Icons.takeout_dining_rounded,
                  color: Colors.white,
                  size: 22,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      'طلب سفري / عام',
                      style: text.titleSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                        fontSize: 15,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'بدون عامل ديليفري • أجر التوصيل: 0 د.ع (صافي 100%)',
                      style: text.bodySmall?.copyWith(
                        fontSize: 11,
                        color: AppColors.success,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              if (count > 0)
                InkWell(
                  key: const ValueKey<String>('view-general-orders-button'),
                  onTap: onViewHistory,
                  borderRadius: BorderRadius.circular(20),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 5,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFFEA580C).withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        const Icon(
                          Icons.receipt_long_rounded,
                          size: 14,
                          color: Color(0xFFEA580C),
                        ),
                        const SizedBox(width: 4),
                        Text(
                          '${formatNumber(count)} • ${formatAmount(totalAmount)}',
                          style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFFEA580C),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: <Widget>[
              Expanded(
                flex: 3,
                child: FilledButton.icon(
                  key: const ValueKey<String>('register-general-order-button'),
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFFEA580C),
                    foregroundColor: Colors.white,
                    minimumSize: const Size.fromHeight(46),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  onPressed: onRegister,
                  icon: const Icon(Icons.add_shopping_cart_rounded, size: 18),
                  label: const Text(
                    'تسجيل طلب سفري / عام',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                flex: 2,
                child: OutlinedButton.icon(
                  key: const ValueKey<String>('scan-takeaway-camera-button'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFFEA580C),
                    minimumSize: const Size.fromHeight(46),
                    side: const BorderSide(
                      color: Color(0xFFEA580C),
                      width: 1.5,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                    backgroundColor:
                        const Color(0xFFEA580C).withValues(alpha: 0.05),
                  ),
                  onPressed: onScanCamera,
                  icon: const Icon(Icons.document_scanner_rounded, size: 18),
                  label: const Text(
                    'مسح الفاتورة',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
