import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:orderly_app/models/miswak_calculation.dart';
import 'package:orderly_app/services/miswak_storage.dart';
import 'package:orderly_app/theme/app_theme.dart';
import 'package:orderly_app/utils/formatters.dart';
import 'package:orderly_app/utils/whatsapp.dart';
import 'package:orderly_app/widgets/stat_tile.dart';

/// شاشة حساب المسواگ والأرباح.
///
/// تتيح إدخال تكاليف المواد والتغليف والمصاريف الأخرى وسعر البيع،
/// وحساب صافي الربح وهامش الربح ونقطة التعادل بدقة تامة وبشكل لحظي،
/// مع إمكانية حفظ الدفعات ومشاركتها عبر الواتساب.
class MiswakScreen extends StatefulWidget {
  const MiswakScreen({super.key, this.showAppBar = true});

  /// هل يتم عرض شريط التطبيق العلوي (يُعطَّل عند تضمينها في التبويب السفلي).
  final bool showAppBar;

  /// عنوان الشاشة في شريط التطبيق.
  static const String title = 'حساب المسواگ والأرباح';

  @override
  State<MiswakScreen> createState() => MiswakScreenState();
}

class MiswakScreenState extends State<MiswakScreen> {
  final TextEditingController _labelController = TextEditingController();
  final TextEditingController _quantityController = TextEditingController();
  final TextEditingController _materialCostController = TextEditingController();
  final TextEditingController _packagingCostController = TextEditingController();
  final TextEditingController _otherCostsController = TextEditingController();
  final TextEditingController _salePriceController = TextEditingController();

  List<MiswakCalculation> _batches = <MiswakCalculation>[];
  bool _isLoading = true;
  bool _isSaving = false;

  /// إعادة تحميل بيانات المسواگ فوراً.
  Future<void> reload() => _loadBatches();

  @override
  void initState() {
    super.initState();
    _loadBatches();
  }

  @override
  void dispose() {
    _labelController.dispose();
    _quantityController.dispose();
    _materialCostController.dispose();
    _packagingCostController.dispose();
    _otherCostsController.dispose();
    _salePriceController.dispose();
    super.dispose();
  }

  /// تحميل الدفعات المحفوظة من التخزين المحلي.
  Future<void> _loadBatches() async {
    final List<MiswakCalculation> items = await MiswakStorage.load();
    if (!mounted) return;
    setState(() {
      _batches = items;
      _isLoading = false;
    });
  }

  /// حساب مباشر للدفعة الحالية من المدخلات.
  MiswakCalculation? _calculateCurrent() {
    final int? quantity = int.tryParse(
      _quantityController.text.replaceAll(',', '').trim(),
    );
    final double? materialCost = parseAmount(_materialCostController.text);
    final double? salePrice = parseAmount(_salePriceController.text);

    if (quantity == null || quantity <= 0 || materialCost == null || salePrice == null) {
      return null;
    }

    final double packagingCost =
        parseAmount(_packagingCostController.text) ?? 0;
    final double otherCosts = parseAmount(_otherCostsController.text) ?? 0;

    return MiswakCalculation(
      label: _labelController.text.trim(),
      quantity: quantity,
      materialCost: materialCost,
      packagingCost: packagingCost,
      otherCosts: otherCosts,
      salePrice: salePrice,
    );
  }

  /// حفظ الدفعة الحالية في التخزين المحلي.
  Future<void> _saveBatch() async {
    final MiswakCalculation? current = _calculateCurrent();
    if (current == null) {
      _showMessage('يرجى ملء الكمية وتكلفة المواد وسعر البيع لحساب الدفعة.');
      return;
    }

    setState(() => _isSaving = true);
    final List<MiswakCalculation> updated = await MiswakStorage.add(current);
    if (!mounted) return;
    setState(() {
      _batches = updated;
      _isSaving = false;
    });
    _showMessage('تم حفظ دفعة «${current.displayLabel}» بنجاح.');
  }

  /// مسح الحقول للبدء بحساب دفعة جديدة.
  void _clearFields() {
    setState(() {
      _labelController.clear();
      _quantityController.clear();
      _materialCostController.clear();
      _packagingCostController.clear();
      _otherCostsController.clear();
      _salePriceController.clear();
    });
  }

