import 'package:flutter/material.dart';
import 'package:orderly_app/models/driver.dart';
import 'package:orderly_app/screens/driver_dashboard_screen.dart';
import 'package:orderly_app/services/driver_session_service.dart';
import 'package:orderly_app/services/driver_storage.dart';
import 'package:orderly_app/theme/app_theme.dart';

/// شاشة تسجيل دخول السائق المبسطة عبر الرمز الخاص (Driver PIN Code: 1001 - 1030).
///
/// مصممة للعمل بسرعة فائقة بلمسة واحدة:
/// * لوحة أرقام واضحة وكبيرة.
/// * بمجرد كتابة الرمز المكون من 4 أرقام يتحقق النظام فوراً.
/// * ينقل السائق مباشرة إلى واجهة عمله دون تعقيد.
class DriverLoginScreen extends StatefulWidget {
  const DriverLoginScreen({super.key});

  static const String title = 'دخول السائق';

  @override
  State<DriverLoginScreen> createState() => _DriverLoginScreenState();
}

class _DriverLoginScreenState extends State<DriverLoginScreen> {
  String _pin = '';
  bool _isLoading = false;
  String? _errorMessage;
  List<Driver> _availableDrivers = <Driver>[];

  @override
  void initState() {
    super.initState();
    _loadAvailableDrivers();
    _checkExistingSession();
  }

  /// التحقق إن كان السائق مسجلاً دخوله مسبقاً للانتقال فوراً.
  Future<void> _checkExistingSession() async {
    final Driver? logged = await DriverSessionService.getLoggedInDriver();
    if (logged != null && mounted) {
      _navigateToDashboard(logged);
    }
  }

  Future<void> _loadAvailableDrivers() async {
    final List<Driver> list = await DriverStorage.loadDrivers();
    if (mounted) {
      setState(() => _availableDrivers = list);
    }
  }

  void _onDigitPressed(String digit) {
    if (_pin.length >= 4) return;
    setState(() {
      _pin += digit;
      _errorMessage = null;
    });

    if (_pin.length == 4) {
      _verifyPin(_pin);
    }
  }

  void _onBackspace() {
    if (_pin.isEmpty) return;
    setState(() {
      _pin = _pin.substring(0, _pin.length - 1);
      _errorMessage = null;
    });
  }

  void _onClear() {
    setState(() {
      _pin = '';
      _errorMessage = null;
    });
  }

  Future<void> _verifyPin(String enteredPin) async {
    setState(() => _isLoading = true);
    await Future<void>.delayed(const Duration(milliseconds: 250));

    final Driver? driver = await DriverSessionService.loginWithPin(enteredPin);
    if (!mounted) return;

    if (driver != null) {
      _navigateToDashboard(driver);
    } else {
      setState(() {
        _isLoading = false;
        _errorMessage = 'الرمز ($enteredPin) غير مسجل. نطاق الرموز: 1001 إلى 1030';
        _pin = '';
      });
    }
  }

