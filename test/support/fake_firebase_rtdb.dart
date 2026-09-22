import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

/// خادم محلي يحاكي Firebase Realtime Database REST API بنفس العقود التي
/// يعتمدها التطبيق فعلياً في الكود الإنتاجي:
///
/// * `GET  /restaurants/{rid}/{path}.json` → القيمة أو `null` (200 دائماً).
/// * `PUT  /restaurants/{rid}/{path}.json` → كتابة القيمة (body: JSON).
/// * `DELETE /restaurants/{rid}/{path}.json` → حذف القيمة.
/// * رأس `X-Firebase-ETag: true` → يُرجِع رأس `ETag` للقراءة والكتابة.
/// * رأس `If-Match: <etag>` → `412 Precondition Failed` عند تعارض النسخة
///   (وهو ما يعتمد عليه `WorkerWebService` في إعادة المحاولة قبل الكتابة).
/// * `Accept: text/event-stream` → بث `event: put` كما يستهلكه `EventSource`
///   في نسخة العامل على الويب (`_worker_live_channel_web.dart`).
///
/// لا يُستخدم في اختبارات الوحدة العادية، بل في اختبارات التكامل الشبكي فقط.
class FakeFirebaseRtdb {
  HttpServer? _server;

  /// مخزن المسارات: المفتاح مسار بدون `.json` (مثل `restaurants/CAFE1/snapshot`).
  final Map<String, Object?> _store = <String, Object?>{};

  /// رقم النسخة لكل مسار (لبناء قيمة ETag).
  final Map<String, int> _etags = <String, int>{};

  /// عملاء البث اللحظي (SSE) المتصلون حالياً.
  final List<_EventStreamClient> _streams = <_EventStreamClient>[];

  /// سجل مختصر لكل طلب وصل للخادم (للتشخيص والتحقق).
  final List<String> requestLog = <String>[];

  /// طباعة تتبّع كل طلب (للتشخيص اليدوي).
  bool verbose = false;

  int _revision = 0;

  /// عدد الكتابات الناجحة (يتيح التأكد أن التغيير وصل «السحابة»).
  int writeCount = 0;

  /// عدد مرات رفض الكتابة بسبب ETag قديم (412).
  int conflictCount = 0;

  /// خطاف اختياري يُنادى قبل معالجة كل PUT — يُستخدم لتوليد حالات تعارض
  /// مقصودة (تغيير رمز ETag بين قراءة العميل وكتابته).
  void Function(String path)? onBeforePut;

  /// عنوان الخادم الكامل (بديل `https://project.firebaseio.com`).
  String get baseUrl => 'http://127.0.0.1:${_server!.port}';

  /// المنفذ المُختار تلقائياً.
  int get port => _server!.port;

  /// تشغيل الخادم على منفذ حر في 127.0.0.1.
  Future<void> start() async {
    if (_server != null) return;
    _server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    _server!.listen(
      _handle,
      onError: (Object _) {
        // أخطاء اتصالات متقطعة أثناء الإغلاق — تُتجاهل.
      },
    );
  }

  /// إيقاف الخادم وإغلاق كل قنوات البث.
  Future<void> stop() async {
    for (final _EventStreamClient client in List<_EventStreamClient>.of(
      _streams,
    )) {
      await client.close();
    }
    _streams.clear();
    final HttpServer? server = _server;
    _server = null;
    await server?.close(force: true);
  }

  /// كتابة قيمة مباشرة في المخزن (لتهيئة بيانات اختبار دون HTTP).
  void seed(String path, Object? value) {
    final String key = _normalize(path);
    _store[key] = _jsonSafe(value);
    _revision++;
    _etags[key] = _revision;
  }

  /// قراءة قيمة من المخزن مباشرة مع دلالات شجرة Firebase: قراءة مسار أب
  /// تُرجع كائناً يحوي الأبناء (مثل `restaurants/{rid}/staff`).
  Object? read(String path) => _readPath(_normalize(path));