  /// تحميل دفعة محفوظة إلى الحقول لإعادة الحساب أو الاطلاع.
  void _loadIntoFields(MiswakCalculation batch) {
    setState(() {
      _labelController.text = batch.label;
      _quantityController.text = batch.quantity.toString();
      _materialCostController.text = batch.materialCost.round().toString();
      _packagingCostController.text =
          batch.packagingCost > 0 ? batch.packagingCost.round().toString() : '';
      _otherCostsController.text =
          batch.otherCosts > 0 ? batch.otherCosts.round().toString() : '';
      _salePriceController.text = batch.salePrice.round().toString();
    });
    _showMessage('تم تحميل بيانات «${batch.displayLabel}» إلى الحقول.');
  }

  /// تأكيد وحذف دفعة محفوظة.
  Future<void> _confirmDelete(int index) async {
    if (index < 0 || index >= _batches.length) return;
    final MiswakCalculation batch = _batches[index];

    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext dialogContext) => AlertDialog(
        title: Row(
          children: <Widget>[
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: AppColors.danger.withValues(alpha: 0.10),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.delete_outline, color: AppColors.danger),
            ),
            const SizedBox(width: 10),
            const Expanded(child: Text('حذف الدفعة')),
          ],
        ),
        content: Text(
          'هل أنت متأكد من حذف دفعة «${batch.displayLabel}»؟\n'
          'الكمية: ${formatNumber(batch.quantity)} حبة — صافي الربح: ${formatAmount(batch.netProfit)}.\n'
          'لا يمكن التراجع عن الحذف.',
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('إلغاء'),
          ),
          FilledButton.icon(
            style: FilledButton.styleFrom(backgroundColor: AppColors.danger),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            icon: const Icon(Icons.delete_outline, size: 18),
            label: const Text('حذف'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    final List<MiswakCalculation> updated = await MiswakStorage.removeAt(index);
    if (!mounted) return;
    setState(() => _batches = updated);
    _showMessage('تم حذف الدفعة بنجاح.');
  }

  /// مشاركة ملخص الدفعة عبر الواتساب.
  Future<void> _shareBatch(MiswakCalculation batch) async {
    final String message =
        '📦 تقرير حساب أرباح: ${batch.displayLabel}\n'
        '• الكمية: ${formatNumber(batch.quantity)} حبة\n'
        '• تكلفة المواد: ${formatAmount(batch.materialCost)}\n'
        '• التكلفة الكلية: ${formatAmount(batch.totalCost)}\n'
        '• تكلفة الحبة: ${formatAmount(batch.costPerUnit)}\n'
        '• سعر بيع الحبة: ${formatAmount(batch.salePrice)}\n'
        '• إجمالي الإيراد: ${formatAmount(batch.revenue)}\n'
        '• صافي الربح: ${formatAmount(batch.netProfit)} (${batch.isProfitable ? "رابحة" : "خاسرة"})\n'
        '• ربح الحبة: ${formatAmount(batch.profitPerUnit)}\n'
        '• هامش الربح: ${batch.marginPercent.toStringAsFixed(1)}%\n'
        '• نقطة التعادل: ${formatNumber(batch.breakEvenUnits)} حبة\n'
        '— تطبيق Orderly';

    final Uri? link = await WhatsAppLink.build(message: message);
    if (!mounted) return;
    if (link == null) {
      _showMessage('يرجى حفظ رقم هاتف المدير في الإعدادات أولاً للمشاركة.');
      return;
    }
    _showMessage('تم تجهيز رسالة الواتساب لرقم: ${link.pathSegments.last}');
    await WhatsAppLink.launch(message: message);
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final MiswakCalculation? current = _calculateCurrent();
    final MiswakTotals totals = MiswakTotals.of(_batches);

    return Scaffold(
      appBar: widget.showAppBar
          ? AppBar(
              title: const Text(MiswakScreen.title),
              leading: IconButton(
                key: const ValueKey<String>('miswak-back'),
                icon: const Icon(Icons.arrow_back),
                tooltip: 'رجوع',
                onPressed: () => Navigator.of(context).pop(),
              ),
              actions: <Widget>[
                IconButton(
                  key: const ValueKey<String>('miswak-clear-btn'),
                  icon: const Icon(Icons.cleaning_services_outlined),
                  tooltip: 'مسح الحقول',
                  onPressed: _clearFields,
                ),
                const SizedBox(width: 4),
              ],
            )
          : null,
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
              children: <Widget>[
                _buildHeaderCard(),
                const SizedBox(height: 14),
                _buildInputsCard(),
                const SizedBox(height: 14),
                if (current != null) ...<Widget>[
                  _buildLiveResultsCard(current),
                  const SizedBox(height: 14),
                ],
                _buildActionButtons(current),
                const SizedBox(height: 24),
                _buildTotalsSummary(totals),
                const SizedBox(height: 14),
                _buildSavedBatchesList(),
              ],
            ),
    );
  }

  Widget _buildHeaderCard() {
    final TextTheme text = Theme.of(context).textTheme;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.primary.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.20)),
      ),
      child: Row(
        children: <Widget>[
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: <Color>[AppColors.primary, AppColors.primaryDark],
              ),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(
              Icons.calculate_outlined,
              color: Colors.white,
              size: 24,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text('حاسبة المسواگ وصافي الأرباح', style: text.titleSmall),
                const SizedBox(height: 3),
                Text(
                  'أدخل التكاليف وسعر البيع لاحتساب صافي الربح الدقيق ونقطة التعادل فورياً.',
                  style: text.bodySmall?.copyWith(height: 1.5),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInputsCard() {
    final TextTheme text = Theme.of(context).textTheme;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                const Icon(Icons.edit_note_outlined, color: AppColors.primary),
                const SizedBox(width: 8),
                Text('بيانات وتكاليف الدفعة', style: text.titleSmall),
              ],
            ),
            const SizedBox(height: 14),
            TextField(
              key: const ValueKey<String>('miswak-label-field'),
              controller: _labelController,
              textInputAction: TextInputAction.next,
              decoration: const InputDecoration(
                labelText: 'اسم الدفعة / المنتج (اختياري)',
                hintText: 'مثال: وجبة مسواك رقم 1',
                prefixIcon: Icon(Icons.bookmark_border_outlined, size: 20),
              ),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 12),
            Row(
              children: <Widget>[
                Expanded(
                  child: TextField(
                    key: const ValueKey<String>('miswak-quantity-field'),
                    controller: _quantityController,
                    textInputAction: TextInputAction.next,
                    keyboardType: TextInputType.number,
                    inputFormatters: <TextInputFormatter>[
                      FilteringTextInputFormatter.digitsOnly,
                    ],
                    decoration: const InputDecoration(
                      labelText: 'عدد الحبات (الكمية)',
                      hintText: 'مثال: 500',
                      prefixIcon: Icon(Icons.format_list_numbered, size: 20),
                      suffixText: 'حبة',
                    ),
                    onChanged: (_) => setState(() {}),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: TextField(
                    key: const ValueKey<String>('miswak-material-cost-field'),
                    controller: _materialCostController,
                    textInputAction: TextInputAction.next,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    inputFormatters: <TextInputFormatter>[
                      FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
                    ],
                    decoration: const InputDecoration(
                      labelText: 'تكلفة المواد (الخام)',
                      hintText: 'مثال: 250000',
                      prefixIcon: Icon(Icons.shopping_bag_outlined, size: 20),
                      suffixText: kCurrency,
                    ),
                    onChanged: (_) => setState(() {}),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: <Widget>[
                Expanded(
                  child: TextField(
                    key: const ValueKey<String>('miswak-packaging-cost-field'),
                    controller: _packagingCostController,
                    textInputAction: TextInputAction.next,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    inputFormatters: <TextInputFormatter>[
                      FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
                    ],
                    decoration: const InputDecoration(
                      labelText: 'تكلفة التغليف (اختياري)',
                      hintText: 'مثال: 25000',
                      prefixIcon: Icon(Icons.inventory_2_outlined, size: 20),
                      suffixText: kCurrency,
                    ),
                    onChanged: (_) => setState(() {}),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: TextField(
                    key: const ValueKey<String>('miswak-other-costs-field'),
                    controller: _otherCostsController,
                    textInputAction: TextInputAction.next,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    inputFormatters: <TextInputFormatter>[
                      FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
                    ],
                    decoration: const InputDecoration(
                      labelText: 'مصاريف أخرى (اختياري)',
                      hintText: 'مثال: 10000',
                      prefixIcon: Icon(Icons.local_shipping_outlined, size: 20),
                      suffixText: kCurrency,
                    ),
                    onChanged: (_) => setState(() {}),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            TextField(
              key: const ValueKey<String>('miswak-sale-price-field'),
              controller: _salePriceController,
              textInputAction: TextInputAction.done,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: <TextInputFormatter>[
                FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
              ],
              decoration: const InputDecoration(
                labelText: 'سعر بيع الحبة الواحدة',
                hintText: 'مثال: 1000',
                prefixIcon: Icon(Icons.sell_outlined, size: 20),
                suffixText: kCurrency,
              ),
              onChanged: (_) => setState(() {}),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLiveResultsCard(MiswakCalculation c) {
    final TextTheme text = Theme.of(context).textTheme;
    final bool isProfitable = c.isProfitable;
    final bool isLoss = c.isLoss;
    final Color profitColor = isProfitable
        ? AppColors.success
        : (isLoss ? AppColors.danger : AppColors.textSecondary);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: isProfitable
              ? AppColors.success.withValues(alpha: 0.35)
              : (isLoss
                  ? AppColors.danger.withValues(alpha: 0.35)
                  : AppColors.border),
          width: 1.5,
        ),
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: profitColor.withValues(alpha: 0.08),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: <Widget>[
              Row(
                children: <Widget>[
                  Icon(
                    isProfitable ? Icons.trending_up : Icons.trending_down,
                    color: profitColor,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'النتائج والحساب الفوري',
                    style: text.titleSmall?.copyWith(color: profitColor),
                  ),
                ],
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: profitColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  isProfitable
                      ? 'دفعة رابحة'
                      : (isLoss ? 'دفعة خاسرة' : 'نقطة تعادل'),
                  style: text.bodySmall?.copyWith(
                    color: profitColor,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          // كارت صافي الربح الرئيسي
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: profitColor.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: profitColor.withValues(alpha: 0.25)),
            ),
            child: Row(
              children: <Widget>[
                Container(
                  width: 46,
                  height: 46,
                  decoration: BoxDecoration(
                    color: profitColor.withValues(alpha: 0.16),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    isProfitable ? Icons.monetization_on_outlined : Icons.money_off_outlined,
                    color: profitColor,
                    size: 24,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text('صافي الربح الإجمالي للدفعة', style: text.bodySmall),
                      const SizedBox(height: 4),
                      Text(
                        formatAmount(c.netProfit),
                        key: const ValueKey<String>('miswak-live-net-profit'),
                        style: text.titleLarge?.copyWith(
                          fontSize: 22,
                          color: profitColor,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          // تفاصيل المقاييس المالية
          Row(
            children: <Widget>[
              Expanded(
                child: StatTile(
                  label: 'التكلفة الكلية',
                  value: formatAmount(c.totalCost),
                  icon: Icons.receipt_outlined,
                  color: const Color(0xFF2563EB),
                  compact: true,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: StatTile(
                  label: 'إجمالي الإيراد',
                  value: formatAmount(c.revenue),
                  icon: Icons.point_of_sale_outlined,
                  color: AppColors.primary,
                  compact: true,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: <Widget>[
              Expanded(
                child: StatTile(
                  label: 'تكلفة الحبة',
                  value: formatAmount(c.costPerUnit),
                  icon: Icons.pie_chart_outline,
                  color: AppColors.textSecondary,
                  compact: true,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: StatTile(
                  label: 'ربح الحبة الواحدة',
                  value: formatAmount(c.profitPerUnit),
                  icon: Icons.price_check_outlined,
                  color: profitColor,
                  compact: true,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: <Widget>[
              Expanded(
                child: StatTile(
                  label: 'هامش الربح',
                  value: '${c.marginPercent.toStringAsFixed(1)}%',
                  icon: Icons.percent_outlined,
                  color: AppColors.accent,
                  compact: true,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: StatTile(
                  label: 'نقطة التعادل',
                  value: '${formatNumber(c.breakEvenUnits)} حبة',
                  icon: Icons.balance_outlined,
                  color: const Color(0xFF8B5CF6),
                  compact: true,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildActionButtons(MiswakCalculation? current) {
    return Row(
      children: <Widget>[
        Expanded(
          flex: 2,
          child: FilledButton.icon(
            key: const ValueKey<String>('miswak-save-batch-btn'),
            onPressed: (current == null || _isSaving) ? null : _saveBatch,
            icon: _isSaving
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Icon(Icons.save_outlined, size: 18),
            label: const Text('حفظ الدفعة في السجل'),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: OutlinedButton.icon(
            key: const ValueKey<String>('miswak-reset-fields-btn'),
            onPressed: _clearFields,
            icon: const Icon(Icons.refresh, size: 18),
            label: const Text('إعادة ضبط'),
          ),
        ),
      ],
    );
  }

  Widget _buildTotalsSummary(MiswakTotals totals) {
    final TextTheme text = Theme.of(context).textTheme;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              const Icon(Icons.inventory_2_outlined, color: AppColors.primary),
              const SizedBox(width: 8),
              Text('إجماليات كل الدفعات المحفوظة', style: text.titleSmall),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(30),
                ),
                child: Text(
                  '${formatNumber(totals.batches)} دفعات',
                  style: text.bodySmall?.copyWith(
                    color: AppColors.primary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: <Widget>[
              Expanded(
                child: StatTile(
                  label: 'مجموع الحبات',
                  value: '${formatNumber(totals.units)} حبة',
                  icon: Icons.format_list_numbered,
                  color: AppColors.primary,
                  compact: true,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: StatTile(
                  label: 'مجموع التكاليف',
                  value: formatAmount(totals.totalCost),
                  icon: Icons.receipt_long_outlined,
                  color: const Color(0xFF2563EB),
                  compact: true,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: <Widget>[
              Expanded(
                child: StatTile(
                  label: 'مجموع الإيرادات',
                  value: formatAmount(totals.totalRevenue),
                  icon: Icons.payments_outlined,
                  color: AppColors.accent,
                  compact: true,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: StatTile(
                  label: 'مجموع صافي الربح',
                  value: formatAmount(totals.totalProfit),
                  icon: Icons.monetization_on_outlined,
                  color: totals.isProfitable ? AppColors.success : AppColors.danger,
                  compact: true,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSavedBatchesList() {
    final TextTheme text = Theme.of(context).textTheme;

    if (_batches.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: AppColors.field,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.border),
        ),
        alignment: Alignment.center,
        child: Column(
          children: <Widget>[
            Icon(
              Icons.inventory_outlined,
              size: 44,
              color: AppColors.textSecondary.withValues(alpha: 0.6),
            ),
            const SizedBox(height: 10),
            Text('لا توجد دفعات محفوظة بعد', style: text.titleSmall),
            const SizedBox(height: 4),
            Text(
              'أدخل الأرقام في الحقول أعلاه واضغط «حفظ الدفعة في السجل» لحفظها هنا.',
              textAlign: TextAlign.center,
              style: text.bodySmall,
            ),
          ],
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          'سجل الدفعات المحفوظة (${formatNumber(_batches.length)}):',
          style: text.titleSmall,
        ),
        const SizedBox(height: 10),
        for (int i = 0; i < _batches.length; i++) ...<Widget>[
          if (i > 0) const SizedBox(height: 10),
          _buildBatchCard(i, _batches[i]),
        ],
      ],
    );
  }

  Widget _buildBatchCard(int index, MiswakCalculation batch) {
    final TextTheme text = Theme.of(context).textTheme;
    final bool isProfitable = batch.isProfitable;
    final Color profitColor = isProfitable ? AppColors.success : AppColors.danger;

    return Card(
      key: ValueKey<String>('miswak-batch-$index'),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.10),
                    shape: BoxShape.circle,
                  ),
                  alignment: Alignment.center,
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
                      Text(batch.displayLabel, style: text.titleSmall),
                      const SizedBox(height: 2),
                      Text(
                        formatDateTime(batch.createdAt),
                        style: text.bodySmall?.copyWith(fontSize: 11.5),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: 'تحميل في الحقول',
                  icon: const Icon(Icons.file_upload_outlined, size: 20),
                  onPressed: () => _loadIntoFields(batch),
                ),
                IconButton(
                  tooltip: 'مشاركة عبر الواتساب',
                  icon: const Icon(
                    Icons.share_outlined,
                    size: 20,
                    color: Color(0xFF25D366),
                  ),
                  onPressed: () => _shareBatch(batch),
                ),
                IconButton(
                  tooltip: 'حذف الدفعة',
                  icon: const Icon(
                    Icons.delete_outline,
                    size: 20,
                    color: AppColors.danger,
                  ),
                  onPressed: () => _confirmDelete(index),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: <Widget>[
                Expanded(
                  child: Text(
                    'الكمية: ${formatNumber(batch.quantity)} حبة • سعر البيع: ${formatAmount(batch.salePrice)}',
                    style: text.bodySmall,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: <Widget>[
                Text(
                  'التكلفة: ${formatAmount(batch.totalCost)}',
                  style: text.bodySmall?.copyWith(fontWeight: FontWeight.w600),
                ),
                Text(
                  'الصافي: ${formatAmount(batch.netProfit)}',
                  style: text.titleSmall?.copyWith(
                    color: profitColor,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
