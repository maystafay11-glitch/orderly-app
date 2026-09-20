/// أنواع دفع الطلب في تطبيق Orderly.
///
/// يحدّد النوع هل يستلم العامل المبلغ نقداً أم لا، وهل تُحتسب له أجرة توصيل
/// عن هذه الطلبية أم تُعامل معاملة الحالات الخاصة بأجرة **صفر**:
/// * [OrderPaymentType.cash]: كاش ⇒ يستلم النقد ويستحق الأجرة كاملة.
/// * [OrderPaymentType.masterCard]: مدفوع بالماستر كارد لحساب المطعم ⇒
///   لا نقد مع العامل ولا أجرة توصيل.
/// * [OrderPaymentType.directReceive]: استلام مباشر من المطعم ⇒
///   لا نقد مع العامل ولا أجرة توصيل.
library;

import 'package:flutter/material.dart';

/// نوع دفع الطلب وأثره على الأجرة وصافي المطعم.
enum OrderPaymentType {
  /// دفع نقدي عادي: العامل يستلم المبلغ ويستحق أجرة التوصيل كاملة.
  cash(
    label: 'كاش',
    description: 'العامل يستلم المبلغ نقداً ويستحق أجرة التوصيل كاملة.',
    countsWage: true,
    collectsCash: true,
    icon: Icons.payments_outlined,
  ),

  /// مدفوع بالماستر كارد: المبلغ يُقبض لحساب المطعم، فلا نقد مع العامل
  /// ولا أجرة توصيل له عن هذه الطلبية.
  masterCard(
    label: 'ماستر كارد',
    description:
        'الطلب مدفوع بالماستر كارد لحساب المطعم: العامل لا يستلم نقداً '
        'ولا تُحتسب له أجرة توصيل.',
    countsWage: false,
    collectsCash: false,
    icon: Icons.credit_card_outlined,
  ),

  /// استلام مباشر من المطعم: الطلب مُسلَّم بلا نقد مع العامل ولا أجرة توصيل.
  directReceive(
    label: 'استلام مباشر',
    description:
        'الطلب مُستلَم مباشرة من المطعم: لا نقد مع العامل '
        'ولا تُحتسب له أجرة توصيل.',
    countsWage: false,
    collectsCash: false,
    icon: Icons.handshake_outlined,
  ),

  /// حالة خاصة بأجر صفر: أي معاملة خاصة إضافية بأجر صفر ولا نقد مع العامل.
  otherSpecial(
    label: 'حالة خاصة',
    description:
        'حالة خاصة: أجر العامل صفر نهائياً ولا تُحتسب أي نسبة توصيل له.',
    countsWage: false,
    collectsCash: false,
    icon: Icons.star_border_outlined,
  );

  const OrderPaymentType({
    required this.label,
    required this.description,
    required this.countsWage,
    required this.collectsCash,
    required this.icon,
  });

  /// النص العربي المعروض في الواجهة (`كاش`، `ماستر كارد`، `استلام مباشر`).
  final String label;

  /// شرح مختصر يوضّح أثر هذا النوع على الأجرة وصافي المطعم.
  final String description;

  /// هل تُحتسب أجرة توصيل عن الطلب بهذا النوع؟
  final bool countsWage;

  /// هل يستلم العامل مبلغ الطلب نقداً (ليُسلّمه للمطعم)؟
  final bool collectsCash;

  /// أيقونة النوع المستخدمة في الرقائق والشارات.
  final IconData icon;

  /// هل هذا النوع حالة خاصة بأجرة صفر (ماستر كارد أو استلام مباشر)؟
  bool get isSpecialCase => !countsWage;

  /// مفتاح التخزين/JSON (اسم القيمة في الـ enum).
  String get storageKey => name;

  /// النص القصير المعروض في الشارات: «الصفر أجرة» للأنواع بلا أجرة.
  String get shortLabel => countsWage ? label : '$label (بدون أجرة)';

  /// قراءة النوع من قيمة مخزّنة، مع الرجوع إلى [OrderPaymentType.cash]
  /// لأي قيمة ناقصة أو غير معروفة (توافق البيانات القديمة).
  static OrderPaymentType fromName(Object? value) {
    final String key = value?.toString().trim() ?? '';
    for (final OrderPaymentType type in OrderPaymentType.values) {
      if (type.name == key) {
        return type;
      }
    }
    return OrderPaymentType.cash;
  }
}