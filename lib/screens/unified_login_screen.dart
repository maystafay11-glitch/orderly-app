import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:orderly_app/models/driver.dart';
import 'package:orderly_app/models/staff_member.dart';
import 'package:orderly_app/screens/driver_dashboard_screen.dart';
import 'package:orderly_app/screens/home_screen.dart';
import 'package:orderly_app/services/auth_session_service.dart';
import 'package:orderly_app/services/driver_storage.dart';
import 'package:orderly_app/services/restaurant_service.dart';
import 'package:orderly_app/services/staff_directory_service.dart';
import 'package:orderly_app/services/staff_session_service.dart';
import 'package:orderly_app/theme/app_theme.dart';

/// واجهة تسجيل الدخول الموحدة — Dark Mode احترافي
///
/// **المرحلة 1:** اختيار الدور (مدير / سائق) بأزرار Glassmorphism
/// **المرحلة 2:** لوحة أرقام أنيقة مع خانات PIN مضاءة
class UnifiedLoginScreen extends StatefulWidget {
  const UnifiedLoginScreen({super.key});

  static const String title = 'تسجيل الدخول';

  @override
  State<UnifiedLoginScreen> createState() => _UnifiedLoginScreenState();
}

enum _LoginMode { none, admin, driver }

class _UnifiedLoginScreenState extends State<UnifiedLoginScreen>
    with TickerProviderStateMixin {
  final TextEditingController _pinController = TextEditingController();

  /// حقل معرّف المطعم الإجباري (Restaurant ID) — يُملأ تلقائياً بمعرّف
  /// هذا الجهاز إن وُجد، مع إمكانية تعديله للدخول لمطعم آخر.
  final TextEditingController _restaurantIdController =
      TextEditingController();

  /// حقل اسم المستخدم (فارغ = المسار السريع القديم برمز PIN للجهاز).
  final TextEditingController _usernameController = TextEditingController();

  String _pin = '';
  bool _isLoading = false;
  String? _errorMessage;
  _LoginMode _mode = _LoginMode.none;

  /// هل المستخدم في وضع تسجيل دخول الحساب (معرّف مطعم + اسم مستخدم)؟
  bool get _isStaffMode => _usernameController.text.trim().isNotEmpty;

  /// أقصى طول للرمز السري: كلمة مرور حساب حتى 8 خانات،
  /// بينما رمز الجهاز السريع يبقى قصيراً كما هو.
  int get _maxSecretLength => _isStaffMode ? 8 : 6;

  // انيميشن الانتقال بين المرحلتين (محجوز للمستقبل)
  late final AnimationController _transitionCtrl;

  // انيميشن نبضة خطأ PIN
  late final AnimationController _shakeCtrl;
  late final Animation<double> _shakeAnim;

  // انيميشن خلفية الجسيمات
  late final AnimationController _bgCtrl;

  @override
  void initState() {
    super.initState();

    // تعبئة معرّف المطعم تلقائياً من معرّف هذا الجهاز (Multi-tenant).
    _restaurantIdController.text = RestaurantService.restaurantId;

    _transitionCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );

    _shakeCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    );
    _shakeAnim = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(parent: _shakeCtrl, curve: Curves.elasticIn),
    );

    _bgCtrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 12),
    )..repeat();
  }

  @override
  void dispose() {
    _pinController.dispose();
    _restaurantIdController.dispose();
    _usernameController.dispose();
    _transitionCtrl.dispose();
    _shakeCtrl.dispose();
    _bgCtrl.dispose();
    super.dispose();
  }

  void _selectMode(_LoginMode mode) {
    HapticFeedback.lightImpact();
    setState(() {
      _mode = mode;
      _pin = '';
      _pinController.clear();
      _usernameController.clear();
      _errorMessage = null;
    });
    _transitionCtrl.forward(from: 0);
  }

  void _backToSelection() {
    HapticFeedback.lightImpact();
    setState(() {
      _mode = _LoginMode.none;
      _pin = '';
      _pinController.clear();
      _usernameController.clear();
      _errorMessage = null;
      _isLoading = false;
    });
    _transitionCtrl.reverse();
  }

  void _onDigitPressed(String digit) {
    if (_pin.length >= _maxSecretLength || _isLoading) return;
    HapticFeedback.selectionClick();
    _setPin(_pin + digit);
  }

  void _onBackspace() {
    if (_pin.isEmpty || _isLoading) return;
    HapticFeedback.selectionClick();
    _setPin(_pin.substring(0, _pin.length - 1));
  }

  void _onClear() {
    if (_isLoading) return;
    _setPin('');
  }

  /// تحديث حالة الواجهة عند تعديل حقول الهوية (معرّف المطعم / اسم المستخدم):
  /// يبدّل تلقائياً بين وضع حساب الموظف والوضع السريع القديم.
  void _onIdentityFieldChanged() {
    setState(() {
      _errorMessage = null;
      if (!_isStaffMode && _pin.length > 6) {
        _pin = _pin.substring(0, 6);
        _pinController.text = _pin;
      }
    });
  }

  void _setPin(String value) {
    setState(() {
      _pin = value;
      _pinController.text = value;
      _errorMessage = null;
    });
    // التحقق التلقائي عند 4 أرقام يعمل فقط في المسار السريع القديم
    // (بدون اسم مستخدم). أما حساب الموظف فيتحقق بزر «دخول» ليدعم
    // كلمات المرور الأطول من 4 خانات.
    if (_pin.length == 4 && !_isStaffMode) {
      _verifyPin(_pin);
    }
  }

  /// زر «دخول»: يوجّه بين مسار الحساب الكامل (معرّف مطعم + اسم مستخدم +
  /// كلمة مرور/PIN) والمسار السريع القديم (رمز الجهاز فقط).
  Future<void> _submit() async {
    if (_isLoading) return;

    if (_restaurantIdController.text.trim().isEmpty) {
      setState(() {
        _errorMessage = 'يرجى إدخال معرّف المطعم قبل تسجيل الدخول.';
      });
      _shakeCtrl.forward(from: 0);
      return;
    }

    final String username = _usernameController.text.trim();
    if (username.isEmpty) {
      // المسار السريع القديم — رمز PIN للجهاز (سلوك سابق محفوظ).
      if (_pin.length < 4) {
        setState(() {
          _errorMessage =
              'أدخل الرمز السري كاملاً (4 أرقام) أو أكمل بيانات الحساب '
              '(معرّف المطعم + اسم المستخدم).';
        });
        _shakeCtrl.forward(from: 0);
        return;
      }
      await _verifyPin(_pin);
      return;
    }

    await _authenticateStaff(
      restaurantId: _restaurantIdController.text,
      username: username,
      secret: _pin,
    );
  }

  /// مصادقة حساب موظف (عامل أو مدير) عبر [StaffDirectoryService]،
  /// ثم حفظ جلسة دائمة وآمنة عبر [StaffSessionService] والانتقال للشاشة.
  Future<void> _authenticateStaff({
    required String restaurantId,
    required String username,
    required String secret,
  }) async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    await Future<void>.delayed(const Duration(milliseconds: 300));

    final StaffAuthResult result = await StaffDirectoryService.authenticate(
      restaurantId: restaurantId,
      username: username,
      secret: secret,
    );

    if (!mounted) return;

    if (!result.success || result.staff == null) {
      HapticFeedback.vibrate();
      _shakeCtrl.forward(from: 0);
      setState(() {
        _isLoading = false;
        _errorMessage = result.message ?? 'بيانات الدخول غير صحيحة.';
        _pin = '';
        _pinController.clear();
      });
      return;
    }

    final StaffMember staff = result.staff!;

    // حساب عامل — يجب إيجاد بيانات ورديته على هذا الجهاز لفتح لوحته.
    Driver? driver;
    if (staff.isWorker) {
      driver = await _resolveDriverForStaff(staff);
      if (driver == null) {
        setState(() {
          _isLoading = false;
          _errorMessage =
              'تم التحقق من الحساب بنجاح، لكن لا توجد بيانات وردية لهذا '
              'العامل على هذا الجهاز بعد. تأكد من إعداد مزامنة Firebase '
              'في الإعدادات ثم أعد المحاولة.';
          _pin = '';
          _pinController.clear();
        });
        return;
      }
    }

    // حفظ الجلسة في Secure Storage — تبقى مسجلاً للدخول بشكل دائم.
    await StaffSessionService.saveSession(StaffSession.fromStaff(staff));
    if (!mounted) return;

    HapticFeedback.heavyImpact();
    setState(() => _isLoading = false);

    final Widget target = staff.isManager
        ? const HomeScreen()
        : DriverDashboardScreen(driver: driver!);
    Navigator.of(context).pushReplacement(
      PageRouteBuilder<void>(
        pageBuilder: (_, _, _) => target,
        transitionsBuilder: (_, Animation<double> anim, _, Widget child) {
          return FadeTransition(opacity: anim, child: child);
        },
        transitionDuration: const Duration(milliseconds: 500),
      ),
    );
  }

  /// إيجاد بيانات العامل (بالرمز ثم بالاسم) مع انتظار قصير للمزامنة
  /// السحابية إن كان رابط Firebase مضبوطاً.
  Future<Driver?> _resolveDriverForStaff(StaffMember staff) async {
    Driver? driver = await DriverStorage.loadDriverByPin(staff.driverPin);
    driver ??= await _findDriverByName(staff.name);
    if (driver != null) return driver;

    final String dbUrl = await StaffDirectoryService.resolveDatabaseUrl();
    if (dbUrl.isEmpty) return null;

    for (int attempt = 0; attempt < 3; attempt++) {
      await Future<void>.delayed(const Duration(seconds: 2));
      if (!mounted) return null;
      driver = await DriverStorage.loadDriverByPin(staff.driverPin);
      driver ??= await _findDriverByName(staff.name);
      if (driver != null) return driver;
    }
    return driver;
  }

  /// إيجاد سائق باسمه (مقارنة موحّدة الحالة والمسافات).
  Future<Driver?> _findDriverByName(String name) async {
    final String needle = StaffMember.normalizeUsername(name);
    if (needle.isEmpty) return null;
    final List<Driver> drivers = await DriverStorage.loadDrivers();
    for (final Driver driver in drivers) {
      if (StaffMember.normalizeUsername(driver.name) == needle) {
        return driver;
      }
    }
    return null;
  }

  Future<void> _verifyPin(String enteredPin) async {
    if (_isLoading) return;
    if (_restaurantIdController.text.trim().isEmpty) {
      setState(() {
        _errorMessage = 'يرجى إدخال معرّف المطعم قبل تسجيل الدخول.';
      });
      _shakeCtrl.forward(from: 0);
      return;
    }
    setState(() => _isLoading = true);

    await Future<void>.delayed(const Duration(milliseconds: 300));
    final AuthResult result = await AuthSessionService.loginWithPin(enteredPin);

    if (!mounted) return;

    if (result.success) {
      HapticFeedback.heavyImpact();
      if (result.role == UserRole.admin) {
        Navigator.of(context).pushReplacement(
          PageRouteBuilder<void>(
            pageBuilder: (_, _, _) => const HomeScreen(),
            transitionsBuilder: (_, Animation<double> anim, _, Widget child) {
              return FadeTransition(opacity: anim, child: child);
            },
            transitionDuration: const Duration(milliseconds: 500),
          ),
        );
      } else if (result.role == UserRole.driver && result.driver != null) {
        Navigator.of(context).pushReplacement(
          PageRouteBuilder<void>(
            pageBuilder: (_, _, _) =>
                DriverDashboardScreen(driver: result.driver!),
            transitionsBuilder: (_, Animation<double> anim, _, Widget child) {
              return FadeTransition(opacity: anim, child: child);
            },
            transitionDuration: const Duration(milliseconds: 500),
          ),
        );
      }
    } else {
      HapticFeedback.vibrate();
      _shakeCtrl.forward(from: 0);
      setState(() {
        _isLoading = false;
        _errorMessage = result.message ?? 'الرمز غير صحيح. يرجى المحاولة مجدداً.';
        _pin = '';
        _pinController.clear();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: Stack(
        children: <Widget>[
          // ── خلفية متحركة ──────────────────────────────────────────
          RepaintBoundary(
            child: _AnimatedBackground(controller: _bgCtrl),
          ),


          // ── المحتوى ────────────────────────────────────────────────
          SafeArea(
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 350),
              switchInCurve: Curves.easeOutCubic,
              switchOutCurve: Curves.easeInCubic,
              transitionBuilder: (Widget child, Animation<double> anim) {
                return FadeTransition(
                  opacity: anim,
                  child: SlideTransition(
                    position: Tween<Offset>(
                      begin: const Offset(0, 0.06),
                      end: Offset.zero,
                    ).animate(anim),
                    child: child,
                  ),
                );
              },
              child: _mode == _LoginMode.none
                  ? _SelectionView(
                      key: const ValueKey<String>('selection'),
                      onAdminTap: () => _selectMode(_LoginMode.admin),
                      onDriverTap: () => _selectMode(_LoginMode.driver),
                    )
                  : _PinView(
                      key: const ValueKey<String>('pin'),
                      mode: _mode,
                      pin: _pin,
                      isLoading: _isLoading,
                      errorMessage: _errorMessage,
                      shakeAnim: _shakeAnim,
                      onBack: _backToSelection,
                      onDigit: _onDigitPressed,
                      onBackspace: _onBackspace,
                      onClear: _onClear,
                      restaurantIdController: _restaurantIdController,
                      usernameController: _usernameController,
                      isStaffMode: _isStaffMode,
                      onSubmit: _submit,
                      onIdentityFieldChanged: _onIdentityFieldChanged,
                    ),
            ),
          ),
        ],
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// خلفية الجسيمات المتحركة
// ══════════════════════════════════════════════════════════════════════════════

class _AnimatedBackground extends StatelessWidget {
  const _AnimatedBackground({required this.controller});
  final AnimationController controller;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (_, _) => CustomPaint(
        painter: _ParticlePainter(controller.value),
        size: Size.infinite,
      ),
    );
  }
}

class _ParticlePainter extends CustomPainter {
  _ParticlePainter(this.t);
  final double t;

  static final List<_Particle> _particles = List<_Particle>.generate(
    18,
    (int i) => _Particle(
      x: (i * 0.137 + 0.05) % 1.0,
      y: (i * 0.193 + 0.1) % 1.0,
      r: 2.0 + (i % 4) * 1.5,
      speed: 0.03 + (i % 5) * 0.008,
      phase: i * 0.35,
    ),
  );

  @override
  void paint(Canvas canvas, Size size) {
    // تدرج الخلفية
    final Paint bgPaint = Paint()
      ..shader = const LinearGradient(
        colors: <Color>[Color(0xFF060E1E), Color(0xFF0B1426), Color(0xFF0D1B30)],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      ).createShader(Rect.fromLTWH(0, 0, size.width, size.height));
    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height), bgPaint);

    // دائرة توهج خضراء كبيرة
    final Paint glow1 = Paint()
      ..shader = RadialGradient(
        colors: <Color>[
          AppColors.primary.withValues(alpha: 0.12),
          Colors.transparent,
        ],
      ).createShader(Rect.fromCircle(
        center: Offset(size.width * 0.2, size.height * 0.25),
        radius: size.width * 0.7,
      ));
    canvas.drawCircle(
      Offset(size.width * 0.2, size.height * 0.25),
      size.width * 0.7,
      glow1,
    );

    // دائرة توهج بنفسجية
    final Paint glow2 = Paint()
      ..shader = RadialGradient(
        colors: <Color>[
          AppColors.accent.withValues(alpha: 0.08),
          Colors.transparent,
        ],
      ).createShader(Rect.fromCircle(
        center: Offset(size.width * 0.85, size.height * 0.75),
        radius: size.width * 0.6,
      ));
    canvas.drawCircle(
      Offset(size.width * 0.85, size.height * 0.75),
      size.width * 0.6,
      glow2,
    );

    // جسيمات صغيرة تتحرك
    for (final _Particle p in _particles) {
      final double angle = (t * p.speed * math.pi * 2) + p.phase;
      final double px = (p.x + math.sin(angle) * 0.04) * size.width;
      final double py = (p.y + math.cos(angle * 0.7) * 0.06) * size.height;

      final Paint dot = Paint()
        ..color = AppColors.primary.withValues(alpha: 0.18 + math.sin(angle) * 0.08)
        ..style = PaintingStyle.fill;
      canvas.drawCircle(Offset(px, py), p.r, dot);
    }
  }

  @override
  bool shouldRepaint(_ParticlePainter old) => old.t != t;
}

