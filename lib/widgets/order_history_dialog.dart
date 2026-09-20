import 'package:flutter/material.dart';

import 'package:orderly_app/models/delivery_order.dart';
import 'package:orderly_app/models/driver.dart';
import 'package:orderly_app/theme/app_theme.dart';
import 'package:orderly_app/utils/formatters.dart';
import 'package:orderly_app/widgets/order_price_dialog.dart';
import 'package:orderly_app/widgets/stat_tile.dart';

/// يفتح نافذة سجل طلبات العامل [driver].
///
/// تعرض النافذة كل طلب برقمه وسعره ووقت إضافته، وبجانب كل طلب زر حذف (🗑️)
/// يحذف تلك الطلبية تحديداً ثم يعيد حساب الأرقام ويحفظها محلياً.
///
/// [onDriverChanged] هي دالة الشاشة المستدعية: تستقبل نسخة العامل الجديدة
/// وتحفظها في التخزين المحلي وتُحدِّث الشاشة، وتُرجع `true` عند النجاح.
Future<void> showOrderHistoryDialog(
  BuildContext context, {
  required Driver driver,
  required Future<bool> Function(Driver updated) onDriverChanged,
}) {
  return showDialog<void>(
    context: context,
    builder: (BuildContext dialogContext) => OrderHistoryDialog(
      driver: driver,
      onDriverChanged: onDriverChanged,
    ),
  );
}

/// نافذة سجل الطلبات: قائمة طلبات العامل + أرقامه + حذف طلب محدد.
class OrderHistoryDialog extends StatefulWidget {
  const OrderHistoryDialog({
    super.key,
    required this.driver,
    required this.onDriverChanged,
  });

  /// العامل الذي تُعرض طلباته.
  final Driver driver;

  /// حفظ أي تغيير (إضافة أو حذف) وإرجاع نجاح العملية.
  final Future<bool> Function(Driver updated) onDriverChanged;

  @override
  State<OrderHistoryDialog> createState() => _OrderHistoryDialogState();
}


class _OrderHistoryDialogState extends State<OrderHistoryDialog> {
  late Driver _driver = widget.driver;
  bool _isBusy = false;

  /// تطبيق تغيير على حساب العامل: حفظ فوري ثم تحديث أرقام النافذة.
  ///
  /// إذا فشل الحفظ لا تُغيَّر البيانات المعروضة ويظهر تنبيه بالخطأ.
  Future<void> _applyChange(Driver updated) async {
    setState(() => _isBusy = true);
    final bool saved = await widget.onDriverChanged(updated);
    if (!mounted) {
      return;
    }
    setState(() {
      _isBusy = false;
      if (saved) {
        _driver = updated;
      }
    });
    if (!saved) {
      _showMessage('تعذّر حفظ التغيير، حاول مرة أخرى.');
    }
  }

