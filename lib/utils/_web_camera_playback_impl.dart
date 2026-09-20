// تنفيذ الويب من تحصين تشغيل معاينة الكاميرا.
//
// ملاحظة مهمة: تنفيذ mobile_scanner على الويب يُنشئ عنصر `<video>` بدون ضبط
// خصائص `playsinline` و`muted` و`autoplay`، وهذا سبب معروف لبقاء المعاينة
// سوداء على Safari في iOS (يتطلب playsinline) ولفشل `play()` التلقائي على
// أندرويد (يتطلب muted). لذلك نضبطها هنا بعد بدء الماسح.
import 'dart:js_interop';

import 'package:web/web.dart' as web;

import 'package:orderly_app/utils/web_camera_playback_state.dart';

/// يضبط خصائص عنصر فيديو الكاميرا ويعيد تشغيله إن كان متوقفاً.
Future<WebCameraPlaybackState> ensureWebCameraPlayback() async {
  try {
    final web.HTMLVideoElement? video = _findCameraVideo();
    if (video == null) {
      return WebCameraPlaybackState.videoNotFound;
    }

    // 1) الخصائص الإلزامية لتشغيل الفيديو تلقائياً داخل الصفحة.
    video
      ..muted = true
      ..autoplay = true
      ..controls = false
      ..playsInline = true
      ..setAttribute('playsinline', '')
      ..setAttribute('webkit-playsinline', '')
      ..setAttribute('muted', '');

    video.style
      ..objectFit = 'cover'
      ..width = '100%'
      ..height = '100%';

    // 2) إعادة التشغيل إن كان متوقفاً (قد ترفضها بعض المتصفحات بلا تفاعل).
    if (video.paused) {
      try {
        await video.play().toDart;
      } catch (_) {
        // نتجاهل الرفض: سيعيد المستخدم المحاولة من زر إعادة التشغيل.
      }
    }

    return video.paused
        ? WebCameraPlaybackState.paused
        : WebCameraPlaybackState.playing;
  } catch (_) {
    return WebCameraPlaybackState.videoNotFound;
  }
}

/// البحث عن عنصر الفيديو الذي يعرض بث الكاميرا.
///
/// يُفضَّل العنصر المرتبط بـ `srcObject` (بث مباشر) لأنه عنصر الماسح، وإن لم
/// يوجد نأخذ أكبر عنصر فيديو في الصفحة.
web.HTMLVideoElement? _findCameraVideo() {
  final web.NodeList videos = web.document.querySelectorAll('video');
  if (videos.length == 0) {
    return null;
  }

  web.HTMLVideoElement? largest;
  int largestArea = -1;

  for (int i = 0; i < videos.length; i++) {
    final web.Node? node = videos.item(i);
    // فحص نوع متوافق مع js_interop (يعمل أيضاً في بناء wasm).
    if (node == null || !node.isA<web.HTMLVideoElement>()) {
      continue;
    }

    final web.HTMLVideoElement video = node as web.HTMLVideoElement;

    if (video.srcObject != null) {
      return video;
    }
    final int area = video.videoWidth * video.videoHeight;
    if (area > largestArea) {
      largestArea = area;
      largest = video;
    }
  }

  return largest;
}
