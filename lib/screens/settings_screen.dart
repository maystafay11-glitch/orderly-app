/// شاشة إعدادات رقم هاتف مدير/المطعم للواتساب وإدارة رموز الدخول.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:orderly_app/models/driver.dart';
import 'package:orderly_app/screens/unified_login_screen.dart';
import 'package:orderly_app/services/app_settings.dart';
import 'package:orderly_app/services/auth_session_service.dart';
import 'package:orderly_app/services/driver_storage.dart';
import 'package:orderly_app/theme/app_theme.dart';

/// أرقام دولية نموذجية تساعد في توجيه المستخدم لتنسيق الرقم الصحيح.
const List<String> kExamplePhones = <String>[
  '9647701234567',
  '971501234567',
  '201001234567',
  '966501234567',
];

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  /// عنوان الشاشة (للاختبارات).
  static const String title = 'إعدادات المدير';

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final TextEditingController _controller = TextEditingController();
  String _savedPhone = '';
  String _adminPin = AppSettings.defaultAdminPin;
  List<Driver> _drivers = <Driver>[];
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  /// قراءة الإعدادات المحفوظة عند الفتح.
  Future<void> _loadSettings() async {
    final String phone = await AppSettings.getWhatsAppPhone();
    final String adminPin = await AppSettings.getAdminPin();
    final List<Driver> drivers = await DriverStorage.loadDrivers();
    if (!mounted) {
      return;
    }
    setState(() {
      _savedPhone = phone;
      _controller.text = phone;
      _adminPin = adminPin;
      _drivers = drivers;
      _isLoading = false;
    });
  }

  /// حفظ رقم المدير بعد التحقق من صلاحيته.
  Future<void> _save() async {
    final String phone = _controller.text.trim();
    if (phone.isEmpty) {
      setState(() => _error = 'أدخل رقم هاتف المدير.');
      return;
    }
    final String digits = phone.replaceAll(RegExp(r'[^0-9]'), '');
    if (digits.length < 7 || digits.length > 15) {
      setState(
        () => _error = 'الرقم غير كامل. استخدم الصيغة الدولية (بدون +).',
      );
      return;
    }
    setState(() => _error = null);
    await AppSettings.setWhatsAppPhone(phone);
    if (!mounted) {
      return;
    }
    setState(() => _savedPhone = phone);
    _showMessage('تم حفظ رقم المدير: $phone');
  }

  /// تغيير رمز المدير السري مع التحقق الأمني.
  Future<void> _changeAdminPin() async {
    final TextEditingController pinCtrl = TextEditingController();
    String? dialogError;

    final String? newPin = await showDialog<String>(
      context: context,
      builder: (BuildContext ctx) => StatefulBuilder(
        builder: (BuildContext context, StateSetter setDialogState) => AlertDialog(
          title: const Row(
            children: <Widget>[
              Icon(Icons.shield_outlined, color: AppColors.primary),
              SizedBox(width: 8),
              Text('تغيير رمز المدير السري'),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              const Text(
                'أدخل الرمز السري الجديد لمدير المطعم (مكون من 4 أرقام على الأقل):',
                style: TextStyle(fontSize: 13),
              ),
              const SizedBox(height: 12),
              TextField(
                key: const ValueKey<String>('change-admin-pin-field'),
                controller: pinCtrl,
                autofocus: true,
                keyboardType: TextInputType.number,
                inputFormatters: <TextInputFormatter>[FilteringTextInputFormatter.digitsOnly],
                decoration: InputDecoration(
                  labelText: 'رمز المدير الجديد',
                  hintText: 'مثال: 7777',
                  prefixIcon: const Icon(Icons.lock_outline),
                  errorText: dialogError,
                ),
              ),
            ],
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('إلغاء'),
            ),
            FilledButton(
              key: const ValueKey<String>('confirm-change-admin-pin-button'),
              onPressed: () {
                final String val = pinCtrl.text.trim();
                if (val.isEmpty) {
                  setDialogState(() => dialogError = 'يرجى إدخال الرمز');
                  return;
                }
                if (val.length < 4) {
                  setDialogState(() => dialogError = 'الرمز يجب أن يتكون من 4 أرقام على الأقل');
                  return;
                }
                if (_drivers.any((Driver d) => d.pin == val)) {
                  setDialogState(() => dialogError = 'هذا الرمز مستخدم بالفعل لسائق، اختر رمزاً آخر');
                  return;
                }
                Navigator.pop(ctx, val);
              },
              child: const Text('حفظ الرمز'),
            ),
          ],
        ),
      ),
    );

    if (newPin != null && newPin.isNotEmpty) {
      await AppSettings.setAdminPin(newPin);
      if (!mounted) return;
      setState(() => _adminPin = newPin);
      _showMessage('تم تغيير وحفظ رمز المدير الجديد: $newPin');
    }
  }

  /// تعديل وتخصيص رمز أي سائق بنقرة واحدة.
  Future<void> _editDriverPin(Driver driver) async {
    final TextEditingController pinCtrl = TextEditingController(text: driver.pin);
    String? dialogError;

    final String? newPin = await showDialog<String>(
      context: context,
      builder: (BuildContext ctx) => StatefulBuilder(
        builder: (BuildContext context, StateSetter setDialogState) => AlertDialog(
          title: Row(
            children: <Widget>[
              const Icon(Icons.badge_outlined, color: AppColors.accent),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'تعديل رمز: ${driver.name}',
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                'الرمز الحالي للسائق: (${driver.pin})\n'
                'أدخل الرمز الجديد (نطاق السائقين: 1001 إلى 1030):',
                style: const TextStyle(fontSize: 13, height: 1.4),
              ),
              const SizedBox(height: 12),
              TextField(
                key: ValueKey<String>('edit-driver-pin-${driver.name}'),
                controller: pinCtrl,
                autofocus: true,
                keyboardType: TextInputType.number,
                inputFormatters: <TextInputFormatter>[FilteringTextInputFormatter.digitsOnly],
                decoration: InputDecoration(
                  labelText: 'رمز السائق الجديد',
                  hintText: '1001 - 1030',
                  prefixIcon: const Icon(Icons.tag_rounded),
                  errorText: dialogError,
                ),
              ),
            ],
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('إلغاء'),
            ),
            FilledButton(
              key: const ValueKey<String>('confirm-change-driver-pin-button'),
              onPressed: () {
                final String val = pinCtrl.text.trim();
                if (val.isEmpty) {
                  setDialogState(() => dialogError = 'يرجى إدخال الرمز');
                  return;
                }
                if (val.length < 4) {
                  setDialogState(() => dialogError = 'الرمز يجب أن يتكون من 4 أرقام على الأقل');
                  return;
                }
                if (val == _adminPin) {
                  setDialogState(() => dialogError = 'هذا الرمز محجوز لمدير المطعم');
                  return;
                }
                if (_drivers.any((Driver d) => d.name != driver.name && d.pin == val)) {
                  setDialogState(() => dialogError = 'هذا الرمز مستخدم بالفعل لسائق آخر');
                  return;
                }
                Navigator.pop(ctx, val);
              },
              child: const Text('حفظ'),
            ),
          ],
        ),
      ),
    );

    if (newPin != null && newPin.isNotEmpty && newPin != driver.pin) {
      final String? error = await DriverStorage.updateDriverPin(
        driverName: driver.name,
        newPin: newPin,
      );
      if (error != null) {
        _showMessage('فشل: $error');
      } else {
        final List<Driver> updated = await DriverStorage.loadDrivers();
        if (!mounted) return;
        setState(() => _drivers = updated);
        _showMessage('تم تحديث رمز السائق ${driver.name} إلى ($newPin)');
      }
    }
  }

  /// تسجيل الخروج من لوحة المدير والعودة لشاشة الدخول.
  Future<void> _logout() async {
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext ctx) => AlertDialog(
        title: const Row(
          children: <Widget>[
            Icon(Icons.logout_rounded, color: AppColors.danger),
            SizedBox(width: 8),
            Text('تأكيد تسجيل الخروج'),
          ],
        ),
        content: const Text('هل ترغب بتسجيل الخروج من لوحة المدير والعودة لبوابة الدخول بالرمز؟'),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('إلغاء'),
          ),
          FilledButton.icon(
            key: const ValueKey<String>('confirm-logout-dialog-button'),
            style: FilledButton.styleFrom(backgroundColor: AppColors.danger),
            onPressed: () => Navigator.pop(ctx, true),
            icon: const Icon(Icons.logout),
            label: const Text('نعم، تسجيل الخروج'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await AuthSessionService.logout();
      if (!mounted) return;
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute<void>(builder: (BuildContext _) => const UnifiedLoginScreen()),
        (Route<dynamic> route) => false,
      );
    }
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text(SettingsScreen.title),
        leading: IconButton(
          key: const ValueKey<String>('settings-back'),
          icon: const Icon(Icons.arrow_back),
          tooltip: 'رجوع',
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 20, 16, 24),
              children: <Widget>[
                // 1. بطاقة رقم هاتف المدير (واتساب)
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Row(
                          children: <Widget>[
                            const Icon(
                              Icons.phone_outlined,
                              color: AppColors.primary,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              'رقم هاتف المدير (واتساب)',
                              style: text.titleSmall,
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        Text(
                          'أرسل التقارير والملخصات مباشرة إلى رقم المدير.'
                          ' استخدم الصيغة الدولية بدون علامة +.',
                          style: text.bodySmall,
                        ),
                        const SizedBox(height: 14),
                        if (_savedPhone.isNotEmpty)
                          Text(
                            'محفّظ حالياً: $_savedPhone',
                            key: const ValueKey<String>('admin-phone-saved'),
                            style: text.bodyMedium?.copyWith(
                              fontWeight: FontWeight.w700,
                              color: AppColors.accent,
                            ),
                          ),
                        if (_savedPhone.isNotEmpty)
                          const SizedBox(height: 14),
                        TextField(
                          key: const ValueKey<String>('admin-phone-field'),
                          controller: _controller,
                          autofocus: false,
                          keyboardType:
                              const TextInputType.numberWithOptions(
                            signed: false,
                            decimal: false,
                          ),
                          inputFormatters: <TextInputFormatter>[
                            FilteringTextInputFormatter.digitsOnly,
                          ],
                          decoration: InputDecoration(
                            labelText: 'رقم الهاتف',
                            hintText: 'مثال: 9647701234567',
                            prefixIcon: const Icon(Icons.phone_outlined),
                            errorText: _error,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Wrap(
                          spacing: 6,
                          children: kExamplePhones
                              .map((String p) => ActionChip(
                            key: ValueKey<String>('example-$p'),
                            label: Text(p),
                            onPressed: () => setState(() {
                              _controller.text = p;
                              _error = null;
                            }),
                            labelStyle: text.bodySmall?.copyWith(
                              color: AppColors.primary,
                            ),
                          ))
                              .toList(),
                        ),
                        const SizedBox(height: 18),
                        SizedBox(
                          width: double.infinity,
                          child: FilledButton.icon(
                            key: const ValueKey<String>('save-admin-phone'),
                            onPressed: _save,
                            icon: const Icon(Icons.save_outlined, size: 18),
                            label: const Text('حفظ رقم المدير'),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 18),

                // 2. بطاقة إدارة رموز الدخول (PIN Management)
                Card(
                  elevation: 2,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Row(
                          children: <Widget>[
                            Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: AppColors.primary.withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: const Icon(Icons.lock_person_outlined, color: AppColors.primary),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: <Widget>[
                                  Text(
                                    'إدارة رموز الدخول (PIN Management)',
                                    style: text.titleSmall?.copyWith(fontWeight: FontWeight.bold),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    'تعديل رمز المدير ورموز السائقين لعزل الصلاحيات',
                                    style: text.bodySmall?.copyWith(color: AppColors.textSecondary),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        const Divider(height: 24),

                        // رمز المدير
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: AppColors.surface,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: AppColors.border),
                          ),
                          child: Row(
                            children: <Widget>[
                              const Icon(Icons.shield_outlined, color: AppColors.primary, size: 22),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: <Widget>[
                                    const Text('رمز المدير الحالي:', style: TextStyle(fontSize: 12, color: AppColors.textSecondary)),
                                    const SizedBox(height: 2),
                                    Text(
                                      _adminPin,
                                      key: const ValueKey<String>('admin-pin-display'),
                                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppColors.primary),
                                    ),
                                  ],
                                ),
                              ),
                              OutlinedButton.icon(
                                key: const ValueKey<String>('change-admin-pin-button'),
                                onPressed: _changeAdminPin,
                                icon: const Icon(Icons.edit_outlined, size: 16),
                                label: const Text('تغيير الرمز'),
                              ),
                            ],
                          ),
                        ),

                        const SizedBox(height: 16),
                        const Text(
                          'تخصيص رموز عمال التوصيل (1001 - 1030):',
                          style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 8),

                        if (_drivers.isEmpty)
                          const Padding(
                            padding: EdgeInsets.symmetric(vertical: 8),
                            child: Text(
                              'لا يوجد عمال مسجلون حالياً. يمكنك إضافتهم من شاشة إدارة العمال.',
                              style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
                            ),
                          )
                        else
                          ListView.separated(
                            shrinkWrap: true,
                            physics: const NeverScrollableScrollPhysics(),
                            itemCount: _drivers.length,
                            separatorBuilder: (BuildContext _, int _) => const Divider(height: 8),
                            itemBuilder: (BuildContext context, int index) {
                              final Driver driver = _drivers[index];
                              return ListTile(
                                dense: true,
                                contentPadding: EdgeInsets.zero,
                                leading: Container(
                                  width: 34,
                                  height: 34,
                                  decoration: BoxDecoration(
                                    color: AppColors.accent.withValues(alpha: 0.1),
                                    shape: BoxShape.circle,
                                  ),
                                  child: const Icon(Icons.two_wheeler, color: AppColors.accent, size: 18),
                                ),
                                title: Text(
                                  driver.name,
                                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                                ),
                                subtitle: Text(
                                  'رمز الدخول: #${driver.pin}',
                                  style: const TextStyle(fontSize: 11, color: AppColors.primaryDark),
                                ),
                                trailing: TextButton.icon(
                                  key: ValueKey<String>('edit-pin-btn-${driver.name}'),
                                  onPressed: () => _editDriverPin(driver),
                                  icon: const Icon(Icons.pin_outlined, size: 15),
                                  label: const Text('تعديل الرمز', style: TextStyle(fontSize: 12)),
                                ),
                              );
                            },
                          ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 22),

                // 3. زر تسجيل خروج المدير من الإعدادات
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    key: const ValueKey<String>('settings-logout-button'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.danger,
                      side: const BorderSide(color: AppColors.danger),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    onPressed: _logout,
                    icon: const Icon(Icons.logout_rounded, color: AppColors.danger),
                    label: const Text(
                      'تسجيل الخروج من لوحة المدير',
                      style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
                    ),
                  ),
                ),
                const SizedBox(height: 20),

                Text('روابط وميزات الأمان', style: text.titleSmall),
                const SizedBox(height: 8),
                Text(
                  '• يتم حفظ الجلسة محلياً ليبقى التطبيق مفتوحاً طوال اليوم.\n'
                  '• عند الضغط على تسجيل الخروج، يُعاد طلب الرمز السري فوراً.\n'
                  '• رمز المدير يفتح لوحة التحكم الكاملة، بينما تقتصر رموز السائقين على متابعة توصيل طلباتهم فقط.',
                  style: text.bodySmall?.copyWith(height: 1.6),
                ),
              ],
            ),
    );
  }
}

