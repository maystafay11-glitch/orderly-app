/// نموذج بيانات الطلب الواحد المسجَّل لعامل التوصيل مع التتبع اللحظي.
///
/// يحتوي كل طلب على:
/// * [DeliveryOrder.id] معرف فريد للطلب لمزامنته لحظياً سحابياً.
/// * [DeliveryOrder.orderNumber] رقم الطلب (نص حر لتنظيم الأوردرات).
/// * [DeliveryOrder.amount] سعر الطلب بالدينار.
/// * [DeliveryOrder.paymentType] نوع الدفع (كاش / ماستر كارد / استلام مباشر).
/// * [DeliveryOrder.addedAt] وقت إضافة الطلب.
/// * [DeliveryOrder.status] حالة الطلب (قيد الإعداد ➡️ مع السائق ➡️ تم التسليم).
/// * [DeliveryOrder.driverPin] رمز السائق المسند إليه الطلب (1001 - 1030).
/// * [DeliveryOrder.driverName] اسم السائق المسند إليه الطلب.
/// * [DeliveryOrder.pickedUpAt] وقت الاستلام الفعلي من المطعم وبدء الطريق.
/// * [DeliveryOrder.deliveredAt] وقت تسليم الطلب للزبون بالكامل.
/// * [DeliveryOrder.expectedDurationMinutes] الوقت الطبيعي للرحلة لكشف التأخير.
library;

import 'package:orderly_app/models/order_payment_type.dart';
import 'package:orderly_app/models/order_status.dart';

class DeliveryOrder {
  /// إنشاء طلب جديد.
  DeliveryOrder({
    String? id,
    this.orderNumber = '',
    required this.amount,
    this.paymentType = OrderPaymentType.cash,
    DateTime? addedAt,
    this.status = OrderStatus.preparing,
    this.driverPin,
    this.driverName,
    this.pickedUpAt,
    this.deliveredAt,
    this.expectedDurationMinutes = 25,
    this.proofImageData,
  })  : id = (id != null && id.isNotEmpty)
            ? id
            : 'ord_${(addedAt ?? DateTime.now()).microsecondsSinceEpoch}_${orderNumber.replaceAll(RegExp(r'\s+'), '')}',
        addedAt = addedAt ?? DateTime.now();

  /// إنشاء طلب من خريطة (JSON) مسترجَعة من التخزين المحلي أو Firebase.
  factory DeliveryOrder.fromJson(Map<String, dynamic> json) {
    final DateTime addedDate = _readDate(json[keyAddedAt]);
    final String ordNum = (json[keyOrderNumber] ?? '').toString().trim();
    final String rawId = (json[keyId] ?? '').toString().trim();

    return DeliveryOrder(
      id: rawId.isNotEmpty
          ? rawId
          : 'ord_${addedDate.microsecondsSinceEpoch}_$ordNum',
      orderNumber: ordNum,
      amount: _readDouble(json[keyAmount]),
      paymentType: OrderPaymentType.fromName(json[keyPaymentType]),
      addedAt: addedDate,
      status: json.containsKey(keyStatus)
          ? OrderStatus.fromName(json[keyStatus])
          : OrderStatus.delivered,
      driverPin: json[keyDriverPin]?.toString(),
      driverName: json[keyDriverName]?.toString(),
      pickedUpAt: json[keyPickedUpAt] != null ? _readDate(json[keyPickedUpAt]) : null,
      deliveredAt: json[keyDeliveredAt] != null ? _readDate(json[keyDeliveredAt]) : null,
      expectedDurationMinutes: _readInt(json[keyExpectedDurationMinutes], fallback: 25),
      proofImageData: json[keyProofImageData]?.toString(),
    );
  }

  /// مفاتيح التخزين/JSON.
  static const String keyId = 'id';
  static const String keyOrderNumber = 'orderNumber';
  static const String keyAmount = 'amount';
  static const String keyAddedAt = 'addedAt';
  static const String keyPaymentType = 'paymentType';
  static const String keyStatus = 'status';
  static const String keyDriverPin = 'driverPin';
  static const String keyDriverName = 'driverName';
  static const String keyPickedUpAt = 'pickedUpAt';
  static const String keyDeliveredAt = 'deliveredAt';
  static const String keyExpectedDurationMinutes = 'expectedDurationMinutes';
  static const String keyProofImageData = 'proofImageData';

  /// المعرف الفريد للطلب.
  final String id;

  /// رقم الطلب (نص حر: قد يكون رقماً أو رمزاً مثل `#A12`).
  final String orderNumber;

  /// سعر الطلب بالدينار.
  final double amount;

  /// نوع دفع الطلب (افتراضياً كاش).
  final OrderPaymentType paymentType;

  /// وقت إضافة الطلب إلى حساب العامل أو النظام.
  final DateTime addedAt;

  /// حالة الطلب الحالية في مسار التوصيل.
  final OrderStatus status;

  /// رمز السائق المسند إليه الطلب (1001 إلى 1030).
  final String? driverPin;

  /// اسم السائق المسند إليه الطلب.
  final String? driverName;

  /// وقت خروج الطلب واستلامه من المطعم.
  final DateTime? pickedUpAt;

  /// وقت تسليم الطلب للزبون.
  final DateTime? deliveredAt;

  /// وقت الرحلة الطبيعي المتوقع بالدقائق (افتراضياً 25 دقيقة).
  final int expectedDurationMinutes;

  /// صورة إثبات الطلب بصيغة Data URL مضغوطة (اختيارية، للويب والهاتف).
  final String? proofImageData;

