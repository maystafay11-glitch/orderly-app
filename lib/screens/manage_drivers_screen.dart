import 'package:flutter/material.dart';

import 'package:orderly_app/models/driver.dart';
import 'package:orderly_app/services/driver_storage.dart';
import 'package:orderly_app/theme/app_theme.dart';
import 'package:orderly_app/utils/formatters.dart';

/// شاشة إدارة أسماء عمال الديليفري.
///
/// * إضافة عامل جديد من حقل نصي + زر «إضافة».
/// * حذف أي عامل بزر سلة المهملات مع رسالة تأكيد.
/// * كل تعديل يُحفظ فوراً في التخزين المحلي، وتُحدَّث الشاشة الرئيسية
///   تلقائياً عند الرجوع إليها.
class ManageDriversScreen extends StatefulWidget {
  const ManageDriversScreen({super.key});

  /// عنوان الشاشة (يُستخدم في الاختبارات).
  static const String title = 'إدارة أسماء العمال';

  @override
  State<ManageDriversScreen> createState() => _ManageDriversScreenState();
}

class _ManageDriversScreenState extends State<ManageDriversScreen> {
  final TextEditingController _nameController = TextEditingController();
  List<Driver> _drivers = <Driver>[];
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadDrivers();
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  /// استرجاع الأسماء المحفوظة محلياً.
  Future<void> _loadDrivers() async {
    final List<Driver> drivers = await DriverStorage.loadDrivers();
    if (!mounted) {
      return;
    }
    setState(() {
      _drivers = drivers;
      _isLoading = false;
    });
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  /// إضافة عامل جديد بالاسم المكتوب في الحقل (يُحفظ فوراً).
  Future<void> _addDriver() async {
    final String name = _nameController.text.trim();

    if (name.isEmpty) {
      setState(() => _error = 'أدخل اسم العامل');
      return;
    }
    if (_drivers.any((Driver driver) => driver.name == name)) {
      setState(() => _error = 'هذا الاسم مسجّل مسبقاً');
      return;
    }

    final String nextPin = Driver.findNextAvailablePin(_drivers);
    await DriverStorage.saveDriver(Driver(name: name, pin: nextPin));
    _nameController.clear();
    if (!mounted) {
      return;
    }
    setState(() => _error = null);
    await _loadDrivers();
    if (!mounted) {
      return;
    }
    _showMessage('تمت إضافة العامل $name برمز دخول ($nextPin)');
  }

  /// حذف عامل بعد رسالة تأكيد (مع كل بياناته المحفوظة).
  Future<void> _confirmDelete(Driver driver) async {
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
            const Expanded(child: Text('حذف العامل')),
          ],
        ),
        content: Text(
          'سيتم حذف «${driver.name}» مع بياناته المحفوظة '
          '(عدد الطلبات: ${formatNumber(driver.ordersCount)} — '
          'صافي المطعم: ${formatAmount(driver.netAmountToRestaurant)}).\n'
          'لا يمكن التراجع عن الحذف.',
          style: text.bodyMedium?.copyWith(height: 1.7),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('إلغاء'),
          ),
          FilledButton.icon(
            key: const ValueKey<String>('confirm-delete-driver-button'),
            style: FilledButton.styleFrom(backgroundColor: AppColors.danger),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            icon: const Icon(Icons.delete_outline, size: 18),
            label: const Text('حذف'),
          ),
        ],
      ),
    );

    if (confirmed != true) {
      return;
    }

    await DriverStorage.deleteDriver(driver.name);
    await _loadDrivers();
    if (!mounted) {
      return;
    }
    _showMessage('تم حذف العامل ${driver.name}');
  }

  Future<void> _editDriverPin(Driver driver) async {
    final TextEditingController pinCtrl =
        TextEditingController(text: driver.pin);
    String? dialogError;
    bool saved = false;
    String? savedPin;

    await showDialog<void>(
      context: context,
      builder: (BuildContext dContext) {
        return StatefulBuilder(
          builder: (BuildContext _, StateSetter setDState) {
            return AlertDialog(
              backgroundColor: AppColors.card,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(18),
                side: const BorderSide(color: AppColors.borderLight),
              ),
              title: Row(
                children: <Widget>[
                  Container(
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(
                      color: AppColors.accent.withValues(alpha: 0.15),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.pin_outlined, color: AppColors.accent, size: 20),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'رمز السائق: ${driver.name}',
                      style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
                    ),
                  ),
                ],
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Text(
                    'أدخل رمز PIN مخصصاً للسائق (4-6 أرقام).\n'
                    'يُشترط عدم تكراره مع أي سائق آخر أو رمز المدير.',
                    style: TextStyle(
                      fontSize: 12,
                      color: AppColors.textSecondary,
                      height: 1.5,
                    ),
                  ),
                  const SizedBox(height: 14),
                  TextField(
                    key: const ValueKey<String>('edit-driver-pin-field'),
                    controller: pinCtrl,
                    autofocus: true,
                    keyboardType: TextInputType.number,
                    maxLength: 6,
                    style: const TextStyle(
                      letterSpacing: 4,
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                    ),
                    textAlign: TextAlign.center,
                    decoration: InputDecoration(
                      labelText: 'رمز الدخول الجديد',
                      prefixIcon: const Icon(Icons.pin_outlined),
                      errorText: dialogError,
                      counterText: '',
                    ),
                  ),
                ],
              ),
              actions: <Widget>[
                TextButton(
                  onPressed: () => Navigator.of(dContext).pop(),
                  child: const Text('إلغاء'),
                ),
                FilledButton(
                  key: const ValueKey<String>('save-driver-pin-button'),
                  onPressed: () async {
                    final String val = pinCtrl.text.trim();
                    if (val.isEmpty || val.length < 4) {
                      setDState(
                        () => dialogError = 'يرجى إدخال 4 أرقام على الأقل',
                      );
                      return;
                    }
                    final String? err = await DriverStorage.updateDriverPin(
                      driverName: driver.name,
                      newPin: val,
                    );
                    if (err != null) {
                      setDState(() => dialogError = err);
                      return;
                    }
                    // حفظ النتيجة قبل إغلاق الحوار
                    saved = true;
                    savedPin = val;
                    if (dContext.mounted) {
                      Navigator.of(dContext).pop();
                    }
                  },
                  child: const Text('حفظ الرمز'),
                ),
              ],
            );
          },
        );
      },
    );
    pinCtrl.dispose();

    // تنفيذ التحديث بعد إغلاق الحوار مع التحقق من mounted
    if (saved && mounted) {
      await _loadDrivers();
      if (mounted) {
        _showMessage(
          'تم تحديث رمز السائق ${driver.name} بنجاح إلى ($savedPin)',
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
            appBar: AppBar(
        title: const Text(ManageDriversScreen.title),
        // زر رجوع واضح يُغلق الشاشة ويُعيد بناء الواجهة الرئيسية.
        automaticallyImplyLeading: true,
        leading: IconButton(
          key: const ValueKey<String>('manage-back'),
          icon: const Icon(Icons.arrow_back),
          tooltip: 'رجوع',
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: <Widget>[
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
                  child: _AddDriverCard(
                    controller: _nameController,
                    count: _drivers.length,
                    errorText: _error,
                    onChanged: () {
                      if (_error != null) {
                        setState(() => _error = null);
                      }
                    },
                    onAdd: _addDriver,
                  ),
                ),
                Expanded(
                  child: _drivers.isEmpty
                      ? const _NoDriversView()
                      : ListView.separated(
                          padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                          itemCount: _drivers.length,
                          separatorBuilder: (BuildContext _, int _) =>
                              const SizedBox(height: 10),
                          itemBuilder: (BuildContext context, int index) {
                            final Driver driver = _drivers[index];
                            return _ManageDriverRow(
                              driver: driver,
                              onDelete: () => _confirmDelete(driver),
                              onEditPin: () => _editDriverPin(driver),
                            );
                          },
                        ),
                ),
              ],
            ),
    );
  }
}

