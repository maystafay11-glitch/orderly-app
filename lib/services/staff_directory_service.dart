/// خدمة دليل حسابات الموظفين (العمال والمدراء) معزولة بمعرّف المطعم.
///
/// **هيكل التخزين (محلياً وسحابياً بنفس المسارات):**
/// ```
/// restaurants/{restaurant_id}/staff/{staff_id}   ← في Firebase Realtime DB
/// orderly.staff_directory → { "<rid>": { "<staffId>": {...} } }  ← محلياً
/// ```
///
/// **ضمانات النظام:**
/// 1. تسجيل الدخول يتطلب (معرّف المطعم + اسم المستخدم + كلمة المرور أو PIN).
/// 2. يُسمح بتشابه الأسماء وكلمات المرور الافتراضية بين مطعمين مختلفين،
///    لأن البحث يقتصر حصراً على الحسابات الموجودة تحت معرّف المطعم المدخل.
/// 3. كلمات المرور لا تُخزَّن نصاً أبداً — بصمة SHA-256 مع ملح عشوائي.
/// 4. تزويد تلقائي: حساب مدير (اسم المستخدم `manager` وكلمة المرور = رمز
///    المدير الحالي) وحساب عامل لكل سائق (كلمة مرور افتراضية `1234`).
library;

import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'package:orderly_app/models/driver.dart';
import 'package:orderly_app/models/staff_member.dart';
import 'package:orderly_app/services/app_settings.dart';
import 'package:orderly_app/services/driver_storage.dart';

/// نتيجة محاولة مصادقة/تسجيل حساب موظف.
class StaffAuthResult {
  const StaffAuthResult({required this.success, this.staff, this.message});

  factory StaffAuthResult.success(StaffMember staff, [String? message]) =>
      StaffAuthResult(success: true, staff: staff, message: message);

  factory StaffAuthResult.failure(String message) =>
      StaffAuthResult(success: false, message: message);

  final bool success;
  final StaffMember? staff;
  final String? message;
}

class StaffDirectoryService {
  const StaffDirectoryService._();

  /// مفتاح الدليل المحلي في SharedPreferences (مقسّم حسب معرّف المطعم).
  static const String directoryKey = 'orderly.staff_directory';

  /// اسم المستخدم الافتراضي لحساب المدير.
  static const String defaultManagerUsername = 'manager';

  /// الاسم المعروض لحساب المدير الافتراضي.
  static const String defaultManagerName = 'مدير المطعم';

  /// كلمة المرور الافتراضية للعمال عند التزويد التلقائي.
  /// تتطابق عادةً بين المطاعم المختلفة — وهذا مقصود وآمن لأن البحث
  /// مرتبط حصراً بمعرّف المطعم المدخل عند تسجيل الدخول.
  static const String defaultWorkerPassword = '1234';

  /// رابط قاعدة بيانات اختياري يُخبَز في التطبيق عند البناء (للموزّع SaaS).
  /// يُستخدم فقط إذا لم يُدخل المدير رابطاً في شاشة الإعدادات.
  /// اتركه فارغاً لتعتمد الخدمة على الرابط المُدخل في الإعدادات فقط.
  static const String defaultDatabaseUrl = '';

  static Future<SharedPreferences> get _prefs =>
      SharedPreferences.getInstance();

  /// مسار الحساب داخل قاعدة البيانات (للعرض والتوثيق).
  static String staffPath(String restaurantId, String staffId) =>
      'restaurants/${_normalizeRid(restaurantId)}/staff/$staffId';

  static String _normalizeRid(String raw) =>
      StaffMember.normalizeRestaurantId(raw);

  /// قراءة رابط قاعدة البيانات (الإعدادات أولاً ثم الرابط المخبوز).
  static Future<String> resolveDatabaseUrl() async {
    final String configured = await AppSettings.getFirebaseDatabaseUrl();
    if (configured.isNotEmpty) return configured;
    return defaultDatabaseUrl;
  }

  // ─── الدليل المحلي (مقسّم حسب معرّف المطعم) ───────────────────────────────