  /// رقم الطلب للعرض في الواجهة (أو «بدون رقم» إذا تُرك الحقل فارغاً).
  String get displayNumber => orderNumber.isEmpty ? 'بدون رقم' : orderNumber;

  /// نص نوع الدفع للعرض في السجل والشارات.
  String get displayPayment => paymentType.label;

  /// هل تُحتسب أجرة توصيل عن هذا الطلب؟
  bool get countsWage => paymentType.countsWage;

  /// هل يُعدّ الطلب حالة خاصة بأجرة صفر؟
  bool get hasZeroWage => paymentType.isSpecialCase;

  /// هل يحمل العامل مبلغ هذا الطلب نقداً (كاش)؟
  bool get collectsCash => paymentType.collectsCash;

  /// مدة الرحلة على الطريق (منذ لحظة الاستلام من المطعم).
  Duration? get duration {
    if (pickedUpAt == null) return null;
    final DateTime end = deliveredAt ?? DateTime.now();
    return end.difference(pickedUpAt!);
  }

  /// مدة الرحلة بالدقائق (أو 0 إذا لم يُستلم بعد).
  int get durationMinutes => duration?.inMinutes ?? 0;

  /// نص منسق لمدة الرحلة بالعربية: مثال «18 دقيقة».
  String get durationFormatted {
    final Duration? d = duration;
    if (d == null) return 'بانتظار الاستلام';
    final int mins = d.inMinutes;
    final int secs = d.inSeconds % 60;
    if (mins == 0) return '$secs ثانية';
    return '$mins دقيقة';
  }

  /// هل تجاوز الطلب الوقت الطبيعي للطريق (متأخر)؟
  bool get isDelayed {
    if (pickedUpAt == null) return false;
    return durationMinutes > expectedDurationMinutes;
  }

  /// عدد الدقائق الإضافية المتأخرة عن الوقت المعتاد للطريق.
  int get delayMinutes {
    if (!isDelayed) return 0;
    return durationMinutes - expectedDurationMinutes;
  }

  /// نسخة جديدة من الطلب مع تعديل بعض القيم.
  DeliveryOrder copyWith({
    String? id,
    String? orderNumber,
    double? amount,
    OrderPaymentType? paymentType,
    DateTime? addedAt,
    OrderStatus? status,
    String? driverPin,
    String? driverName,
    DateTime? pickedUpAt,
    DateTime? deliveredAt,
    int? expectedDurationMinutes,
    String? proofImageData,
  }) =>
      DeliveryOrder(
        id: id ?? this.id,
        orderNumber: orderNumber ?? this.orderNumber,
        amount: amount ?? this.amount,
        paymentType: paymentType ?? this.paymentType,
        addedAt: addedAt ?? this.addedAt,
        status: status ?? this.status,
        driverPin: driverPin ?? this.driverPin,
        driverName: driverName ?? this.driverName,
        pickedUpAt: pickedUpAt ?? this.pickedUpAt,
        deliveredAt: deliveredAt ?? this.deliveredAt,
        expectedDurationMinutes:
            expectedDurationMinutes ?? this.expectedDurationMinutes,
        proofImageData: proofImageData ?? this.proofImageData,
      );

  /// تحويل الطلب إلى خريطة قابلة للتخزين بصيغة JSON أو الإرسال إلى Firebase.
  Map<String, dynamic> toJson() => <String, dynamic>{
        keyId: id,
        keyOrderNumber: orderNumber,
        keyAmount: amount,
        keyPaymentType: paymentType.storageKey,
        keyAddedAt: addedAt.toIso8601String(),
        keyStatus: status.storageKey,
        if (driverPin != null) keyDriverPin: driverPin,
        if (driverName != null) keyDriverName: driverName,
        if (pickedUpAt != null) keyPickedUpAt: pickedUpAt!.toIso8601String(),
        if (deliveredAt != null) keyDeliveredAt: deliveredAt!.toIso8601String(),
        keyExpectedDurationMinutes: expectedDurationMinutes,
        if (proofImageData != null && proofImageData!.isNotEmpty)
          keyProofImageData: proofImageData,
      };

  /// قراءة قيمة عشرية من JSON بأمان.
  static double _readDouble(Object? value) {
    if (value is double) return value;
    if (value is num) return value.toDouble();
    if (value == null) return 0;
    return double.tryParse(value.toString().replaceAll(',', '').trim()) ?? 0;
  }

  /// قراءة قيمة صحيحة من JSON بأمان.
  static int _readInt(Object? value, {int fallback = 0}) {
    if (value is int) return value;
    if (value is num) return value.round();
    if (value == null) return fallback;
    return int.tryParse(value.toString().replaceAll(',', '').trim()) ?? fallback;
  }

  /// قراءة وقت الإضافة من JSON بأمان (نص ISO أو عدد ميلي ثانية).
  static DateTime _readDate(Object? value) {
    if (value is DateTime) return value;
    if (value is num) return DateTime.fromMillisecondsSinceEpoch(value.round());
    final DateTime? parsed = DateTime.tryParse(value?.toString() ?? '');
    return parsed?.toLocal() ?? DateTime.now();
  }

  @override
  String toString() =>
      'DeliveryOrder(id: $id, orderNumber: $orderNumber, amount: $amount, '
      'status: ${status.name}, driverPin: $driverPin, '
      'paymentType: ${paymentType.storageKey}, '
      'addedAt: ${addedAt.toIso8601String()})';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is DeliveryOrder &&
          other.orderNumber == orderNumber &&
          other.amount == amount &&
          other.paymentType == paymentType &&
          other.addedAt == addedAt;

  @override
  int get hashCode => Object.hash(orderNumber, amount, paymentType, addedAt);
}
