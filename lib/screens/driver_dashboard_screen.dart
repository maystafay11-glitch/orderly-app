import 'dart:async';

import 'package:flutter/material.dart';
import 'package:orderly_app/models/delivery_order.dart';
import 'package:orderly_app/models/driver.dart';
import 'package:orderly_app/models/order_payment_type.dart';
import 'package:orderly_app/models/order_status.dart';
import 'package:orderly_app/screens/unified_login_screen.dart';
import 'package:orderly_app/services/auth_session_service.dart';
import 'package:orderly_app/services/driver_storage.dart';
import 'package:orderly_app/services/firebase_tracking_service.dart';
import 'package:orderly_app/theme/app_theme.dart';
import 'package:orderly_app/utils/formatters.dart';

/// تطبيق وواجهة السائق المباشرة (Driver App).
///
/// مصممة خصيصاً للاستخدام السريع والميداني:
/// * أزرار عريضة وواضحة (تم الاستلام من المطعم 🛵 / تم التسليم للزبون ✅).
/// * عداد زمني حي لحساب وقت الرحلة على الطريق بدقة ومنع "التسخيت".
/// * مؤشر تحذيري باللون الأحمر عند تجاوز وقت الطريق الطبيعي (25 دقيقة).
/// * مزامنة سحابية لحظية مع لوحة الكاشير والمطعم.
class DriverDashboardScreen extends StatefulWidget {
  const DriverDashboardScreen({super.key, required this.driver});

  final Driver driver;

  @override
  State<DriverDashboardScreen> createState() => _DriverDashboardScreenState();
}

class _DriverDashboardScreenState extends State<DriverDashboardScreen> {
  late Driver _currentDriver;
  int _selectedTab = 0; // 0: الطلبات النشطة، 1: وردية اليوم
  Timer? _tickerTimer;
  StreamSubscription<List<DeliveryOrder>>? _ordersSubscription;

  @override
  void initState() {
    super.initState();
    _currentDriver = widget.driver;
    _startPeriodicTimer();
    _listenToTrackingUpdates();
  }

  @override
  void dispose() {
    _tickerTimer?.cancel();
    _ordersSubscription?.cancel();
    super.dispose();
  }

  /// مؤقت دوري كل 10 ثوانٍ لتحديث عدادات الرحلة الحية على الشاشة بدقة.
  void _startPeriodicTimer() {
    _tickerTimer = Timer.periodic(const Duration(seconds: 10), (Timer _) {
      if (mounted) {
        setState(() {});
      }
    });
  }

  /// الاستماع لتحديثات السحابة وFirebase اللحظية.
  void _listenToTrackingUpdates() {
    _ordersSubscription = FirebaseTrackingService.instance.ordersStream.listen((_) {
      _refreshDriverData();
    });
  }

  Future<void> _refreshDriverData() async {
    final Driver? refreshed = await DriverStorage.loadDriverByPin(_currentDriver.pin);
    if (refreshed != null && mounted) {
      setState(() => _currentDriver = refreshed);
    }
  }

