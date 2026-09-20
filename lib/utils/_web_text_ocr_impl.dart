// تنفيذ الويب لقراءة النصوص (OCR) من صورة ثابتة عبر Tesseract.js.
//
// * يُحمَّل المحرّك من CDN **عند أول استخدام فقط** (ثم يبقى في ذاكرة المتصفح).
// * كل الأخطاء مُعالَجة: تعذّر الشبكة → `offline`، أي خطأ آخر → `failed`،
//   فلا يتوقف التطبيق ولا تظهر شاشة سوداء.
import 'dart:async';
import 'dart:convert';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

import 'package:orderly_app/utils/web_text_ocr_state.dart';

/// مُعرّف سكربت المحرّك داخل الصفحة (لمنع تحميله مرتين).
const String _scriptId = 'orderly-tesseract-js';

/// نسخة مثبّتة من محرّك القراءة (تحميل من CDN).
const String _scriptUrl =
    'https://cdn.jsdelivr.net/npm/tesseract.js@5.1.1/dist/tesseract.min.js';

/// مهلة تحميل المحرّك (أول استخدام يحتاج تنزيل ملفات WASM).
const Duration _libraryTimeout = Duration(seconds: 20);

/// مهلة تنفيذ القراءة نفسها.
const Duration _recognizeTimeout = Duration(seconds: 25);

/// يقرأ النصوص من الصورة [bytes] ويعيد النص الخام.
Future<WebTextOcrResult> recognizeTextFromImage(
  Uint8List bytes, {
  String mimeType = 'image/jpeg',
  Duration timeout = _recognizeTimeout,
}) async {
  if (bytes.isEmpty) {
    return const WebTextOcrResult(status: WebTextOcrStatus.failed);
  }

  final bool libraryReady = await _ensureLibraryLoaded();
  if (!libraryReady) {
    return const WebTextOcrResult(status: WebTextOcrStatus.offline);
  }

  try {
    final JSObject tesseract = globalContext.getProperty<JSObject>(
      'Tesseract'.toJS,
    );
    final String dataUrl = 'data:$mimeType;base64,${base64Encode(bytes)}';

    final JSPromise<JSObject> promise = tesseract
        .callMethod<JSPromise<JSObject>>(
          'recognize'.toJS,
          dataUrl.toJS,
          'eng'.toJS,
        );

    final JSObject result = await promise.toDart.timeout(timeout);
    final JSObject? data = result.getProperty<JSObject?>('data'.toJS);
    final String? text = data?.getProperty<JSString?>('text'.toJS)?.toDart;

    if (text == null) {
      return const WebTextOcrResult(status: WebTextOcrStatus.failed);
    }

    return WebTextOcrResult(status: WebTextOcrStatus.ok, text: text);
  } catch (_) {
    return const WebTextOcrResult(status: WebTextOcrStatus.failed);
  }
}

/// يضمن تحميل مكتبة القراءة، ويُرجع `false` إذا تعذّر تحميلها.
Future<bool> _ensureLibraryLoaded() async {
  if (_libraryAvailable()) {
    return true;
  }

  if (web.document.querySelector('script#$_scriptId') == null) {
    final Completer<bool> completer = Completer<bool>();
    final web.HTMLScriptElement script = web.HTMLScriptElement()
      ..id = _scriptId
      ..async = true
      ..crossOrigin = 'anonymous'
      ..src = _scriptUrl
      ..onload = ((JSAny _) {
        if (!completer.isCompleted) {
          completer.complete(true);
        }
      }).toJS
      ..onerror = ((JSAny _) {
        if (!completer.isCompleted) {
          completer.complete(false);
        }
      }).toJS;

    web.document.head!.appendChild(script);

    final bool loaded = await completer.future.timeout(
      _libraryTimeout,
      onTimeout: () => false,
    );
    if (!loaded) {
      return false;
    }
  }

  // السكربت موجود لكن المكتبة قد تحتاج لحظة لتُسجّل نفسها.
  for (int attempt = 0; attempt < 40; attempt++) {
    if (_libraryAvailable()) {
      return true;
    }
    await Future<void>.delayed(const Duration(milliseconds: 120));
  }

  return _libraryAvailable();
}

/// هل مكتبة `Tesseract` جاهزة في الصفحة؟
bool _libraryAvailable() {
  try {
    return globalContext.has('Tesseract');
  } catch (_) {
    return false;
  }
}
