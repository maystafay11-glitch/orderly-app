import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'package:orderly_app/models/delivery_order.dart';
import 'package:orderly_app/models/driver.dart';
import 'package:orderly_app/models/order_payment_type.dart';
import 'package:orderly_app/models/order_status.dart';
import 'package:orderly_app/models/staff_member.dart';
import 'package:orderly_app/services/app_settings.dart';
import 'package:orderly_app/services/driver_storage.dart';
import 'package:orderly_app/services/firebase_realtime_service.dart';
import 'package:orderly_app/services/firebase_tracking_service.dart';
import 'package:orderly_app/services/restaurant_service.dart';
import 'package:orderly_app/services/staff_directory_service.dart';
import 'package:orderly_app/services/worker_web_service.dart';

import 'support/fake_firebase_rtdb.dart';

/// ─────────────────────────────────────────────────────────────────────────────
/// اختبار تكامل شبكي حقيقي (Real Network Integration):
///
/// يفتح خادم HTTP محلياً يحاكي Firebase Realtime Database بعقوده الفعلية
/// (REST + ETag/If-Match + SSE)، ثم يشغّل **نفس الكود الإنتاجي** للطرفين:
///   • واجهة العامل على الويب: `WorkerWebService` (+ قناة البث اللحظي).
///   • تطبيق المدير (APK): `FirebaseTrackingService` + `FirebaseRealtimeService`
///     مع `DriverStorage` و `StaffDirectoryService`.
/// ويتحقق من:
///   1. تسجيل دخول العامل بالشبكة مع عزل تام بين المطاعم.
///   2. المزامنة في الاتجاهين (مدير ← عامل، عامل ← مدير) خلال نفس اللحظة.
///   3. عقد ETag/If-Match وحماية الطلبات من الفقد عند التزاحم.
///   4. عقد بث SSE الذي يستهلكه `EventSource` في متصفح الآيفون.
///
/// التشغيل: `flutter test test/worker_firebase_integration_test.dart`
/// ─────────────────────────────────────────────────────────────────────────────

const String _rid1 = 'CAFE1001';
const String _rid2 = 'CAFE2002';
const String _driverName = 'عمر التوصيل';
const String _workerPassword = '1234';

/// مدة انتظار سخية: دورات المزامنة الحقيقية كل 2-3 ثوانٍ.
const Duration _syncTimeout = Duration(seconds: 25);

/// تصفير الحالة المحلية بالكامل (يحاكي جهازاً جديداً بلا بيانات).
Future<void> _resetLocalState() async {
  SharedPreferences.setMockInitialValues(<String, Object>{});
  final SharedPreferences prefs = await SharedPreferences.getInstance();
  await prefs.clear();
}

/// تشغيل «تطبيق المدير» على معرّف مطعم ورابط سحابي محددين:
/// يجهّز العمال محلياً، ويرفع حسابات الموظفين للسحابة، ثم يبدأ المزامنة.
Future<void> _startManagerApp(
  FakeFirebaseRtdb server,
  String restaurantId, {
  List<String> driverNames = const <String>[_driverName],
}) async {
  final SharedPreferences prefs = await SharedPreferences.getInstance();
  await prefs.setString('orderly.restaurant_id', restaurantId);
  await AppSettings.setFirebaseDatabaseUrl(server.baseUrl);
  await RestaurantService.init();
  for (final String name in driverNames) {
    await DriverStorage.loadOrCreate(name);
  }
  // يرفع حساب مدير + حساب عامل لكل سائق إلى السحابة (staff_directory_service).
  await StaffDirectoryService.ensureProvisioned(restaurantId);
  FirebaseRealtimeService.instance.dispose();
  await FirebaseTrackingService.instance.initialize();
}

/// دفع التغيير الحالي لتطبيق المدير إلى السحابة (نفس مسار الكود الإنتاجي).
Future<void> _managerPushAndWait(
  FakeFirebaseRtdb server,
  String restaurantId,
  String orderId,
) async {
  final bool ok = await FirebaseTrackingService.instance.markOrderPickedUp(
    orderId: orderId,
  );
  expect(ok, isTrue, reason: 'تغيير الحالة في تطبيق المدير يجب أن ينجح');
  await _waitUntil(
    () async => server.read('restaurants/$restaurantId/snapshot') != null,
  );
}

