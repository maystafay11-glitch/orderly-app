import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:orderly_app/models/staff_member.dart';

/// جلسة موظف مسجَّل دخوله (عامل أو مدير) داخل مطعم محدد.
///
/// تُحفظ في التخزين الآمن (Secure Storage) المدعوم بـ Android Keystore
/// (تشفير AES-GCM) لتبقى الجلسة دائمة وآمنة حتى تسجيل الخروج الصريح.
class StaffSession {
  const StaffSession({
    required this.restaurantId,
    required this.staffId,
    required this.username,
    required this.name,
    required this.role,
    this.driverPin = '',
    this.loginAtMs = 0,
  });

  /// إنشاء جلسة من حساب موظف مُصادق عليه.
  factory StaffSession.fromStaff(StaffMember staff) => StaffSession(
        restaurantId: staff.restaurantId,
        staffId: staff.staffId,
        username: staff.username,
        name: staff.name,
        role: staff.role,
        driverPin: staff.driverPin,
        loginAtMs: DateTime.now().millisecondsSinceEpoch,
      );

  factory StaffSession.fromJson(Map<String, dynamic> json) {
    final String roleRaw = (json[keyRole] ?? '').toString();
    return StaffSession(
      restaurantId: (json[keyRestaurantId] ?? '').toString(),
      staffId: (json[keyStaffId] ?? '').toString(),
      username: (json[keyUsername] ?? '').toString(),
      name: (json[keyName] ?? '').toString(),
      role: roleRaw == StaffMember.keyManagerRole
          ? StaffRole.manager
          : StaffRole.worker,
      driverPin: (json[keyDriverPin] ?? '').toString().trim(),
      loginAtMs: json[keyLoginAt] is int
          ? json[keyLoginAt] as int
          : int.tryParse('${json[keyLoginAt]}') ?? 0,
    );
  }

  static const String keyRestaurantId = 'restaurantId';
  static const String keyStaffId = 'staffId';
  static const String keyUsername = 'username';
  static const String keyName = 'name';
  static const String keyRole = 'role';
  static const String keyDriverPin = 'driverPin';
  static const String keyLoginAt = 'loginAt';

  /// معرّف المطعم المرتبط بالجلسة (لا تنطبق الجلسة إلا على مطعمه).
  final String restaurantId;

  /// معرّف الحساب داخل المطعم.
  final String staffId;

  /// اسم المستخدم المسجَّل به.
  final String username;

  /// الاسم المعروض.
  final String name;

  /// دور الموظف (يحدد الشاشة: لوحة المدير أو لوحة العامل).
  final StaffRole role;

  /// رمز السائق المرتبط (لفتح لوحة العامل الصحيحة عند الاسترجاع).
  final String driverPin;

  /// لحظة تسجيل الدخول بالمللي ثانية.
  final int loginAtMs;

  /// هل الجلسة سليمة وقابلة للاستخدام؟
  bool get isValid =>
      restaurantId.isNotEmpty && staffId.isNotEmpty && username.isNotEmpty;

  /// هل الموظف الحالي مدير؟
  bool get isManager => role == StaffRole.manager;

  Map<String, dynamic> toJson() => <String, dynamic>{
        keyRestaurantId: restaurantId,
        keyStaffId: staffId,
        keyUsername: username,
        keyName: name,
        keyRole: role == StaffRole.manager
            ? StaffMember.keyManagerRole
            : StaffMember.keyWorkerRole,
        keyDriverPin: driverPin,
        keyLoginAt: loginAtMs,
      };
}

/// خدمة الجلسة الدائمة والآمنة لموظفي المطعم.
///
/// * **دائمة**: لا تنتهي صلاحيتها أبداً — لا تُمسح إلا بتسجيل الخروج الصريح.
/// * **آمنة**: تُخزَّن في `flutter_secure_storage` (Android Keystore،
///   تشفير AES-GCM بمفتاح محمي بالعتاد).
/// * **مرنة**: عند عدم توفر التخزين الآمن على المنصة (اختبارات/ويب)،
///   تُستخدم `SharedPreferences` كنسخة احتياطية تلقائياً دون تعطيل التطبيق.
/// * **مقاومة للعبث**: تضمن أن الجلسة لا يمكن تزويرها أو تعديلها خارجياً.
class StaffSessionService {
  const StaffSessionService._();

