import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:orderly_app/models/delivery_order.dart';
import 'package:orderly_app/models/driver.dart';
import 'package:orderly_app/models/order_payment_type.dart';
import 'package:orderly_app/screens/camera_scan_screen.dart';
import 'package:orderly_app/services/ocr_service.dart';
import 'package:orderly_app/theme/app_theme.dart';
import 'package:orderly_app/utils/formatters.dart';
import 'package:orderly_app/widgets/stat_tile.dart';

/// يفتح حواراً سريعاً لتسجيل طلب جديد للعامل [driver].
///
/// يُرجع الطلب الجديد ([DeliveryOrder]) مع رقمه وسعره ونوع دفعه ووقت إضافته،
/// أو `null` إذا أُلغي الحوار أو أُغلق دون إدخال. ويُضاف الطلب للحساب خارج
/// الحوار باستخدام `driver.addDeliveryOrder(order)` ثم يُحفظ محلياً.
Future<DeliveryOrder?> showOrderPriceDialog(
  BuildContext context, {
  required Driver driver,
}) {
  return showDialog<DeliveryOrder>(
    context: context,
    builder: (BuildContext dialogContext) => OrderPriceDialog(driver: driver),
  );
}

/// حوار إدخال رقم الطلب وسعره مع عرض أرقام العامل وحساب الأجرة والصافي فوراً.
class OrderPriceDialog extends StatefulWidget {
  const OrderPriceDialog({super.key, required this.driver});

  /// العامل الذي تُسجَّل الطلب باسمه.
  final Driver driver;

  @override
  State<OrderPriceDialog> createState() => _OrderPriceDialogState();
}

class _OrderPriceDialogState extends State<OrderPriceDialog> {
  final TextEditingController _numberController = TextEditingController();
  final TextEditingController _controller = TextEditingController();
  double? _price;
  bool _submitted = false;
  bool _isScanning = false;
  String? _scanNotice;
  List<double> _scannedAmounts = <double>[];
  List<String> _scannedNumbers = <String>[];

  /// نوع دفع الطلب المختار (كاش افتراضياً)، والماستر كارد والاستلام المباشر
  /// يُعاملان معاملة الحالات الخاصة بأجرة صفر.
  OrderPaymentType _paymentType = OrderPaymentType.cash;

  @override
  void initState() {
    super.initState();
    // رقم مقترح تلقائياً لتنظيم الأوردرات (قابل للتعديل أو الحذف).
    _numberController.text = widget.driver.suggestedOrderNumber;
    _numberController.selection = TextSelection.collapsed(
      offset: _numberController.text.length,
    );
  }

  @override
  void dispose() {
    _numberController.dispose();
    _controller.dispose();
    super.dispose();
  }

  void _onChanged(String value) {
    setState(() => _price = parseAmount(value));
  }

  /// فتح شاشة الكاميرا، ثم ملء حقلي **رقم الطلب والسعر** بأفضل ما تم
  /// التعرف عليه من الصورة.
  Future<void> _scanWithCamera() async {
    if (_isScanning) {
      return;
    }
    setState(() {
      _isScanning = true;
      _scanNotice = null;
    });

    OcrResult? result;
    try {
      result = await Navigator.of(context).push<OcrResult>(
        MaterialPageRoute<OcrResult>(
          builder: (BuildContext _) => CameraScanScreen(
            initialPrice: _price,
            initialOrderNumber: _numberController.text.trim().isNotEmpty
                ? _numberController.text.trim()
                : null,
          ),
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _isScanning = false);
      }
    }

    if (!mounted || result == null) {
      return;
    }
    _applyScanResult(result);
  }