  /// قراءة الدليل الكامل: { معرف_المطعم: { معرف_الحساب: بيانات } }.
  static Future<Map<String, Map<String, Map<String, dynamic>>>> _loadAll() async {
    final SharedPreferences prefs = await _prefs;
    final String? raw = prefs.getString(directoryKey);
    if (raw == null || raw.trim().isEmpty) {
      return <String, Map<String, Map<String, dynamic>>>{};
    }
    try {
      final Object? decoded = jsonDecode(raw);
      if (decoded is! Map) {
        return <String, Map<String, Map<String, dynamic>>>{};
      }
      return decoded.map(
        (Object? rid, Object? bucket) => MapEntry<String,
            Map<String, Map<String, dynamic>>>(
          rid.toString(),
          bucket is Map
              ? bucket.map(
                  (Object? id, Object? account) => MapEntry<String,
                      Map<String, dynamic>>(
                    id.toString(),
                    account is Map
                        ? Map<String, dynamic>.from(account)
                        : <String, dynamic>{},
                  ),
                )
              : <String, Map<String, dynamic>>{},
        ),
      );
    } catch (_) {
      return <String, Map<String, Map<String, dynamic>>>{};
    }
  }

  /// حفظ الدليل الكامل محلياً.
  static Future<void> _saveAll(
    Map<String, Map<String, Map<String, dynamic>>> all,
  ) async {
    final SharedPreferences prefs = await _prefs;
    if (all.isEmpty) {
      await prefs.remove(directoryKey);
      return;
    }
    await prefs.setString(directoryKey, jsonEncode(all));
  }

  /// تحميل حسابات موظفي مطعم محدد فقط (عزل تام بين المطاعم).
  static Future<List<StaffMember>> loadStaff(String restaurantId) async {
    final String rid = _normalizeRid(restaurantId);
    if (rid.isEmpty) return <StaffMember>[];
    final Map<String, Map<String, Map<String, dynamic>>> all = await _loadAll();
    final Map<String, Map<String, dynamic>> bucket =
        all[rid] ?? const <String, Map<String, dynamic>>{};
    final List<StaffMember> staff = bucket.values
        .where((Map<String, dynamic> json) => json.isNotEmpty)
        .map(StaffMember.fromJson)
        .toList();
    staff.sort((StaffMember a, StaffMember b) {
      if (a.isManager != b.isManager) return a.isManager ? -1 : 1;
      return a.name.compareTo(b.name);
    });
    return staff;
  }

  /// حفظ (إضافة/تحديث) حسابات لمطعم محدد مع دفعها سحابياً اختيارياً.
  static Future<void> saveStaff(
    String restaurantId,
    List<StaffMember> staff, {
    bool pushToCloud = true,
  }) async {
    final String rid = _normalizeRid(restaurantId);
    if (rid.isEmpty) return;
    final Map<String, Map<String, Map<String, dynamic>>> all = await _loadAll();
    final Map<String, Map<String, dynamic>> bucket = Map<String,
        Map<String, dynamic>>.of(all[rid] ?? <String, Map<String, dynamic>>{});
    for (final StaffMember member in staff) {
      bucket[member.staffId] = member.toJson();
    }
    all[rid] = bucket;
    await _saveAll(all);
    if (pushToCloud) {
      for (final StaffMember member in staff) {
        await _pushToCloud(rid, member);
      }
    }
  }

  /// البحث عن حساب بالمعرف داخل مطعم محدد.
  static Future<StaffMember?> findById(
    String restaurantId,
    String staffId,
  ) async {
    final List<StaffMember> staff = await loadStaff(restaurantId);
    for (final StaffMember member in staff) {
      if (member.staffId == staffId) return member;
    }
    return null;
  }

  /// البحث عن حساب باسم المستخدم (أو الاسم المعروض) داخل مطعم محدد فقط.
  static Future<StaffMember?> findByUsername(
    String restaurantId,
    String usernameOrName,
  ) async {
    final String needle = StaffMember.normalizeUsername(usernameOrName);
    if (needle.isEmpty) return null;
    final List<StaffMember> staff = await loadStaff(restaurantId);
    for (final StaffMember member in staff) {
      if (StaffMember.normalizeUsername(member.username) == needle ||
          StaffMember.normalizeUsername(member.name) == needle) {
        return member;
      }
    }
    return null;
  }



