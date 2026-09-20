// تنفيذ فحص بيئة الكاميرا على Flutter Web.
//
// يُستورد شرطياً من `camera_web_support.dart` فقط عند توفر
// `dart.library.js_interop` (أي على الويب)، ولا يُترجم على Android/iOS.
import 'dart:async';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:web/web.dart' as web;

import 'package:orderly_app/utils/camera_web_models.dart';

/// رسالة تُعرض عندما تُخدم الصفحة عبر بروتوكول غير آمن (http).
const String _insecureContextMessage =
    'متصفحات الجوال لا تسمح بتشغيل الكاميرا إلا عبر اتصال آمن (https).\n\n'
    'افتح رابط التطبيق الذي يبدأ بـ https:// ثم أعد المحاولة.';

/// رسالة تُعرض عندما لا يوفّر المتصفح واجهة الوسائط `mediaDevices`.
const String _unsupportedBrowserMessage =
    'هذا المتصفح لا يدعم تشغيل الكاميرا من داخل صفحات الويب.\n\n'
    'استخدم Chrome أو Safari أو Edge بإصدار حديث.';

/// رسالة تُعرض عندما يكون إذن الكاميرا مرفوضاً مسبقاً في المتصفح.
const String _permissionDeniedMessage =
    'إذن الكاميرا مرفوض لهذا الموقع داخل المتصفح، ولن يعرض المتصفح نافذة '
    'الطلب مرة أخرى.\n\n'
    'فعّل الإذن من أيقونة الإعدادات/القفل بجانب عنوان الموقع، أو من '
    '«إعدادات الموقع ← الكاميرا»، ثم اضغط «إعادة المحاولة».';

/// يفحص: السياق الآمن (https)، دعم المتصفح، وحالة الإذن المحفوظة للكاميرا.
///
/// لا يطلب الإذن ولا يفتح الكاميرا؛ الفحص فقط لتحديد ما إذا كان التشغيل
/// ممكناً وما إذا كان يحتاج نقرة صريحة من المستخدم.
Future<CameraEnvironment> probeCameraEnvironment() async {
  final bool isSecureContext = web.window.isSecureContext;
  final bool hasMediaDevices = web.window.navigator.has('mediaDevices');

  // 1) لا توجد واجهة وسائط: إما سياق غير آمن أو متصفح غير داعم.
  if (!hasMediaDevices) {
    return CameraEnvironment(
      isSecureContext: isSecureContext,
      hasMediaDevices: false,
      permissionState: CameraPermissionState.unknown,
      blockingMessage: isSecureContext
          ? _unsupportedBrowserMessage
          : _insecureContextMessage,
    );
  }

  // 2) واجهة الوسائط موجودة لكن الصفحة غير آمنة → الطلب مرفوض دائماً.
  if (!isSecureContext) {
    return const CameraEnvironment(
      isSecureContext: false,
      hasMediaDevices: true,
      permissionState: CameraPermissionState.unknown,
      blockingMessage: _insecureContextMessage,
    );
  }

  // 3) قراءة حالة الإذن المحفوظة إن كان المتصفح يوفّر Permissions API.
  CameraPermissionState permissionState = CameraPermissionState.unknown;
  if (web.window.navigator.has('permissions')) {
    try {
      final JSObject descriptor =
          <String, String>{'name': 'camera'}.jsify()! as JSObject;
      final web.PermissionStatus status = await web
          .window
          .navigator
          .permissions
          .query(descriptor)
          .toDart;
      permissionState = _parsePermissionState(status.state);
    } catch (_) {
      // استعلام غير مدعوم أو مرفوض (Safari وبعض إصدارات Firefox):
      // نُكمل بحالة unknown، وسيطلب المتصفح الإذن عند التشغيل.
      permissionState = CameraPermissionState.unknown;
    }
  }

  return CameraEnvironment(
    isSecureContext: true,
    hasMediaDevices: true,
    permissionState: permissionState,
    blockingMessage: permissionState == CameraPermissionState.denied
        ? _permissionDeniedMessage
        : null,
  );
}

/// تحويل قيمة `PermissionStatus.state` النصية إلى [CameraPermissionState].
CameraPermissionState _parsePermissionState(String state) {
  switch (state) {
    case 'granted':
      return CameraPermissionState.granted;
    case 'denied':
      return CameraPermissionState.denied;
    case 'prompt':
      return CameraPermissionState.prompt;
    default:
      return CameraPermissionState.unknown;
  }
}