  /// تطبيق نتيجة القراءة: ملء رقم الطلب والسعر تلقائياً وعرض البدائل.
  ///
  /// رقم الطلب يُملأ فقط إذا عُثر على رقم واضح مرتبط بكلمة «طلب» أو `#`،
  /// فلا يُستبدل الرقم المقترح تلقائياً بسعر عشوائي.
  void _applyScanResult(OcrResult result) {
    final double? best = result.best;
    final String? scannedNumber = result.bestOrderNumber;

    setState(() {
      _scannedAmounts = result.amounts.take(5).toList();
      _scannedNumbers = result.orderNumbers.take(5).toList();
      _scanNotice = _buildScanNotice(best, scannedNumber);
    });

    if (best != null) {
      _fillPrice(best);
    }
    if (scannedNumber != null && scannedNumber != _numberController.text.trim()) {
      _fillOrderNumber(scannedNumber);
    }
  }

  /// نص تنبيه المسح حسب ما تم التعرف عليه فعلاً.
  String _buildScanNotice(double? best, String? number) {
    if (best == null && number == null) {
      return 'لم يتم التعرف على أرقام واضحة في الصورة. جرّب المسح مرة أخرى '
          'أو أدخل رقم الطلب والسعر يدوياً.';
    }
    if (best != null && number != null) {
      return 'تم التعرف على رقم الطلب $number والسعر من الصورة، ويمكنك '
          'تعديلهما يدوياً قبل الإضافة.';
    }
    if (number != null) {
      return 'تم التعرف على رقم الطلب $number من الصورة، وأدخل السعر يدوياً.';
    }
    return 'تم التعرف على السعر من الصورة وملء الحقل تلقائياً، ويمكنك '
        'تعديله يدوياً قبل الإضافة.';
  }

  /// كتابة رقم الطلب [value] في حقل رقم الطلب (يبقى قابلاً للتعديل يدوياً).
  void _fillOrderNumber(String value) {
    _numberController.text = value;
    _numberController.selection = TextSelection.collapsed(
      offset: value.length,
    );
    setState(() {});
  }

  /// كتابة المبلغ [value] في حقل السعر (يبقى الحقل قابلاً للتعديل يدوياً).
  void _fillPrice(double value) {
    final String text = value.round().toString();
    _controller.text = text;
    _controller.selection = TextSelection.collapsed(offset: text.length);
    _onChanged(text);
  }