  // ─── التسجيل وتغيير كلمات المرور ──────────────────────────────────────────

  /// تسجيل حساب موظف جديد داخل مطعم محدد.
  ///
  /// * اسم المستخدم فريد **داخل المطعم الواحد فقط** — لا مانع من تكراره
  ///   في مطعم آخر (المعرّفان مختلفان → مساران مختلفان تماماً).
  /// * كلمة المرور تُخزَّن بصمة مشفرة فقط.
  static Future<StaffAuthResult> registerStaff({
    required String restaurantId,
    required String name,
    required String username,
    required String password,
    StaffRole role = StaffRole.worker,
    String pin = '',
    String driverPin = '',
    bool autoProvisioned = false,
  }) async {
    final String rid = _normalizeRid(restaurantId);
    final String displayName = name.trim();
    final String uname = username.trim();
    final String secret = password.trim();

    if (rid.isEmpty) {
      return StaffAuthResult.failure('معرّف المطعم مطلوب لإنشاء الحساب.');
    }
    if (displayName.isEmpty) {
      return StaffAuthResult.failure('يرجى إدخال اسم الموظف.');
    }
    if (uname.isEmpty) {
      return StaffAuthResult.failure('يرجى إدخال اسم المستخدم.');
    }
    if (secret.length < 4) {
      return StaffAuthResult.failure(
          'كلمة المرور يجب أن تتكون من 4 خانات على الأقل.');
    }

    final StaffMember? existing = await findByUsername(rid, uname);
    if (existing != null) {
      return StaffAuthResult.failure(
          'اسم المستخدم «$uname» مستخدم بالفعل داخل هذا المطعم.');
    }

    final StaffMember member = StaffMember(
      staffId: StaffMember.buildStaffId(rid, uname),
      restaurantId: rid,
      name: displayName,
      username: uname,
      role: role,
      pin: pin.trim(),
      driverPin: driverPin.trim(),
      active: true,
      autoProvisioned: autoProvisioned,
      createdAtMs: DateTime.now().millisecondsSinceEpoch,
    ).withNewPassword(secret);

    await saveStaff(rid, <StaffMember>[member]);
    return StaffAuthResult.success(member);
  }

  /// تعيين كلمة مرور جديدة لحساب (يحوّله لحساب مُدار يدوياً).
  static Future<StaffAuthResult> setPassword(
    String restaurantId,
    String staffId,
    String newPassword, {
    String? newPin,
  }) async {
    final String rid = _normalizeRid(restaurantId);
    final String secret = newPassword.trim();
    if (rid.isEmpty) {
      return StaffAuthResult.failure('معرّف المطعم مطلوب.');
    }
    if (secret.length < 4) {
      return StaffAuthResult.failure(
          'كلمة المرور يجب أن تتكون من 4 خانات على الأقل.');
    }
    final StaffMember? existing = await findById(rid, staffId);
    if (existing == null) {
      return StaffAuthResult.failure('الحساب غير موجود لهذا المطعم.');
    }
    StaffMember updated = existing
        .withNewPassword(secret)
        .copyWith(autoProvisioned: false);
    if (newPin != null) {
      updated = updated.copyWith(pin: newPin.trim());
    }
    await saveStaff(rid, <StaffMember>[updated]);
    return StaffAuthResult.success(updated, 'تم تحديث كلمة المرور بنجاح.');
  }

  // ─── التزويد التلقائي (Manager + Workers) ─────────────────────────────────

