import 'package:flutter/material.dart';

/// مربّع صغير يعرض رقماً معنوناً: عدد الطلبات، إجمالي المبالغ، الأجرة، الصافي.
class StatTile extends StatelessWidget {
  const StatTile({
    super.key,
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
    this.valueKey,
    this.compact = false,
  });

  /// عنوان الرقم (مثال: إجمالي المبالغ).
  final String label;

  /// القيمة المعروضة كنص جاهز (مثال: 250,000 د.ع).
  final String value;

  /// أيقونة توضيحية بجانب العنوان.
  final IconData icon;

  /// لون التمييز الخاص بالرقم.
  final Color color;

  /// مفتاح يُستخدم في الاختبارات للوصول إلى قيمة الرقم.
  final Key? valueKey;

  /// نسخة مضغوطة تُستخدم داخل بطاقات العمال.
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;

    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 10 : 12,
        vertical: compact ? 10 : 12,
      ),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withValues(alpha: 0.20)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Row(
            children: <Widget>[
              Icon(icon, size: compact ? 15 : 17, color: color),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: text.bodySmall?.copyWith(
                    fontSize: compact ? 11.5 : 12.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            value,
            key: valueKey,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: text.titleSmall?.copyWith(
              color: color,
              fontSize: compact ? 14.5 : 16,
            ),
          ),
        ],
      ),
    );
  }
}
