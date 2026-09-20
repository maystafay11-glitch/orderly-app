// تنفيذ الويب: قراءة الباركود/QR من صورة ثابتة عبر `BarcodeDetector`
// (واجهة المتصفح الأصلية — Chrome/Edge 83+ وSafari 17+).
//
// لا يوجد هنا أي بث فيديو مباشر ولا `getUserMedia`، لذلك لا شاشة سوداء.
import 'dart:async';
import 'dart:convert';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

import 'package:orderly_app/utils/web_image_barcode_state.dart';

/// واجهة `BarcodeDetector` الأصلية في المتصفح.
@JS('BarcodeDetector')
extension type _BarcodeDetector._(JSObject _) implements JSObject {
  external factory _BarcodeDetector();

  external JSPromise<JSArray<JSObject>> detect(JSAny image);
}

/// نتيجة اكتشاف واحدة (نكتفي بالنص الخام).
extension type _DetectedBarcode._(JSObject _) implements JSObject {
  external String get rawValue;
}

/// مهلة قراءة الباركود من الصورة (تجنّب انتظار لا نهائي على صور ضخمة).
const Duration _detectTimeout = Duration(seconds: 12);

/// يقرأ الباركود/QR من الصورة [bytes] ويعيد نصوصها.
Future<WebImageBarcodeResult> readBarcodesFromImage(
  Uint8List bytes, {
  String mimeType = 'image/jpeg',
}) async {
  if (bytes.isEmpty) {
    return const WebImageBarcodeResult(status: WebImageBarcodeStatus.failed);
  }

  // 1) هل يدعم المتصفح الواجهة؟
  bool supported;
  try {
    supported = globalContext.has('BarcodeDetector');
  } catch (_) {
    supported = false;
  }
  if (!supported) {
    return const WebImageBarcodeResult(
      status: WebImageBarcodeStatus.unsupported,
    );
  }

  try {
    // 2) تحويل البايتات إلى صورة قابلة للقراءة داخل المتصفح.
    final web.HTMLImageElement image = web.HTMLImageElement()
      ..src = 'data:$mimeType;base64,${base64Encode(bytes)}';
    await image.decode().toDart.timeout(_detectTimeout);

    // 3) القراءة بكل الصيغ المدعومة.
    final _BarcodeDetector detector = _BarcodeDetector();
    final JSArray<JSObject> results = await detector
        .detect(image)
        .toDart
        .timeout(_detectTimeout);

    final List<String> payloads = <String>[];
    for (final JSObject item in results.toDart) {
      if (!item.isA<_DetectedBarcode>()) {
        continue;
      }
      final String value = (item as _DetectedBarcode).rawValue.trim();
      if (value.isNotEmpty && !payloads.contains(value)) {
        payloads.add(value);
      }
    }

    return WebImageBarcodeResult(
      status: WebImageBarcodeStatus.ok,
      payloads: payloads,
    );
  } catch (_) {
    return const WebImageBarcodeResult(status: WebImageBarcodeStatus.failed);
  }
}
