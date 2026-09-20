import 'package:shared_preferences/shared_preferences.dart';

import 'package:orderly_app/models/driver.dart';
import 'package:orderly_app/services/app_settings.dart';
import 'package:orderly_app/services/driver_storage.dart';

/// الأدوار والصلاحيات المتاحة في النظام.
enum UserRole {
  /// مدير المطعم / الكاشير: يملك الصلاحية الكاملة (إدارة المبيعات، الصندوق، أجور العمال، الإعدادات).
  admin,

  /// سائق التوصيل: محصور في واجهة الطلبات الميدانية المسندة إليه فقط وزري الاستلام والتسليم.
  driver,
}

/// نتيجة محاولة تسجيل الدخول بالرمز.
class AuthResult {
  const AuthResult({
    required this.success,
    this.role,
    this.driver,
    this.message,
  });

  factory AuthResult.successAdmin() => const AuthResult(
        success: true,
        role: UserRole.admin,
        message: 'تم الدخول بنجاح إلى لوحة تحكم المدير والمطعم',
      );

  factory AuthResult.successDriver(Driver driver) => AuthResult(
        success: true,
        role: UserRole.driver,
        driver: driver,
        message: 'أهلاً بك يا ${driver.name} (رمز: ${driver.pin})',
      );

  factory AuthResult.failure(String message) => AuthResult(
        success: false,
        message: message,
      );

  final bool success;
  final UserRole? role;
  final Driver? driver;
  final String? message;
}

/// خدمة إدارة الجلسات الموحدة وعزل الصلاحيات واستمرار الدخول.
class AuthSessionService {
  const AuthSessionService._();

  static const String activeRoleKey = 'orderly.active_user_role';
  static const String activeDriverPinKey = 'orderly.active_driver_pin';

  static Future<SharedPreferences> get _prefs => SharedPreferences.getInstance();

  /// التحقق من الرمز المدخل وتسجيل الجلسة المناسبة (مدير أو سائق).
  static Future<AuthResult> loginWithPin(String pin) async {
    final String cleanPin = pin.trim();
    if (cleanPin.isEmpty) {
      return AuthResult.failure('يرجى إدخال الرمز السري للدخول.');
    }

    // 1. فحص رمز المدير أولاً (الافتراضي 7777 أو الرمز المحدث)
    final bool isAdmin = await AppSettings.verifyAdminPin(cleanPin);
    if (isAdmin) {
      final SharedPreferences prefs = await _prefs;
      await prefs.setString(activeRoleKey, UserRole.admin.name);
      await prefs.remove(activeDriverPinKey);
      return AuthResult.successAdmin();
    }

    // 2. فحص رموز السائقين المسجلين (1001 إلى 1030 أو الرموز المخصصة)
    final List<Driver> drivers = await DriverStorage.loadDrivers();
    for (final Driver driver in drivers) {
      if (driver.pin == cleanPin) {
        final SharedPreferences prefs = await _prefs;
        await prefs.setString(activeRoleKey, UserRole.driver.name);
        await prefs.setString(activeDriverPinKey, cleanPin);
        return AuthResult.successDriver(driver);
      }
    }

    return AuthResult.failure(
      'الرمز غير صحيح. تأكد من إدخال رمز المدير أو رمز السائق الخاص بك.',
    );
  }

  /// استرجاع الدور النشط المسجل حالياً في الجلسة المحفوظة.
  static Future<UserRole?> getActiveRole() async {
    final SharedPreferences prefs = await _prefs;
    final String? roleName = prefs.getString(activeRoleKey);
    if (roleName == null) return null;

    if (roleName == UserRole.admin.name) {
      return UserRole.admin;
    } else if (roleName == UserRole.driver.name) {
      return UserRole.driver;
    }
    return null;
  }

  /// استرجاع بيانات السائق النشط حالياً، إن كان المستخدم الحالي سائقاً.
  static Future<Driver?> getActiveDriver() async {
    final UserRole? role = await getActiveRole();
    if (role != UserRole.driver) return null;

    final SharedPreferences prefs = await _prefs;
    final String? pin = prefs.getString(activeDriverPinKey);
    if (pin == null || pin.isEmpty) return null;

    return DriverStorage.loadDriverByPin(pin);
  }

  /// هل المدير مسجل دخوله حالياً؟
  static Future<bool> isAdminLoggedIn() async {
    final UserRole? role = await getActiveRole();
    return role == UserRole.admin;
  }

  /// هل هناك جلسة دخول نشطة ومحفوظة (مدير أو سائق)؟
  static Future<bool> hasActiveSession() async {
    final UserRole? role = await getActiveRole();
    if (role == UserRole.admin) return true;
    if (role == UserRole.driver) {
      final Driver? driver = await getActiveDriver();
      return driver != null;
    }
    return false;
  }

  /// تسجيل الخروج ومسح الجلسة تماماً للعودة لشاشة الدخول.
  static Future<void> logout() async {
    final SharedPreferences prefs = await _prefs;
    await prefs.remove(activeRoleKey);
    await prefs.remove(activeDriverPinKey);
  }
}
