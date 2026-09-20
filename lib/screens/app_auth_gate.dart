import 'package:flutter/material.dart';
import 'package:orderly_app/models/driver.dart';
import 'package:orderly_app/screens/activation_screen.dart';
import 'package:orderly_app/screens/driver_dashboard_screen.dart';
import 'package:orderly_app/screens/home_screen.dart';
import 'package:orderly_app/screens/unified_login_screen.dart';
import 'package:orderly_app/services/auth_session_service.dart';
import 'package:orderly_app/services/license_service.dart';
import 'package:orderly_app/theme/app_theme.dart';

/// البوابة الجذرية للتطبيق — تتحقق من:
/// 1. ترخيص الموزع (أولوية قصوى — شاشة التفعيل إذا لم يكن مُفعَّلاً).
/// 2. الجلسة النشطة (مدير / سائق / لا جلسة).
class AppAuthGate extends StatefulWidget {
  const AppAuthGate({super.key});

  @override
  State<AppAuthGate> createState() => _AppAuthGateState();
}

class _AppAuthGateState extends State<AppAuthGate> {
  bool _checking = true;
  bool _licensed = false;
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

    // ② الترخيص صالح — فحص الجلسة
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

    if (mounted) {
      setState(() {
        _licensed = true;
        _activeRole = null;
        _activeDriver = null;
        _checking = false;
      });
    }
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

    // ── جلسة مدير ──────────────────────────────────────────────
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