  void _navigateToDashboard(Driver driver) {
    Navigator.of(context).pushReplacement(
      MaterialPageRoute<void>(
        builder: (BuildContext _) => DriverDashboardScreen(driver: driver),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('بوابة السائق السريعة'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          tooltip: 'العودة للمطعم',
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: SafeArea(
        child: LayoutBuilder(
          builder: (BuildContext context, BoxConstraints constraints) {
            return SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
              child: ConstrainedBox(
                constraints: BoxConstraints(minHeight: constraints.maxHeight - 32),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: <Widget>[
                    Column(
                      children: <Widget>[
                        const SizedBox(height: 12),
                        // أيقونة البوابة
                        Container(
                          width: 72,
                          height: 72,
                          decoration: BoxDecoration(
                            gradient: const LinearGradient(
                              colors: <Color>[AppColors.primary, AppColors.primaryDark],
                              begin: Alignment.topRight,
                              end: Alignment.bottomLeft,
                            ),
                            shape: BoxShape.circle,
                            boxShadow: <BoxShadow>[
                              BoxShadow(
                                color: AppColors.primary.withValues(alpha: 0.3),
                                blurRadius: 16,
                                offset: const Offset(0, 6),
                              ),
                            ],
                          ),
                          child: const Icon(
                            Icons.two_wheeler_rounded,
                            size: 38,
                            color: Colors.white,
                          ),
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'تسجيل دخول السائق',
                          style: text.titleLarge?.copyWith(fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'اكتب رمز الدخول الخاص بك (1001 إلى 1030)',
                          style: text.bodyMedium?.copyWith(color: AppColors.textSecondary),
                        ),
                        const SizedBox(height: 24),

                        // مؤشر الـ 4 خانات للرمز
                        _buildPinDisplay(),

                        if (_errorMessage != null) ...<Widget>[
                          const SizedBox(height: 14),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                            decoration: BoxDecoration(
                              color: AppColors.danger.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(
                                color: AppColors.danger.withValues(alpha: 0.3),
                              ),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: <Widget>[
                                const Icon(Icons.error_outline, size: 16, color: AppColors.danger),
                                const SizedBox(width: 8),
                                Flexible(
                                  child: Text(
                                    _errorMessage!,
                                    style: text.bodySmall?.copyWith(
                                      color: AppColors.danger,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ],
                    ),

                    // لوحة الأرقام السريعة (Keypad)
                    Padding(
                      padding: const EdgeInsets.only(top: 16, bottom: 8),
                      child: _buildKeypad(),
                    ),

                    // اختصارات سريعة للاختبار (السائقين المسجلين)
                    if (_availableDrivers.isNotEmpty) ...<Widget>[
                      const SizedBox(height: 8),
                      _buildQuickDriverChips(),
                    ],
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  /// خانات عرض الرمز المكون من 4 أرقام
  Widget _buildPinDisplay() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List<Widget>.generate(4, (int index) {
        final bool isFilled = index < _pin.length;
        final String char = isFilled ? _pin[index] : '';

        return Container(
          width: 54,
          height: 58,
          margin: const EdgeInsets.symmetric(horizontal: 6),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: isFilled ? AppColors.primary : AppColors.border,
              width: isFilled ? 2 : 1.2,
            ),
            boxShadow: <BoxShadow>[
              if (isFilled)
                BoxShadow(
                  color: AppColors.primary.withValues(alpha: 0.15),
                  blurRadius: 8,
                  offset: const Offset(0, 3),
                ),
            ],
          ),
          child: _isLoading && index == 3
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Text(
                  char,
                  style: const TextStyle(
                    fontSize: 26,
                    fontWeight: FontWeight.bold,
                    color: AppColors.primary,
                  ),
                ),
        );
      }),
    );
  }

  /// لوحة الأرقام الهاتفية السريعة
  Widget _buildKeypad() {
    final List<List<String>> rows = <List<String>>[
      <String>['1', '2', '3'],
      <String>['4', '5', '6'],
      <String>['7', '8', '9'],
      <String>['C', '0', '⌫'],
    ];

    return Column(
      children: rows.map((List<String> row) {
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: row.map((String key) {
              final bool isSpecial = key == 'C' || key == '⌫';
              return Container(
                width: 76,
                height: 56,
                margin: const EdgeInsets.symmetric(horizontal: 10),
                child: Material(
                  color: isSpecial
                      ? Colors.grey.shade100
                      : AppColors.surface,
                  borderRadius: BorderRadius.circular(16),
                  elevation: isSpecial ? 0 : 1.5,
                  child: InkWell(
                    borderRadius: BorderRadius.circular(16),
                    onTap: _isLoading
                        ? null
                        : () {
                            if (key == '⌫') {
                              _onBackspace();
                            } else if (key == 'C') {
                              _onClear();
                            } else {
                              _onDigitPressed(key);
                            }
                          },
                    child: Center(
                      child: key == '⌫'
                          ? const Icon(Icons.backspace_outlined, size: 22, color: AppColors.danger)
                          : Text(
                              key,
                              style: TextStyle(
                                fontSize: isSpecial ? 17 : 24,
                                fontWeight: FontWeight.w700,
                                color: isSpecial ? AppColors.textSecondary : AppColors.textPrimary,
                              ),
                            ),
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
        );
      }).toList(),
    );
  }

  /// رقائق سريعة لأسماء ورموز السائقين المسجلين للتجربة بنقرة واحدة
  Widget _buildQuickDriverChips() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: <Widget>[
        const Text(
          'سائقون مسجلون للاختبار السريع:',
          style: TextStyle(fontSize: 11, color: AppColors.textSecondary),
        ),
        const SizedBox(height: 6),
        Wrap(
          spacing: 8,
          runSpacing: 6,
          alignment: WrapAlignment.center,
          children: _availableDrivers.take(6).map((Driver d) {
            return ActionChip(
              avatar: const Icon(Icons.badge_outlined, size: 14, color: AppColors.primary),
              label: Text('${d.name} (${d.pin})'),
              labelStyle: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
              backgroundColor: AppColors.surface,
              onPressed: () => _verifyPin(d.pin),
            );
          }).toList(),
        ),
      ],
    );
  }
}
