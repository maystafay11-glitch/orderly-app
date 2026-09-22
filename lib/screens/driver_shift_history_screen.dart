import 'package:flutter/material.dart';
import 'package:orderly_app/models/delivery_order.dart';
import 'package:orderly_app/models/driver.dart';
import 'package:orderly_app/models/shift_record.dart';
import 'package:orderly_app/services/driver_storage.dart';
import 'package:orderly_app/theme/app_theme.dart';
import 'package:orderly_app/utils/formatters.dart';
import 'package:orderly_app/utils/whatsapp.dart';

/// شاشة سجل مسار التوصيل اليومي (Shift History).
///
/// أرشيف يومي لكل سائق يوضح:
/// * عدد الطلبات المنجزة وأوقاتها بدقة.
/// * وقت خروج الطلب ووقت التسليم والمدة المستغرقة.
/// * نسبة الالتزام بالوقت وعدد الطلبات المتأخرة لتقييم الأداء بدقة نهاية الأسبوع.
/// * إمكانية مشاركة تقرير الوردية المنظّم عبر واتساب للمدير.
class DriverShiftHistoryScreen extends StatefulWidget {
  const DriverShiftHistoryScreen({super.key, this.initialDriverPin});

  final String? initialDriverPin;

  static const String title = 'سجل مسار التوصيل اليومي';

  @override
  State<DriverShiftHistoryScreen> createState() => _DriverShiftHistoryScreenState();
}

