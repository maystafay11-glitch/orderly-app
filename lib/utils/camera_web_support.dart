// واجهة عامة لفحص بيئة الكاميرا مع اختيار التنفيذ بحسب المنصة:
//   * الويب (`dart.library.js_interop` متاح): `_camera_web_impl.dart`
//   * غير ذلك (Android/iOS/الكمبيوتر): `_camera_web_stub.dart`
//
// بهذه الطريقة تستدعي شاشة المسح دالة واحدة فقط، ولا تحتاج أي شرط إضافي.
import 'package:orderly_app/utils/_camera_web_stub.dart'
    if (dart.library.js_interop)
        'package:orderly_app/utils/_camera_web_impl.dart' as impl;

import 'package:orderly_app/utils/camera_web_models.dart';

export 'package:orderly_app/utils/camera_web_models.dart';

/// فحص بيئة الكاميرا قبل التشغيل:
/// السياق الآمن (https)، دعم المتصفح، وحالة الإذن المحفوظة.
///
/// لا يفتح الكاميرا ولا يطلب الإذن؛ للتشغيل استخدم شاشة المسح
/// (`CameraScanScreen`) التي تتعامل مع الطلب والأخطاء.
Future<CameraEnvironment> probeCameraEnvironment() =>
    impl.probeCameraEnvironment();