  /// ضمان جاهزية حسابات تسجيل الدخول لمطعم محدد:
  /// 1. حساب المدير: اسم المستخدم [defaultManagerUsername] وكلمة المرور =
  ///    رمز المدير الحالي (يتزامن تلقائياً عند تغيير الرمز في الإعدادات).
  /// 2. حساب عامل لكل سائق: اسم المستخدم = اسم السائق، كلمة المرور الافتراضية
  ///    [defaultWorkerPassword]، ورمز PIN = رمز السائق (1001-1030).
  /// 3. حذف الحسابات التلقائية لعمال حُذفوا من القائمة.
  /// 4. دفع كل التغييرات سحابياً عند توفر رابط قاعدة البيانات.
  ///
  /// الدالة idempotent (آمنة للاستدعاء المتكرر) ولا تلمس الحسابات المُدارة
  /// يدوياً (autoProvisioned = false).
  static Future<void> ensureProvisioned(String restaurantId) async {
    final String rid = _normalizeRid(restaurantId);
    if (rid.isEmpty) return;
    try {
      final Map<String, Map<String, Map<String, dynamic>>> all =
          await _loadAll();
      final Map<String, Map<String, dynamic>> bucket = Map<String,
          Map<String, dynamic>>.of(
          all[rid] ?? <String, Map<String, dynamic>>{});
      bool changed = false;
      final int now = DateTime.now().millisecondsSinceEpoch;

      // ① حساب المدير — كلمة المرور تتبع رمز المدير الحالي.
      final String adminPin = await AppSettings.getAdminPin();
      final String managerId =
          StaffMember.buildStaffId(rid, defaultManagerUsername);
      final Object? managerRaw = bucket[managerId];
      final StaffMember? existingManager =
          _memberFromRaw(managerRaw);

      if (existingManager == null) {
        bucket[managerId] = StaffMember(
          staffId: managerId,
          restaurantId: rid,
          name: defaultManagerName,
          username: defaultManagerUsername,
          role: StaffRole.manager,
          active: true,
          autoProvisioned: true,
          createdAtMs: now,
        ).withNewPassword(adminPin).toJson();
        changed = true;
      } else if (existingManager.autoProvisioned &&
          !existingManager.verifyPassword(adminPin)) {
        bucket[managerId] = existingManager.withNewPassword(adminPin).toJson();
        changed = true;
      }

      // ② حسابات العمال من قائمة السائقين الحالية.
      final List<Driver> drivers = await DriverStorage.loadDrivers();
      final Set<String> activeWorkerKeys = <String>{};
      for (final Driver driver in drivers) {
        final String uname = driver.name.trim();
        if (uname.isEmpty) continue;
        activeWorkerKeys.add(StaffMember.normalizeUsername(uname));
        final String workerId = StaffMember.buildStaffId(rid, uname);
        final StaffMember? existing = _memberFromRaw(bucket[workerId]);

        if (existing == null) {
          bucket[workerId] = StaffMember(
            staffId: workerId,
            restaurantId: rid,
            name: uname,
            username: uname,
            role: StaffRole.worker,
            pin: driver.pin,
            driverPin: driver.pin,
            active: true,
            autoProvisioned: true,
            createdAtMs: now,
          ).withNewPassword(defaultWorkerPassword).toJson();
          changed = true;
        } else if (existing.pin != driver.pin ||
            existing.driverPin != driver.pin) {
          bucket[workerId] = existing
              .copyWith(pin: driver.pin, driverPin: driver.pin, active: true)
              .toJson();
          changed = true;
        }
      }

      // ③ حذف حسابات العمال التلقائية التي حُذف عاملها من القائمة.
      final List<String> orphanIds = <String>[];
      bucket.forEach((String id, Map<String, dynamic> json) {
        if (json.isEmpty) return;
        final StaffMember member = StaffMember.fromJson(json);
        if (member.isWorker &&
            member.autoProvisioned &&
            !activeWorkerKeys
                .contains(StaffMember.normalizeUsername(member.username))) {
          orphanIds.add(id);
        }
      });
      for (final String orphanId in orphanIds) {
        bucket.remove(orphanId);
        changed = true;
        await _deleteFromCloud(rid, orphanId);
      }

      if (changed) {
        all[rid] = bucket;
        await _saveAll(all);
        for (final Map<String, dynamic> json in bucket.values) {
          if (json.isEmpty) continue;
          await _pushToCloud(rid, StaffMember.fromJson(json));
        }
      }
    } catch (e) {
      debugPrint('[StaffDirectory] ensureProvisioned خطأ: $e');
    }
  }

