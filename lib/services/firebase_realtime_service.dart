/// خدمة Firebase Realtime Database عبر REST API.
///
/// **لماذا REST API وليس Firebase SDK؟**
/// * لا يحتاج إلى `google-services.json` — كل مطعم يُدخل فقط Database URL.
/// * خفيف جداً (يستخدم `http` package الموجود).
/// * يعمل مع أي Firebase Project بدون إعادة بناء APK.
/// * مثالي لنموذج SaaS حيث يُباع نفس APK لمطاعم مختلفة.
///
/// **هيكل البيانات في Firebase:**
/// ```
/// restaurants/{restaurantId}/
///   snapshot/          ← نسخة كاملة من بيانات المطعم (للمزامنة الأولية)
///     drivers: [...]
///     orders: [...]
///   heartbeat: 1234567 ← آخر تحديث (timestamp) لاكتشاف التغييرات
/// ```
///
/// **نمط المزامنة (Polling-based):**
/// يُراقب `heartbeat` كل 3 ثوانٍ — إذا تغيّرت قيمته، يُحمَّل snapshot جديد.
/// هذا النمط أموثوق من SSE على Android ولا يستهلك بطارية.
library;

import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'package:orderly_app/services/restaurant_service.dart';

/// حالة اتصال Firebase.
enum FirebaseConnectionState {
  /// غير مهيّأ بعد (لم يُدخَل URL).
  notConfigured,

  /// يحاول الاتصال.
  connecting,

  /// متصل ويعمل.
  connected,

  /// انقطع الاتصال — يُعاد المحاولة تلقائياً.
  disconnected,

  /// خطأ غير قابل للتعافي (URL خاطئ مثلاً).
  error,
}

/// نتيجة محاولة كتابة snapshot محمية بـ ETag.
enum SnapshotPushOutcome {
  /// كُتبت بنجاح.
  success,

  /// تغيّر المستند على جهاز آخر بين القراءة والكتابة (HTTP 412)
  /// — نُعيد القراءة بدل الكتابة فوق تغييرات العامل.
  conflict,

  /// فشل شبكي أو رد غير متوقع.
  failure,
}

class FirebaseRealtimeService {
  FirebaseRealtimeService._();

  static final FirebaseRealtimeService instance = FirebaseRealtimeService._();

  // ─── الحالة الداخلية ──────────────────────────────────────────────────────

  String _databaseUrl = '';
  String _restaurantId = '';
  Timer? _pollingTimer;
  int _lastHeartbeat = 0;

  /// رمز ETag لآخر `snapshot` قُرِئ من السحابة — يُستخدم لجعل الكتابة محمية
  /// من الكتابة فوق تغييرات جهاز آخر (العامل على الويب مثلاً).
  String? _lastSnapshotEtag;

  final StreamController<Map<String, dynamic>> _snapshotController =
      StreamController<Map<String, dynamic>>.broadcast();

  final StreamController<FirebaseConnectionState> _stateController =
      StreamController<FirebaseConnectionState>.broadcast();

  FirebaseConnectionState _state = FirebaseConnectionState.notConfigured;

  // ─── الواجهة العامة ───────────────────────────────────────────────────────

  /// دفق تحديثات البيانات الواردة من Firebase.
  Stream<Map<String, dynamic>> get snapshotStream => _snapshotController.stream;

  /// دفق تغيرات حالة الاتصال.
  Stream<FirebaseConnectionState> get connectionStateStream =>
      _stateController.stream;

  /// حالة الاتصال الحالية.
  FirebaseConnectionState get connectionState => _state;

  /// هل Firebase مفعّل ومتصل؟
  bool get isConnected => _state == FirebaseConnectionState.connected;

  /// هل تمت الإعداد (URL مدخل)؟
  bool get isConfigured => _databaseUrl.isNotEmpty;

  /// تهيئة الخدمة وبدء المزامنة.
  ///
  /// [databaseUrl] رابط Firebase Realtime Database
  /// (مثال: `https://my-project-default-rtdb.firebaseio.com`).
  Future<void> initialize(String databaseUrl) async {
    if (databaseUrl.trim().isEmpty) {
      _setState(FirebaseConnectionState.notConfigured);
      return;
    }

    _databaseUrl = databaseUrl.trim().replaceAll(RegExp(r'/$'), '');
    _restaurantId = RestaurantService.restaurantId;

    if (_restaurantId.isEmpty) {
      debugPrint('[Firebase] restaurantId فارغ — لن يبدأ الاتصال');
      return;
    }

    _pollingTimer?.cancel();
    _setState(FirebaseConnectionState.connecting);

    // أول اتصال فوري
    await _poll();

    // بدء polling كل 3 ثوانٍ
    _pollingTimer = Timer.periodic(
      const Duration(seconds: 3),
      (_) => _poll(),
    );
  }

