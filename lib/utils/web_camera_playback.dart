// واجهة عامة لتحصين تشغيل معاينة الكاميرا في المتصفح.
//
//   * الويب: `_web_camera_playback_impl.dart` (يضبط playsinline/muted/autoplay).
//   * غير ذلك: `_web_camera_playback_stub.dart` (لا يفعل شيئاً).
import 'package:orderly_app/utils/_web_camera_playback_stub.dart'
    if (dart.library.js_interop)
        'package:orderly_app/utils/_web_camera_playback_impl.dart' as impl;

import 'package:orderly_app/utils/web_camera_playback_state.dart';

export 'package:orderly_app/utils/web_camera_playback_state.dart';

/// يضمن أن معاينة كاميرا المتصفح تعمل فعلاً (وليست شاشة سوداء).
///
/// آمن تماماً على المنصات الأصلية (يُرجع `notApplicable`).
Future<WebCameraPlaybackState> ensureWebCameraPlayback() =>
    impl.ensureWebCameraPlayback();
