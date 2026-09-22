import 'dart:async';
import 'dart:js_interop';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

/// التقاط/اختيار صورة عبر عنصر ملف HTML — الأنسب لسفاري آيفون داخل HTTPS.
Future<Uint8List?> captureQuickPhoto({bool preferCamera = true}) async {
  final Completer<Uint8List?> completer = Completer<Uint8List?>();
  final web.HTMLInputElement input = web.HTMLInputElement()
    ..type = 'file'
    ..accept = 'image/jpeg,image/png,image/webp,image/heic,image/heif,image/*'
    ..multiple = false;

  if (preferCamera) {
    input.setAttribute('capture', 'environment');
  }

  input.addEventListener(
    'change',
    (web.Event _) {
      final web.FileList? files = input.files;
      if (files == null || files.length == 0) {
        if (!completer.isCompleted) completer.complete(null);
        return;
      }
      final web.File? file = files.item(0);
      if (file == null) {
        if (!completer.isCompleted) completer.complete(null);
        return;
      }
      file.arrayBuffer().toDart.then((JSArrayBuffer buffer) {
        if (!completer.isCompleted) {
          completer.complete(Uint8List.view(buffer.toDart));
        }
      }).catchError((Object _) {
        if (!completer.isCompleted) completer.complete(null);
      });
    }.toJS,
  );

  input.addEventListener(
    'cancel',
    (web.Event _) {
      if (!completer.isCompleted) completer.complete(null);
    }.toJS,
  );

  input.click();
  return completer.future.timeout(
    const Duration(minutes: 3),
    onTimeout: () => null,
  );
}
