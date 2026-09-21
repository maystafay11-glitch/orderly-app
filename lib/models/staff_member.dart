import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';

/// أدوار الموظفين في نظام المصادقة متعدد المطاعم.
enum StaffRole {
  /// عامل توصيل: واجهة الطلبات الميدانية المسندة إليه فقط.
  worker,

  /// مدير المطعم: صلاحية كاملة (الصندوق، الأجور، الإعدادات، إدارة الحسابات).
  manager,
}

/// حساب موظف داخل مطعم محدد (Worker / Manager Account).
///
/// **عزل المطاعم (Multi-tenant):**
/// كل حساب ينتمي حتماً إلى [restaurantId]، ويُخزَّن في المسار:
/// `restaurants/{restaurantId}/staff/{staffId}`
/// لذلك يُسمح بتكرار نفس اسم المستخدم وكلمة المرور بين مطعمين مختلفين
/// تماماً دون أي تداخل، لأن المسار يتضمن معرّف المطعم.
class StaffMember {
  const StaffMember({
    required this.staffId,
    required this.restaurantId,
    required this.name,
    required this.username,
    required this.role,
    this.passwordSalt = '',
    this.passwordHash = '',
    this.pin = '',
    this.driverPin = '',
    this.active = true,
    this.autoProvisioned = false,
    this.createdAtMs = 0,
  });

  /// إنشاء عامل من خريطة (JSON) مسترجَعة من التخزين المحلي أو Firebase.
  factory StaffMember.fromJson(Map<String, dynamic> json) {
    final String roleRaw = (json[keyRole] ?? keyWorkerRole).toString();
    return StaffMember(
      staffId: (json[keyStaffId] ?? '').toString(),
      restaurantId: (json[keyRestaurantId] ?? '').toString(),
      name: (json[keyName] ?? '').toString(),
      username: (json[keyUsername] ?? '').toString(),
      role: roleRaw == keyManagerRole ? StaffRole.manager : StaffRole.worker,
      passwordSalt: (json[keyPasswordSalt] ?? '').toString(),
      passwordHash: (json[keyPasswordHash] ?? '').toString(),
      pin: (json[keyPin] ?? '').toString().trim(),
      driverPin: (json[keyDriverPin] ?? '').toString().trim(),
      active: json[keyActive] is bool ? json[keyActive] as bool : true,
      autoProvisioned: json[keyAutoProvisioned] == true,
      createdAtMs: _readInt(json[keyCreatedAt]),
    );
  }

  // ─── مفاتيح التخزين / JSON ────────────────────────────────────────────────
  static const String keyStaffId = 'staffId';
  static const String keyRestaurantId = 'restaurantId';
  static const String keyName = 'name';
  static const String keyUsername = 'username';
  static const String keyRole = 'role';
  static const String keyWorkerRole = 'worker';
  static const String keyManagerRole = 'manager';
  static const String keyPasswordSalt = 'passwordSalt';
  static const String keyPasswordHash = 'passwordHash';
  static const String keyPin = 'pin';
  static const String keyDriverPin = 'driverPin';
  static const String keyActive = 'active';
  static const String keyAutoProvisioned = 'autoProvisioned';
  static const String keyCreatedAt = 'createdAt';

  /// المعرف الفريد للحساب داخل المطعم (مفتاح المسار في قاعدة البيانات).
  final String staffId;

  /// معرّف المطعم المالك للحساب (أساس العزل بين المطاعم).
  final String restaurantId;

  /// الاسم المعروض للعامل (قد يتطابق بين مطعمين مختلفين).
  final String name;

  /// اسم المستخدم لتسجيل الدخول (فريد داخل المطعم الواحد فقط).
  final String username;

  /// دور الحساب: عامل أو مدير.
  final StaffRole role;

  /// ملح كلمة المرور (قيمة عشوائية لكل حساب).
  final String passwordSalt;

  /// بصمة كلمة المرور (SHA-256 بعد دمج الملح — لا تُخزَّن كلمة المرور نصاً).
  final String passwordHash;

  /// رمز PIN اختياري (بديل سريع لكلمة المرور — مثل رمز السائق 1001-1030).
  final String pin;

  /// رمز السائق المرتبط بالحساب (لفتح لوحة العامل الصحيحة).
  final String driverPin;

  /// هل الحساب مفعّل؟ (الحسابات المعطلة لا تُسمح لها بالدخول).
  final bool active;

  /// هل أُنشئ الحساب تلقائياً من قائمة العمال؟ (يُحدَّث/يُحذف تلقائياً).
  final bool autoProvisioned;

  /// تاريخ الإنشاء بالمللي ثانية (0 = غير محدد).
  final int createdAtMs;

  /// هل الحساب مدير؟
  bool get isManager => role == StaffRole.manager;

  /// هل الحساب عامل توصيل؟
  bool get isWorker => role == StaffRole.worker;

  /// هل كلمة المرور مضبوطة (يوجد ملح وبصمة)؟
  bool get hasPassword => passwordSalt.isNotEmpty && passwordHash.isNotEmpty;