  Object? _readPath(String path) {
    if (_store.containsKey(path)) return _store[path];
    final String prefix = path.isEmpty ? '' : '$path/';
    final Map<String, Object?> nested = <String, Object?>{};
    for (final MapEntry<String, Object?> entry in _store.entries) {
      if (entry.key.startsWith(prefix) && entry.key.length > prefix.length) {
        final String rest = entry.key.substring(prefix.length);
        final String head = rest.split('/').first;
        nested[head] = _readPath('$prefix$head');
      }
    }
    return nested.isEmpty ? null : nested;
  }

  /// تغيير رمز ETag لمسار ما دون تغيير بياناته — لمحاكاة كتابة جهاز آخر
  /// في اللحظة الفاصلة بين قراءة العميل وكتابته (يؤدي إلى 412 مقصود).
  void invalidateEtag(String path) {
    final String key = _normalize(path);
    _revision++;
    _etags[key] = _revision;
  }


  // ─── المنطق الداخلي ───────────────────────────────────────────────────────

  static String _normalize(String rawPath) {
    String path = rawPath.trim();
    while (path.startsWith('/')) {
      path = path.substring(1);
    }
    if (path.endsWith('.json')) {
      path = path.substring(0, path.length - 5);
    }
    if (path.endsWith('/')) {
      path = path.substring(0, path.length - 1);
    }
    return path;
  }

  static Object? _jsonSafe(Object? value) {
    if (value == null) return null;
    return jsonDecode(jsonEncode(value));
  }

  String _etagFor(String path) => '"rev${_etags[path] ?? 0}"';

  void _log(String message) {
    if (verbose) debugPrint('[FakeRTDB] $message');
  }

  Future<void> _handle(HttpRequest request) async {
    final String path = _normalize(request.uri.path);
    requestLog.add('${request.method} /$path');
    _log('→ ${request.method} /$path');
    try {
      final String accept =
          request.headers.value(HttpHeaders.acceptHeader) ?? '';
      if (request.method == 'GET' && accept.contains('text/event-stream')) {
        await _serveEventStream(request, path);
        return;
      }
      switch (request.method) {
        case 'GET':
          await _handleGet(request, path);
        case 'PUT':
          await _handlePut(request, path);
        case 'DELETE':
          _store.removeWhere(
            (String key, Object? _) =>
                key == path || key.startsWith('$path/'),
          );
          _revision++;
          _etags[path] = _revision;
          await _notify(path, null);
          await _writeResponse(request, 'null');
        default:
          request.response.statusCode = HttpStatus.methodNotAllowed;
          request.response.add(
            utf8.encode('{"error":"method not allowed"}'),
          );
          await request.response.close();
      }
    } catch (error) {
      _log('!! error: $error');
      try {
        request.response.statusCode = HttpStatus.internalServerError;
        request.response.add(utf8.encode('{"error":"$error"}'));
        await request.response.close();
      } catch (_) {
        // الاتصال مُغلق — لا شيء لفعله.
      }
    }
  }

  Future<void> _handleGet(HttpRequest request, String path) async {
    final Object? value = _readPath(path);
    final HttpResponse response = request.response;
    response.headers.set(
      HttpHeaders.contentTypeHeader,
      'application/json; charset=utf-8',
    );
    if ((request.headers.value('x-firebase-etag') ?? '') == 'true') {
      response.headers.set('etag', _etagFor(path));
    }
    response.add(utf8.encode(value == null ? 'null' : jsonEncode(value)));
    await response.close();
  }

  Future<void> _handlePut(HttpRequest request, String path) async {
    onBeforePut?.call(path);
    _log('PUT body reading...');
    final String body = await utf8.decoder.bind(request).join();
    _log('PUT body=${body.length} bytes');
    final String? ifMatch = request.headers.value('if-match');
    if (ifMatch != null && ifMatch.isNotEmpty && ifMatch != _etagFor(path)) {
      conflictCount++;
      request.response.statusCode = HttpStatus.preconditionFailed;
      request.response.write('{"error":"ETag mismatch"}');
      await request.response.close();
      return;
    }

    Object? value;
    try {
      value = jsonDecode(body);
    } catch (_) {
      value = body;
    }
    _store[path] = value;
    _revision++;
    _etags[path] = _revision;
    writeCount++;
    _log('PUT stored (${jsonEncode(value).length} chars) → responding');
    await _notify(path, value);
    await _writeResponse(request, jsonEncode(value));
    _log('PUT response closed');
  }

