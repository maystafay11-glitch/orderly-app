// نسخة المنصات الأصلية: لا يوجد عنصر فيديو في DOM ولا متصفح.
import 'package:orderly_app/utils/web_camera_playback_state.dart';

/// على Android/iOS تُدار معاينة الكاميرا بواسطة المكتبة الأصلية،
/// فلا حاجة لأي إجراء هنا.
Future<WebCameraPlaybackState> ensureWebCameraPlayback() async =>
    WebCameraPlaybackState.notApplicable;
