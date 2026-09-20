/// نموذج حساب تكلفة وربح دفعة «مسواگ» (المسواك).
///
/// يحتوي على مدخلات المستخدم:
/// * [MiswakCalculation.label] اسم الدفعة/المنتج (اختياري للتنظيم).
/// * [MiswakCalculation.quantity] عدد الحبات في الدفعة.
/// * [MiswakCalculation.materialCost] تكلفة المواد (المسواگ الخام).
/// * [MiswakCalculation.packagingCost] تكلفة التغليف والتعبئة.
/// * [MiswakCalculation.otherCosts] مصاريف أخرى (نقل، أجور، ضرائب…).
/// * [MiswakCalculation.salePrice] سعر بيع الحبة الواحدة.
///
/// وتُحسب منها تلقائياً كل الأرقام المالية بدقة:
/// [MiswakCalculation.totalCost] التكلفة الكلية،
/// [MiswakCalculation.costPerUnit] تكلفة الحبة،
/// [MiswakCalculation.revenue] إجمالي الإيراد،
/// [MiswakCalculation.netProfit] صافي الربح،
/// [MiswakCalculation.profitPerUnit] ربح الحبة،
/// [MiswakCalculation.marginPercent] هامش الربح،
/// و[MiswakCalculation.breakEvenUnits] عدد الحبات المطلوب لتفادي الخسارة.
library;

class MiswakCalculation {
  /// إنشاء حساب دفعة مسواگ.
  ///
  /// إذا لم يُمرَّر [createdAt] يُستخدم وقت الإنشاء الحالي.
  MiswakCalculation({
    this.label = '',
    required this.quantity,
    required this.materialCost,
    this.packagingCost = 0,
    this.otherCosts = 0,
    required this.salePrice,
    DateTime? createdAt,
  }) : createdAt = createdAt ?? DateTime.now();

  /// إنشاء حساب من خريطة (JSON) مسترجَعة من التخزين المحلي.
  ///
  /// أي قيمة ناقصة أو تالفة تُستبدَل بقيمة آمنة بدل إسقاط التطبيق.
  factory MiswakCalculation.fromJson(Map<String, dynamic> json) =>
      MiswakCalculation(
        label: (json[keyLabel] ?? '').toString().trim(),
        quantity: _readInt(json[keyQuantity]),
        materialCost: _readDouble(json[keyMaterialCost]),
        packagingCost: _readDouble(json[keyPackagingCost]),
        otherCosts: _readDouble(json[keyOtherCosts]),
        salePrice: _readDouble(json[keySalePrice]),
        createdAt: _readDate(json[keyCreatedAt]),
      );

  /// مفاتيح التخزين/JSON.
  static const String keyLabel = 'label';

  /// مفتاح عدد الحبات.
  static const String keyQuantity = 'quantity';

  /// مفتاح تكلفة المواد.
  static const String keyMaterialCost = 'materialCost';

  /// مفتاح تكلفة التغليف.
  static const String keyPackagingCost = 'packagingCost';

  /// مفتاح المصاريف الأخرى.
  static const String keyOtherCosts = 'otherCosts';

  /// مفتاح سعر بيع الحبة.
  static const String keySalePrice = 'salePrice';

  /// مفتاح وقت الإنشاء.
  static const String keyCreatedAt = 'createdAt';

  /// اسم الدفعة/المنتج (يُعرض في القائمة).
  final String label;

  /// عدد الحبات في الدفعة.
  final int quantity;

  /// تكلفة المواد الإجمالية للدفعة بالدينار.
  final double materialCost;

  /// تكلفة التغليف والتعبئة الإجمالية بالدينار.
  final double packagingCost;

  /// مصاريف أخرى إجمالية بالدينار (نقل، أجور، غيرها).
  final double otherCosts;

  /// سعر بيع الحبة الواحدة بالدينار.
  final double salePrice;

  /// وقت إنشاء الحساب.
  final DateTime createdAt;

  /// التكلفة الكلية للدفعة = المواد + التغليف + المصاريف الأخرى.
  double get totalCost => materialCost + packagingCost + otherCosts;

  /// تكلفة الحبة الواحدة (تُرجع صفراً إذا كان العدد غير صالح).
  double get costPerUnit => quantity <= 0 ? 0 : totalCost / quantity;

  /// إجمالي الإيراد = عدد الحبات × سعر بيع الحبة.
  double get revenue => quantity * salePrice;

  /// صافي الربح = الإيراد − التكلفة الكلية (قد يكون سالباً عند الخسارة).
  double get netProfit => revenue - totalCost;

  /// ربح الحبة الواحدة = سعر البيع − تكلفة الحبة.
  double get profitPerUnit => salePrice - costPerUnit;

  /// هامش الربح من الإيراد بالنسبة المئوية (0 تعني بلا إيراد).
  double get marginPercent => revenue <= 0 ? 0 : (netProfit / revenue) * 100;

  /// نسبة الربح إلى التكلفة بالنسبة المئوية (0 تعني بلا تكلفة).
  double get markupPercent => totalCost <= 0 ? 0 : (netProfit / totalCost) * 100;

  /// هل الدفعة رابحة؟ (صافي الربح أكبر من صفر)
  bool get isProfitable => netProfit > 0;

  /// هل الدفعة خاسرة؟ (صافي الربح أقل من صفر)
  bool get isLoss => netProfit < 0;

