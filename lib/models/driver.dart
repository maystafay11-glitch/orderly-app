/// نموذج بيانات عامل التوصيل (Driver) مع دعم رمز الدخول السريع (1001-1030).
///
/// يجمع البيانات المُدخَلة لكل عامل:
/// * [Driver.name] اسم العامل.
/// * [Driver.pin] رمز الدخول السريع (من 1001 إلى 1030 لدعم 30 عاملاً).
/// * [Driver.orders] قائمة الطلبات المسجَّلة باسمه ومساراتها.
///
/// ويحسب القيم المالية تلقائياً من قائمة الطلبات:
/// * [Driver.ordersCount] عدد الطلبات.
/// * [Driver.totalOrdersAmount] مجموع مبالغ الطلبات (بالدينار).
/// * [Driver.wage] أجرة العامل.
/// * [Driver.netAmountToRestaurant] صافي قيمة الطلبات للمطعم.
library;

import 'package:orderly_app/models/delivery_order.dart';
import 'package:orderly_app/models/order_payment_type.dart';

class Driver {
  /// إنشاء عامل جديد.
  const Driver({
    required this.name,
    this.pin = '',
    this.orders = const <DeliveryOrder>[],
    this.wagePerOrder = defaultWagePerOrder,
    this.legacyOrdersCount = 0,
    this.legacyOrdersAmount = 0,
  });

  /// إنشاء عامل من خريطة (JSON) مسترجَعة من التخزين المحلي.
  factory Driver.fromJson(Map<String, dynamic> json) {
    final bool hasOrdersKey = json.containsKey(keyOrders);
    return Driver(
      name: (json[keyName] ?? '').toString(),
      pin: (json[keyPin] ?? '').toString().trim(),
      orders: _readOrders(json[keyOrders]),
      legacyOrdersCount: _readInt(
        hasOrdersKey ? json[keyLegacyOrdersCount] : json[keyOrdersCount],
      ),
      legacyOrdersAmount: _readDouble(
        hasOrdersKey ? json[keyLegacyOrdersAmount] : json[keyTotalOrdersAmount],
      ),
      wagePerOrder: _readInt(
        json[keyWagePerOrder],
        fallback: defaultWagePerOrder,
      ),
    );
  }

  /// أجرة العامل عن الطلب الواحد بالدينار (القيمة الافتراضية).
  static const int defaultWagePerOrder = 1000;

  /// نطاق رموز الدخول الخاصة بالسائقين (1001 إلى 1030).
  static const int minPin = 1001;
  static const int maxPin = 1030;
  static const int maxDrivers = 30;

  /// مفاتيح التخزين/JSON.
  static const String keyName = 'name';
  static const String keyPin = 'pin';
  static const String keyOrders = 'orders';
  static const String keyLegacyOrdersCount = 'legacyOrdersCount';
  static const String keyLegacyOrdersAmount = 'legacyOrdersAmount';
  static const String keyOrdersCount = 'ordersCount';
  static const String keyTotalOrdersAmount = 'totalOrdersAmount';
  static const String keyWagePerOrder = 'wagePerOrder';

  /// اسم العامل.
  final String name;

  /// رمز الدخول الخاص بالسائق (1001 إلى 1030).
  final String pin;

  /// الطلبات المسجَّلة باسم العامل (مرتّبة بترتيب الإضافة).
  final List<DeliveryOrder> orders;

  /// أجرة الطلب الواحد بالدينار.
  final int wagePerOrder;

  /// عدد الطلبات المُرحَّلة من إصدار سابق (بدون تفاصيل لكل طلب).
  final int legacyOrdersCount;

  /// إجمالي مبالغ الطلبات المُرحَّلة من إصدار سابق.
  final double legacyOrdersAmount;

  /// رمز العرض (أو الرمز المقترح إذا لم يكن مخصصاً).
  String get displayPin => pin.isNotEmpty ? pin : 'بدون رمز';