  Future<void> _writeResponse(HttpRequest request, String body) async {
    final HttpResponse response = request.response;
    response.headers.set(
      HttpHeaders.contentTypeHeader,
      'application/json; charset=utf-8',
    );
    if ((request.headers.value('x-firebase-etag') ?? '') == 'true') {
      response.headers.set('etag', _etagFor(_normalize(request.uri.path)));
    }
    response.add(utf8.encode(body));
    await response.close();
  }

  /// إخطار قنوات SSE المرتبطة بالمسار (المسار نفسه أو أب/ابن له)
  /// — نفس سلوك Firebase في بث التغييرات على الشجرة.
  Future<void> _notify(String path, Object? value) async {
    for (final _EventStreamClient client in List<_EventStreamClient>.of(
      _streams,
    )) {
      final String listen = client.path;
      final bool related = listen.isEmpty ||
          path == listen ||
          path.startsWith('$listen/') ||
          listen.startsWith('$path/');
      if (related) await client.sendPut(path, value);
    }
  }

  Future<void> _serveEventStream(HttpRequest request, String path) async {
    final HttpResponse response = request.response;
    response.statusCode = HttpStatus.ok;
    response.headers.set(
      HttpHeaders.contentTypeHeader,
      'text/event-stream; charset=utf-8',
    );
    response.headers.set(HttpHeaders.cacheControlHeader, 'no-cache');
    response.headers.set(HttpHeaders.connectionHeader, 'keep-alive');
    // بدون تخزين مؤقت حتى تصل الأحداث لحظياً كما في Firebase.
    response.bufferOutput = false;
    await response.flush();

    final _EventStreamClient client = _EventStreamClient(path, response);
    _streams.add(client);
    _log('SSE open /$path');
    await client.send('keep-alive', 'null');
    _log('SSE keep-alive sent');
    try {
      await response.done;
      _log('SSE response.done completed');
    } catch (_) {
      // العميل أغلق الاتصال.
    } finally {
      _streams.remove(client);
      _log('SSE closed /$path');
    }
  }
}

/// عميل SSE واحد مرتبط بمسار محدد.
class _EventStreamClient {
  _EventStreamClient(this.path, this._response);

  /// المسار الذي يستمع إليه العميل (مثل `restaurants/CAFE1/heartbeat`).
  final String path;

  final HttpResponse _response;

  Future<void> send(String event, String data) async {
    try {
      _response.add(utf8.encode('event: $event\ndata: $data\n\n'));
      await _response.flush();
    } catch (_) {
      // القناة مُغلقة — تُنظَّف من القائمة تلقائياً عند إغلاق الاتصال.
    }
  }

  /// بث حدث كتابة بنفس شكل Firebase: `path` نسبي بالنسبة للمسار المستمع إليه
  /// (`/` عند الكتابة على نفس المسار أو على أب له، ومسار الابن عند الكتابة داخله).
  Future<void> sendPut(String changedPath, Object? value) {
    final String listen = path;
    String relative;
    if (listen.isEmpty) {
      relative = changedPath.isEmpty ? '/' : '/$changedPath';
    } else if (changedPath == listen) {
      relative = '/';
    } else if (changedPath.startsWith('$listen/')) {
      relative = '/${changedPath.substring(listen.length + 1)}';
    } else {
      relative = '/';
    }
    return send(
      'put',
      jsonEncode(<String, Object?>{
        'path': relative,
        'data': value,
      }),
    );
  }

  Future<void> close() async {
    try {
      await _response.close();
    } catch (_) {
      // مُغلق سابقاً.
    }
  }
}
