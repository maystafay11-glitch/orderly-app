import 'dart:typed_data';

/// على المنصات غير الويب لا يُستخدم التقاط HTML؛ [image_picker] يتولّى الأمر.
Future<Uint8List?> captureQuickPhoto({bool preferCamera = true}) async => null;