  void _submit() {
    final double? price = _price;
    if (price == null) {
      setState(() => _submitted = true);
      return;
    }
    Navigator.of(context).pop(
      DeliveryOrder(
        orderNumber: _numberController.text.trim(),
        amount: price,
        paymentType: _paymentType,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final Driver driver = widget.driver;
    final TextTheme text = Theme.of(context).textTheme;
    final double? price = _price;
    // معاينة فورية للنتيجة قبل الحفظ.
    final Driver preview = price == null
        ? driver
        : driver.addOrder(
            price,
            orderNumber: _numberController.text,
            paymentType: _paymentType,
          );
    final bool showError =
        price == null && (_submitted || _controller.text.trim().isNotEmpty);

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
              Icons.add_shopping_cart_outlined,
              color: AppColors.primary,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  'تسجيل طلب جديد',
                  key: const ValueKey<String>('order-dialog-title'),
                  style: text.titleMedium,
                ),
                const SizedBox(height: 2),
                Text(
                  driver.name.isEmpty ? 'بدون اسم' : driver.name,
                  style: text.bodySmall,
                ),
              ],
            ),
          ),
        ],
      ),
      content: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Row(
              children: <Widget>[
                Expanded(
                  child: StatTile(
                    label: 'عدد الطلبات',
                    value: formatNumber(driver.ordersCount),
                    icon: Icons.receipt_long_outlined,
                    color: AppColors.primary,
                    valueKey: const ValueKey<String>('dialog-orders'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: StatTile(
                    label: 'إجمالي المبالغ',
                    value: formatAmount(driver.totalOrdersAmount),
                    icon: Icons.payments_outlined,
                    color: const Color(0xFF2563EB),
                    valueKey: const ValueKey<String>('dialog-total'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: <Widget>[
                Expanded(
                  child: StatTile(
                    label: 'أجرة العامل',
                    value: formatAmount(driver.wage),
                    icon: Icons.savings_outlined,
                    color: AppColors.accent,
                    valueKey: const ValueKey<String>('dialog-wage'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: StatTile(
                    label: 'صافي المطعم',
                    value: formatAmount(driver.netAmountToRestaurant),
                    icon: Icons.storefront_outlined,
                    color: AppColors.success,
                    valueKey: const ValueKey<String>('dialog-net'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              'الأجرة = عدد الطلبات المستحقة × '
              '${formatAmount(driver.wagePerOrder)}، والصافي = كامل قيمة الطلبات دون أي خصم.',
              style: text.bodySmall?.copyWith(height: 1.6),
            ),
            const SizedBox(height: 10),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Expanded(
                  child: TextField(
                    key: const ValueKey<String>('order-number-field'),
                    controller: _numberController,
                    textInputAction: TextInputAction.next,
                    keyboardType: TextInputType.text,
                    onChanged: (String _) => setState(() {}),
                    decoration: const InputDecoration(
                      labelText: 'رقم الطلب',
                      hintText: 'مثال: 1024',
                      prefixIcon: Icon(Icons.tag_outlined, size: 20),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: TextField(
                    key: const ValueKey<String>('order-price-field'),
                    controller: _controller,
                    autofocus: true,
                    textInputAction: TextInputAction.done,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    inputFormatters: <TextInputFormatter>[
                      FilteringTextInputFormatter.allow(RegExp('[0-9.]')),
                    ],
                    onChanged: _onChanged,
                    onSubmitted: (String _) => _submit(),
                    decoration: InputDecoration(
                      labelText: 'سعر الطلب',
                      hintText: 'مثال: 15000',
                      prefixIcon: const Icon(Icons.edit_outlined, size: 20),
                      suffixText: kCurrency,
                      errorText: showError
                          ? 'أدخل سعراً صحيحاً أكبر من صفر'
                          : null,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              'أدخل رقم الطلب والسعر يدوياً أو اقرأهما تلقائياً من صورة '
              'الفاتورة بزر «مسح بالكاميرا».',
              style: text.bodySmall?.copyWith(height: 1.6),
            ),
            const SizedBox(height: 12),
            _PaymentTypePicker(
              selected: _paymentType,
              onChanged: (OrderPaymentType type) =>
                  setState(() => _paymentType = type),
            ),
            const SizedBox(height: 10),
            OutlinedButton.icon(
              key: const ValueKey<String>('camera-scan-button'),
              onPressed: _isScanning ? null : _scanWithCamera,
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.primary,
                minimumSize: const Size.fromHeight(48),
                side: const BorderSide(color: AppColors.primary),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
                textStyle: text.labelLarge,
              ),
              icon: _isScanning
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.photo_camera_outlined, size: 20),
              label: Text(
                _isScanning
                    ? 'جاري فتح الكاميرا…'
                    : 'مسح بالكاميرا (رقم الطلب والسعر)',
              ),
            ),
            if (_scanNotice != null) ...<Widget>[
              const SizedBox(height: 10),
              _ScanNoticeBox(message: _scanNotice!),
            ],
            if (_scannedAmounts.length > 1) ...<Widget>[
              const SizedBox(height: 12),
              Text(
                'الأرقام المكتشفة في الصورة (اختر الرقم الصحيح):',
                style: text.bodySmall,
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: _scannedAmounts
                    .map(
                      (double amount) => ActionChip(
                        key: ValueKey<String>(
                          'scanned-amount-${amount.round()}',
                        ),
                        label: Text(formatAmount(amount)),
                        backgroundColor: AppColors.primary.withValues(
                          alpha: 0.08,
                        ),
                        side: BorderSide(
                          color: AppColors.primary.withValues(alpha: 0.25),
                        ),
                        labelStyle: text.bodySmall?.copyWith(
                          color: AppColors.primary,
                          fontWeight: FontWeight.w700,
                        ),
                        onPressed: () => _fillPrice(amount),
                      ),
                    )
                    .toList(),
              ),
            ],
            if (_scannedNumbers.isNotEmpty) ...<Widget>[
              const SizedBox(height: 12),
              Text(
                'أرقام الطلبات المكتشفة في الصورة (اختر الرقم الصحيح):',
                style: text.bodySmall,
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: _scannedNumbers
                    .map(
                      (String number) => ActionChip(
                        key: ValueKey<String>('scanned-number-$number'),
                        avatar: const Icon(Icons.tag_outlined, size: 16),
                        label: Text(number),
                        backgroundColor: AppColors.accent.withValues(
                          alpha: 0.12,
                        ),
                        side: BorderSide(
                          color: AppColors.accent.withValues(alpha: 0.35),
                        ),
                        labelStyle: text.bodySmall?.copyWith(
                          color: AppColors.textPrimary,
                          fontWeight: FontWeight.w700,
                        ),
                        onPressed: () => _fillOrderNumber(number),
                      ),
                    )
                    .toList(),
              ),
            ],
            if (price != null) _OrderPreview(preview: preview, payment: _paymentType),
          ],
        ),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('إلغاء'),
        ),
        FilledButton.icon(
          key: const ValueKey<String>('order-submit-button'),
          onPressed: price == null ? null : _submit,
          icon: const Icon(Icons.check, size: 18),
          label: const Text('إضافة الطلب'),
        ),
      ],
    );
  }
}

/// معاينة فورية لأرقام العامل بعد إضافة الطلب (الطلبات، المبالغ، الأجرة، الصافي).
class _OrderPreview extends StatelessWidget {
  const _OrderPreview({required this.preview, required this.payment});

  /// العامل مع الطلب الجديد (لحساب الأرقام المتوقعة).
  final Driver preview;

  /// نوع دفع الطلب الجديد (يُعرض في المعاينة مع أثره على الأجرة).
  final OrderPaymentType payment;

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;

    return Container(
      margin: const EdgeInsets.only(top: 14),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.primary.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.20)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              const Icon(
                Icons.calculate_outlined,
                size: 17,
                color: AppColors.primary,
              ),
              const SizedBox(width: 6),
              Text(
                'بعد إضافة الطلب',
                style: text.titleSmall?.copyWith(fontSize: 13.5),
              ),
            ],
          ),
          const SizedBox(height: 10),
          if (preview.orders.isNotEmpty)
            _PreviewRow(
              label: 'الطلب الجديد',
              value:
                  '${preview.orders.last.displayNumber} • '
                  '${formatAmount(preview.orders.last.amount)}',
              valueKey: const ValueKey<String>('dialog-preview-new-order'),
            ),
          _PreviewRow(
            label: 'نوع الدفع',
            value: payment.label,
            valueKey: const ValueKey<String>('dialog-preview-payment'),
          ),
          if (payment.isSpecialCase)
            _PreviewRow(
              label: 'أجرة هذه الطلبية',
              value: formatAmount(0),
              valueKey: const ValueKey<String>('dialog-preview-zero-wage'),
            ),
          _PreviewRow(
            label: 'عدد الطلبات',
            value: formatNumber(preview.ordersCount),
            valueKey: const ValueKey<String>('dialog-preview-orders'),
          ),
          _PreviewRow(
            label: 'إجمالي المبالغ',
            value: formatAmount(preview.totalOrdersAmount),
            valueKey: const ValueKey<String>('dialog-preview-total'),
          ),
          _PreviewRow(
            label: 'أجرة العامل',
            value: formatAmount(preview.wage),
            valueKey: const ValueKey<String>('dialog-preview-wage'),
          ),
          _PreviewRow(
            label: 'صافي المطعم',
            value: formatAmount(preview.netAmountToRestaurant),
            valueKey: const ValueKey<String>('dialog-preview-net'),
            highlight: true,
          ),
        ],
      ),
    );
  }
}

/// سطر واحد داخل صندوق المعاينة (عنوان + قيمة).
class _PreviewRow extends StatelessWidget {
  const _PreviewRow({
    required this.label,
    required this.value,
    required this.valueKey,
    this.highlight = false,
  });

  final String label;
  final String value;
  final Key valueKey;
  final bool highlight;

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: <Widget>[
          Text(label, style: text.bodySmall),
          Text(
            value,
            key: valueKey,
            style: text.titleSmall?.copyWith(
              color: highlight ? AppColors.success : AppColors.textPrimary,
            ),
          ),
        ],
      ),
    );
  }
}

