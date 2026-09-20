// نماذج مشتركة لفحص بيئة الكاميرا قبل تشغيلها.
//
// تُستخدم من تنفيذي الفحص:
//   * الويب: `_camera_web_impl.dart`
//   * المنصات الأصلية: `_camera_web_stub.dart`
// عبر الواجهة العامة في `camera_web_support.dart`، حتى تكون شاشة المسح
// مستقلة عن المنصة ولا تستورد أي مكتبة ويب على Android/iOS.

/// حالة إذن الكاميرا كما يعرفها المتصفح.
enum CameraPermissionState {
  /// المتصفح لا يوفّر Permissions API (كما في بعض إصدارات Safari) أو رفض
  /// الاستعلام عن الكاميرا؛ في هذه الحالة يعرض المتصفح نافذة الإذن عند
  /// أول محاولة تشغيل.
  unknown,

  /// لم يُحسم الإذن بعد، وسيُطلب من المستخدم عند أول استخدام للكاميرا.
  prompt,

  /// الإذن ممنوح مسبقاً لهذا الموقع، ويمكن تشغيل الكاميرا تلقائياً.
  granted,

  /// الإذن مرفوض، ولن يعرض المتصفح نافذة الطلب مرة أخرى إلا بعد تغييره
  /// من إعدادات الموقع.
  denied,
}

/// وصف بيئة تشغيل الكاميرا: هل التشغيل ممكن؟ وهل يحتاج تدخلاً من المستخدم؟
class CameraEnvironment {
  /// إنشاء وصف البيئة.
  const CameraEnvironment({
    required this.isSecureContext,
    required this.hasMediaDevices,
    required this.permissionState,
    this.blockingMessage,
  });

  /// هل الصفحة تُخدم عبر سياق آمن (https أو localhost)؟
  ///
  /// على المنصات الأصلية تكون القيمة `true` دائماً.
  final bool isSecureContext;

  /// هل يوفّر المتصفح `navigator.mediaDevices` (واجهة تشغيل الكاميرا)؟
  ///
  /// على المنصات الأصلية تكون القيمة `true` دائماً.
  final bool hasMediaDevices;

  /// حالة الإذن المحفوظة في المتصفح.
  final CameraPermissionState permissionState;

  /// رسالة عربية جاهزة للعرض عندما يستحيل تشغيل الكاميرا (سياق غير آمن أو
  /// متصفح لا يدعم الواجهة). القيمة `null` تعني أن المحاولة ممكنة.
  final String? blockingMessage;

  /// هل يمكن محاولة تشغيل الكاميرا الآن؟
  bool get isReadyForStart => blockingMessage == null;

  /// هل يحتاج التشغيل إلى نقرة صريحة من المستخدم؟
  ///
  /// متصفحات الجوال (Safari خصوصاً) تمنع تشغيل الكاميرا بدون تفاعل مباشر،
  /// لذلك نطلب نقرة عندما لا يكون الإذن ممنوحاً مسبقاً.
  bool get needsUserGesture =>
      permissionState != CameraPermissionState.granted;
}
