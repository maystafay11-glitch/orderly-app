import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'package:orderly_app/models/weekly_archive.dart';

/// حفظ واسترجاع إعدادات التطبيق (رقم واتساب المدير، إعدادات Firebase، والوقت المعتاد).
class AppSettings {
  const AppSettings._();

  // --- إعدادات رقم واتساب المدير ---
  static const String whatsAppPhoneKey = 'whatsapp_phone';

  // --- إعدادات رمز المدير السري (Admin PIN) ---
  static const String adminPinKey = 'admin_pin_code';
  static const String defaultAdminPin = '7777';

  // --- إعدادات التتبع والربط السحابي (Firebase) ---
  static const String firebaseDatabaseUrlKey = 'firebase_database_url';
  static const String expectedDurationKey = 'expected_delivery_duration_mins';
  static const String soundAlertsKey = 'sound_alerts_enabled';

  static Future<SharedPreferences> get _prefs => SharedPreferences.getInstance();

  /// قراءة رمز المدير السري (الافتراضي: 7777).
  static Future<String> getAdminPin() async {
    final SharedPreferences prefs = await _prefs;
    final String? pin = prefs.getString(adminPinKey);
    if (pin == null || pin.trim().isEmpty) {
      return defaultAdminPin;
    }
    return pin.trim();
  }

  /// حفظ / تعديل رمز المدير السري.
  static Future<void> setAdminPin(String newPin) async {
    final SharedPreferences prefs = await _prefs;
    final String clean = newPin.trim();
    if (clean.isNotEmpty) {
      await prefs.setString(adminPinKey, clean);
    }
  }

  /// التحقق من تطابق الرمز المدخل مع رمز المدير.
  static Future<bool> verifyAdminPin(String enteredPin) async {
    final String current = await getAdminPin();
    return current == enteredPin.trim();
  }

  /// قراءة رقم هاتف المدير/المطعم المخزن بصيغته الدولية (بدون +).
  static Future<String> getWhatsAppPhone() async {
    final SharedPreferences prefs = await _prefs;
    return (prefs.getString(whatsAppPhoneKey) ?? '').trim();
  }

  /// حفظ / تحديث رقم هاتف المدير المحلي.
  static Future<void> setWhatsAppPhone(String phone) async {
    final SharedPreferences prefs = await _prefs;
    await prefs.setString(whatsAppPhoneKey, phone.trim());
  }

  /// قراءة عنوان قاعدة بيانات Firebase السحابية.
  static Future<String> getFirebaseDatabaseUrl() async {
    final SharedPreferences prefs = await _prefs;
    return (prefs.getString(firebaseDatabaseUrlKey) ?? '').trim();
  }

  /// حفظ عنوان قاعدة بيانات Firebase السحابية.
  static Future<void> setFirebaseDatabaseUrl(String url) async {
    final SharedPreferences prefs = await _prefs;
    await prefs.setString(firebaseDatabaseUrlKey, url.trim());
  }

  /// مدة الطريق المعتادة بالدقائق لكشف التأخير والتسخيت (افتراضياً 25 دقيقة).
  static Future<int> getExpectedDeliveryDuration() async {
    final SharedPreferences prefs = await _prefs;
    return prefs.getInt(expectedDurationKey) ?? 25;
  }

  /// تعديل مدة الطريق المعتادة.
  static Future<void> setExpectedDeliveryDuration(int minutes) async {
    final SharedPreferences prefs = await _prefs;
    await prefs.setInt(expectedDurationKey, minutes);
  }

  /// هل التنبيهات الصوتية للطلبات والتسليم مفعلة؟
  static Future<bool> getSoundAlertsEnabled() async {
    final SharedPreferences prefs = await _prefs;
    return prefs.getBool(soundAlertsKey) ?? true;
  }

  /// تفعيل / كتم التنبيهات الصوتية.
  static Future<void> setSoundAlertsEnabled(bool enabled) async {
    final SharedPreferences prefs = await _prefs;
    await prefs.setBool(soundAlertsKey, enabled);
  }

  // --- الأرشيف الأسبوعي ---
  static const String archivesKey = 'weekly_archives';

