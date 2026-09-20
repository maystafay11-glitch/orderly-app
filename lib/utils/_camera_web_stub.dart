// نسخة المنصات الأصلية (Android/iOS/الكمبيوتر) من فحص بيئة الكاميرا.
//
// لا يوجد متصفح هنا: أذونات الكاميرا تُدار عبر `permission_handler`،
// وتشغيل الكاميرا عبر مكتبة `camera` الأصلية.
import 'package:orderly_app/utils/camera_web_models.dart';

/// على المنصات الأصلية لا يوجد سياق متصفح ولا Permissions API، لذلك نُعيد
/// بيئة تسمح بمحاولة تشغيل الكاميرا فوراً (كما كان سلوك التطبيق سابقاً).
Future<CameraEnvironment> probeCameraEnvironment() async {
  return const CameraEnvironment(
    isSecureContext: true,
    hasMediaDevices: true,
    permissionState: CameraPermissionState.granted,
  );
}