  /// تحويل بيانات خام إلى حساب بأمان (يرجع null إذا كانت فارغة/تالفة).
  static StaffMember? _memberFromRaw(Object? raw) {
    if (raw is! Map || (raw as Map<Object?, Object?>).isEmpty) return null;
    try {
      return StaffMember.fromJson(
        Map<String, dynamic>.from(raw as Map<Object?, Object?>),
      );
    } catch (_) {
      return null;
    }
  }

  // ─── المصادقة (تسجيل الدخول) ──────────────────────────────────────────────

  /// مصادقة موظف: (معرّف المطعم + اسم المستخدم + كلمة المرور أو PIN).
  ///
  /// **آلية العزل:** البحث يقتصر حصراً على الدليل الفرعي الخاص بمعرّف
  /// المطعم المدخل — حتى لو تطابق الاسم وكلمة المرور حرفياً بين مطعمين،
  /// لا يمكن للحساب في مطعم «ألف» أن يفتح جلسة لمطعم «باء».
  ///
  /// **آلية المزامنة:** إذا كان رابط قاعدة البيانات مضبوطاً، تُجلب الحسابات
  /// السحابية أولاً (السحابة هي المرجع) ويُدمج بها الدليل المحلي، مع
  /// الاحتفاظ بالحسابات المحلية غير المرفوعة بعد (وضع Offline-First).
  static Future<StaffAuthResult> authenticate({
    required String restaurantId,
    required String username,
    required String secret,
  }) async {
    final String rid = _normalizeRid(restaurantId);
    final String uname = StaffMember.normalizeUsername(username);
    final String pass = secret.trim();

    // تحقق صارم من معرّف المطعم
    if (rid.isEmpty) {
      return StaffAuthResult.failure(
          'يرجى إدخال معرّف المطعم (Restaurant ID).');
    }
    
    // تحقق من تنسيق معرّف المطعم (يجب أن يحتوي على أحرف وأرقام فقط)
    if (!RegExp(r'^[a-zA-Z0-9]+$').hasMatch(rid)) {
      return StaffAuthResult.failure(
          'معرّف المطعم يجب أن يحتوي على أحرف وأرقام فقط (بدون مسافات أو رموز خاصة).');
    }
    
    // تحقق من طول معرّف المطعم
    if (rid.length < 4) {
      return StaffAuthResult.failure(
          'معرّف المطعم قصير جداً. يجب أن يكون 4 أحرف على الأقل.');
    }

    if (uname.isEmpty) {
      return StaffAuthResult.failure('يرجى إدخال اسم المستخدم.');
    }
    if (pass.isEmpty) {
      return StaffAuthResult.failure('يرجى إدخال كلمة المرور أو الرمز السري.');
    }

    List<StaffMember> staff = await loadStaff(rid);

    // مزامنة من السحابة إن كان الاتصال مضبوطاً (لضمان الحداثة).
    final Map<String, Map<String, dynamic>>? remote =
        await _fetchStaffFromCloud(rid);
    if (remote != null) {
      staff = await _mergeRemoteIntoLocal(rid, remote);
    }

    if (staff.isEmpty) {
      return StaffAuthResult.failure(
        'لا توجد حسابات موظفين لهذا المعرّف ($rid). '
        'تأكد من صحة معرّف المطعم أو من إعداد رابط قاعدة البيانات.',
      );
    }

    StaffMember? match;
    for (final StaffMember member in staff) {
      if (StaffMember.normalizeUsername(member.username) == uname ||
          StaffMember.normalizeUsername(member.name) == uname) {
        match = member;
        break;
      }
    }

    if (match == null || !match.active) {
      return StaffAuthResult.failure(
        'بيانات الدخول غير صحيحة لهذا المطعم. '
        'تحقق من اسم المستخدم وكلمة المرور/PIN.',
      );
    }

    final bool passwordOk = match.verifyPassword(pass);
    final bool pinOk = match.pin.isNotEmpty && match.pin == pass;
    if (!passwordOk && !pinOk) {
      return StaffAuthResult.failure('كلمة المرور أو الرمز السري غير صحيح.');
    }

    return StaffAuthResult.success(match, 'أهلاً بك يا ${match.name}');
  }