class _DriverShiftHistoryScreenState extends State<DriverShiftHistoryScreen> {
  List<Driver> _drivers = <Driver>[];
  List<ShiftRecord> _records = <ShiftRecord>[];
  String? _selectedPin;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _selectedPin = widget.initialDriverPin;
    _loadData();
  }

  Future<void> _loadData() async {
    final List<Driver> drivers = await DriverStorage.loadDrivers();
    final List<ShiftRecord> records = await DriverStorage.loadShiftRecords();

    if (mounted) {
      setState(() {
        _drivers = drivers;
        _records = records;
        if (_selectedPin == null && drivers.isNotEmpty) {
          _selectedPin = drivers.first.pin;
        }
        _isLoading = false;
      });
    }
  }

  ShiftRecord? get _currentShiftRecord {
    if (_selectedPin == null) return null;

    // البحث في السجلات المسجلة أولاً
    for (final ShiftRecord r in _records) {
      if (r.driverPin == _selectedPin) {
        return r;
      }
    }

    // إذا لم يوجد سجل تاريخي بعد، نولد سجلاً حياً من طلبات السائق الحالية
    final Driver driver = _drivers.firstWhere(
      (Driver d) => d.pin == _selectedPin,
      orElse: () => const Driver(name: ''),
    );

    if (driver == null || driver.name.isEmpty) return null;

    return ShiftRecord(
      driverPin: driver.pin,
      driverName: driver.name,
      date: DateTime.now(),
      orders: driver.orders,
    );
  }

  Future<void> _shareReportViaWhatsApp(ShiftRecord record) async {
    final StringBuffer buffer = StringBuffer();
    buffer.writeln('📋 *تقرير مسار التوصيل اليومي — Orderly*');
    buffer.writeln('🛵 السائق: ${record.driverName} (PIN: ${record.driverPin})');
    buffer.writeln('📅 التاريخ: ${formatDate(record.date)}');
    buffer.writeln('━━━━━━━━━━━━━━━━━━');
    buffer.writeln('📦 إجمالي الطلبات: ${formatNumber(record.totalOrdersCount)}');
    buffer.writeln('✅ الطلبات المنجزة: ${formatNumber(record.completedOrdersCount)}');
    buffer.writeln('⏱️ متوسط وقت التوصيل: ${record.averageDeliveryMinutes.round()} دقيقة');
    buffer.writeln('⚠️ طلبات متأخرة: ${formatNumber(record.delayedOrdersCount)}');
    buffer.writeln('🎯 نسبة الالتزام بالوقت: ${record.onTimeRatePercent}%');
    buffer.writeln('💵 الكاش المقبوض: ${formatAmount(record.totalCollectedCash)}');
    buffer.writeln('💰 أجور التوصيل المستحقة: ${formatAmount(record.totalWagesEarned)}');
    buffer.writeln('━━━━━━━━━━━━━━━━━━');
    buffer.writeln('تفاصيل الرحلات:');

    for (final DeliveryOrder o in record.orders) {
      buffer.writeln(
        '• طلب #${o.displayNumber}: ${formatAmount(o.amount)} — '
        'المدة: ${o.durationFormatted} '
        '${o.isDelayed ? '(⚠️ متأخر)' : ''}',
      );
    }

    await WhatsAppLink.launch(message: buffer.toString());
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text(DriverShiftHistoryScreen.title),
        actions: <Widget>[
          if (_currentShiftRecord != null)
            IconButton(
              icon: const Icon(Icons.share_outlined),
              tooltip: 'مشاركة التقرير عبر واتساب',
              onPressed: () => _shareReportViaWhatsApp(_currentShiftRecord!),
            ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: <Widget>[
                // شريط اختيار السائق بالرمز والاسم
                if (_drivers.isNotEmpty) _buildDriverSelector(),

                Expanded(
                  child: _currentShiftRecord == null
                      ? const Center(child: Text('لا توجد بيانات متاحة لهذا السائق'))
                      : _buildShiftDetails(_currentShiftRecord!),
                ),
              ],
            ),
    );
  }

  Widget _buildDriverSelector() {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 16),
      color: AppColors.surface,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: _drivers.map((Driver d) {
            final bool isSelected = d.pin == _selectedPin;
            return Padding(
              padding: const EdgeInsets.only(left: 8),
              child: ChoiceChip(
                avatar: Icon(
                  Icons.person_pin_outlined,
                  size: 16,
                  color: isSelected ? Colors.white : AppColors.primary,
                ),
                label: Text('${d.name} (${d.pin})'),
                selected: isSelected,
                selectedColor: AppColors.primary,
                labelStyle: TextStyle(
                  color: isSelected ? Colors.white : AppColors.textPrimary,
                  fontWeight: FontWeight.bold,
                  fontSize: 12,
                ),
                onSelected: (_) => setState(() => _selectedPin = d.pin),
              ),
            );
          }).toList(),
        ),
      ),
    );
  }

  Widget _buildShiftDetails(ShiftRecord record) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: <Widget>[
        // بطاقة إحصائيات الأداء السريع
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: AppColors.border),
          ),
          child: Column(
            children: <Widget>[
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: <Widget>[
                  _buildMetric('الطلبات', '${record.completedOrdersCount}', AppColors.primary),
                  _buildMetric('متوسط الرحلة', '${record.averageDeliveryMinutes.round()} د', const Color(0xFF2563EB)),
                  _buildMetric('المتأخرة', '${record.delayedOrdersCount}', AppColors.danger),
                  _buildMetric('الالتزام', '${record.onTimeRatePercent}%', AppColors.success),
                ],
              ),
              const Divider(height: 24),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: <Widget>[
                  Text('الكاش المسلّم: ${formatAmount(record.totalCollectedCash)}',
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                  Text('الأجور: ${formatAmount(record.totalWagesEarned)}',
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: AppColors.accent)),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 18),

        const Text('مسار رحلات اليوم بالتفصيل:',
            style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
        const SizedBox(height: 10),

        if (record.orders.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 30),
            child: Center(
              child: Text(
                'لم يتم تسجيل أي رحلات لهذا السائق اليوم.',
                style: TextStyle(color: AppColors.textSecondary),
              ),
            ),
          )
        else
          for (final DeliveryOrder order in record.orders) ...<Widget>[
            _buildOrderHistoryTile(order),
            const SizedBox(height: 8),
          ],
      ],
    );
  }

  Widget _buildMetric(String label, String value, Color color) {
    return Column(
      children: <Widget>[
        Text(value, style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: color)),
        const SizedBox(height: 2),
        Text(label, style: const TextStyle(fontSize: 11, color: AppColors.textSecondary)),
      ],
    );
  }

  Widget _buildOrderHistoryTile(DeliveryOrder order) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: order.isDelayed ? AppColors.danger.withValues(alpha: 0.5) : AppColors.border,
        ),
      ),
      child: Row(
        children: <Widget>[
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: order.isDelayed
                  ? AppColors.danger.withValues(alpha: 0.1)
                  : AppColors.success.withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(
              order.isDelayed ? Icons.warning_amber_rounded : Icons.check,
              color: order.isDelayed ? AppColors.danger : AppColors.success,
              size: 20,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  'طلب #${order.displayNumber} • ${formatAmount(order.amount)}',
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                ),
                const SizedBox(height: 2),
                Text(
                  'استلام: ${order.pickedUpAt != null ? formatTime(order.pickedUpAt!) : '—'} ➡️ '
                  'تسليم: ${order.deliveredAt != null ? formatTime(order.deliveredAt!) : '—'}',
                  style: const TextStyle(fontSize: 11, color: AppColors.textSecondary),
                ),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: <Widget>[
              Text(
                order.durationFormatted,
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 13,
                  color: order.isDelayed ? AppColors.danger : AppColors.textPrimary,
                ),
              ),
              if (order.isDelayed)
                Text(
                  'متأخر +${order.delayMinutes}د',
                  style: const TextStyle(fontSize: 10, color: AppColors.danger, fontWeight: FontWeight.bold),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
