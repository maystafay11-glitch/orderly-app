import 'package:flutter/material.dart';
import 'package:orderly_app/models/driver.dart';
import 'package:orderly_app/models/staff_member.dart';
import 'package:orderly_app/screens/activation_screen.dart';
import 'package:orderly_app/screens/driver_dashboard_screen.dart';
import 'package:orderly_app/screens/home_screen.dart';
import 'package:orderly_app/screens/unified_login_screen.dart';
import 'package:orderly_app/services/auth_session_service.dart';
import 'package:orderly_app/services/driver_storage.dart';
import 'package:orderly_app/services/license_service.dart';
import 'package:orderly_app/services/restaurant_service.dart';
import 'package:orderly_app/services/staff_directory_service.dart';
import 'package:orderly_app/services/staff_session_service.dart';
import 'package:orderly_app/theme/app_theme.dart';

/// البوابة الجذرية للتطبيق — تتحقق من:
/// 1. ترخيص الموزع (أولوية قصوى — شاشة التفعيل إذا لم يكن مُفعَّلاً).
/// 2. الجلسة الآمنة الدائمة لموظفي المطعم (مدير / عامل — Secure Storage).
/// 3. الجلسة القديمة المحلية (رمز PIN للجهاز).
class AppAuthGate extends StatefulWidget {
  const AppAuthGate({super.key});

  @override
  State<AppAuthGate> createState() => _AppAuthGateState();
}

class _AppAuthGateState extends State<AppAuthGate> {
  bool _checking = true;
  bool _licensed = false;

  /// جلسة الموظف المسترجَعة من التخزين الآمن (لا تنتهي حتى الخروج الصريح).
  StaffSession? _staffSession;

  /// بيانات العامل المرتبطة بجلسة الموظف (لفتح لوحة العامل الصحيحة).
  Driver? _staffDriver;

  UserRole? _activeRole;
  Driver? _activeDriver;

  @override
  void initState() {
    super.initState();
    _checkAll();
  }

  Future<void> _checkAll() async {
    // ① فحص الترخيص أولاً
    final bool licensed = await LicenseService.isActivated();

    if (!licensed) {
      if (mounted) {
        setState(() {
          _licensed = false;
          _checking = false;
        });
      }
      return;
    }

    // ② الجلسة الآمنة لموظفي المطعم (عامل / مدير) — دائمة وآمنة.
    final StaffSession? staffSession = await StaffSessionService.restore();
    if (staffSession != null && staffSession.isValid) {
      // التحقق من صحة الجلسة (مقاومة للعبث)
      final bool isValidSession = await StaffSessionService.validateSession();
      if (!isValidSession) {
        await StaffSessionService.clear();
        // تابع إلى المسار التالي
      } else {
        if (staffSession.isManager) {
          if (mounted) {
            setState(() {
              _licensed = true;
              _staffSession = staffSession;
              _checking = false;
            });
          }
          return;
        }

        // عامل: إيجاد بيانات ورديته على هذا الجهاز لفتح لوحته.
        final Driver? staffDriver = await _resolveStaffDriver(staffSession);
        if (staffDriver != null) {
          if (mounted) {
            setState(() {
              _licensed = true;
              _staffSession = staffSession;
              _staffDriver = staffDriver;
              _checking = false;
            });
          }
          return;
        }

        // بيانات العامل غير موجودة على هذا الجهاز — امسح الجلسة للدخول من جديد.
        await StaffSessionService.clear();
      }
    }

    // ③ المسار القديم: جلسة رمز PIN المحلي (مدير / سائق).
    final UserRole? role = await AuthSessionService.getActiveRole();

    if (role == UserRole.admin) {
      if (mounted) {
        setState(() {
          _licensed = true;
          _activeRole = UserRole.admin;
          _checking = false;
        });
      }
      return;
    } else if (role == UserRole.driver) {
      final Driver? driver = await AuthSessionService.getActiveDriver();
      if (driver != null) {
        if (mounted) {
          setState(() {
            _licensed = true;
            _activeRole = UserRole.driver;
            _activeDriver = driver;
            _checking = false;
          });
        }
        return;
      } else {
        await AuthSessionService.logout();
      }
    }

    // ④ لا جلسة — تجهيز حسابات تسجيل الدخول (مدير + عمال) قبل الشاشة.
    try {
      await StaffDirectoryService.ensureProvisioned(
        RestaurantService.restaurantId,
      );
    } catch (_) {
      // التزويد إضافي غير حرج — لا يمنع فتح شاشة الدخول.
    }

    if (mounted) {
      setState(() {
        _licensed = true;
        _activeRole = null;
        _activeDriver = null;
        _checking = false;
      });
    }
  }

  /// إيجاد بيانات العامل المرتبطة بالجلسة (بالرمز ثم بالاسم).
  Future<Driver?> _resolveStaffDriver(StaffSession session) async {
    Driver? driver = await DriverStorage.loadDriverByPin(session.driverPin);
    if (driver != null) return driver;

    final String needle = StaffMember.normalizeUsername(session.name);
    if (needle.isEmpty) return null;
    final List<Driver> drivers = await DriverStorage.loadDrivers();
    for (final Driver candidate in drivers) {
      if (StaffMember.normalizeUsername(candidate.name) == needle) {
        return candidate;
      }
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    // ── شاشة التحميل الأولية ────────────────────────────────────
    if (_checking) {
      return const Scaffold(
        backgroundColor: AppColors.background,
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              CircularProgressIndicator(color: AppColors.primary),
              SizedBox(height: 16),
              Text(
                'جاري التحقق...',
                style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
              ),
            ],
          ),
        ),
      );
    }

    // ── التطبيق غير مُفعَّل — شاشة الترخيص ──────────────────────
    if (!_licensed) {
      return ActivationScreen(
        onActivated: () {
          if (mounted) {
            setState(() {
              _licensed = true;
              _checking = true;
            });
            _checkAll();
          }
        },
      );
    }

    // ── جلسة موظفين آمنة (Secure Storage) — دائمة ───────────────
    if (_staffSession != null && _staffSession!.isValid) {
      if (_staffSession!.isManager) {
        return const HomeScreen();
      }
      if (_staffDriver != null) {
        return DriverDashboardScreen(driver: _staffDriver!);
      }
    }

    // ── جلسة مدير قديمة (رمز الجهاز) ────────────────────────────
    if (_activeRole == UserRole.admin) {
      return const HomeScreen();
    }

    // ── جلسة سائق ──────────────────────────────────────────────
    if (_activeRole == UserRole.driver && _activeDriver != null) {
      return DriverDashboardScreen(driver: _activeDriver!);
    }

    // ── لا جلسة — شاشة تسجيل الدخول ────────────────────────────
    return const UnifiedLoginScreen();
  }
}
