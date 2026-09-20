/// نموذج بيانات سجل الوردية اليومي (Shift History) لعامل التوصيل.
///
/// يوثّق أداء السائق خلال اليوم:
/// * عدد الطلبات المستلمة والمنجزة.
/// * أوقات الاستلام وأوقات التسليم بدقة.
/// * مدة كل رحلة، ومتوسط وقت التوصيل.
/// * الطلبات المتأخرة عن وقت الطريق المعتاد لكشف "التسخيت".
/// * إجمالي مبالغ الكاش المقبوضة والأجور المستحقة.
library;

import 'package:orderly_app/models/delivery_order.dart';
import 'package:orderly_app/models/order_status.dart';

class ShiftRecord {
  const ShiftRecord({
    required this.driverPin,
    required this.driverName,
    required this.date,
    this.orders = const <DeliveryOrder>[],
  });

  /// إنشاء سجل وردية من خريطة JSON.
  factory ShiftRecord.fromJson(Map<String, dynamic> json) {
    return ShiftRecord(
      driverPin: (json['driverPin'] ?? '').toString(),
      driverName: (json['driverName'] ?? '').toString(),
      date: json['date'] != null
          ? DateTime.tryParse(json['date'].toString()) ?? DateTime.now()
          : DateTime.now(),
      orders: (json['orders'] is List)
          ? (json['orders'] as List)
              .whereType<Map<Object?, Object?>>()
              .map((Map<Object?, Object?> item) =>
                  DeliveryOrder.fromJson(Map<String, dynamic>.from(item)))
              .toList()
          : const <DeliveryOrder>[],
    );
  }

  /// رمز السائق (1001-1030).
  final String driverPin;

  /// اسم السائق.
  final String driverName;

  /// تاريخ الوردية.
  final DateTime date;

  /// قائمة طلبات الوردية.
  final List<DeliveryOrder> orders;

  /// إجمالي الطلبات في الوردية.
  int get totalOrdersCount => orders.length;

  /// الطلبات المسلّمة فعلياً بنجاح.
  List<DeliveryOrder> get deliveredOrders =>
      orders.where((DeliveryOrder o) => o.status == OrderStatus.delivered).toList();

  /// عدد الطلبات المكتملة.
  int get completedOrdersCount => deliveredOrders.length;

  /// الطلبات المتأخرة عن وقت الطريق المعتاد.
  List<DeliveryOrder> get delayedOrders =>
      orders.where((DeliveryOrder o) => o.isDelayed).toList();

  /// عدد الطلبات المتأخرة.
  int get delayedOrdersCount => delayedOrders.length;

  /// متوسط وقت التوصيل للطلبات المنجزة بالدقائق.
  double get averageDeliveryMinutes {
    final List<DeliveryOrder> withDuration =
        deliveredOrders.where((DeliveryOrder o) => o.duration != null).toList();
    if (withDuration.isEmpty) return 0;
    final int totalMins = withDuration.fold<int>(
      0,
      (int sum, DeliveryOrder o) => sum + o.durationMinutes,
    );
    return totalMins / withDuration.length;
  }

  /// نسبة الالتزام بالوقت المعتاد (0 .. 100%).
  int get onTimeRatePercent {
    if (completedOrdersCount == 0) return 100;
    final int onTimeCount = completedOrdersCount - delayedOrdersCount;
    return ((onTimeCount / completedOrdersCount) * 100).round().clamp(0, 100);
  }

  /// إجمالي المبالغ النقدية المقبوضة التي يحملها السائق.
  double get totalCollectedCash => orders
      .where((DeliveryOrder o) => o.collectsCash)
      .fold<double>(0, (double sum, DeliveryOrder o) => sum + o.amount);

  /// إجمالي الأجور المستحقة للسائق عن هذه الوردية (1000 لكل طلب مستحق).
  double get totalWagesEarned => orders
      .where((DeliveryOrder o) => o.countsWage)
      .fold<double>(0, (double sum, DeliveryOrder o) => sum + 1000);

  /// تحويل السجل إلى خريطة قابلة للحفظ في JSON أو Firebase.
  Map<String, dynamic> toJson() => <String, dynamic>{
        'driverPin': driverPin,
        'driverName': driverName,
        'date': date.toIso8601String(),
        'orders': orders.map((DeliveryOrder o) => o.toJson()).toList(),
      };
}
