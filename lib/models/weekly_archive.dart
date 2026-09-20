/// نموذج ملخص أسبوعي يُؤرشف عند تصفير الحسابات الأسبوعية.
///
/// يحتوي على إجماليات الفترة لتتبعها لاحقاً في «الملخص الأسبوعي»:
/// * [WeeklyArchive.totalOrders] عدد الطلبات الكلي خلال الأسبوع.
/// * [WeeklyArchive.totalAmount] إجمالي المبالغ بالدينار.
/// * [WeeklyArchive.totalWage] أجور العمال خلال الأسبوع.
/// * [WeeklyArchive.netAmount] صافي أرباح المطعم.
/// * [WeeklyArchive.periodStart]/[WeeklyArchive.periodEnd] تواريخ الفترة.
/// * [WeeklyArchive.createdAt] وقت الأرشفة.
library;

class WeeklyArchive {
  WeeklyArchive({
    required this.totalOrders,
    required this.totalAmount,
    required this.totalWage,
    required this.netAmount,
    required this.periodStart,
    required this.periodEnd,
    DateTime? createdAt,
  }) : createdAt = createdAt ?? DateTime.now();

  factory WeeklyArchive.fromJson(Map<String, dynamic> json) => WeeklyArchive(
    totalOrders: _readInt(json['totalOrders']),
    totalAmount: _readDouble(json['totalAmount']),
    totalWage: _readDouble(json['totalWage']),
    netAmount: _readDouble(json['netAmount']),
    periodStart: _readDate(json['periodStart']),
    periodEnd: _readDate(json['periodEnd']),
    createdAt: _readDate(json['createdAt']),
  );

  final int totalOrders;
  final double totalAmount;
  final double totalWage;
  final double netAmount;
  final DateTime periodStart;
  final DateTime periodEnd;
  final DateTime createdAt;

  Map<String, dynamic> toJson() => <String, dynamic>{
    'totalOrders': totalOrders,
    'totalAmount': totalAmount,
    'totalWage': totalWage,
    'netAmount': netAmount,
    'periodStart': periodStart.toIso8601String(),
    'periodEnd': periodEnd.toIso8601String(),
    'createdAt': createdAt.toIso8601String(),
  };

  static int _readInt(Object? value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value == null) return 0;
    return int.tryParse(value.toString().trim()) ?? 0;
  }

  static double _readDouble(Object? value) {
    if (value is double) return value;
    if (value is num) return value.toDouble();
    if (value == null) return 0;
    return double.tryParse(value.toString().replaceAll(',', '').trim()) ?? 0;
  }

  static DateTime _readDate(Object? value) {
    if (value is DateTime) return value;
    if (value is num) {
      return DateTime.fromMillisecondsSinceEpoch(value.round());
    }
    final DateTime? parsed = DateTime.tryParse(value?.toString() ?? '');
    return parsed ?? DateTime.now();
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is WeeklyArchive &&
          other.totalOrders == totalOrders &&
          other.totalAmount == totalAmount &&
          other.totalWage == totalWage &&
          other.netAmount == netAmount &&
          other.periodStart == periodStart &&
          other.periodEnd == periodEnd;

  @override
  int get hashCode =>
      Object.hash(totalOrders, totalAmount, totalWage, netAmount, periodStart, periodEnd);
}