/// رقائق اختيار نوع دفع الطلب (كاش / ماستر كارد / استلام مباشر).
///
/// الماستر كارد والاستلام المباشر يُعاملان معاملة الحالات الخاصة بأجرة
/// **صفر**، فلا تُحتسب لهما أي أجور توصيل.
class _PaymentTypePicker extends StatelessWidget {
  const _PaymentTypePicker({required this.selected, required this.onChanged});

  /// النوع المختار حالياً.
  final OrderPaymentType selected;

  /// يُستدعى عند اختيار نوع آخر.
  final ValueChanged<OrderPaymentType> onChanged;

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Row(
          children: <Widget>[
            const Icon(
              Icons.credit_card_outlined,
              size: 17,
              color: AppColors.textSecondary,
            ),
            const SizedBox(width: 6),
            Text('نوع الدفع', style: text.titleSmall?.copyWith(fontSize: 13.5)),
          ],
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: OrderPaymentType.values
              .map(
                (OrderPaymentType type) => ChoiceChip(
                  key: ValueKey<String>('payment-type-${type.storageKey}'),
                  selected: type == selected,
                  onSelected: (bool _) => onChanged(type),
                  avatar: Icon(
                    type.icon,
                    size: 16,
                    color: type == selected
                        ? AppColors.primary
                        : AppColors.textSecondary,
                  ),
                  label: Text(type.label),
                  selectedColor: AppColors.primary.withValues(alpha: 0.12),
                  side: BorderSide(
                    color: type == selected
                        ? AppColors.primary
                        : AppColors.border,
                  ),
                  labelStyle: text.bodySmall?.copyWith(
                    color: type == selected
                        ? AppColors.primary
                        : AppColors.textPrimary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              )
              .toList(),
        ),
        const SizedBox(height: 8),
        _PaymentHintBox(payment: selected),
      ],
    );
  }
}

