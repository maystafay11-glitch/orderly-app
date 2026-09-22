import 'dart:typed_data';

import 'package:orderly_app/utils/_web_photo_capture_stub.dart'
    if (dart.library.js_interop)
        'package:orderly_app/utils/_web_photo_capture_impl.dart' as impl;

/// يفتح منتقي ملفات المتصفح مع `capture=environment` على الهواتف
/// (آيفون/سفاري) لالتقاط صورة إثبات بسرعة دون بث كاميرا مباشر.
Future<Uint8List?> captureQuickPhoto({bool preferCamera = true}) =>
    impl.captureQuickPhoto(preferCamera: preferCamera);
