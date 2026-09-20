import 'package:shared_preferences/shared_preferences.dart';

/// نظام حماية وتفعيل الموزع (Distributor License Protection).
///
/// يتحقق عند أول تشغيل للتطبيق على أي جهاز من وجود ترخيص صالح.
/// إذا لم يكن مُفعَّلاً، يُطلب من المستخدم إدخال كلمة مرور الموزع.
/// بعد التحقق الناجح، تُحفظ حالة الترخيص محلياً ولا تُطلب مرة أخرى.
class LicenseService {
  const LicenseService._();

  /// مفتاح التخزين المحلي لحالة الترخيص.
  static const String _licenseKey = 'orderly_distributor_license_activated';

  /// كلمة مرور الموزع الثابتة (مخزنة بشكل آمن في الكود).
  static const String _distributorPassword = 'orderly77';

  static Future<SharedPreferences> get _prefs =>
      SharedPreferences.getInstance();

  /// هل التطبيق مُفعَّل على هذا الجهاز؟
  static Future<bool> isActivated() async {
    final SharedPreferences prefs = await _prefs;
    return prefs.getBool(_licenseKey) ?? false;
  }

  /// التحقق من كلمة المرور وتفعيل الترخيص إذا كانت صحيحة.
  ///
  /// تُرجع `true` عند نجاح التفعيل، و`false` إذا كانت كلمة المرور خاطئة.
  static Future<bool> activate(String password) async {
    if (password.trim() == _distributorPassword) {
      final SharedPreferences prefs = await _prefs;
      await prefs.setBool(_licenseKey, true);
      return true;
    }
    return false;
  }

  /// إلغاء التفعيل (للاختبارات أو إعادة الضبط).
  static Future<void> deactivate() async {
    final SharedPreferences prefs = await _prefs;
    await prefs.remove(_licenseKey);
  }
}
