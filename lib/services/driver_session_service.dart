import 'package:shared_preferences/shared_preferences.dart';

import 'package:orderly_app/models/driver.dart';
import 'package:orderly_app/services/driver_storage.dart';

/// إدارة جلسة تسجيل دخول السائق في تطبيق السائق (Driver App).
///
/// تتيح للسائق الدخول الفوري عبر رمزه الخاص (1001 إلى 1030) والاحتفاظ
/// بالجلسة نشطة لتفادي تكرار إدخال الرمز أثناء وردية العمل.
class DriverSessionService {
  const DriverSessionService._();

  static const String _activeDriverPinKey = 'orderly.active_driver_pin';

  static Future<SharedPreferences> get _prefs => SharedPreferences.getInstance();

  /// تسجيل دخول السائق باستخدام الرمز الخاص (1001 - 1030).
  ///
  /// يُرجع كائن [Driver] عند تطابق الرمز، أو `null` إذا لم يكن الرمز مسجلاً.
  static Future<Driver?> loginWithPin(String pin) async {
    final String cleanPin = pin.trim();
    if (cleanPin.isEmpty) return null;

    final List<Driver> drivers = await DriverStorage.loadDrivers();
    for (final Driver driver in drivers) {
      if (driver.pin == cleanPin) {
        final SharedPreferences prefs = await _prefs;
        await prefs.setString(_activeDriverPinKey, cleanPin);
        return driver;
      }
    }
    return null;
  }

  /// استرجاع الرمز الخاص بالسائق المسجّل دخوله حالياً، إن وُجد.
  static Future<String?> getSavedDriverPin() async {
    final SharedPreferences prefs = await _prefs;
    final String? pin = prefs.getString(_activeDriverPinKey);
    return (pin != null && pin.trim().isNotEmpty) ? pin.trim() : null;
  }

  /// استرجاع بيانات السائق المسجّل دخوله حالياً مع أحدث بيانات طلباته.
  static Future<Driver?> getLoggedInDriver() async {
    final String? pin = await getSavedDriverPin();
    if (pin == null) return null;

    final List<Driver> drivers = await DriverStorage.loadDrivers();
    for (final Driver driver in drivers) {
      if (driver.pin == pin) {
        return driver;
      }
    }
    return null;
  }

  /// هل يوجد سائق مسجّل دخوله حالياً؟
  static Future<bool> isLoggedIn() async {
    final String? pin = await getSavedDriverPin();
    return pin != null;
  }

  /// تسجيل الخروج ومسح الجلسة.
  static Future<void> logout() async {
    final SharedPreferences prefs = await _prefs;
    await prefs.remove(_activeDriverPinKey);
  }
}
