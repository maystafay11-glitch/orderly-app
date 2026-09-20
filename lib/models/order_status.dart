/// حالات الطلب ومراحل التوصيل في نظام Orderly والتتبع اللحظي.
library;

import 'package:flutter/material.dart';
import 'package:orderly_app/theme/app_theme.dart';

/// حالة مسار الطلب من الإعداد إلى التسليم.
enum OrderStatus {
  /// قيد الإعداد بالمطعم (بانتظار استلام السائق).
  preparing(
    label: 'قيد الإعداد',
    description: 'الطلب قيد التحضير بالمطعم وجاهز للاستلام من السائق.',
    stepIndex: 0,
    color: Color(0xFFF59E0B), // أصفر كهرماني
    icon: Icons.outdoor_grill_outlined,
  ),

  /// مع السائق (بالطريق إلى الزبون).
  pickedUp(
    label: 'مع السائق (بالطريق)',
    description: 'استلم السائق الطلب وهو الآن في طريقه إلى الزبون.',
    stepIndex: 1,
    color: Color(0xFF2563EB), // أزرق نشط
    icon: Icons.two_wheeler_rounded,
  ),

  /// تم التسليم للزبون بنجاح.
  delivered(
    label: 'تم التسليم',
    description: 'تم تسليم الطلب للزبون واحتساب الأجرة والمدة.',
    stepIndex: 2,
    color: AppColors.success, // أخضر
    icon: Icons.check_circle_rounded,
  ),

  /// تم إلغاء الطلب.
  cancelled(
    label: 'ملغي',
    description: 'تم إلغاء الطلب.',
    stepIndex: -1,
    color: AppColors.danger, // أحمر
    icon: Icons.cancel_outlined,
  );

  const OrderStatus({
    required this.label,
    required this.description,
    required this.stepIndex,
    required this.color,
    required this.icon,
  });

  /// النص العربي لحالة الطلب.
  final String label;

  /// الشرح التوضيحي للحالة.
  final String description;

  /// رقم مرحلة التقدم (0: إعداد، 1: طريق، 2: تسليم).
  final int stepIndex;

  /// اللون المخصص للحالة.
  final Color color;

  /// أيقونة الحالة.
  final IconData icon;

  /// هل الطلب لا يزال جارياً ونشطاً؟
  bool get isActive => this == OrderStatus.preparing || this == OrderStatus.pickedUp;

  /// هل الطلب في الطريق مع السائق حالياً؟
  bool get isOnTheRoad => this == OrderStatus.pickedUp;

  /// هل اكتمل تسليم الطلب؟
  bool get isCompleted => this == OrderStatus.delivered;

  /// مفتاح التخزين بصيغة JSON.
  String get storageKey => name;

  /// قراءة الحالة من قيمة مخزنة بأمان.
  static OrderStatus fromName(Object? value) {
    final String key = value?.toString().trim() ?? '';
    for (final OrderStatus status in OrderStatus.values) {
      if (status.name == key) {
        return status;
      }
    }
    // للبيانات القديمة التي ليس لها حالة محددة، نعتبرها جاهزة ومكتملة
    return OrderStatus.delivered;
  }
}
