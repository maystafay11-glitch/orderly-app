import 'dart:async';

import 'package:flutter/material.dart';
import 'package:orderly_app/models/delivery_order.dart';
import 'package:orderly_app/models/driver.dart';
import 'package:orderly_app/models/order_status.dart';
import 'package:orderly_app/screens/driver_login_screen.dart';
import 'package:orderly_app/screens/driver_shift_history_screen.dart';
import 'package:orderly_app/services/driver_storage.dart';
import 'package:orderly_app/services/firebase_tracking_service.dart';
import 'package:orderly_app/theme/app_theme.dart';
import 'package:orderly_app/utils/formatters.dart';

/// شاشة تتبع السائقين وحالات الطلبات اللحظية (Restaurant Live Tracking Dashboard).
///
/// تمكّن الكاشير وإدارة المطعم من:
/// * متابعة مسار كل طلب (قيد الإعداد ➡️ مع السائق ➡️ تم التسليم).
/// * عداد زمني حي لكل طلب مع السائق، ومؤشر تحذيري باللون الأحمر عند التأخير.
/// * كشف "التسخيت" فوراً ومتابعة السائقين والطلبات المتأخرة.
class LiveTrackingScreen extends StatefulWidget {
  const LiveTrackingScreen({super.key});

  static const String title = 'تتبع السائقين والطلبات';

  @override
  State<LiveTrackingScreen> createState() => _LiveTrackingScreenState();
}

class _LiveTrackingScreenState extends State<LiveTrackingScreen> {
  List<Driver> _drivers = <Driver>[];
  List<DeliveryOrder> _allOrders = <DeliveryOrder>[];
  OrderStatus? _filterStatus;
  Timer? _refreshTimer;
  StreamSubscription<List<DeliveryOrder>>? _ordersSubscription;

  @override
  void initState() {
    super.initState();
    _loadData();
    _refreshTimer = Timer.periodic(const Duration(seconds: 10), (Timer _) {
      if (mounted) setState(() {});
    });
    _ordersSubscription = FirebaseTrackingService.instance.ordersStream.listen((_) {
      _loadData();
    });
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    _ordersSubscription?.cancel();
    super.dispose();
  }

  Future<void> _loadData() async {
    final List<Driver> drivers = await DriverStorage.loadDrivers();
    final List<DeliveryOrder> general = await DriverStorage.loadGeneralOrders();

    final List<DeliveryOrder> orders = <DeliveryOrder>[];
    for (final Driver d in drivers) {
      orders.addAll(d.orders);
    }
    orders.addAll(general);

    if (mounted) {
      setState(() {
        _drivers = drivers;
        _allOrders = orders;
      });
    }
  }

  List<DeliveryOrder> get _filteredOrders {
    if (_filterStatus == null) return _allOrders;
    return _allOrders.where((DeliveryOrder o) => o.status == _filterStatus).toList();
  }