/// بطاقة الإضافة: حقل نصي لاسم العامل + زر «إضافة».
class _AddDriverCard extends StatelessWidget {
  const _AddDriverCard({
    required this.controller,
    required this.count,
    required this.onAdd,
    this.errorText,
    this.onChanged,
  });

  final TextEditingController controller;

  /// عدد العمال المسجّلين حالياً (يُعرض في ترويسة البطاقة).
  final int count;
  final VoidCallback onAdd;
  final String? errorText;
  final VoidCallback? onChanged;

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;

    return Container(
      padding: const EdgeInsets.all(14),
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
              const Icon(
                Icons.person_add_alt_1_outlined,
                size: 18,
                color: AppColors.primary,
              ),
              const SizedBox(width: 6),
              Text('إضافة عامل جديد', style: text.titleSmall),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 5,
                ),
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(30),
                ),
                child: Text(
                  '${formatNumber(count)} عمال',
                  key: const ValueKey<String>('manage-drivers-count'),
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
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Expanded(
                child: TextField(
                  key: const ValueKey<String>('manage-driver-name-field'),
                  controller: controller,
                  textInputAction: TextInputAction.done,
                  textCapitalization: TextCapitalization.words,
                  onChanged: (String _) => onChanged?.call(),
                  onSubmitted: (String _) => onAdd(),
                  decoration: InputDecoration(
                    labelText: 'اسم العامل',
                    hintText: 'مثال: أحمد',
                    prefixIcon: const Icon(Icons.badge_outlined, size: 20),
                    errorText: errorText,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              SizedBox(
                height: 54,
                child: FilledButton.icon(
                  key: const ValueKey<String>('manage-add-driver-button'),
                  onPressed: onAdd,
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('إضافة'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'يُحفظ الاسم مباشرة ويُسند له رمز دخول تلقائي (1001-1030) لتطبيق السائق.',
            style: text.bodySmall?.copyWith(height: 1.6),
          ),
        ],
      ),
    );
  }
}

/// صف عامل في شاشة الإدارة: الاسم + الأرقام + زر حذف (سلة مهملات).
class _ManageDriverRow extends StatelessWidget {
  const _ManageDriverRow({
    required this.driver,
    required this.onDelete,
    this.onEditPin,
  });

  final Driver driver;
  final VoidCallback onDelete;
  final VoidCallback? onEditPin;

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    final String name = driver.name.isEmpty ? 'بدون اسم' : driver.name;

    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: <Widget>[
          Container(
            width: 44,
            height: 44,
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topRight,
                end: Alignment.bottomLeft,
                colors: <Color>[AppColors.primary, AppColors.primaryDark],
              ),
              shape: BoxShape.circle,
            ),
            alignment: Alignment.center,
            child: Text(
              name.substring(0, 1),
              style: text.titleMedium?.copyWith(color: Colors.white),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    Flexible(
                      child: Text(
                        name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: text.titleSmall,
                      ),
                    ),
                    const SizedBox(width: 8),
                    InkWell(
                      onTap: onEditPin,
                      borderRadius: BorderRadius.circular(6),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 7,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: AppColors.primary.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: <Widget>[
                            Text(
                              'PIN: ${driver.pin}',
                              key: ValueKey<String>('driver-pin-$name'),
                              style: const TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                                color: AppColors.primary,
                              ),
                            ),
                            if (onEditPin != null) ...<Widget>[
                              const SizedBox(width: 3),
                              const Icon(
                                Icons.edit_outlined,
                                size: 12,
                                color: AppColors.primary,
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  'الطلبات: ${formatNumber(driver.ordersCount)}  •  '
                  'الأجرة: ${formatAmount(driver.wage)}  •  '
                  'الصافي: ${formatAmount(driver.netAmountToRestaurant)}',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: text.bodySmall?.copyWith(height: 1.6),
                ),
              ],
            ),
          ),
          if (onEditPin != null)
            IconButton(
              key: ValueKey<String>('edit-driver-pin-$name'),
              onPressed: onEditPin,
              tooltip: 'تعديل رمز السائق',
              icon: const Icon(Icons.edit_outlined, color: AppColors.primary, size: 20),
            ),
          IconButton(
            key: ValueKey<String>('delete-driver-$name'),
            onPressed: onDelete,
            tooltip: 'حذف العامل',
            icon: const Icon(Icons.delete_outline, color: AppColors.danger),
          ),
        ],
      ),
    );
  }
}

/// يُعرض عندما لا يوجد أي عامل مسجّل.
class _NoDriversView extends StatelessWidget {
  const _NoDriversView();

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(
              Icons.person_off_outlined,
              size: 54,
              color: AppColors.textSecondary.withValues(alpha: 0.7),
            ),
            const SizedBox(height: 14),
            Text('لا يوجد عمال مسجّلون', style: text.titleSmall),
            const SizedBox(height: 6),
            Text(
              'اكتب اسم العامل في الحقل أعلاه ثم اضغط «إضافة».',
              textAlign: TextAlign.center,
              style: text.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}