  /// إيقاف المزامنة (عند تغيير URL أو تسجيل الخروج).
  void dispose() {
    _pollingTimer?.cancel();
    _pollingTimer = null;
    _lastSnapshotEtag = null;
    _setState(FirebaseConnectionState.notConfigured);
  }

  // ─── كتابة البيانات ───────────────────────────────────────────────────────

  /// حفظ snapshot كامل لبيانات المطعم في Firebase.
  ///
  /// يُستدعى بعد كل تغيير مهم (إضافة طلب، تحديث حالة، إلخ).
  Future<bool> pushSnapshot(Map<String, dynamic> data) async {
    if (!isConfigured || _restaurantId.isEmpty) return false;

    try {
      final String url =
          '$_databaseUrl/restaurants/$_restaurantId/snapshot.json';
      final http.Response response = await http
          .put(
            Uri.parse(url),
            headers: <String, String>{'Content-Type': 'application/json'},
            body: jsonEncode(data),
          )
          .timeout(const Duration(seconds: 10));

      if (response.statusCode >= 200 && response.statusCode < 300) {
        // تحديث heartbeat للإعلام بأن هناك تغييراً
        await _updateHeartbeat();
        _setState(FirebaseConnectionState.connected);
        return true;
      }
      debugPrint('[Firebase] pushSnapshot فشل: ${response.statusCode}');
      return false;
    } catch (e) {
      debugPrint('[Firebase] pushSnapshot خطأ: $e');
      _setState(FirebaseConnectionState.disconnected);
      return false;
    }
  }

  /// كتابة `snapshot` محمية بـ ETag.
  ///
  /// تُستخدم من تطبيق المدير: إن كان جهاز آخر (واجهة العامل مثلاً) قد كتب
  /// مستنداً أحدث بين آخر قراءة وهذه الكتابة، يُرفض الطلب بـ `412` بدل
  /// الكتابة فوق تعديلاته، فيُبلَّغ المستدعي ([SnapshotPushOutcome.conflict])
  /// ليعيد القراءة والدمج ثم المحاولة مرة أخرى.
  Future<SnapshotPushOutcome> pushSnapshotGuarded(
    Map<String, dynamic> data,
  ) async {
    if (!isConfigured || _restaurantId.isEmpty) {
      return SnapshotPushOutcome.failure;
    }

    try {
      final String etag = _lastSnapshotEtag ?? '';
      final http.Response response = await http
          .put(
            Uri.parse(
              '$_databaseUrl/restaurants/$_restaurantId/snapshot.json',
            ),
            headers: <String, String>{
              'Content-Type': 'application/json',
              if (etag.isNotEmpty) 'If-Match': etag,
            },
            body: jsonEncode(data),
          )
          .timeout(const Duration(seconds: 10));

      if (response.statusCode == 412) {
        debugPrint('[Firebase] تعارض ETag — مستند أحدث على جهاز آخر');
        return SnapshotPushOutcome.conflict;
      }
      if (response.statusCode >= 200 && response.statusCode < 300) {
        await _updateHeartbeat();
        _setState(FirebaseConnectionState.connected);
        return SnapshotPushOutcome.success;
      }
      debugPrint('[Firebase] pushSnapshotGuarded فشل: ${response.statusCode}');
      return SnapshotPushOutcome.failure;
    } catch (e) {
      debugPrint('[Firebase] pushSnapshotGuarded خطأ: $e');
      _setState(FirebaseConnectionState.disconnected);
      return SnapshotPushOutcome.failure;
    }
  }

  /// كتابة قيمة واحدة في مسار محدد داخل namespace المطعم.
  ///
  /// مثال: `writeValue('drivers/1001/status', 'delivering')`
  Future<bool> writeValue(String path, dynamic value) async {
    if (!isConfigured || _restaurantId.isEmpty) return false;

    try {
      final String url =
          '$_databaseUrl/restaurants/$_restaurantId/$path.json';
      final http.Response response = await http
          .put(
            Uri.parse(url),
            headers: <String, String>{'Content-Type': 'application/json'},
            body: jsonEncode(value),
          )
          .timeout(const Duration(seconds: 8));

      if (response.statusCode >= 200 && response.statusCode < 300) {
        await _updateHeartbeat();
        return true;
      }
      return false;
    } catch (e) {
      debugPrint('[Firebase] writeValue خطأ ($path): $e');
      return false;
    }
  }