  /// إيجاد أول رمز متاح وغير مستخدم بين 1001 و 1030 لدعم التخصيص التلقائي.
  static String findNextAvailablePin(Iterable<Driver> drivers) {
    final Set<String> usedPins = drivers
        .map((Driver d) => d.pin.trim())
        .where((String p) => p.isNotEmpty)
        .toSet();

    for (int i = minPin; i <= maxPin; i++) {
      final String candidate = i.toString();
      if (!usedPins.contains(candidate)) {
        return candidate;
      }
    }
    return minPin.toString();
  }

  /// عدد الطلبات = عدد الطلبات المسجَّلة + الأرقام المُرحَّلة.
  int get ordersCount => orders.length + legacyOrdersCount;

  /// مجموع مبالغ الطلبات بالدينار = مبالغ الطلبات المسجَّلة + المُرحَّلة.
  double get totalOrdersAmount =>
      legacyOrdersAmount +
      orders.fold<double>(0, (double sum, DeliveryOrder order) {
        return sum + order.amount;
      });

  /// عدد الطلبات التي تُحتسب لها أجرة توصيل (الطلبات النقدية فقط).
  int get wageEligibleOrdersCount =>
      legacyOrdersCount +
      orders
          .where((DeliveryOrder order) => order.countsWage)
          .length;

  /// عدد الطلبات الخاصة بأجرة صفر (ماستر كارد أو استلام مباشر).
  int get zeroWageOrdersCount =>
      orders.where((DeliveryOrder order) => order.hasZeroWage).length;

  /// مجموع مبالغ الطلبات الخاصة بأجرة صفر.
  double get zeroWageOrdersAmount => orders
      .where((DeliveryOrder order) => order.hasZeroWage)
      .fold<double>(0, (double sum, DeliveryOrder order) => sum + order.amount);

  /// مجموع مبالغ الطلبات النقدية (المبالغ التي يحملها العامل نقداً).
  double get cashOrdersAmount =>
      legacyOrdersAmount +
      orders
          .where((DeliveryOrder order) => order.collectsCash)
          .fold<double>(0, (double sum, DeliveryOrder order) => sum + order.amount);

  /// هل يوجد طلبات بحالة خاصة بأجرة صفر؟
  bool get hasZeroWageOrders => zeroWageOrdersCount > 0;

  /// هل أجرة الطلب الواحد لهذا العامل صفر؟
  bool get hasZeroWageRate => wagePerOrder == 0;

  /// أجرة العامل المستحقة.
  double get wage => wageEligibleOrdersCount * wagePerOrder.toDouble();

  /// صافي قيمة الطلبات للمطعم.
  double get netAmountToRestaurant => totalOrdersAmount;

  /// هل يوجد عدد/مبلغ طلبات مُرحَّل من إصدار سابق؟
  bool get hasLegacyOrders =>
      legacyOrdersCount > 0 || legacyOrdersAmount > 0;

  /// رقم مقترح للطلب الجديد.
  String get suggestedOrderNumber {
    int highest = 0;
    for (final DeliveryOrder order in orders) {
      final int? number = int.tryParse(order.orderNumber.trim());
      if (number != null && number > highest) {
        highest = number;
      }
    }
    return '${(highest > 0 ? highest : ordersCount) + 1}';
  }

  /// نسخة جديدة من العامل مع تعديل بعض القيم.
  Driver copyWith({
    String? name,
    String? pin,
    List<DeliveryOrder>? orders,
    int? wagePerOrder,
    int? legacyOrdersCount,
    double? legacyOrdersAmount,
  }) => Driver(
    name: name ?? this.name,
    pin: pin ?? this.pin,
    orders: orders ?? this.orders,
    wagePerOrder: wagePerOrder ?? this.wagePerOrder,
    legacyOrdersCount: legacyOrdersCount ?? this.legacyOrdersCount,
    legacyOrdersAmount: legacyOrdersAmount ?? this.legacyOrdersAmount,
  );

  /// إضافة طلب جديد بقيمة [amount] دينار إلى هذا العامل.
  Driver addOrder(
    double amount, {
    String orderNumber = '',
    OrderPaymentType paymentType = OrderPaymentType.cash,
    DateTime? addedAt,
  }) => addDeliveryOrder(
    DeliveryOrder(
      orderNumber: orderNumber.trim(),
      amount: amount,
      paymentType: paymentType,
      addedAt: addedAt,
      driverPin: pin,
      driverName: name,
    ),
  );

