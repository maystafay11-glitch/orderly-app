import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:orderly_app/models/delivery_order.dart';
import 'package:orderly_app/models/order_payment_type.dart';
import 'package:orderly_app/screens/camera_scan_screen.dart';
import 'package:orderly_app/services/ocr_service.dart';
import 'package:orderly_app/theme/app_theme.dart';
import 'package:orderly_app/utils/formatters.dart';

/// يفتح حوار تسجيل طلب عام / سفري مستقل بدون عامل ديليفري.
///
/// يُرجع [DeliveryOrder] أو `null` في حال الإلغاء.
Future<DeliveryOrder?> showGeneralOrderDialog(
  BuildContext context, {
  double? initialPrice,
  String? initialOrderNumber,
}) {
  return showDialog<DeliveryOrder>(
    context: context,
    builder: (BuildContext dialogContext) => GeneralOrderDialog(
      initialPrice: initialPrice,
      initialOrderNumber: initialOrderNumber,
    ),
  );
}

/// نافذة إدخال طلب سفري / عام مستقل (دون احتساب أي أجور توصيل لعامل محدد).
class GeneralOrderDialog extends StatefulWidget {
  const GeneralOrderDialog({
    super.key,
    this.initialPrice,
    this.initialOrderNumber,
  });

  final double? initialPrice;
  final String? initialOrderNumber;

  @override
  State<GeneralOrderDialog> createState() => _GeneralOrderDialogState();
}

class _GeneralOrderDialogState extends State<GeneralOrderDialog> {
  final TextEditingController _numberController = TextEditingController();
  final TextEditingController _priceController = TextEditingController();
  double? _price;
  bool _submitted = false;
  bool _isScanning = false;
  String? _scanNotice;

  /// أنواع الدفع المتاحة للطلبات العامة:
  /// * سفري نقدي (كاش للمطعم)
  /// * ماستر كارد (إلكتروني للمطعم)
  /// * استلام مباشر
  OrderPaymentType _paymentType = OrderPaymentType.cash;

  @override
  void initState() {
    super.initState();
    if (widget.initialPrice != null && widget.initialPrice! > 0) {
      _price = widget.initialPrice;
      _priceController.text = formatNumber(widget.initialPrice!);
    }
    if (widget.initialOrderNumber != null &&
        widget.initialOrderNumber!.isNotEmpty) {
      _numberController.text = widget.initialOrderNumber!;
    }
  }

  @override
  void dispose() {
    _numberController.dispose();
    _priceController.dispose();
    super.dispose();
  }

  void _onPriceChanged(String value) {
    setState(() => _price = parseAmount(value));
  }

  /// مسح الفاتورة أو الباركود عبر الكاميرا.
  Future<void> _scanWithCamera() async {
    if (_isScanning) return;
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

    if (!mounted || result == null) return;
    _applyScanResult(result);
  }

  void _applyScanResult(OcrResult result) {
    setState(() {
      if (result.best != null && result.best! > 0) {
        _price = result.best;
        _priceController.text = formatNumber(result.best!);
        _priceController.selection = TextSelection.collapsed(
          offset: _priceController.text.length,
        );
      }
      if (result.bestOrderNumber != null &&
          result.bestOrderNumber!.isNotEmpty) {
        _numberController.text = result.bestOrderNumber!;
        _numberController.selection = TextSelection.collapsed(
          offset: _numberController.text.length,
        );
      }
      if (result.best != null || result.bestOrderNumber != null) {
        _scanNotice = 'تمت قراءة الفاتورة بنجاح عبر الكاميرا ✅';
      }
    });
  }