  /// طلب تأكيد حذف الطلب الواقع في الترتيب [index] من سجل طلبات العامل.
  ///
  /// التأكيد يحمي من الحذف بالخطأ، وبعد الموافقة يُنفَّذ الحذف فوراً:
  /// خصم قيمة الطلب من إجمالي المبالغ، إنقاص عدد الطلبات بمقدار واحد،
  /// إعادة حساب الأجرة وصافي المطعم، ثم الحفظ محلياً.
  Future<void> _confirmDeleteOrder(int index) async {
    if (_isBusy || index < 0 || index >= _driver.orders.length) {
      return;
    }
    final DeliveryOrder order = _driver.orders[index];
    final TextTheme text = Theme.of(context).textTheme;

    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext dialogContext) => AlertDialog(
        titlePadding: const EdgeInsets.fromLTRB(20, 20, 20, 10),
        contentPadding: const EdgeInsets.fromLTRB(20, 0, 20, 10),
        actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        title: Row(
          children: <Widget>[
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: AppColors.danger.withValues(alpha: 0.10),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.delete_outline, color: AppColors.danger),
            ),
            const SizedBox(width: 12),
            const Expanded(child: Text('حذف الطلب')),
          ],
        ),
        content: Text(
          'سيتم حذف الطلب مع رقم الطلب: ${order.displayNumber} '
          '(${formatAmount(order.amount)}) من حساب '
          '«${_driver.name.isEmpty ? 'بدون اسم' : _driver.name}».\n'
          'سيُخصم مبلغه فوراً من إجمالي المبالغ ويُنقص عدد الطلبات واحداً، '
          'وتُعاد حساب الأجرة وصافي المطعم.\n'
          'لا يمكن التراجع عن الحذف.',
          key: const ValueKey<String>('delete-order-message'),
          style: text.bodyMedium?.copyWith(height: 1.7),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('إلغاء'),
          ),
          FilledButton.icon(
            key: const ValueKey<String>('confirm-delete-order-button'),
            style: FilledButton.styleFrom(backgroundColor: AppColors.danger),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            icon: const Icon(Icons.delete_outline, size: 18),
            label: const Text('حذف'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) {
      return;
    }
    await _deleteOrder(index);
  }

  /// حذف الطلب الواقع في الترتيب [index] من سجل طلبات العامل.
  ///
  /// الحذف يخصم مبلغ الطلب من إجمالي مبالغ العامل، ويُنقص عدد الطلبات بمقدار
  /// واحد، ثم يُعيد حساب الأجرة وصافي المطعم ويحفظ كل شيء محلياً.
  Future<void> _deleteOrder(int index) async {
    if (_isBusy || index < 0 || index >= _driver.orders.length) {
      return;
    }
    final DeliveryOrder removed = _driver.orders[index];
    final Driver updated = _driver.removeOrderAt(index);

    await _applyChange(updated);
    if (!mounted || identical(_driver, updated)) {
      return;
    }
    _showMessage(
      'حُذف الطلب ${removed.displayNumber} (${formatAmount(removed.amount)}) — '
      'الطلبات: ${formatNumber(updated.ordersCount)} | '
      'الأجرة: ${formatAmount(updated.wage)} | '
      'صافي المطعم: ${formatAmount(updated.netAmountToRestaurant)}',
    );
  }

  /// إضافة طلب جديد للعامل من داخل سجل الطلبات.
  Future<void> _addOrder() async {
    if (_isBusy) {
      return;
    }
    final DeliveryOrder? order = await showOrderPriceDialog(
      context,
      driver: _driver,
    );
    if (order == null || !mounted) {
      return;
    }
    await _applyChange(_driver.addDeliveryOrder(order));
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    final Driver driver = _driver;
    final String name = driver.name.isEmpty ? 'بدون اسم' : driver.name;

    return AlertDialog(
      titlePadding: const EdgeInsets.fromLTRB(20, 20, 20, 10),
      contentPadding: const EdgeInsets.fromLTRB(20, 0, 20, 10),
      actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      title: Row(
        children: <Widget>[
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.10),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.receipt_long_outlined,
              color: AppColors.primary,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  'سجل الطلبات',
                  key: const ValueKey<String>('order-history-title'),
                  style: text.titleMedium,
                ),
                const SizedBox(height: 2),
                Text(name, style: text.bodySmall),
              ],
            ),
          ),
        ],
      ),
      content: SizedBox(
        width: double.maxFinite,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Row(children: _statsTop(driver)),
              const SizedBox(height: 8),
              Row(children: _statsBottom(driver)),
              if (driver.hasZeroWageOrders) ...<Widget>[
                const SizedBox(height: 10),
                _ZeroWageNotice(driver: driver),
              ],
              const SizedBox(height: 14),
              Text(
                'الطلبات المسجّلة (${formatNumber(driver.orders.length)}):',
                style: text.titleSmall?.copyWith(fontSize: 14),
              ),
              const SizedBox(height: 8),
              if (driver.orders.isEmpty)
                _EmptyOrdersNotice(hasLegacyOrders: driver.hasLegacyOrders)
              else
                for (int index = 0; index < driver.orders.length; index++) ...[
                  if (index > 0) const SizedBox(height: 8),
                  _OrderRow(
                    index: index,
                    order: driver.orders[index],
                    onDelete: _isBusy ? null : () => _confirmDeleteOrder(index),
                  ),
                ],
              if (driver.hasLegacyOrders) ...<Widget>[
                const SizedBox(height: 10),
                _LegacyOrdersNotice(driver: driver),
              ],
            ],
          ),
        ),
      ),
      actions: <Widget>[
        TextButton(
          key: const ValueKey<String>('order-history-close'),
          onPressed: _isBusy ? null : () => Navigator.of(context).pop(),
          child: const Text('إغلاق'),
        ),
        FilledButton.icon(
          key: const ValueKey<String>('order-history-add-order'),
          onPressed: _isBusy ? null : _addOrder,
          icon: const Icon(Icons.add, size: 18),
          label: const Text('إضافة طلب'),
        ),
      ],
    );
  }

  /// مربّعا الرقمين الأعلى: عدد الطلبات + إجمالي المبالغ.
  List<Widget> _statsTop(Driver driver) => <Widget>[
    Expanded(
      child: StatTile(
        label: 'عدد الطلبات',
        value: formatNumber(driver.ordersCount),
        icon: Icons.receipt_long_outlined,
        color: AppColors.primary,
        valueKey: const ValueKey<String>('history-orders'),
      ),
    ),
    const SizedBox(width: 8),
    Expanded(
      child: StatTile(
        label: 'إجمالي المبالغ',
        value: formatAmount(driver.totalOrdersAmount),
        icon: Icons.payments_outlined,
        color: const Color(0xFF2563EB),
        valueKey: const ValueKey<String>('history-total'),
      ),
    ),
  ];

  /// مربّعا الرقمين الأسفل: أجرة العامل + صافي المطعم.
  List<Widget> _statsBottom(Driver driver) => <Widget>[
    Expanded(
      child: StatTile(
        label: 'أجرة العامل',
        value: formatAmount(driver.wage),
        icon: Icons.savings_outlined,
        color: AppColors.accent,
        valueKey: const ValueKey<String>('history-wage'),
      ),
    ),
    const SizedBox(width: 8),
    Expanded(
      child: StatTile(
        label: 'صافي المطعم',
        value: formatAmount(driver.netAmountToRestaurant),
        icon: Icons.storefront_outlined,
        color: AppColors.success,
        valueKey: const ValueKey<String>('history-net'),
      ),
    ),
  ];
}