  /// إضافة طلب جاهز (بكل تفاصيله) إلى حساب العامل مع ربطه بالرمز والاسم.
  Driver addDeliveryOrder(DeliveryOrder order) {
    final DeliveryOrder linked = (order.driverPin == null || order.driverPin!.isEmpty)
        ? order.copyWith(driverPin: pin, driverName: name)
        : order;
    return copyWith(
      orders: <DeliveryOrder>[...orders, linked],
    );
  }

  /// حذف الطلب الواقع في الترتيب [index] من قائمة الطلبات.
  Driver removeOrderAt(int index) {
    if (index < 0 || index >= orders.length) {
      return this;
    }
    return copyWith(
      orders: <DeliveryOrder>[
        for (int i = 0; i < orders.length; i++)
          if (i != index) orders[i],
      ],
    );
  }

  /// حذف أول طلب مطابق للطلب [order].
  Driver removeOrder(DeliveryOrder order) => removeOrderAt(orders.indexOf(order));

  /// تصفير حسابات اليوم مع الاحتفاظ باسم العامل ورمزه الخاص وأجرة الطلب.
  Driver resetDay() => copyWith(
    orders: const <DeliveryOrder>[],
    legacyOrdersCount: 0,
    legacyOrdersAmount: 0,
  );

  /// تحويل العامل إلى خريطة قابلة للتخزين بصيغة JSON أو Firebase.
  Map<String, dynamic> toJson() => <String, dynamic>{
    keyName: name,
    keyPin: pin,
    keyOrders: orders.map((DeliveryOrder order) => order.toJson()).toList(),
    keyLegacyOrdersCount: legacyOrdersCount,
    keyLegacyOrdersAmount: legacyOrdersAmount,
    keyWagePerOrder: wagePerOrder,
  };

  /// قراءة قائمة الطلبات المحفوظة بأمان.
  static List<DeliveryOrder> _readOrders(Object? value) {
    if (value is! List) {
      return const <DeliveryOrder>[];
    }
    return value
        .whereType<Map<Object?, Object?>>()
        .map(
          (Map<Object?, Object?> item) =>
              DeliveryOrder.fromJson(Map<String, dynamic>.from(item)),
        )
        .toList();
  }

  /// قراءة قيمة صحيحة من JSON بأمان.
  static int _readInt(Object? value, {int fallback = 0}) {
    if (value is int) return value;
    if (value is num) return value.round();
    if (value == null) return fallback;
    return int.tryParse(value.toString().replaceAll(',', '').trim()) ??
        fallback;
  }

  /// قراءة قيمة عشرية من JSON بأمان.
  static double _readDouble(Object? value) {
    if (value is double) return value;
    if (value is num) return value.toDouble();
    if (value == null) return 0;
    return double.tryParse(value.toString().replaceAll(',', '').trim()) ?? 0;
  }

  @override
  String toString() =>
      'Driver(name: $name, pin: $pin, ordersCount: $ordersCount, '
      'wageEligibleOrdersCount: $wageEligibleOrdersCount, '
      'zeroWageOrdersCount: $zeroWageOrdersCount, '
      'totalOrdersAmount: $totalOrdersAmount, wage: $wage, '
      'netAmountToRestaurant: $netAmountToRestaurant, '
      'orders: ${orders.length})';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Driver &&
          other.name == name &&
          other.wagePerOrder == wagePerOrder &&
          other.legacyOrdersCount == legacyOrdersCount &&
          other.legacyOrdersAmount == legacyOrdersAmount &&
          _sameOrders(other.orders, orders);

  /// مقارنة قائمتي طلبات عنصراً بعنصر.
  static bool _sameOrders(List<DeliveryOrder> a, List<DeliveryOrder> b) {
    if (identical(a, b)) {
      return true;
    }
    if (a.length != b.length) {
      return false;
    }
    for (int i = 0; i < a.length; i++) {
      if (a[i] != b[i]) {
        return false;
      }
    }
    return true;
  }

  @override
  int get hashCode => Object.hash(
    name,
    wagePerOrder,
    legacyOrdersCount,
    legacyOrdersAmount,
    Object.hashAll(orders),
  );
}