/// انتظار حقيقي (بلا fake async) حتى يتحقق الشرط أو تنتهي المهلة.
Future<void> _waitUntil(
  Future<bool> Function() condition, {
  Duration timeout = _syncTimeout,
  String reason = 'لم يتحقق الشرط داخل المهلة',
}) async {
  final DateTime deadline = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(deadline)) {
    if (await condition()) return;
    await Future<void>.delayed(const Duration(milliseconds: 150));
  }
  fail('$reason (${timeout.inSeconds}s)');
}

/// قراءة أسطر قناة SSE حتى ظهور سطر مطابق (أو انتهاء المهلة).
Future<List<String>> _readStreamUntil(
  StreamIterator<String> iterator,
  String needle, {
  Duration timeout = const Duration(seconds: 10),
}) async {
  final List<String> seen = <String>[];
  final DateTime deadline = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(deadline)) {
    bool hasNext;
    try {
      hasNext = await iterator
          .moveNext()
          .timeout(const Duration(seconds: 5), onTimeout: () => false);
    } catch (_) {
      hasNext = false;
    }
    if (!hasNext) break;
    final String line = iterator.current;
    seen.add(line);
    if (line.contains(needle)) return seen;
  }
  fail('لم يصل "$needle" على قناة SSE. ما ورد: $seen');
}