  /// عدد الحبات المطلوب بيعها لتغطية التكلفة (نقطة التعادل)، وصفر إذا كان
  /// سعر البيع أو التكلفة غير صالحين.
  int get breakEvenUnits {
    if (salePrice <= 0 || totalCost <= 0) {
      return 0;
    }
    return (totalCost / salePrice).ceil();
  }

  /// هل المدخلات كافية لحساب ربح صحيح؟ (عدد وتكلفة وسعر بيع صالحة)
  bool get isValid => quantity > 0 && totalCost > 0 && salePrice > 0;

  /// اسم الدفعة المعروض (أو «دفعة مسواگ» إذا لم يُكتب اسم).
  String get displayLabel => label.isEmpty ? 'دفعة مسواگ' : label;

  /// نسخة جديدة من الحساب مع تعديل بعض القيم.
  MiswakCalculation copyWith({
    String? label,
    int? quantity,
    double? materialCost,
    double? packagingCost,
    double? otherCosts,
    double? salePrice,
    DateTime? createdAt,
  }) => MiswakCalculation(
    label: label ?? this.label,
    quantity: quantity ?? this.quantity,
    materialCost: materialCost ?? this.materialCost,
    packagingCost: packagingCost ?? this.packagingCost,
    otherCosts: otherCosts ?? this.otherCosts,
    salePrice: salePrice ?? this.salePrice,
    createdAt: createdAt ?? this.createdAt,
  );

  /// تحويل الحساب إلى خريطة قابلة للتخزين بصيغة JSON.
  Map<String, dynamic> toJson() => <String, dynamic>{
    keyLabel: label,
    keyQuantity: quantity,
    keyMaterialCost: materialCost,
    keyPackagingCost: packagingCost,
    keyOtherCosts: otherCosts,
    keySalePrice: salePrice,
    keyCreatedAt: createdAt.toIso8601String(),
  };

  /// قراءة قيمة صحيحة من JSON بأمان.
  static int _readInt(Object? value) {
    if (value is int) return value;
    if (value is num) return value.round();
    if (value == null) return 0;
    return int.tryParse(value.toString().replaceAll(',', '').trim()) ?? 0;
  }

  /// قراءة قيمة عشرية من JSON بأمان.
  static double _readDouble(Object? value) {
    if (value is double) return value;
    if (value is num) return value.toDouble();
    if (value == null) return 0;
    return double.tryParse(value.toString().replaceAll(',', '').trim()) ?? 0;
  }

  /// قراءة وقت الإنشاء من JSON بأمان (نص ISO أو عدد ميلي ثانية).
  static DateTime _readDate(Object? value) {
    if (value is DateTime) return value;
    if (value is num) return DateTime.fromMillisecondsSinceEpoch(value.round());
    final DateTime? parsed = DateTime.tryParse(value?.toString() ?? '');
    return parsed ?? DateTime.now();
  }

  @override
  String toString() =>
      'MiswakCalculation(label: $label, quantity: $quantity, '
      'totalCost: $totalCost, revenue: $revenue, netProfit: $netProfit)';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is MiswakCalculation &&
          other.label == label &&
          other.quantity == quantity &&
          other.materialCost == materialCost &&
          other.packagingCost == packagingCost &&
          other.otherCosts == otherCosts &&
          other.salePrice == salePrice &&
          other.createdAt == createdAt;

  @override
  int get hashCode => Object.hash(
    label,
    quantity,
    materialCost,
    packagingCost,
    otherCosts,
    salePrice,
    createdAt,
  );
}

/// إجماليات مجموعة دفعات مسواگ محفوظة (تُعرض في ملخص صفحة المسواگ).
class MiswakTotals {
  const MiswakTotals({
    required this.batches,
    required this.units,
    required this.totalCost,
    required this.totalRevenue,
  });

  /// حساب الإجماليات من قائمة الدفعات المحفوظة.
  factory MiswakTotals.of(List<MiswakCalculation> items) {
    int units = 0;
    double cost = 0;
    double revenue = 0;
    for (final MiswakCalculation item in items) {
      units += item.quantity;
      cost += item.totalCost;
      revenue += item.revenue;
    }
    return MiswakTotals(
      batches: items.length,
      units: units,
      totalCost: cost,
      totalRevenue: revenue,
    );
  }

  /// عدد الدفعات المحفوظة.
  final int batches;

  /// مجموع الحبات في كل الدفعات.
  final int units;

  /// مجموع تكاليف الدفعات.
  final double totalCost;

  /// مجموع إيرادات الدفعات.
  final double totalRevenue;

  /// مجموع صافي الربح = الإيراد − التكلفة.
  double get totalProfit => totalRevenue - totalCost;

  /// هامش الربح الكلي بالنسبة المئوية (0 تعني بلا إيراد).
  double get totalMarginPercent =>
      totalRevenue <= 0 ? 0 : (totalProfit / totalRevenue) * 100;

  /// هل مجموع الدفعات رابح؟
  bool get isProfitable => totalProfit > 0;

  /// هل لا توجد دفعات محفوظة؟
  bool get isEmpty => batches == 0;

  @override
  String toString() =>
      'MiswakTotals(batches: $batches, units: $units, '
      'totalCost: $totalCost, totalProfit: $totalProfit)';
}