  /// جميع الأرشيفات المخزنة (مرتّبة من الأحدث إلى الأقدم).
  static Future<List<WeeklyArchive>> loadArchives() async {
    final SharedPreferences prefs = await _prefs;
    try {
      final String? raw = prefs.getString(archivesKey);
      if (raw == null || raw.trim().isEmpty) {
        return <WeeklyArchive>[];
      }
      final Object? decoded = jsonDecode(raw);
      if (decoded is! List) {
        return <WeeklyArchive>[];
      }
      return decoded
          .whereType<Map<Object?, Object?>>()
          .map(
            (Map<Object?, Object?> item) =>
                WeeklyArchive.fromJson(Map<String, dynamic>.from(item)),
          )
          .toList()
          ..sort((WeeklyArchive a, WeeklyArchive b) =>
              b.periodEnd.compareTo(a.periodEnd));
    } catch (_) {
      return <WeeklyArchive>[];
    }
  }

  /// حفظ / استبدال الأرشيفات.
  static Future<void> saveArchives(List<WeeklyArchive> archives) async {
    final SharedPreferences prefs = await _prefs;
    if (archives.isEmpty) {
      await prefs.remove(archivesKey);
      return;
    }
    final String payload = jsonEncode(
      archives.map((WeeklyArchive archive) => archive.toJson()).toList(),
    );
    await prefs.setString(archivesKey, payload);
  }

  /// إغلاق فترة أسبوعية: أرشفة ملخصها الآن، ثم حذف الأرشيفات الأقدم من أسبوع.
  static Future<void> archiveWeek({
    required int totalOrders,
    required double totalAmount,
    required double totalWage,
    required double netAmount,
    required DateTime periodStart,
    required DateTime periodEnd,
  }) async {
    final List<WeeklyArchive> archives = await loadArchives();
    archives.add(
      WeeklyArchive(
        totalOrders: totalOrders,
        totalAmount: totalAmount,
        totalWage: totalWage,
        netAmount: netAmount,
        periodStart: periodStart,
        periodEnd: periodEnd,
      ),
    );
    await _pruneOld(archives);
  }

  /// حذف الأرشيفات التي مرّ عليها أكثر من 7 أيام (تنقية أسبوعية).
  static Future<void> pruneOldArchives() async {
    final List<WeeklyArchive> archives = await loadArchives();
    await _pruneOld(archives);
  }

  static Future<void> _pruneOld(List<WeeklyArchive> archives) async {
    final DateTime cutoff = DateTime.now().subtract(const Duration(days: 7));
    final List<WeeklyArchive> kept = archives
        .where((WeeklyArchive archive) => !archive.createdAt.isBefore(cutoff))
        .toList();
    await saveArchives(kept);
  }

  /// مسح كل الأرشيفات والإعدادات (للاختبارات فقط).
  static Future<void> clearAll() async {
    final SharedPreferences prefs = await _prefs;
    await prefs.remove(whatsAppPhoneKey);
    await prefs.remove(archivesKey);
    await prefs.remove(_lastNoticeKey);
    await prefs.remove(firebaseDatabaseUrlKey);
    await prefs.remove(expectedDurationKey);
    await prefs.remove(soundAlertsKey);
    await prefs.remove(adminPinKey);
    await prefs.remove('orderly_distributor_license_activated');
  }

  // --- تنبيه أسبوعي ---
  static const String _lastNoticeKey = 'weekly_notice_last_shown';

  /// آخر مرة عرض فيها التنبيه الأسبوعي (أو تاريخ بعيد إذا لم يُعرض أبداً).
  static Future<DateTime> getLastWeeklyNotice() async {
    final SharedPreferences prefs = await _prefs;
    final String? raw = prefs.getString(_lastNoticeKey);
    if (raw == null || raw.trim().isEmpty) {
      return DateTime(2000);
    }
    final DateTime? parsed = DateTime.tryParse(raw);
    return parsed ?? DateTime(2000);
  }

  /// تسجيل أن التنبيه الأسبوعي عُرض في [when].
  static Future<void> setLastWeeklyNotice(DateTime when) async {
    final SharedPreferences prefs = await _prefs;
    await prefs.setString(_lastNoticeKey, when.toIso8601String());
  }
}
