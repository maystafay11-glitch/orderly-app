// stub لـ permission_handler على Flutter Web
// على الويب، المتصفح يتعامل مع أذونات الكاميرا بنفسه عند أول استخدام
// هذا الملف يُوفّر واجهة متوافقة بدون تنفيذ فعلي

/// نوع وهمي يُمثّل Permission على الويب
class Permission {
  static final _PermissionSlot camera = _PermissionSlot._();
  static final _PermissionSlot microphone = _PermissionSlot._();
}

class _PermissionSlot {
  const _PermissionSlot._();

  /// على الويب: نُرجع granted دائماً — المتصفح سيطلب الإذن عند الحاجة
  Future<PermissionStatus> request() async => PermissionStatus.granted;

  Future<PermissionStatus> get status async => PermissionStatus.granted;
}

/// حالة الإذن
enum PermissionStatus {
  denied,
  granted,
  restricted,
  limited,
  permanentlyDenied,
}

extension PermissionStatusExtension on PermissionStatus {
  bool get isGranted => this == PermissionStatus.granted;
  bool get isPermanentlyDenied =>
      this == PermissionStatus.permanentlyDenied;
  bool get isDenied => this == PermissionStatus.denied;
}

/// فتح إعدادات التطبيق — لا معنى له على الويب
Future<bool> openAppSettings() async => false;
