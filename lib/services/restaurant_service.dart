/// خدمة معرّف المطعم الفريد (Restaurant ID) لعزل البيانات في نظام Multi-tenant.
///
/// عند أول تشغيل للتطبيق، يُولَّد [restaurantId] عشوائياً ويُخزَّن دائماً.
/// يُستخدم هذا المعرّف كـ namespace في Firebase وفي SharedPreferences
/// لضمان أن بيانات كل مطعم معزولة تماماً عن غيره.
///
/// **مثال على هيكل Firebase:**
/// ```
/// restaurants/{restaurantId}/drivers/{pin}/...
/// restaurants/{restaurantId}/orders/{orderId}/...
/// ```
library;

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

class RestaurantService {
  const RestaurantService._();

  static const String _restaurantIdKey = 'orderly.restaurant_id';
  static const String _restaurantNameKey = 'orderly.restaurant_name';

  static final Uuid _uuid = const Uuid();

  /// الـ ID المُحمَّل في الذاكرة (يُعيَّن عند أول استدعاء لـ [init]).
  static String _cachedId = '';

  /// اسم المطعم المُخزَّن (اختياري — للعرض فقط).
  static String _cachedName = '';

  /// تهيئة الخدمة: يُولَّد ID جديد إذا لم يكن موجوداً، ويُخزَّن.
  ///
  /// يجب استدعاء هذه الدالة مرة واحدة في [main] قبل [runApp].
  static Future<void> init() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    String? saved = prefs.getString(_restaurantIdKey);
    if (saved == null || saved.trim().isEmpty) {
      saved = _uuid.v4().replaceAll('-', '').substring(0, 16).toUpperCase();
      await prefs.setString(_restaurantIdKey, saved);
      debugPrint('[RestaurantService] Generated new restaurantId: $saved');
    }
    _cachedId = saved;
    _cachedName = prefs.getString(_restaurantNameKey) ?? '';
    debugPrint('[RestaurantService] Loaded restaurantId: $_cachedId');
  }

  /// المعرّف الفريد للمطعم (16 حرفاً).
  ///
  /// يجب استدعاء [init] أولاً. إذا لم يُستدعَ، يُرجع سلسلة فارغة
  /// ولا يُفعَّل أي ربط سحابي لمنع التداخل بين المطاعم.
  static String get restaurantId => _cachedId;

  /// اسم المطعم للعرض في الواجهة.
  static String get restaurantName => _cachedName;

  /// هل تمت التهيئة بنجاح؟
  static bool get isInitialized => _cachedId.isNotEmpty;

  /// تحديث اسم المطعم (اختياري).
  static Future<void> setRestaurantName(String name) async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    _cachedName = name.trim();
    await prefs.setString(_restaurantNameKey, _cachedName);
  }

  /// إعادة توليد ID جديد (للاستخدام عند نقل التطبيق لمطعم آخر — خطير!).
  ///
  /// يؤدي هذا إلى فقدان التزامن مع بيانات Firebase القديمة.
  static Future<String> regenerateId() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    final String newId =
        _uuid.v4().replaceAll('-', '').substring(0, 16).toUpperCase();
    _cachedId = newId;
    await prefs.setString(_restaurantIdKey, newId);
    debugPrint('[RestaurantService] Regenerated restaurantId: $newId');
    return newId;
  }

  /// نص مختصر للعرض في الإعدادات (أول 8 أحرف فقط).
  static String get shortId {
    if (_cachedId.length >= 8) return _cachedId.substring(0, 8);
    return _cachedId;
  }
}