/// سطر طلب واحد: رقم الطلب + السعر + وقت الإضافة + زر حذف (🗑️).
class _OrderRow extends StatelessWidget {
  const _OrderRow({
    required this.index,
    required this.order,
    required this.onDelete,
  });

  /// ترتيب الطلب داخل السجل (يُستخدم في عدّاد الصف ومفاتيح الاختبار).
  final int index;

  /// الطلب المعروض.
  final DeliveryOrder order;

  /// حذف هذا الطلب تحديداً (يكون `null` أثناء تنفيذ عملية حفظ).
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;

    return Container(
      key: ValueKey<String>('order-row-$index'),
      padding: const EdgeInsets.fromLTRB(12, 10, 6, 10),
      decoration: BoxDecoration(
        color: AppColors.field,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: <Widget>[
          Container(
            width: 32,
            height: 32,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.10),
              shape: BoxShape.circle,
            ),
            child: Text(
              '${index + 1}',
              style: text.bodySmall?.copyWith(
                color: AppColors.primary,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    Text('رقم الطلب: ', style: text.bodySmall),
                    Expanded(
                      child: Text(
                        order.displayNumber,
                        key: ValueKey<String>('history-order-number-$index'),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: text.titleSmall?.copyWith(fontSize: 13.5),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 3),
                Text(
                  '${formatAmount(order.amount)} • '
                  '${formatDateTime(order.addedAt)}',
                  key: ValueKey<String>('history-order-meta-$index'),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: text.bodySmall,
                ),
                const SizedBox(height: 6),
                _PaymentBadge(index: index, order: order),
              ],
            ),
          ),
          IconButton(
            key: ValueKey<String>('delete-order-$index'),
            onPressed: onDelete,
            tooltip: 'حذف هذا الطلب',
            icon: const Icon(Icons.delete_outline, color: AppColors.danger),
          ),
        ],
      ),
    );
  }
}
/// يُعرض عندما لا توجد طلبات مسجّلة تفصيلياً للعامل.
class _EmptyOrdersNotice extends StatelessWidget {
  const _EmptyOrdersNotice({required this.hasLegacyOrders});