  // ─── المزامنة السحابية (Firebase REST — Offline-First) ────────────────────

  /// جلب حسابات مطعم من السحابة. خريطة فارغة = نجاح اتصال بلا حسابات.
  /// `null` يعني فشل الاتصال — عندها يُستخدم الدليل المحلي كما هو.
  static Future<Map<String, Map<String, dynamic>>?> _fetchStaffFromCloud(
    String rid,
  ) async {
    final String url = await resolveDatabaseUrl();
    if (url.isEmpty) return null;
    try {
      final http.Response response = await http
          .get(
            Uri.parse(
              '$url/restaurants/${Uri.encodeComponent(rid)}/staff.json',
            ),
          )
          .timeout(const Duration(seconds: 8));
      if (response.statusCode != 200) return null;
      final Object? decoded = jsonDecode(response.body);
      if (decoded == null) {
        // المطعم غير موجود سحابياً بعد — نجاح اتصال بدليل فارغ.
        return <String, Map<String, dynamic>>{};
      }
      if (decoded is! Map) return null;
      return decoded.map(
        (Object? id, Object? account) => MapEntry<String, Map<String, dynamic>>(
          id.toString(),
          account is Map
              ? Map<String, dynamic>.from(account)
              : <String, dynamic>{},
        ),
      );
    } catch (e) {
      debugPrint('[StaffDirectory] fetchStaffFromCloud خطأ: $e');
      return null;
    }
  }

  /// دمج الحسابات السحابية مع الدليل المحلي (السحابة هي المرجع للمعتمد).
  static Future<List<StaffMember>> _mergeRemoteIntoLocal(
    String rid,
    Map<String, Map<String, dynamic>> remote,
  ) async {
    final Map<String, Map<String, Map<String, dynamic>>> all = await _loadAll();
    final Map<String, Map<String, dynamic>> bucket = Map<String,
        Map<String, dynamic>>.of(
        all[rid] ?? <String, Map<String, dynamic>>{});
    bool changed = false;
    remote.forEach((String id, Map<String, dynamic> json) {
      if (json.isEmpty) return;
      final Map<String, dynamic>? local = bucket[id];
      if (local == null || jsonEncode(local) != jsonEncode(json)) {
        bucket[id] = json;
        changed = true;
      }
    });
    if (changed) {
      all[rid] = bucket;
      await _saveAll(all);
    }
    return bucket.values
        .where((Map<String, dynamic> json) => json.isNotEmpty)
        .map(StaffMember.fromJson)
        .toList();
  }

  /// رفع حساب واحد إلى السحابة (تجاهل أخطاء الشبكة بهدوء — Offline-First).
  static Future<void> _pushToCloud(String rid, StaffMember member) async {
    final String url = await resolveDatabaseUrl();
    if (url.isEmpty) return;
    try {
      final http.Response response = await http
          .put(
            Uri.parse(
              '$url/restaurants/${Uri.encodeComponent(rid)}/staff/'
              '${Uri.encodeComponent(member.staffId)}.json',
            ),
            headers: <String, String>{'Content-Type': 'application/json'},
            body: jsonEncode(member.toJson()),
          )
          .timeout(const Duration(seconds: 8));
      if (response.statusCode < 200 || response.statusCode >= 300) {
        debugPrint(
          '[StaffDirectory] pushToCloud فشل (${response.statusCode}) '
          'لـ ${member.staffId}',
        );
      }
    } catch (e) {
      debugPrint('[StaffDirectory] pushToCloud خطأ: $e');
    }
  }

  /// حذف حساب من السحابة (لتنظيف الحسابات اليتيمة التلقائية).
  static Future<void> _deleteFromCloud(String rid, String staffId) async {
    final String url = await resolveDatabaseUrl();
    if (url.isEmpty) return;
    try {
      await http
          .delete(
            Uri.parse(
              '$url/restaurants/${Uri.encodeComponent(rid)}/staff/'
              '${Uri.encodeComponent(staffId)}.json',
            ),
          )
          .timeout(const Duration(seconds: 8));
    } catch (e) {
      debugPrint('[StaffDirectory] deleteFromCloud خطأ: $e');
    }
  }
}