  /// حذف مسار محدد من بيانات المطعم.
  Future<bool> deleteValue(String path) async {
    if (!isConfigured || _restaurantId.isEmpty) return false;

    try {
      final String url =
          '$_databaseUrl/restaurants/$_restaurantId/$path.json';
      final http.Response response = await http
          .delete(Uri.parse(url))
          .timeout(const Duration(seconds: 8));

      return response.statusCode >= 200 && response.statusCode < 300;
    } catch (e) {
      debugPrint('[Firebase] deleteValue خطأ ($path): $e');
      return false;
    }
  }

  // ─── قراءة البيانات ───────────────────────────────────────────────────────

  /// قراءة snapshot كامل مباشرة من Firebase (للمزامنة الأولية).
  ///
  /// تُخزَّن قيمة `ETag` المرجَعة لتُستخدم لاحقاً في الكتابة المحمية
  /// ([pushSnapshotGuarded]) بدل الكتابة فوق تغييرات جهاز آخر.
  Future<Map<String, dynamic>?> fetchSnapshot() async {
    if (!isConfigured || _restaurantId.isEmpty) return null;

    try {
      final String url =
          '$_databaseUrl/restaurants/$_restaurantId/snapshot.json';
      final http.Response response = await http
          .get(
            Uri.parse(url),
            headers: <String, String>{'X-Firebase-ETag': 'true'},
          )
          .timeout(const Duration(seconds: 10));

      _lastSnapshotEtag = response.headers['etag'] ?? _lastSnapshotEtag;

      if (response.statusCode == 200 && response.body != 'null') {
        final dynamic decoded = jsonDecode(response.body);
        if (decoded is Map) {
          return Map<String, dynamic>.from(decoded as Map<Object?, Object?>);
        }
      }
      return null;
    } catch (e) {
      debugPrint('[Firebase] fetchSnapshot خطأ: $e');
      return null;
    }
  }

  // ─── المنطق الداخلي ───────────────────────────────────────────────────────

  /// فحص heartbeat — إذا تغيّر، يُحمَّل snapshot جديد.
  Future<void> _poll() async {
    if (!isConfigured || _restaurantId.isEmpty) return;

    try {
      final String url =
          '$_databaseUrl/restaurants/$_restaurantId/heartbeat.json';
      final http.Response response = await http
          .get(Uri.parse(url))
          .timeout(const Duration(seconds: 5));

      if (response.statusCode != 200) {
        _setState(FirebaseConnectionState.disconnected);
        return;
      }

      _setState(FirebaseConnectionState.connected);

      final dynamic raw = jsonDecode(response.body);
      final int heartbeat =
          raw is num ? raw.toInt() : int.tryParse(raw.toString()) ?? 0;

      if (heartbeat != _lastHeartbeat && heartbeat > 0) {
        _lastHeartbeat = heartbeat;
        final Map<String, dynamic>? snapshot = await fetchSnapshot();
        if (snapshot != null && !_snapshotController.isClosed) {
          _snapshotController.add(snapshot);
          debugPrint('[Firebase] تحديث جديد مُستلَم (heartbeat: $heartbeat)');
        }
      }
    } catch (e) {
      _setState(FirebaseConnectionState.disconnected);
    }
  }

  /// تحديث heartbeat (timestamp حالي) للإعلام بوجود تغيير.
  Future<void> _updateHeartbeat() async {
    if (!isConfigured || _restaurantId.isEmpty) return;
    try {
      final int now = DateTime.now().millisecondsSinceEpoch;
      final String url =
          '$_databaseUrl/restaurants/$_restaurantId/heartbeat.json';
      await http
          .put(
            Uri.parse(url),
            headers: <String, String>{'Content-Type': 'application/json'},
            body: now.toString(),
          )
          .timeout(const Duration(seconds: 5));
      _lastHeartbeat = now;
    } catch (_) {
      // non-critical — لا يوقف المزامنة المحلية
    }
  }

  void _setState(FirebaseConnectionState newState) {
    if (_state == newState) return;
    _state = newState;
    if (!_stateController.isClosed) {
      _stateController.add(newState);
    }
  }
}