  @override
  Widget build(BuildContext context) {
    final List<DeliveryOrder> preparingOrders =
        _allOrders.where((DeliveryOrder o) => o.status == OrderStatus.preparing).toList();
    final List<DeliveryOrder> onRoadOrders =
        _allOrders.where((DeliveryOrder o) => o.status == OrderStatus.pickedUp).toList();
    final List<DeliveryOrder> delayedOrders =
        _allOrders.where((DeliveryOrder o) => o.status == OrderStatus.pickedUp && o.isDelayed).toList();
    final List<DeliveryOrder> deliveredToday =
        _allOrders.where((DeliveryOrder o) => o.status == OrderStatus.delivered).toList();

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text(LiveTrackingScreen.title),
        actions: <Widget>[
          IconButton(
            icon: const Icon(Icons.assessment_outlined),
            tooltip: 'أرشيف الورديات اليومية',
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (BuildContext _) => const DriverShiftHistoryScreen(),
                ),
              );
            },
          ),
          IconButton(
            icon: const Icon(Icons.two_wheeler_outlined),
            tooltip: 'فتح تطبيق السائق (PIN)',
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (BuildContext _) => const DriverLoginScreen(),
                ),
              );
            },
          ),
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            tooltip: 'تحديث',
            onPressed: _loadData,
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _loadData,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: <Widget>[
            // لوحة العدادات العلوية
            _buildCountersGrid(
              preparing: preparingOrders.length,
              onRoad: onRoadOrders.length,
              delayed: delayedOrders.length,
              delivered: deliveredToday.length,
            ),
            const SizedBox(height: 16),

            // أزرار تصفية الحالات
            _buildStatusFilters(),
            const SizedBox(height: 14),

            // قائمة الطلبات المباشرة
            if (_filteredOrders.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 40),
                child: Center(
                  child: Column(
                    children: <Widget>[
                      Icon(Icons.inventory_2_outlined, size: 48, color: Colors.grey.shade400),
                      const SizedBox(height: 12),
                      const Text(
                        'لا توجد طلبات تطابق هذه الحالة',
                        style: TextStyle(color: AppColors.textSecondary),
                      ),
                    ],
                  ),
                ),
              )
            else
              for (final DeliveryOrder order in _filteredOrders) ...<Widget>[
                _buildLiveOrderCard(order),
                const SizedBox(height: 12),
              ],
          ],
        ),
      ),
    );
  }

  /// شبكة العدادات الإحصائية السريعة
  Widget _buildCountersGrid({
    required int preparing,
    required int onRoad,
    required int delayed,
    required int delivered,
  }) {
    return Row(
      children: <Widget>[
        Expanded(
          child: _buildCounterTile(
            title: 'قيد الإعداد',
            count: preparing,
            color: const Color(0xFFF59E0B),
            icon: Icons.outdoor_grill_outlined,
            onTap: () => setState(() => _filterStatus = OrderStatus.preparing),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _buildCounterTile(
            title: 'مع السائق',
            count: onRoad,
            color: const Color(0xFF2563EB),
            icon: Icons.two_wheeler_rounded,
            onTap: () => setState(() => _filterStatus = OrderStatus.pickedUp),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _buildCounterTile(
            title: 'متأخرة ⚠️',
            count: delayed,
            color: AppColors.danger,
            icon: Icons.warning_amber_rounded,
            isHighlighted: delayed > 0,
            onTap: () => setState(() => _filterStatus = OrderStatus.pickedUp),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _buildCounterTile(
            title: 'تم التسليم',
            count: delivered,
            color: AppColors.success,
            icon: Icons.check_circle_rounded,
            onTap: () => setState(() => _filterStatus = OrderStatus.delivered),
          ),
        ),
      ],
    );
  }

  Widget _buildCounterTile({
    required String title,
    required int count,
    required Color color,
    required IconData icon,
    bool isHighlighted = false,
    VoidCallback? onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
        decoration: BoxDecoration(
          color: isHighlighted ? color.withValues(alpha: 0.15) : AppColors.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: isHighlighted ? color : AppColors.border,
            width: isHighlighted ? 1.8 : 1.0,
          ),
        ),
        child: Column(
          children: <Widget>[
            Icon(icon, color: color, size: 20),
            const SizedBox(height: 4),
            Text(
              '$count',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: isHighlighted ? color : AppColors.textPrimary,
              ),
            ),
            Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 10, color: AppColors.textSecondary),
            ),
          ],
        ),
      ),
    );
  }

  /// شريط الفلاتر السريعة
  Widget _buildStatusFilters() {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: <Widget>[
          ChoiceChip(
            label: const Text('جميع الحالات'),
            selected: _filterStatus == null,
            onSelected: (_) => setState(() => _filterStatus = null),
          ),
          const SizedBox(width: 8),
          ChoiceChip(
            label: const Text('قيد الإعداد بالمطعم'),
            selected: _filterStatus == OrderStatus.preparing,
            onSelected: (_) => setState(() => _filterStatus = OrderStatus.preparing),
          ),
          const SizedBox(width: 8),
          ChoiceChip(
            label: const Text('مع السائق (بالطريق)'),
            selected: _filterStatus == OrderStatus.pickedUp,
            onSelected: (_) => setState(() => _filterStatus = OrderStatus.pickedUp),
          ),
          const SizedBox(width: 8),
          ChoiceChip(
            label: const Text('تم التسليم للزبون'),
            selected: _filterStatus == OrderStatus.delivered,
            onSelected: (_) => setState(() => _filterStatus = OrderStatus.delivered),
          ),
        ],
      ),
    );
  }

  /// بطاقة متابعة مسار الطلب للكاشير
  Widget _buildLiveOrderCard(DeliveryOrder order) {
    final bool isOnRoad = order.status == OrderStatus.pickedUp;
    final bool isDelayed = order.isDelayed;

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: isDelayed ? AppColors.danger : (isOnRoad ? const Color(0xFF2563EB) : AppColors.border),
          width: isDelayed ? 2.0 : 1.0,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            // الترويسة: رقم الطلب، السائق، والمبلغ
            Row(
              children: <Widget>[
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    'طلب #${order.displayNumber}',
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: AppColors.primary),
                  ),
                ),
                const SizedBox(width: 8),
                if (order.driverName != null && order.driverName!.isNotEmpty)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.blue.shade50,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      children: <Widget>[
                        const Icon(Icons.badge_outlined, size: 13, color: Color(0xFF2563EB)),
                        const SizedBox(width: 4),
                        Text(
                          '${order.driverName} (${order.driverPin ?? ''})',
                          style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFF2563EB)),
                        ),
                      ],
                    ),
                  )
                else
                  const Text('طلب سفري عام', style: TextStyle(fontSize: 11, color: AppColors.textSecondary)),
                const Spacer(),
                Text(
                  formatAmount(order.amount),
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                ),
              ],
            ),
            const SizedBox(height: 12),

            // مؤشر مسار الطلب المرحلي (Stepper)
            _buildOrderStepper(order.status),
            const SizedBox(height: 10),

            // مؤشر وقت الطريق والتحذير الأحمر
            if (isOnRoad)
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: isDelayed ? AppColors.danger.withValues(alpha: 0.12) : const Color(0xFF2563EB).withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: isDelayed ? AppColors.danger : const Color(0xFF2563EB).withValues(alpha: 0.3),
                  ),
                ),
                child: Row(
                  children: <Widget>[
                    Icon(
                      isDelayed ? Icons.warning_amber_rounded : Icons.timer_outlined,
                      color: isDelayed ? AppColors.danger : const Color(0xFF2563EB),
                      size: 20,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        isDelayed
                            ? '⚠️ تحذير تأخير: الطلب في الطريق منذ ${order.durationFormatted} (تجاوز الوقت بـ +${order.delayMinutes} دقيقة)'
                            : 'مدة الطريق حتى الآن: ${order.durationFormatted} (ضمن الوقت الطبيعي)',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: isDelayed ? AppColors.danger : const Color(0xFF2563EB),
                        ),
                      ),
                    ),
                  ],
                ),
              ),

            if (order.status == OrderStatus.delivered && order.duration != null)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  '✅ تم التسليم • استغرقت الرحلة: ${order.durationFormatted} '
                  '${order.isDelayed ? '(متأخر)' : ''}',
                  style: TextStyle(
                    fontSize: 11,
                    color: order.isDelayed ? AppColors.danger : AppColors.success,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  /// رسم المؤشر المرحلي للطلب: (قيد الإعداد ➡️ مع السائق ➡️ تم التسليم)
  Widget _buildOrderStepper(OrderStatus status) {
    return Row(
      children: <Widget>[
        _buildStepIndicator(
          title: 'قيد الإعداد',
          isDone: status.stepIndex >= 0,
          isActive: status == OrderStatus.preparing,
          icon: Icons.outdoor_grill_outlined,
          color: const Color(0xFFF59E0B),
        ),
        Expanded(
          child: Container(
            height: 2,
            color: status.stepIndex >= 1 ? const Color(0xFF2563EB) : Colors.grey.shade300,
          ),
        ),
        _buildStepIndicator(
          title: 'مع السائق',
          isDone: status.stepIndex >= 1,
          isActive: status == OrderStatus.pickedUp,
          icon: Icons.two_wheeler_rounded,
          color: const Color(0xFF2563EB),
        ),
        Expanded(
          child: Container(
            height: 2,
            color: status.stepIndex >= 2 ? AppColors.success : Colors.grey.shade300,
          ),
        ),
        _buildStepIndicator(
          title: 'تم التسليم',
          isDone: status.stepIndex >= 2,
          isActive: status == OrderStatus.delivered,
          icon: Icons.check_circle_rounded,
          color: AppColors.success,
        ),
      ],
    );
  }

  Widget _buildStepIndicator({
    required String title,
    required bool isDone,
    required bool isActive,
    required IconData icon,
    required Color color,
  }) {
    final Color currentColor = isDone ? color : Colors.grey.shade400;

    return Column(
      children: <Widget>[
        Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            color: isActive ? currentColor : currentColor.withValues(alpha: 0.15),
            shape: BoxShape.circle,
            border: Border.all(color: currentColor, width: 1.5),
          ),
          child: Icon(
            icon,
            size: 16,
            color: isActive ? Colors.white : currentColor,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          title,
          style: TextStyle(
            fontSize: 10,
            fontWeight: isActive ? FontWeight.bold : FontWeight.normal,
            color: isDone ? AppColors.textPrimary : AppColors.textSecondary,
          ),
        ),
      ],
    );
  }
}