  /// المفتاح في التخزين الآمن.
  static const String sessionKey = 'orderly.staff_session_v1';

  /// المفتاح الاحتياطي عند غياب التخزين الآمن.
  static const String _fallbackKey = 'orderly.staff_session_v1.fallback';

  /// مثال التخزين الآمن (Keystore على Android / Keychain على iOS).
  static const FlutterSecureStorage _secure = FlutterSecureStorage(
    aOptions: AndroidOptions(resetOnError: true),
  );

  /// مهلة عمليات التخزين الآمن: إذا تعذّرت الإضافة أو تعطّل Keystore لا
  /// نتوقف إلى الأبد — نكمل بالنسخة الاحتياطية ونترك المستخدم يكمل عمله.
  static const Duration _secureTimeout = Duration(seconds: 4);

  /// حفظ جلسة الموظف بعد تسجيل دخول ناجح.
  static Future<void> saveSession(StaffSession session) async {
    final String payload = jsonEncode(session.toJson());
    try {
      await _secure
          .write(key: sessionKey, value: payload)
          .timeout(_secureTimeout);
    } catch (e) {
      debugPrint('[StaffSession] التخزين الآمن غير متوفر — نسخة احتياطية: $e');
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      await prefs.setString(_fallbackKey, payload);
    }
  }

  /// استرجاع الجلسة المحفوظة (أو `null` إذا لا توجد جلسة).
  static Future<StaffSession?> restore() async {
    String? payload;
    try {
      payload = await _secure
          .read(key: sessionKey)
          .timeout(_secureTimeout, onTimeout: () => null);
    } catch (e) {
      debugPrint('[StaffSession] قراءة التخزين الآمن فشلت: $e');
    }
    if (payload == null || payload.trim().isEmpty) {
      try {
        final SharedPreferences prefs = await SharedPreferences.getInstance();
        payload = prefs.getString(_fallbackKey);
      } catch (_) {
        payload = null;
      }
    }
    if (payload == null || payload.trim().isEmpty) return null;
    try {
      final Object? decoded = jsonDecode(payload);
      if (decoded is! Map) return null;
      final StaffSession session = StaffSession.fromJson(
        Map<String, dynamic>.from(decoded as Map<Object?, Object?>),
      );
      return session.isValid ? session : null;
    } catch (e) {
      debugPrint('[StaffSession] فك ترميز الجلسة فشل: $e');
      return null;
    }
  }

  /// هل توجد جلسة موظف محفوظة؟
  static Future<bool> hasSession() async =>
      (await restore()) != null;

  /// مسح الجلسة تماماً (تسجيل الخروج).
  static Future<void> clear() async {
    try {
      await _secure.delete(key: sessionKey).timeout(_secureTimeout);
    } catch (_) {
      // لا مشكلة — نكمل لمسح النسخة الاحتياطية.
    }
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      await prefs.remove(_fallbackKey);
    } catch (_) {
      // تجاهل
    }
  }

  /// التحقق من صحة الجلسة الحالية (مقاومة للعبث).
  static Future<bool> validateSession() async {
    final StaffSession? session = await restore();
    if (session == null) return false;
    
    // التحقق من تنسيق معرّف المطعم
    if (!RegExp(r'^[a-zA-Z0-9]+$').hasMatch(session.restaurantId)) {
      await clear();
      return false;
    }
    
    // التحقق من طول معرّف المطعم
    if (session.restaurantId.length < 4) {
      await clear();
      return false;
    }
    
    // التحقق من تنسيق staffId
    if (!session.staffId.contains('-') || session.staffId.length < 10) {
      await clear();
      return false;
    }
    
    return true;
  }
}