  Future<void> _handlePickedUp(DeliveryOrder order) async {
    final bool success = await FirebaseTrackingService.instance.markOrderPickedUp(
      orderId: order.id,
      driverPin: _currentDriver.pin,
    );

    if (success && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('🛵 تم تسجيل خروج الطلب (${order.displayNumber}) وبدء مؤقت الرحلة'),
          backgroundColor: AppColors.primary,
        ),
      );
      await _refreshDriverData();
    }
  }

  Future<void> _handleDelivered(DeliveryOrder order) async {
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext ctx) => AlertDialog(
        title: const Row(
          children: <Widget>[
            Icon(Icons.check_circle_outline, color: AppColors.success),
            SizedBox(width: 8),
            Text('تأكيد التسليم للزبون'),
          ],
        ),
        content: Text(
          'هل تم تسليم الطلب رقم «${order.displayNumber}» واستلام المبلغ '
          '(${formatAmount(order.amount)}) بنجاح؟',
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('تراجع'),
          ),
          FilledButton.icon(
            style: FilledButton.styleFrom(backgroundColor: AppColors.success),
            onPressed: () => Navigator.pop(ctx, true),
            icon: const Icon(Icons.done_all),
            label: const Text('نعم، تم التسليم'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    final bool success = await FirebaseTrackingService.instance.markOrderDelivered(
      orderId: order.id,
      driverPin: _currentDriver.pin,
    );

    if (success && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('🎉 تم تسليم الطلب (${order.displayNumber}) واحتساب أجرتك!'),
          backgroundColor: AppColors.success,
        ),
      );
      await _refreshDriverData();
    }
  }

  Future<void> _logout() async {
    await AuthSessionService.logout();
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute<void>(builder: (BuildContext _) => const UnifiedLoginScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    final List<DeliveryOrder> activeOrders =
        _currentDriver.orders.where((DeliveryOrder o) => o.status.isActive).toList();
    final List<DeliveryOrder> deliveredOrders =
        _currentDriver.orders.where((DeliveryOrder o) => o.status.isCompleted).toList();

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.surface,
        automaticallyImplyLeading: false,
        title: Row(
          children: <Widget>[
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                gradient: AppColors.accentGradient,
                shape: BoxShape.circle,
                boxShadow: <BoxShadow>[
                  BoxShadow(
                    color: AppColors.accent.withValues(alpha: 0.35),
                    blurRadius: 10,
                  ),
                ],
              ),
              alignment: Alignment.center,
              child: Text(
                _currentDriver.name.substring(0, 1),
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w800,
                  fontSize: 16,
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    _currentDriver.name,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 15,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  Text(
                    'PIN: ${_currentDriver.pin}',
                    style: const TextStyle(
                      fontSize: 11,
                      color: AppColors.textMuted,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        bottom: const PreferredSize(
          preferredSize: Size.fromHeight(1),
          child: Divider(height: 1, color: AppColors.border),
        ),
        actions: <Widget>[
          // مؤشر الاتصال المباشر بالسحابة
          Container(
            margin: const EdgeInsets.symmetric(vertical: 14, horizontal: 4),
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: AppColors.success.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.success.withValues(alpha: 0.3)),
            ),
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Icon(Icons.circle, color: AppColors.success, size: 7),
                SizedBox(width: 5),
                Text(
                  'مباشر',
                  style: TextStyle(
                    fontSize: 11,
                    color: AppColors.successLight,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.logout_rounded, color: AppColors.textSecondary),
            tooltip: 'تسجيل الخروج',
            onPressed: _logout,
          ),
        ],
      ),
      bottomNavigationBar: Container(
        decoration: const BoxDecoration(
          color: AppColors.surface,
          border: Border(top: BorderSide(color: AppColors.border)),
        ),
        child: NavigationBar(
          selectedIndex: _selectedTab,
          onDestinationSelected: (int index) =>
              setState(() => _selectedTab = index),
          backgroundColor: Colors.transparent,
          elevation: 0,
          indicatorColor: AppColors.accent.withValues(alpha: 0.15),
          destinations: <NavigationDestination>[
            NavigationDestination(
              icon: Badge(
                isLabelVisible: activeOrders.isNotEmpty,
                label: Text('${activeOrders.length}'),
                child: const Icon(
                    Icons.motorcycle_outlined, color: AppColors.textMuted),
              ),
              selectedIcon: Badge(
                isLabelVisible: activeOrders.isNotEmpty,
                label: Text('${activeOrders.length}'),
                child:
                    const Icon(Icons.motorcycle, color: AppColors.accent),
              ),
              label: 'الطلبات النشطة',
            ),
            const NavigationDestination(
              icon: Icon(Icons.history_outlined, color: AppColors.textMuted),
              selectedIcon: Icon(Icons.history, color: AppColors.accent),
              label: 'سجل وردية اليوم',
            ),
          ],
        ),
      ),
      body: _selectedTab == 0
          ? _buildActiveOrdersView(activeOrders)
          : _buildShiftHistoryView(deliveredOrders),
    );
  }

  /// واجهة الطلبات النشطة (الاستلام والتسليم)
  Widget _buildActiveOrdersView(List<DeliveryOrder> activeOrders) {
    if (activeOrders.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              Container(
                width: 90,
                height: 90,
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.two_wheeler_outlined, size: 48, color: AppColors.primary),
              ),
              const SizedBox(height: 20),
              const Text(
                'لا توجد طلبات جارية حالياً',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              const Text(
                'بمجرد إسناد الكاشير لطلب جديد، سيظهر لك هنا فوراً مع تنبيه صوتي.',
                textAlign: TextAlign.center,
                style: TextStyle(color: AppColors.textSecondary, fontSize: 13, height: 1.5),
              ),
            ],
          ),
        ),
      );
    }

    return ListView(
      padding: const EdgeInsets.all(16),
      children: <Widget>[
        // لافتة توجيهية: واجهة السائق مقتصرة على زري المتابعة فقط
        Container(
          margin: const EdgeInsets.only(bottom: 14),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: AppColors.primary.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppColors.primary.withValues(alpha: 0.2)),
          ),
          child: const Row(
            children: <Widget>[
              Icon(Icons.touch_app_outlined, color: AppColors.primary, size: 22),
              SizedBox(width: 10),
              Expanded(
                child: Text(
                  'متابعة لحظية لمنع التأخير: واجهة السائق مقتصرة على زري متابعة الحالة فقط أدناه لتحديث السحابة فوراً (إدخال الطلبات يتم من الكاشير).',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary,
                    height: 1.4,
                  ),
                ),
              ),
            ],
          ),
        ),

        // قائمة الطلبات النشطة المسندة للسائق
        for (final DeliveryOrder order in activeOrders) ...<Widget>[
          _buildDriverOrderCard(order),
          const SizedBox(height: 14),
        ],
      ],
    );
  }

  /// بطاقة الطلب التفاعلية للسائق المقتصرة على زري المتابعة فقط
  Widget _buildDriverOrderCard(DeliveryOrder order) {
    final bool isOnTheRoad = order.status == OrderStatus.pickedUp;
    final bool isDelayed = order.isDelayed;

    return Card(
      elevation: 3,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(
          color: isDelayed
              ? AppColors.danger
              : (isOnTheRoad ? const Color(0xFF2563EB) : AppColors.border),
          width: isDelayed ? 2.0 : 1.2,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            // السطر العلوي: رقم الطلب والمبلغ ونوع الدفع وحالة المتابعة
            Row(
              children: <Widget>[
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    'طلب #${order.displayNumber}',
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 15,
                      color: AppColors.primary,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: order.paymentType == OrderPaymentType.cash
                        ? Colors.green.shade50
                        : Colors.purple.shade50,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    order.displayPayment,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: order.paymentType == OrderPaymentType.cash
                          ? Colors.green.shade800
                          : Colors.purple.shade800,
                    ),
                  ),
                ),
                const Spacer(),
                Text(
                  formatAmount(order.amount),
                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                    color: AppColors.textPrimary,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),

            // مؤقت الرحلة والتنبيه الزمني لمنع التأخير
            if (isOnTheRoad) ...<Widget>[
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: isDelayed
                      ? AppColors.danger.withValues(alpha: 0.1)
                      : const Color(0xFF2563EB).withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: isDelayed
                      ? AppColors.danger.withValues(alpha: 0.4)
                      : const Color(0xFF2563EB).withValues(alpha: 0.3),
                  ),
                ),
                child: Row(
                  children: <Widget>[
                    Icon(
                      isDelayed ? Icons.warning_amber_rounded : Icons.timer_outlined,
                      color: isDelayed ? AppColors.danger : const Color(0xFF2563EB),
                      size: 22,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Text(
                            'وقت الرحلة على الطريق: ${order.durationFormatted}',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.bold,
                              color: isDelayed ? AppColors.danger : const Color(0xFF2563EB),
                            ),
                          ),
                          if (isDelayed)
                            Text(
                              '⚠️ متأخر +${order.delayMinutes} دقيقة عن الوقت الطبيعي (منع التسخيت)',
                              style: const TextStyle(
                                fontSize: 11,
                                color: AppColors.danger,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
            ],

            // شريط إرشادي للزرين التفاعليين
            Row(
              children: <Widget>[
                Icon(
                  isOnTheRoad ? Icons.directions_bike : Icons.store_mall_directory_outlined,
                  size: 16,
                  color: AppColors.textSecondary,
                ),
                const SizedBox(width: 6),
                Text(
                  isOnTheRoad
                      ? 'الخطوة الحالية: في الطريق للزبون 🛵'
                      : 'الخطوة الحالية: بانتظار الاستلام من المطعم ⏳',
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),

            // الزر 1: زر (تم الاستلام من المطعم)
            if (!isOnTheRoad)
              FilledButton.icon(
                key: const Key('pickup_action_button'),
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                onPressed: () => _handlePickedUp(order),
                icon: const Icon(Icons.two_wheeler_rounded, size: 22),
                label: const Text(
                  'تم الاستلام من المطعم',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                ),
              )
            else
              OutlinedButton.icon(
                key: const Key('pickup_done_button'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.green.shade700,
                  side: BorderSide(color: Colors.green.shade400, width: 1.2),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  backgroundColor: Colors.green.shade50.withValues(alpha: 0.5),
                ),
                onPressed: () {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        order.pickedUpAt != null
                            ? 'تم استلام الطلب من المطعم في الساعة ${formatTime(order.pickedUpAt!)} والرحلة جارية'
                            : 'تم تأكيد الاستلام من المطعم مسبقاً',
                      ),
                      duration: const Duration(seconds: 2),
                    ),
                  );
                },
                icon: const Icon(Icons.check_circle, color: AppColors.success, size: 20),
                label: Text(
                  order.pickedUpAt != null
                      ? 'تم الاستلام من المطعم (${formatTime(order.pickedUpAt!)})'
                      : 'تم الاستلام من المطعم ✓',
                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
                ),
              ),

            const SizedBox(height: 10),

            // الزر 2: زر (تم التسليم للزبون)
            if (isOnTheRoad)
              FilledButton.icon(
                key: const Key('deliver_action_button'),
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.success,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  elevation: 2,
                ),
                onPressed: () => _handleDelivered(order),
                icon: const Icon(Icons.done_all_rounded, size: 22),
                label: const Text(
                  'تم التسليم للزبون',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                ),
              )
            else
              OutlinedButton.icon(
                key: const Key('deliver_pending_button'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.textSecondary,
                  side: const BorderSide(color: AppColors.border, width: 1.2),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                onPressed: () {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('⚠️ يرجى الضغط على زر (تم الاستلام من المطعم) أولاً لبدء الرحلة وتفعيل التسليم'),
                      duration: Duration(seconds: 2),
                    ),
                  );
                },
                icon: const Icon(Icons.check_circle_outline, size: 20),
                label: const Text(
                  'تم التسليم للزبون (يتطلب الاستلام أولاً)',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                ),
              ),
          ],
        ),
      ),
    );
  }

  /// واجهة سجل وردية اليوم وإحصائيات أداء السائق
  Widget _buildShiftHistoryView(List<DeliveryOrder> deliveredOrders) {
    final double totalCash = deliveredOrders
        .where((DeliveryOrder o) => o.collectsCash)
        .fold<double>(0, (double s, DeliveryOrder o) => s + o.amount);

    return ListView(
      padding: const EdgeInsets.all(16),
      children: <Widget>[
        // بطاقة ملخص الوردية
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: <Color>[AppColors.primaryDark, AppColors.primary],
              begin: Alignment.topRight,
              end: Alignment.bottomLeft,
            ),
            borderRadius: BorderRadius.circular(20),
            boxShadow: <BoxShadow>[
              BoxShadow(
                color: AppColors.primary.withValues(alpha: 0.25),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              const Text('ملخص وردية اليوم', style: TextStyle(color: Colors.white70, fontSize: 13)),
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: <Widget>[
                  _buildShiftStat('الطلبات المنجزة', '${deliveredOrders.length}', Icons.check_circle_outline),
                  _buildShiftStat('أجرتك اليوم', formatAmount(_currentDriver.wage), Icons.savings_outlined),
                  _buildShiftStat('الكاش معك', formatAmount(totalCash), Icons.payments_outlined),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),

        const Text(
          'الطلبات المكتملة اليوم:',
          style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 10),

        if (deliveredOrders.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 30),
            child: Center(
              child: Text(
                'لم تكمل أي طلبات اليوم حتى الآن.',
                style: TextStyle(color: AppColors.textSecondary),
              ),
            ),
          )
        else
          for (final DeliveryOrder order in deliveredOrders) ...<Widget>[
            Card(
              margin: const EdgeInsets.only(bottom: 10),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              child: ListTile(
                leading: Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: AppColors.success.withValues(alpha: 0.15),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.check, color: AppColors.success, size: 20),
                ),
                title: Text(
                  'طلب #${order.displayNumber} • ${formatAmount(order.amount)}',
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                ),
                subtitle: Text(
                  'مدة الرحلة: ${order.durationFormatted} '
                  '${order.isDelayed ? '(⚠️ متأخر)' : '(في الوقت المحدد)'}',
                  style: TextStyle(
                    fontSize: 12,
                    color: order.isDelayed ? AppColors.danger : AppColors.textSecondary,
                  ),
                ),
                trailing: Text(
                  order.deliveredAt != null ? formatTime(order.deliveredAt!) : '',
                  style: const TextStyle(fontSize: 11, color: AppColors.textSecondary),
                ),
              ),
            ),
          ],
      ],
    );
  }

  Widget _buildShiftStat(String label, String value, IconData icon) {
    return Column(
      children: <Widget>[
        Icon(icon, color: Colors.white, size: 20),
        const SizedBox(height: 4),
        Text(
          value,
          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14),
        ),
        Text(
          label,
          style: const TextStyle(color: Colors.white70, fontSize: 10),
        ),
      ],
    );
  }
}