/// لقطة الطلبات المسجّلة لسائق معيّن كما يراها تطبيق المدير محلياً.
Future<List<DeliveryOrder>> _managerOrdersFor(String driverPin) =>
    FirebaseTrackingService.instance.getOrdersForDriver(driverPin);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // flutter_test يستبدل HttpClient بمُحاكي يمنع الشبكة — نُعيد العميل الحقيقي
  // حتى تُنفَّذ طلبات HTTP فعلياً على الخادم المحلي.
  HttpOverrides.global = null;

  late FakeFirebaseRtdb server;

  setUp(() async {
    HttpOverrides.global = null;
    server = FakeFirebaseRtdb();
    await server.start();
    await _resetLocalState();
  });

  tearDown(() async {
    FirebaseRealtimeService.instance.dispose();
    await AppSettings.setFirebaseDatabaseUrl('');
    // مهلة قصيرة ليُكمل أي طلب غير مُنتظَر (كتابة/فحص heartbeat) قبل إغلاق
    // الخادم، فلا تظهر أخطاء اتصال مضللة في السجل.
    await Future<void>.delayed(const Duration(milliseconds: 300));
    await server.stop();
  });

  test(
    'دخول العامل عبر الشبكة: عزل تام بين مطعمين بنفس الاسم وكلمة المرور',
    () async {
      // مطعمان مختلفان بنفس اسم العامل ونفس كلمة المرور الافتراضية '1234'.
      await _startManagerApp(server, _rid1);
      await _resetLocalState();
      await _startManagerApp(server, _rid2);

      // جهاز عامل جديد تماماً: لا بيانات محلية، والدخول من السحابة.
      await _resetLocalState();
      expect(
        (await SharedPreferences.getInstance()).getKeys(),
        isEmpty,
        reason: 'يجب أن يبدأ العامل من حالة فارغة (جهاز جديد)',
      );

      final WorkerWebService worker1 = WorkerWebService(
        databaseUrl: server.baseUrl,
        restaurantId: _rid1,
      );
      final WorkerWebService worker2 = WorkerWebService(
        databaseUrl: server.baseUrl,
        restaurantId: _rid2,
      );

      final StaffAuthResult auth1 = await worker1.authenticate(
        username: _driverName,
        secret: _workerPassword,
      );
      final StaffAuthResult auth2 = await worker2.authenticate(
        username: _driverName,
        secret: _workerPassword,
      );

      expect(auth1.success, isTrue, reason: auth1.message);
      expect(auth2.success, isTrue, reason: auth2.message);
      expect(auth1.staff!.restaurantId, _rid1);
      expect(auth2.staff!.restaurantId, _rid2);
      expect(
        auth1.staff!.staffId,
        isNot(auth2.staff!.staffId),
        reason: 'نفس الاسم في مطعمين مختلفين = حسابان مستقلان',
      );
      expect(auth1.staff!.staffId, StaffMember.buildStaffId(_rid1, _driverName));
      expect(auth2.staff!.staffId, StaffMember.buildStaffId(_rid2, _driverName));
      expect(auth1.staff!.isWorker, isTrue);

      // الدخول بالـ PIN أيضاً (بديل كلمة المرور) عبر الشبكة.
      final StaffAuthResult byPin = await worker1.authenticate(
        username: _driverName,
        secret: auth1.staff!.pin,
      );
      expect(byPin.success, isTrue, reason: byPin.message);
      expect(byPin.staff!.staffId, auth1.staff!.staffId);

      // معرّف مطعم غير مسجّل سحابياً → رفض صريح.
      final StaffAuthResult unknownRid = await WorkerWebService(
        databaseUrl: server.baseUrl,
        restaurantId: 'MISSING01',
      ).authenticate(username: _driverName, secret: _workerPassword);
      expect(unknownRid.success, isFalse);

      // الحسابات مفصولة فعلياً في مسارين مختلفين داخل نفس قاعدة البيانات.
      final Object? cloud1 = server.read('restaurants/$_rid1/staff');
      final Object? cloud2 = server.read('restaurants/$_rid2/staff');
      expect(cloud1, isNotNull);
      expect(cloud2, isNotNull);
      expect((cloud1! as Map<Object?, Object?>).keys, isNot(equals((cloud2! as Map<Object?, Object?>).keys)));
    },
    timeout: const Timeout(Duration(minutes: 2)),
  );

  test(
    'مزامنة لحظية في الاتجاهين: طلب المدير يصل للعامل وطلب العامل يصل للمدير',
    () async {
      await _startManagerApp(server, _rid1);
      // عامل المطعم على جهاز المدير (APK) قبل تصفير جهاز الويب.
      final Driver driver = (await DriverStorage.loadDrivers()).single;

      // ① العامل يسجّل الدخول من جهاز ويب جديد (بيانات الحساب من السحابة).
      await _resetLocalState();
      final WorkerWebService worker = WorkerWebService(
        databaseUrl: server.baseUrl,
        restaurantId: _rid1,
      );
      final StaffAuthResult auth = await worker.authenticate(
        username: _driverName,
        secret: _workerPassword,
      );
      expect(auth.success, isTrue, reason: auth.message);
      final StaffMember staff = auth.staff!;
      expect(staff.driverPin, isNotEmpty);

      // ② المدير (APK) يسجّل طلباً محلياً ثم يدفعه للسحابة بمسار الخدمة نفسه.
      final DeliveryOrder managerOrder = DeliveryOrder(
        orderNumber: 'M-77',
        amount: 7000,
        driverPin: driver.pin,
        driverName: driver.name,
      );
      await DriverStorage.saveDriver(driver.addDeliveryOrder(managerOrder));
      await _managerPushAndWait(server, _rid1, managerOrder.id);

      // ③ العامل يرى طلب المدير فوراً من السحابة (مدير ← عامل).
      await _waitUntil(() async {
        final List<DeliveryOrder> orders = await worker.loadOrders(
          driverPin: staff.driverPin,
          driverName: staff.name,
        );
        return orders.any((DeliveryOrder o) => o.id == managerOrder.id) &&
            orders
                    .firstWhere((DeliveryOrder o) => o.id == managerOrder.id)
                    .status ==
                OrderStatus.pickedUp;
      }, reason: 'طلب المدير لم يصل إلى واجهة العامل');

      // ④ العامل يرسل طلباً جديداً مع صورة إثبات (موثّق بالصورة).
      const String proof = 'data:image/jpeg;base64,/9j/4AAQSkZJRgABAQAAAQ==';
      final bool created = await worker.createOrder(
        driverPin: staff.driverPin,
        driverName: staff.name,
        orderNumber: 'W-12',
        amount: 4500,
        paymentType: OrderPaymentType.cash,
        proofImageData: proof,
      );
      expect(created, isTrue, reason: 'إرسال طلب العامل للسحابة فشل');

      // ⑤ تطبيق المدير يلتقط طلب العامل خلال دورة المزامنة (عامل ← مدير).
      await _waitUntil(() async {
        final List<DeliveryOrder> orders = await _managerOrdersFor(driver.pin);
        final Iterable<DeliveryOrder> fromWorker = orders.where(
          (DeliveryOrder o) => o.orderNumber == 'W-12',
        );
        return fromWorker.length == 1 &&
            fromWorker.single.amount == 4500 &&
            fromWorker.single.proofImageData == proof &&
            fromWorker.single.status == OrderStatus.preparing;
      }, reason: 'طلب العامل لم يصل إلى تطبيق المدير');

      // ⑥ الطلبان موجودان معاً عند الطرفين (لا فقدان ولا كتابة فوق بعضها).
      final List<DeliveryOrder> managerOrders = await _managerOrdersFor(driver.pin);
      expect(
        managerOrders.map((DeliveryOrder o) => o.orderNumber),
        containsAll(<String>['M-77', 'W-12']),
      );
      final List<DeliveryOrder> workerOrders = await worker.loadOrders(
        driverPin: staff.driverPin,
        driverName: staff.name,
      );
      expect(
        workerOrders.map((DeliveryOrder o) => o.orderNumber),
        containsAll(<String>['M-77', 'W-12']),
      );

      // ⑦ قناة العامل اللحظية: أي تغيير من المدير يُنبّه الواجهة تلقائياً.
      int notifications = 0;
      worker.startLiveSync(() => notifications++);
      addTearDown(worker.stopLiveSync);
      await Future<void>.delayed(const Duration(milliseconds: 600));
      final int baseline = notifications;
      final DeliveryOrder workerOrder = workerOrders.firstWhere(
        (DeliveryOrder o) => o.orderNumber == 'W-12',
      );

      // المدير يغيّر حالة طلب العامل (كما يفعل عند ضغط «تم التسليم»).
      final bool delivered =
          await FirebaseTrackingService.instance.markOrderDelivered(
        orderId: workerOrder.id,
      );
      expect(delivered, isTrue);

      await _waitUntil(
        () async => notifications > baseline,
        reason: 'قناة العامل اللحظية لم تُنبّه بأي تغيير قادم من المدير',
      );
      await _waitUntil(() async {
        final List<DeliveryOrder> orders = await worker.loadOrders(
          driverPin: staff.driverPin,
          driverName: staff.name,
        );
        return orders
                .firstWhere((DeliveryOrder o) => o.id == workerOrder.id)
                .status ==
            OrderStatus.delivered;
      }, reason: 'حالة التسليم من المدير لم تصل لواجهة العامل');

      // ⑧ كل هذا داخل مسار المطعم فقط (لا تسرّب لمطعم آخر).
      expect(server.read('restaurants/$_rid2/snapshot'), isNull);
      expect(
        jsonEncode(server.read('restaurants/$_rid1/snapshot')),
        contains('W-12'),
      );
    },
    timeout: const Timeout(Duration(minutes: 3)),
  );

  test(
    'عقد ETag/If-Match: 412 عند التعارض + إعادة محاولة العامل بلا فقدان طلبات',
    () async {
      // ① الطبقة السحابية تفرض ETag تماماً كما يفعل Firebase.
      final Uri probe = Uri.parse(
        '${server.baseUrl}/restaurants/$_rid1/probe.json',
      );
      final http.Response empty = await http.get(
        probe,
        headers: <String, String>{'X-Firebase-ETag': 'true'},
      );
      expect(empty.statusCode, 200);
      expect(empty.body, 'null');
      final String? etag = empty.headers['etag'];
      expect(etag, isNotNull, reason: 'Firebase يُرجِع ETag عند طلبه');

      final http.Response firstWrite = await http.put(
        probe,
        headers: <String, String>{
          'Content-Type': 'application/json',
          'X-Firebase-ETag': 'true',
          'If-Match': etag!,
        },
        body: jsonEncode(<String, Object?>{'value': 1}),
      );
      expect(firstWrite.statusCode, 200);
      final String freshEtag = firstWrite.headers['etag']!;
      expect(freshEtag, isNot(etag));

      // نسخة قديمة → 412 (وهو ما يُجبر كود العامل على إعادة القراءة).
      final http.Response stale = await http.put(
        probe,
        headers: <String, String>{
          'Content-Type': 'application/json',
          'If-Match': etag,
        },
        body: jsonEncode(<String, Object?>{'value': 2}),
      );
      expect(stale.statusCode, 412);
      expect(server.conflictCount, 1);

      // ② تجهيز الحالة الحقيقية: المدير يدفع snapshot يحوي طلباً سابقاً.
      await _startManagerApp(server, _rid1);
      final Driver driver = (await DriverStorage.loadDrivers()).single;
      final DeliveryOrder managerOrder = DeliveryOrder(
        orderNumber: 'A-0',
        amount: 1000,
        driverPin: driver.pin,
        driverName: driver.name,
      );
      await DriverStorage.saveDriver(driver.addDeliveryOrder(managerOrder));
      await _managerPushAndWait(server, _rid1, managerOrder.id);
      final int conflictsBefore = server.conflictCount;

      // ③ إجبار تعارض ETag حقيقي أثناء كتابة العامل: نُبطل الرمز بين
      //    قراءة العامل للـ snapshot وكتابته، فيُرفض أول PUT برمز 412.
      bool failedOnce = false;
      server.onBeforePut = (String path) {
        if (!failedOnce && path.endsWith('/snapshot')) {
          failedOnce = true;
          server.invalidateEtag(path);
        }
      };
      addTearDown(() => server.onBeforePut = null);

      await _resetLocalState();
      final WorkerWebService worker = WorkerWebService(
        databaseUrl: server.baseUrl,
        restaurantId: _rid1,
      );
      final StaffAuthResult auth = await worker.authenticate(
        username: _driverName,
        secret: _workerPassword,
      );
      expect(auth.success, isTrue, reason: auth.message);

      final bool created = await worker.createOrder(
        driverPin: auth.staff!.driverPin,
        driverName: auth.staff!.name,
        orderNumber: 'A-1',
        amount: 3300,
        paymentType: OrderPaymentType.cash,
      );
      expect(created, isTrue, reason: 'إعادة المحاولة بعد 412 يجب أن تنجح');
      expect(
        server.conflictCount,
        greaterThan(conflictsBefore),
        reason: 'يجب أن يكون هناك تعارض ETag حقيقي واحد على الأقل',
      );

      // ④ لا فقدان بيانات: طلب المدير السابق + طلب العامل موجودان سحابياً.
      final Object? snapshot = server.read('restaurants/$_rid1/snapshot');
      final String snapshotText = jsonEncode(snapshot);
      expect(snapshotText, contains('A-0'));
      expect(snapshotText, contains('A-1'));

      final List<DeliveryOrder> orders = await worker.loadOrders(
        driverPin: auth.staff!.driverPin,
        driverName: auth.staff!.name,
      );
      expect(
        orders.map((DeliveryOrder o) => o.orderNumber),
        containsAll(<String>['A-0', 'A-1']),
      );
    },
    timeout: const Timeout(Duration(minutes: 2)),
  );

  test(
    'عقد البث اللحظي SSE: event=put على heartbeat.json كما يستهلكه EventSource',
    () async {
      final HttpClient client = HttpClient();
      addTearDown(() => client.close(force: true));
      final Uri heartbeat = Uri.parse(
        '${server.baseUrl}/restaurants/$_rid1/heartbeat.json',
      );

      final HttpClientRequest request = await client.getUrl(heartbeat);
      request.headers.set(HttpHeaders.acceptHeader, 'text/event-stream');
      final HttpClientResponse response = await request.close();
      expect(response.statusCode, 200);
      expect(response.headers.contentType?.mimeType, 'text/event-stream');

      final StreamIterator<String> lines = StreamIterator<String>(
        response.transform(utf8.decoder).transform(const LineSplitter()),
      );
      addTearDown(lines.cancel);

      // Firebase يرسل keep-alive ترحيبياً فور الاتصال.
      await _readStreamUntil(lines, 'event: keep-alive');

      // العامل يكتب heartbeat (نفس ما يفعله createOrder بعد كل حفظ).
      final int stamp = DateTime.now().millisecondsSinceEpoch;
      final http.Response put = await http.put(
        heartbeat,
        headers: <String, String>{'Content-Type': 'application/json'},
        body: stamp.toString(),
      );
      expect(put.statusCode, 200);

      // يجب أن يصل حدث put بالمسار والقيمة الجديدة (وهو ما يُشغّل onChange
      // في `_worker_live_channel_web.dart` داخل متصفح الآيفون).
      final List<String> received = await _readStreamUntil(lines, 'event: put');
      expect(received, contains('event: put'));
      // سطر البيانات الخاص بحدث put: المسار النسبي '/' (كتابة على نفس المسار)
      // والقيمة الجديدة (طابع heartbeat) — وهو ما يُشغّل onChange في المتصفح.
      final List<String> withData = await _readStreamUntil(
        lines,
        '"path":"/"',
      );
      final String dataLine = withData.firstWhere(
        (String line) => line.startsWith('data: '),
      );
      expect(
        dataLine,
        contains('"path":"/"'),
      );
      expect(dataLine, contains('$stamp'));
    },
    timeout: const Timeout(Duration(minutes: 1)),
  );

  test(
    'كتابة المدير لا تُلغي طلباً أرسله العامل (دمج + ETag 412)',
    () async {
      await _startManagerApp(server, _rid1);
      final Driver driver = (await DriverStorage.loadDrivers()).single;

      // ① المدير ينشئ طلباً من جهازه ويرفعه للسحابة.
      final DeliveryOrder managerOrder = DeliveryOrder(
        orderNumber: 'M-01',
        amount: 6000,
        driverPin: driver.pin,
        driverName: driver.name,
      );
      await DriverStorage.saveDriver(driver.addDeliveryOrder(managerOrder));
      await _managerPushAndWait(server, _rid1, managerOrder.id);
      final Driver managerDriver = (await DriverStorage.loadDrivers()).single;

      // ② العامل (الويب) يرسل طلباً آخر إلى نفس المطعم.
      final WorkerWebService worker = WorkerWebService(
        databaseUrl: server.baseUrl,
        restaurantId: _rid1,
      );
      final StaffAuthResult auth = await worker.authenticate(
        username: _driverName,
        secret: _workerPassword,
      );
      expect(auth.success, isTrue, reason: auth.message);
      expect(
        await worker.createOrder(
          driverPin: auth.staff!.driverPin,
          driverName: auth.staff!.name,
          orderNumber: 'W-01',
          amount: 5000,
          paymentType: OrderPaymentType.cash,
        ),
        isTrue,
      );

      // ③ المدير لا يزال لا يعرف بطلب العامل (نُعيد حالته المحلية القديمة)
      //    ثم يكتب من جهازه — وهنا كان يُفقد طلب العامل قبل الإصلاح.
      await DriverStorage.saveDriver(
        managerDriver.copyWith(orders: <DeliveryOrder>[managerOrder]),
      );

      // ④ نُجبر أيضاً تعارض ETag حقيقياً أثناء كتابة المدير لنتحقق من التعافي.
      bool canceledOnce = false;
      server.onBeforePut = (String path) {
        if (!canceledOnce && path.endsWith('/snapshot')) {
          canceledOnce = true;
          server.invalidateEtag(path);
        }
      };
      addTearDown(() => server.onBeforePut = null);
      final int conflictsBefore = server.conflictCount;
      final int writesBefore = server.writeCount;

      expect(
        await FirebaseTrackingService.instance.markOrderPickedUp(
          orderId: managerOrder.id,
        ),
        isTrue,
      );

      // ⑤ ننتظر اكتمال كتابة المدير فعلياً: طلبه + طلب العامل المدموج محلياً
      //    (الدمج المحلي لا يحدث إلا بعد نجاح الكتابة، فهو دليل اكتمالها).
      await _waitUntil(() async {
        if (server.writeCount <= writesBefore) return false;
        final List<DeliveryOrder> orders = await _managerOrdersFor(driver.pin);
        return orders.any((DeliveryOrder o) => o.orderNumber == 'W-01') &&
            orders.any((DeliveryOrder o) => o.orderNumber == 'M-01');
      }, reason: 'لم تُكمل كتابة المدير دمج طلب العامل');

      // ⑥ لا فقدان في السحابة: الطلبان موجودان.
      final String cloudSnapshot =
          jsonEncode(server.read('restaurants/$_rid1/snapshot'));
      expect(cloudSnapshot, contains('W-01'));
      expect(cloudSnapshot, contains('M-01'));

      // ⑦ وتعارض ETag حقيقي حدث فعلاً ثم تعافى الكود بإعادة القراءة والدمج.
      expect(server.conflictCount, greaterThan(conflictsBefore));

      // ⑧ والعامل يرى الطلبين أيضاً.
      final List<DeliveryOrder> workerOrders = await worker.loadOrders(
        driverPin: auth.staff!.driverPin,
        driverName: auth.staff!.name,
      );
      expect(
        workerOrders.map((DeliveryOrder o) => o.orderNumber),
        containsAll(<String>['M-01', 'W-01']),
      );
    },
    timeout: const Timeout(Duration(minutes: 3)),
  );

  test(
    'طلب حذفه المدير لا يعود للظهور بعد الدمج (العلامة الزمنية)',
    () async {
      await _startManagerApp(server, _rid1);
      final Driver driver = (await DriverStorage.loadDrivers()).single;

      // ① طلب قديم للمدير يُرفع للسحابة.
      final DeliveryOrder oldOrder = DeliveryOrder(
        orderNumber: 'M-OLD',
        amount: 2000,
        driverPin: driver.pin,
        driverName: driver.name,
        addedAt: DateTime.now().subtract(const Duration(minutes: 5)),
      );
      await DriverStorage.saveDriver(driver.addDeliveryOrder(oldOrder));
      await _managerPushAndWait(server, _rid1, oldOrder.id);

      // ② العامل يضيف طلباً جديداً → المدير يستقبله (تتحرك العلامة الزمنية).
      final WorkerWebService worker = WorkerWebService(
        databaseUrl: server.baseUrl,
        restaurantId: _rid1,
      );
      expect(
        await worker.createOrder(
          driverPin: driver.pin,
          driverName: driver.name,
          orderNumber: 'W-NEW',
          amount: 3000,
          paymentType: OrderPaymentType.cash,
        ),
        isTrue,
      );
      await _waitUntil(() async {
        final List<DeliveryOrder> orders = await _managerOrdersFor(driver.pin);
        return orders.any((DeliveryOrder o) => o.orderNumber == 'W-NEW');
      }, reason: 'المدير لم يستقبل طلب العامل الجديد');

      // ③ المدير يحذف الطلب القديم محلياً (كما يفعل من سجل الطلبات)
      //    ثم يدفع تغييره للسحابة.
      final List<DeliveryOrder> beforeDelete = await _managerOrdersFor(
        driver.pin,
      );
      final DeliveryOrder freshOrder = beforeDelete.firstWhere(
        (DeliveryOrder o) => o.orderNumber == 'W-NEW',
      );
      await DriverStorage.saveDrivers(<Driver>[
        driver.copyWith(
          orders: beforeDelete
              .where((DeliveryOrder o) => o.id != oldOrder.id)
              .toList(),
        ),
      ]);
      expect(
        await FirebaseTrackingService.instance.markOrderPickedUp(
          orderId: freshOrder.id,
        ),
        isTrue,
      );

      // ④ الطلب المحذوف لا يعود، والجديد محفوظ — في الجهاز وفي السحابة.
      await _waitUntil(() async {
        final List<DeliveryOrder> orders = await _managerOrdersFor(driver.pin);
        return !orders.any((DeliveryOrder o) => o.orderNumber == 'M-OLD') &&
            orders.any((DeliveryOrder o) => o.orderNumber == 'W-NEW');
      }, reason: 'الطلب المحذوف عاد للظهور محلياً بعد الدمج');
      await _waitUntil(
        () async => !jsonEncode(server.read('restaurants/$_rid1/snapshot'))
            .contains('M-OLD'),
        reason: 'الطلب المحذوف ما زال في السحابة',
      );
    },
    timeout: const Timeout(Duration(minutes: 3)),
  );
}