/// تنبيه يوضّح أثر نوع الدفع المختار على الأجرة وصافي المطعم.
class _PaymentHintBox extends StatelessWidget {
  const _PaymentHintBox({required this.payment});

  /// نوع الدفع المختار.
  final OrderPaymentType payment;

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    final bool special = payment.isSpecialCase;
    final Color color = special ? AppColors.warning : AppColors.success;

    return Container(
      key: const ValueKey<String>('payment-hint'),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: special
            ? AppColors.warningSurface
            : AppColors.success.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.32)),
      ),
      child: Row(
        children: <Widget>[
          Icon(
            special ? Icons.info_outline : Icons.check_circle_outline,
            size: 16,
            color: color,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              payment.description,
              key: const ValueKey<String>('payment-hint-text'),
              style: text.bodySmall?.copyWith(height: 1.5, color: color),
            ),
          ),
        ],
      ),
    );
  }
}

/// صندوق تنبيه صغير يعرض نتيجة المسح بالكاميرا أسفل حقل السعر.
class _ScanNoticeBox extends StatelessWidget {
  const _ScanNoticeBox({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;

    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: AppColors.accent.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.accent.withValues(alpha: 0.30)),
      ),
      child: Row(
        children: <Widget>[
          const Icon(Icons.info_outline, size: 16, color: AppColors.accent),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              key: const ValueKey<String>('scan-notice'),
              style: text.bodySmall?.copyWith(height: 1.5),
            ),
          ),
        ],
      ),
    );
  }
}