  /// التحقق من كلمة مرور نصية مقابل البصمة المحفوظة.
  bool verifyPassword(String plainPassword) {
    if (passwordSalt.isEmpty || passwordHash.isEmpty) return false;
    final String candidate = hashPassword(plainPassword, passwordSalt);
    return _safeEquals(candidate, passwordHash);
  }

  /// تحويل الحساب إلى خريطة قابلة للتخزين بصيغة JSON أو Firebase.
  Map<String, dynamic> toJson() => <String, dynamic>{
    keyStaffId: staffId,
    keyRestaurantId: restaurantId,
    keyName: name,
    keyUsername: username,
    keyRole: role == StaffRole.manager ? keyManagerRole : keyWorkerRole,
    keyPasswordSalt: passwordSalt,
    keyPasswordHash: passwordHash,
    keyPin: pin,
    keyDriverPin: driverPin,
    keyActive: active,
    keyAutoProvisioned: autoProvisioned,
    keyCreatedAt: createdAtMs,
  };

  /// نسخة معدَّلة من الحساب.
  StaffMember copyWith({
    String? name,
    String? username,
    StaffRole? role,
    String? passwordSalt,
    String? passwordHash,
    String? pin,
    String? driverPin,
    bool? active,
    bool? autoProvisioned,
  }) {
    return StaffMember(
      staffId: staffId,
      restaurantId: restaurantId,
      name: name ?? this.name,
      username: username ?? this.username,
      role: role ?? this.role,
      passwordSalt: passwordSalt ?? this.passwordSalt,
      passwordHash: passwordHash ?? this.passwordHash,
      pin: pin ?? this.pin,
      driverPin: driverPin ?? this.driverPin,
      active: active ?? this.active,
      autoProvisioned: autoProvisioned ?? this.autoProvisioned,
      createdAtMs: createdAtMs,
    );
  }

  /// تعيين كلمة مرور جديدة (يولِّد ملحاً جديداً ويحدّث البصمة).
  StaffMember withNewPassword(String plainPassword) {
    final String salt = generateSalt();
    return copyWith(
      passwordSalt: salt,
      passwordHash: hashPassword(plainPassword, salt),
    );
  }

  /// توليد ملح عشوائي آمن (16 حرفاً سداسي عشري).
  static String generateSalt() {
    final Random random = Random.secure();
    final List<String> parts = <String>[
      for (int i = 0; i < 8; i++) random.nextInt(256).toRadixString(16).padLeft(2, '0'),
    ];
    return parts.join();
  }

  /// بصمة كلمة المرور: SHA-256( الملح ::: كلمة المرور ).
  static String hashPassword(String plainPassword, String salt) {
    final List<int> bytes =
        utf8.encode('$salt:::${plainPassword.trim()}:::orderly');
    return sha256.convert(bytes).toString();
  }

  /// توحيد اسم المستخدم للمقارنة (يتجاهل حالة الأحرف والمسافات الزائدة).
  static String normalizeUsername(String raw) =>
      raw.trim().replaceAll(RegExp(r'\s+'), ' ').toLowerCase();

  /// مفتاح مسار فريد داخل المطعم: restaurants/{rid}/staff/{staffId}.
  ///
  /// مشتق حتمياً من (معرّف المطعم + اسم المستخدم)، لذلك:
  /// * نفس الاسم في نفس المطعم = نفس staffId دائماً (تحديث لا تكرار).
  /// * نفس الاسم في مطعمين مختلفين = معرفان مختلفان (عزل تام).
  /// * الرموز غير المدعومة في مسارات Firebase (.\$#[]/) تُستبدل.
  static String buildStaffId(String restaurantId, String username) {
    final String rid = normalizeRestaurantId(restaurantId);
    final String normalized = normalizeUsername(username);
    final String digest = sha256
        .convert(utf8.encode('$rid|$normalized|orderly-staff'))
        .toString();
    final String sanitized = normalized
        .replaceAll(RegExp(r'[^\w\u0600-\u06FF]'), '_')
        .replaceAll(RegExp(r'_+'), '_');
    final String prefix =
        sanitized.isEmpty || sanitized == '_' ? 'staff' : sanitized;
    return '${prefix.substring(0, prefix.length.clamp(0, 24))}-'
        '${digest.substring(0, 10)}';
  }

  /// توحيد معرّف المطعم للمقارنة والتخزين (حروف كبيرة بدون مسافات).
  static String normalizeRestaurantId(String raw) =>
      raw.trim().replaceAll(RegExp(r'\s+'), '').toUpperCase();

  static int _readInt(Object? value) {
    if (value is int) return value;
    return int.tryParse('$value') ?? 0;
  }

  static bool _safeEquals(String left, String right) {
    if (left.length != right.length) return false;
    var difference = 0;
    for (var index = 0; index < left.length; index++) {
      difference |= left.codeUnitAt(index) ^ right.codeUnitAt(index);
    }
    return difference == 0;
  }
}