class _Particle {
  const _Particle({
    required this.x,
    required this.y,
    required this.r,
    required this.speed,
    required this.phase,
  });
  final double x, y, r, speed, phase;
}

// ══════════════════════════════════════════════════════════════════════════════
// المرحلة 1: اختيار نوع الدخول
// ══════════════════════════════════════════════════════════════════════════════

class _SelectionView extends StatelessWidget {
  const _SelectionView({
    super.key,
    required this.onAdminTap,
    required this.onDriverTap,
  });

  final VoidCallback onAdminTap;
  final VoidCallback onDriverTap;

  @override
  Widget build(BuildContext context) {
    final Size screen = MediaQuery.of(context).size;

    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
      child: ConstrainedBox(
        constraints: BoxConstraints(minHeight: screen.height - 100),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            SizedBox(height: screen.height * 0.06),

            // ── شعار التطبيق ──────────────────────────────────────
            _buildLogo(),
            const SizedBox(height: 28),

            // ── العنوان ───────────────────────────────────────────
            Text(
              'Orderly',
              style: GoogleFonts.cairo(
                fontSize: 36,
                fontWeight: FontWeight.w900,
                color: AppColors.textPrimary,
                letterSpacing: 1.5,
              ),
            ),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(30),
                border: Border.all(
                  color: AppColors.primary.withValues(alpha: 0.25),
                ),
              ),
              child: Text(
                'نظام إدارة التوصيل الذكي',
                style: GoogleFonts.cairo(
                  fontSize: 12.5,
                  color: AppColors.primary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            SizedBox(height: screen.height * 0.06),

            // ── زر دخول المدير ────────────────────────────────────
            _RoleCard(
              key: const ValueKey<String>('login-admin-btn'),
              icon: Icons.admin_panel_settings_rounded,
              label: 'تسجيل دخول المدير',
              subtitle: 'لوحة التحكم الكاملة · الكاشير · التحليلات',
              gradientColors: const <Color>[Color(0xFF00A878), Color(0xFF00C896)],
              glowColor: AppColors.primary,
              onTap: onAdminTap,
            ),
            const SizedBox(height: 16),

            // ── زر دخول السائقين ──────────────────────────────────
            _RoleCard(
              key: const ValueKey<String>('login-driver-btn'),
              icon: Icons.two_wheeler_rounded,
              label: 'تسجيل دخول السائقين',
              subtitle: 'واجهة التوصيل الميدانية · متابعة الطلبات',
              gradientColors: const <Color>[Color(0xFF6D28D9), Color(0xFF7C3AED)],
              glowColor: AppColors.accent,
              onTap: onDriverTap,
            ),

            SizedBox(height: screen.height * 0.05),

            // ── ملاحظة الأمان ─────────────────────────────────────
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: <Widget>[
                Icon(
                  Icons.shield_rounded,
                  size: 13,
                  color: AppColors.textMuted,
                ),
                const SizedBox(width: 6),
                Text(
                  'محمي بنظام رموز سرية متشفرة',
                  style: GoogleFonts.cairo(
                    fontSize: 11.5,
                    color: AppColors.textMuted,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  Widget _buildLogo() {
    return Container(
      width: 96,
      height: 96,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: AppColors.primaryGradient,
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: AppColors.primary.withValues(alpha: 0.4),
            blurRadius: 30,
            spreadRadius: 2,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: const Icon(
        Icons.storefront_rounded,
        size: 48,
        color: Colors.white,
      ),
    );
  }
}

// ── بطاقة اختيار الدور ────────────────────────────────────────────────────

class _RoleCard extends StatefulWidget {
  const _RoleCard({
    super.key,
    required this.icon,
    required this.label,
    required this.subtitle,
    required this.gradientColors,
    required this.glowColor,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final String subtitle;
  final List<Color> gradientColors;
  final Color glowColor;
  final VoidCallback onTap;

  @override
  State<_RoleCard> createState() => _RoleCardState();
}

class _RoleCardState extends State<_RoleCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pressCtrl;
  late final Animation<double> _scaleAnim;

  @override
  void initState() {
    super.initState();
    _pressCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 120),
      lowerBound: 0.96,
      upperBound: 1.0,
      value: 1.0,
    );
    _scaleAnim = _pressCtrl;
  }

  @override
  void dispose() {
    _pressCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => _pressCtrl.reverse(),
      onTapUp: (_) {
        _pressCtrl.forward();
        widget.onTap();
      },
      onTapCancel: () => _pressCtrl.forward(),
      child: ScaleTransition(
        scale: _scaleAnim,
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(24),
            gradient: LinearGradient(
              colors: widget.gradientColors,
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            boxShadow: <BoxShadow>[
              BoxShadow(
                color: widget.glowColor.withValues(alpha: 0.35),
                blurRadius: 24,
                spreadRadius: 0,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Stack(
            children: <Widget>[
              // تأثير بريق داخلي
              Positioned(
                top: -20,
                right: -20,
                child: Container(
                  width: 100,
                  height: 100,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.white.withValues(alpha: 0.07),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 22),
                child: Row(
                  children: <Widget>[
                    // أيقونة
                    Container(
                      width: 56,
                      height: 56,
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: Colors.white.withValues(alpha: 0.2),
                        ),
                      ),
                      child: Icon(widget.icon, color: Colors.white, size: 30),
                    ),
                    const SizedBox(width: 18),
                    // النصوص
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Text(
                            widget.label,
                            style: GoogleFonts.cairo(
                              color: Colors.white,
                              fontSize: 16,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            widget.subtitle,
                            style: GoogleFonts.cairo(
                              color: Colors.white.withValues(alpha: 0.75),
                              fontSize: 11.5,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ),
                    // سهم
                    Container(
                      width: 34,
                      height: 34,
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.15),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.arrow_forward_ios_rounded,
                        color: Colors.white,
                        size: 16,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// المرحلة 2: إدخال الرمز السري
// ══════════════════════════════════════════════════════════════════════════════

class _PinView extends StatelessWidget {
  const _PinView({
    super.key,
    required this.mode,
    required this.pin,
    required this.isLoading,
    required this.errorMessage,
    required this.shakeAnim,
    required this.onBack,
    required this.onDigit,
    required this.onBackspace,
    required this.onClear,
    required this.restaurantIdController,
    required this.usernameController,
    required this.isStaffMode,
    required this.onSubmit,
    required this.onIdentityFieldChanged,
  });

  final _LoginMode mode;
  final String pin;
  final bool isLoading;
  final String? errorMessage;
  final Animation<double> shakeAnim;
  final VoidCallback onBack;
  final void Function(String) onDigit;
  final VoidCallback onBackspace;
  final VoidCallback onClear;
  final TextEditingController restaurantIdController;
  final TextEditingController usernameController;
  final bool isStaffMode;
  final VoidCallback onSubmit;
  final VoidCallback onIdentityFieldChanged;

  bool get _isAdmin => mode == _LoginMode.admin;
  Color get _modeColor => _isAdmin ? AppColors.primary : AppColors.accent;
  IconData get _modeIcon => _isAdmin
      ? Icons.admin_panel_settings_rounded
      : Icons.two_wheeler_rounded;
  String get _modeLabel => _isAdmin ? 'حساب المدير' : 'حساب العامل';
  String get _modeHint => _isAdmin
      ? 'أدخل معرّف المطعم واسم المستخدم وكلمة المرور للوصول إلى لوحة التحكم'
      : 'أدخل معرّف المطعم واسمك وكلمة المرور أو رمز PIN الخاص بك';

  @override
  Widget build(BuildContext context) {
    final Size screen = MediaQuery.of(context).size;

    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      child: ConstrainedBox(
        constraints: BoxConstraints(minHeight: screen.height - 60),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: <Widget>[
            Column(
              children: <Widget>[
                const SizedBox(height: 8),
                // ── شريط العنوان ──────────────────────────────────
                _buildTopBar(),
                SizedBox(height: screen.height * 0.04),

                // ── أيقونة القفل ──────────────────────────────────
                _buildLockIcon(),
                const SizedBox(height: 20),

                // ── العنوان والتلميح ──────────────────────────────
                Text(
                  _modeLabel,
                  style: GoogleFonts.cairo(
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  _modeHint,
                  textAlign: TextAlign.center,
                  style: GoogleFonts.cairo(
                    fontSize: 12.5,
                    color: AppColors.textSecondary,
                  ),
                ),
                const SizedBox(height: 16),

                // ── بيانات الحساب (معرّف المطعم + اسم المستخدم) ────
                _buildIdentityFields(),

                const SizedBox(height: 16),

                // ── خانات كلمة المرور / PIN ───────────────────────
                AnimatedBuilder(
                  animation: shakeAnim,
                  builder: (_, Widget? child) {
                    final double shake =
                        math.sin(shakeAnim.value * math.pi * 5) * 10;
                    return Transform.translate(
                      offset: Offset(shake, 0),
                      child: child,
                    );
                  },
                  child: _buildPinDots(),
                ),

                const SizedBox(height: 14),

                // ── زر الدخول ─────────────────────────────────────
                _buildLoginButton(),

                // ── رسالة الخطأ ───────────────────────────────────
                if (errorMessage != null) ...<Widget>[
                  const SizedBox(height: 16),
                  _buildErrorBanner(),
                ],
              ],
            ),

            // ── لوحة الأرقام ──────────────────────────────────────
            Padding(
              padding: const EdgeInsets.only(top: 24, bottom: 12),
              child: _buildKeypad(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTopBar() {
    return Row(
      children: <Widget>[
        Material(
          color: Colors.transparent,
          child: InkWell(
            key: const ValueKey<String>('pin-back-btn'),
            borderRadius: BorderRadius.circular(12),
            onTap: isLoading ? null : onBack,
            child: Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: AppColors.card,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.border),
              ),
              child: const Icon(
                Icons.arrow_back_ios_new_rounded,
                size: 18,
                color: AppColors.textSecondary,
              ),
            ),
          ),
        ),
        const SizedBox(width: 12),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
          decoration: BoxDecoration(
            color: _modeColor.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(30),
            border: Border.all(color: _modeColor.withValues(alpha: 0.3)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Icon(_modeIcon, size: 15, color: _modeColor),
              const SizedBox(width: 6),
              Text(
                _isAdmin ? 'دخول المدير' : 'دخول السائق',
                style: GoogleFonts.cairo(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: _modeColor,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildLockIcon() {
    return Container(
      width: 80,
      height: 80,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
          colors: <Color>[
            _modeColor.withValues(alpha: 0.2),
            _modeColor.withValues(alpha: 0.05),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        border: Border.all(
          color: _modeColor.withValues(alpha: 0.25),
          width: 2,
        ),
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: _modeColor.withValues(alpha: 0.15),
            blurRadius: 20,
            spreadRadius: 2,
          ),
        ],
      ),
      child: Icon(Icons.lock_rounded, size: 38, color: _modeColor),
    );
  }

  /// حقول الهوية الإجبارية لتسجيل دخول الحساب:
  /// معرّف المطعم (Restaurant ID) + اسم المستخدم.
  /// ترك اسم المستخدم فارغاً يُبقي المسار السريع القديم برمز الجهاز.
  Widget _buildIdentityFields() {
    return Column(
      children: <Widget>[
        TextField(
          key: const ValueKey<String>('login-restaurant-id-field'),
          controller: restaurantIdController,
          enabled: !isLoading,
          textDirection: TextDirection.ltr,
          style: GoogleFonts.cairo(
            fontSize: 14,
            fontWeight: FontWeight.w700,
            color: AppColors.textPrimary,
          ),
          decoration: _identityDecoration(
            label: 'معرّف المطعم (Restaurant ID) *',
            hint: 'مثال: A1B2C3D4E5F6G7H8',
            icon: Icons.storefront_rounded,
          ),
          onChanged: (_) => onIdentityFieldChanged(),
        ),
        const SizedBox(height: 10),
        TextField(
          key: const ValueKey<String>('login-username-field'),
          controller: usernameController,
          enabled: !isLoading,
          style: GoogleFonts.cairo(
            fontSize: 14,
            fontWeight: FontWeight.w700,
            color: AppColors.textPrimary,
          ),
          decoration: _identityDecoration(
            label: 'اسم المستخدم *',
            hint: isStaffMode
                ? 'وضع حساب الموظف مفعّل ✓'
                : 'اتركه فارغاً للدخول السريع برمز الجهاز',
            icon: Icons.badge_rounded,
          ),
          onChanged: (_) => onIdentityFieldChanged(),
        ),
      ],
    );
  }

  /// تنسيق موحد لحقول الهوية (وضع داكن متناسق مع هوية التطبيق).
  InputDecoration _identityDecoration({
    required String label,
    required String hint,
    required IconData icon,
  }) {
    return InputDecoration(
      labelText: label,
      hintText: hint,
      prefixIcon: Icon(icon, size: 18, color: _modeColor),
      filled: true,
      fillColor: AppColors.field,
      isDense: true,
      contentPadding: const EdgeInsets.symmetric(
        horizontal: 14,
        vertical: 12,
      ),
      labelStyle: GoogleFonts.cairo(
        fontSize: 11.5,
        color: AppColors.textSecondary,
      ),
      hintStyle: GoogleFonts.cairo(fontSize: 11, color: AppColors.textMuted),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: AppColors.border, width: 1.2),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(
          color: _modeColor.withValues(alpha: 0.6),
          width: 1.6,
        ),
      ),
      disabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: AppColors.border, width: 1.2),
      ),
    );
  }

  /// زر الدخول: مصادقة الحساب الكامل أو المسار السريع القديم.
  Widget _buildLoginButton() {
    return SizedBox(
      width: double.infinity,
      height: 48,
      child: FilledButton.icon(
        key: const ValueKey<String>('staff-login-btn'),
        style: FilledButton.styleFrom(
          backgroundColor: _modeColor,
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          disabledBackgroundColor: _modeColor.withValues(alpha: 0.5),
        ),
        onPressed: isLoading ? null : onSubmit,
        icon: isLoading
            ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                  strokeWidth: 2.4,
                  color: Colors.white,
                ),
              )
            : const Icon(Icons.login_rounded, size: 20),
        label: Text(
          isStaffMode ? 'دخول بحساب الموظف' : 'دخول سريع (رمز الجهاز)',
          style: GoogleFonts.cairo(
            fontSize: 14.5,
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
    );
  }

  Widget _buildPinDots() {
    // عدد الخانات ديناميكي: 4 أساسياً، ويزيد لكلمات المرور الأطول.
    final int dotCount = pin.length < 4 ? 4 : pin.length;
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List<Widget>.generate(dotCount, (int i) {
        final bool filled = i < pin.length;
        final bool isCurrentLoading = isLoading && i == pin.length - 1;

        return AnimatedContainer(
          key: ValueKey<String>('pin-digit-$i'),
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOutBack,
          width: filled ? 62 : 58,
          height: filled ? 66 : 62,
          margin: const EdgeInsets.symmetric(horizontal: 7),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: filled
                ? _modeColor.withValues(alpha: 0.1)
                : AppColors.card,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: filled ? _modeColor : AppColors.border,
              width: filled ? 2 : 1.2,
            ),
            boxShadow: <BoxShadow>[
              if (filled)
                BoxShadow(
                  color: _modeColor.withValues(alpha: 0.2),
                  blurRadius: 12,
                  spreadRadius: 1,
                  offset: const Offset(0, 4),
                ),
            ],
          ),
          child: isCurrentLoading
              ? SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.5,
                    color: _modeColor,
                  ),
                )
              : AnimatedScale(
                  scale: filled ? 1.0 : 0.0,
                  duration: const Duration(milliseconds: 200),
                  curve: Curves.elasticOut,
                  child: Container(
                    width: 14,
                    height: 14,
                    decoration: BoxDecoration(
                      color: _modeColor,
                      shape: BoxShape.circle,
                      boxShadow: <BoxShadow>[
                        BoxShadow(
                          color: _modeColor.withValues(alpha: 0.5),
                          blurRadius: 6,
                        ),
                      ],
                    ),
                  ),
                ),
        );
      }),
    );
  }

  Widget _buildErrorBanner() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.danger.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.danger.withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          const Icon(Icons.error_rounded, size: 17, color: AppColors.danger),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              errorMessage!,
              style: GoogleFonts.cairo(
                fontSize: 12.5,
                color: AppColors.dangerLight,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

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
              final bool isBackspace = key == '⌫';
              final bool isClear = key == 'C';
              final bool isSpecial = isBackspace || isClear;

              return _KeypadButton(
                keyValue: key,
                isSpecial: isSpecial,
                isBackspace: isBackspace,
                isClear: isClear,
                accentColor: _modeColor,
                isLoading: isLoading,
                onTap: () {
                  if (isBackspace) {
                    onBackspace();
                  } else if (isClear) {
                    onClear();
                  } else {
                    onDigit(key);
                  }
                },
              );
            }).toList(),
          ),
        );
      }).toList(),
    );
  }
}

// ── زر لوحة المفاتيح ──────────────────────────────────────────────────────

class _KeypadButton extends StatefulWidget {
  const _KeypadButton({
    required this.keyValue,
    required this.isSpecial,
    required this.isBackspace,
    required this.isClear,
    required this.accentColor,
    required this.isLoading,
    required this.onTap,
  });

  final String keyValue;
  final bool isSpecial;
  final bool isBackspace;
  final bool isClear;
  final Color accentColor;
  final bool isLoading;
  final VoidCallback onTap;

  @override
  State<_KeypadButton> createState() => _KeypadButtonState();
}

class _KeypadButtonState extends State<_KeypadButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 100),
      lowerBound: 0.88,
      upperBound: 1.0,
      value: 1.0,
    );
    _scale = _ctrl;
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: widget.isLoading ? null : (_) => _ctrl.reverse(),
      onTapUp: widget.isLoading
          ? null
          : (_) {
              _ctrl.forward();
              widget.onTap();
            },
      onTapCancel: () => _ctrl.forward(),
      child: ScaleTransition(
        scale: _scale,
        child: Container(
          key: ValueKey<String>('keypad-${widget.keyValue}'),
          width: 84,
          height: 62,
          margin: const EdgeInsets.symmetric(horizontal: 8),
          decoration: BoxDecoration(
            color: widget.isSpecial ? AppColors.background : AppColors.card,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: widget.isBackspace
                  ? AppColors.danger.withValues(alpha: 0.25)
                  : AppColors.border,
            ),
            boxShadow: widget.isSpecial
                ? null
                : <BoxShadow>[
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.25),
                      blurRadius: 8,
                      offset: const Offset(0, 4),
                    ),
                    BoxShadow(
                      color: widget.accentColor.withValues(alpha: 0.04),
                      blurRadius: 12,
                      spreadRadius: 1,
                    ),
                  ],
          ),
          alignment: Alignment.center,
          child: widget.isBackspace
              ? const Icon(
                  Icons.backspace_rounded,
                  size: 24,
                  color: AppColors.danger,
                )
              : widget.isClear
                  ? const Icon(
                      Icons.close_rounded,
                      size: 24,
                      color: AppColors.textMuted,
                    )
                  : Text(
                      widget.keyValue,
                      style: GoogleFonts.cairo(
                        fontSize: 28,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textPrimary,
                        height: 1,
                      ),
                    ),
        ),
      ),
    );
  }
}