  /// هل هناك أرقام مُرحَّلة من إصدار سابق؟
  final bool hasLegacyOrders;

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.primary.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.18)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            'لا توجد طلبات مسجّلة بالتفصيل بعد.',
            key: const ValueKey<String>('history-empty'),
            style: text.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 4),
          Text(
            hasLegacyOrders
                ? 'الأرقام الظاهرة أعلاه مُرحَّلة من نسخة سابقة؛ اضغط «إضافة '
                      'طلب» لتسجيل طلبات جديدة برقم وسعر ووقت.'
                : 'اضغط «إضافة طلب» لتسجيل طلب برقمه وسعره، وسيظهر هنا فوراً.',
            style: text.bodySmall?.copyWith(height: 1.6),
          ),
        ],
      ),
    );
  }
}

/// شارة نوع دفع الطلب: تُبرز الحالات الخاصة (ماستر كارد / استلام مباشر)
/// التي لا تُحتسب لها أي أجرة توصيل.
class _PaymentBadge extends StatelessWidget {
  const _PaymentBadge({required this.index, required this.order});

  /// ترتيب الطلب في السجل (يُستخدم في مفاتيح الاختبار).
  final int index;

  /// الطلب المعروض.
  final DeliveryOrder order;

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    final bool special = order.hasZeroWage;
    final Color color = special ? AppColors.warning : AppColors.primary;

    return Container(
      key: ValueKey<String>('history-order-payment-$index'),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(30),
        border: Border.all(color: color.withValues(alpha: 0.28)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(order.paymentType.icon, size: 13, color: color),
          const SizedBox(width: 4),
          Text(
            order.paymentType.shortLabel,
            style: text.bodySmall?.copyWith(
              fontSize: 11.5,
              color: color,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

/// تنبيه بالأرقام الخاصة بأجرة صفر المسجَّلة على هذا العامل.
class _ZeroWageNotice extends StatelessWidget {
  const _ZeroWageNotice({required this.driver});

  /// العامل المعروض سجله.
  final Driver driver;

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.warningSurface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.warning.withValues(alpha: 0.30)),
      ),
      child: Text(
        'يوجد ${formatNumber(driver.zeroWageOrdersCount)} طلب بمبلغ '
        '${formatAmount(driver.zeroWageOrdersAmount)} مدفوع بالماستر كارد أو '
        'بالاستلام المباشر أو حالة خاصة، ولا تُحتسب له أي أجرة توصيل.',
        key: const ValueKey<String>('history-zero-wage-notice'),
        style: text.bodySmall?.copyWith(
          height: 1.6,
          color: AppColors.warning,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

/// تنبيه بالأرقام المُرحَّلة من إصدار سابق (عدد ومبلغ بلا تفاصيل لكل طلب).
class _LegacyOrdersNotice extends StatelessWidget {
  const _LegacyOrdersNotice({required this.driver});

  final Driver driver;

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.warningSurface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.warning.withValues(alpha: 0.30)),
      ),
      child: Text(
        'يوجد ${formatNumber(driver.legacyOrdersCount)} طلب بمبلغ '
        '${formatAmount(driver.legacyOrdersAmount)} مُرحَّل من نسخة سابقة بدون '
        'رقم أو سعر لكل طلب، ويبقى محسوباً ضمن الأرقام إلى أن يُصفَّر اليوم.',
        key: const ValueKey<String>('history-legacy-notice'),
        style: text.bodySmall?.copyWith(
          height: 1.6,
          color: AppColors.warning,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