  void _submit() {
    setState(() => _submitted = true);
    final double? price = _price;
    if (price == null || price <= 0) {
      return;
    }

    final DeliveryOrder order = DeliveryOrder(
      orderNumber: _numberController.text.trim(),
      amount: price,
      // الطلب العام يذهب 100% للمطعم دون أجور توصيل
      paymentType: _paymentType,
      addedAt: DateTime.now(),
    );

    Navigator.of(context).pop(order);
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final TextTheme text = theme.textTheme;
    final bool priceValid = _price != null && _price! > 0;

    return AlertDialog(
      titlePadding: const EdgeInsets.fromLTRB(20, 20, 20, 10),
      contentPadding: const EdgeInsets.fromLTRB(20, 0, 20, 10),
      actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      title: Row(
        children: <Widget>[
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: <Color>[Color(0xFFEA580C), Color(0xFFC2410C)],
                begin: Alignment.topRight,
                end: Alignment.bottomLeft,
              ),
              borderRadius: BorderRadius.circular(14),
              boxShadow: <BoxShadow>[
                BoxShadow(
                  color: const Color(0xFFEA580C).withValues(alpha: 0.25),
                  blurRadius: 8,
                  offset: const Offset(0, 3),
                ),
              ],
            ),
            child: const Icon(
              Icons.takeout_dining_rounded,
              color: Colors.white,
              size: 24,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                const Text('تسجيل طلب سفري / عام'),
                const SizedBox(height: 2),
                Text(
                  'أجرة التوصيل: 0 د.ع • صافي 100% للمطعم',
                  style: text.bodySmall?.copyWith(
                    color: AppColors.success,
                    fontWeight: FontWeight.bold,
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            const SizedBox(height: 12),

            // تنبيه نجاح المسح إن وُجد
            if (_scanNotice != null) ...<Widget>[
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: AppColors.success.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: AppColors.success.withValues(alpha: 0.3),
                  ),
                ),
                child: Row(
                  children: <Widget>[
                    const Icon(
                      Icons.check_circle_outline,
                      size: 16,
                      color: AppColors.success,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _scanNotice!,
                        style: text.bodySmall?.copyWith(
                          color: AppColors.success,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
            ],

            // صف: حقل السعر + زر الكاميرا السريع
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Expanded(
                  flex: 3,
                  child: TextField(
                    key: const ValueKey<String>('general-order-price-field'),
                    controller: _priceController,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    inputFormatters: <TextInputFormatter>[
                      FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
                    ],
                    autofocus: widget.initialPrice == null,
                    decoration: InputDecoration(
                      labelText: 'سعر الطلب *',
                      hintText: 'مثال: 15,000',
                      suffixText: 'د.ع',
                      errorText: _submitted && !priceValid
                          ? 'أدخل سعر الطلب بالدينار'
                          : null,
                      prefixIcon: const Icon(Icons.payments_outlined),
                    ),
                    onChanged: _onPriceChanged,
                    onSubmitted: (_) => _submit(),
                  ),
                ),
                const SizedBox(width: 8),
                Tooltip(
                  message: 'مسح الفاتورة أو الباركود بالكاميرا',
                  child: SizedBox(
                    height: 56,
                    child: OutlinedButton(
                      key: const ValueKey<String>('scan-general-order-camera'),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                        side: const BorderSide(
                          color: AppColors.primary,
                          width: 1.5,
                        ),
                        backgroundColor:
                            AppColors.primary.withValues(alpha: 0.06),
                      ),
                      onPressed: _isScanning ? null : _scanWithCamera,
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: <Widget>[
                          const Icon(
                            Icons.document_scanner_rounded,
                            size: 20,
                            color: AppColors.primary,
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'مسح OCR',
                            style: text.bodySmall?.copyWith(
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                              color: AppColors.primary,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),

            // حقل رقم الطلب أو الفاتورة
            TextField(
              key: const ValueKey<String>('general-order-number-field'),
              controller: _numberController,
              decoration: const InputDecoration(
                labelText: 'رقم الفاتورة / الطلب (اختياري)',
                hintText: 'مثال: #105 أو باركود',
                prefixIcon: Icon(Icons.tag_rounded),
              ),
              onSubmitted: (_) => _submit(),
            ),
            const SizedBox(height: 16),

            // خيارات نوع الدفع
            Text(
              'طريقة دفع الطلب:',
              style: text.bodySmall?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 6),
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: <Widget>[
                ChoiceChip(
                  key: const ValueKey<String>('general-pay-cash'),
                  label: const Text('سفري نقدي (كاش)'),
                  avatar: const Icon(Icons.payments_outlined, size: 16),
                  selected: _paymentType == OrderPaymentType.cash,
                  selectedColor: AppColors.primary.withValues(alpha: 0.2),
                  onSelected: (bool selected) {
                    if (selected) {
                      setState(() => _paymentType = OrderPaymentType.cash);
                    }
                  },
                ),
                ChoiceChip(
                  key: const ValueKey<String>('general-pay-mastercard'),
                  label: const Text('ماستر كارد'),
                  avatar: const Icon(Icons.credit_card_outlined, size: 16),
                  selected: _paymentType == OrderPaymentType.masterCard,
                  selectedColor: Colors.purple.withValues(alpha: 0.2),
                  onSelected: (bool selected) {
                    if (selected) {
                      setState(() => _paymentType = OrderPaymentType.masterCard);
                    }
                  },
                ),
                ChoiceChip(
                  key: const ValueKey<String>('general-pay-direct'),
                  label: const Text('استلام مباشر'),
                  avatar: const Icon(Icons.handshake_outlined, size: 16),
                  selected: _paymentType == OrderPaymentType.directReceive,
                  selectedColor: Colors.teal.withValues(alpha: 0.2),
                  onSelected: (bool selected) {
                    if (selected) {
                      setState(
                        () => _paymentType = OrderPaymentType.directReceive,
                      );
                    }
                  },
                ),
              ],
            ),
            const SizedBox(height: 16),

            // بطاقة التوضيح المالي
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.success.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: AppColors.success.withValues(alpha: 0.2),
                ),
              ),
              child: Row(
                children: <Widget>[
                  const Icon(
                    Icons.store_rounded,
                    color: AppColors.success,
                    size: 22,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(
                          'صافي ربح المطعم: ${formatAmount(_price ?? 0)}',
                          style: text.bodyMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                            color: AppColors.success,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'لا يُحسم أي أجر توصيل (0 د.ع) لعدم وجود ديليفري.',
                          style: text.bodySmall?.copyWith(fontSize: 11),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('إلغاء'),
        ),
        FilledButton.icon(
          key: const ValueKey<String>('confirm-general-order-button'),
          style: FilledButton.styleFrom(
            backgroundColor: const Color(0xFFEA580C),
            foregroundColor: Colors.white,
          ),
          onPressed: _submit,
          icon: const Icon(Icons.check_circle_outline, size: 18),
          label: const Text('تسجيل الطلب'),
        ),
      ],
    );
  }
}
