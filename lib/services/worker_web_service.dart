import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'package:orderly_app/models/delivery_order.dart';
import 'package:orderly_app/models/driver.dart';
import 'package:orderly_app/models/order_payment_type.dart';
import 'package:orderly_app/models/order_status.dart';
import 'package:orderly_app/models/staff_member.dart';
import 'package:orderly_app/services/app_settings.dart';
import 'package:orderly_app/services/staff_directory_service.dart';
import 'package:orderly_app/services/worker_live_channel.dart';

/// نتيجة جلب لقطة المطعم مع بصمة ETag لمنع الكتابة فوق تحديث المدير.
class RestaurantSnapshot {
  const RestaurantSnapshot({this.data, this.etag});

  final Map<String, dynamic>? data;
  final String? etag;

  List<Driver> get drivers => readDrivers(data);

  static List<Driver> readDrivers(Map<String, dynamic>? snapshot) {
    if (snapshot == null) return <Driver>[];
    final Object? raw = snapshot['drivers'];
    if (raw is! List) return <Driver>[];
    return raw
        .whereType<Map<Object?, Object?>>()
        .map(
          (Map<Object?, Object?> item) =>
              Driver.fromJson(Map<String, dynamic>.from(item)),
        )
        .toList();
  }

  static List<DeliveryOrder> ordersForDriver(
    List<Driver> drivers, {
    required String driverPin,
    String driverName = '',
  }) {
    for (final Driver driver in drivers) {
      if (driver.pin == driverPin && driverPin.isNotEmpty) {
        return List<DeliveryOrder>.of(driver.orders);
      }
    }
    final String needle = StaffMember.normalizeUsername(driverName);
    if (needle.isEmpty) return <DeliveryOrder>[];
    for (final Driver driver in drivers) {
      if (StaffMember.normalizeUsername(driver.name) == needle) {
        return List<DeliveryOrder>.of(driver.orders);
      }
    }
    return <DeliveryOrder>[];
  }

  static int indexOfDriver(
    List<Driver> drivers, {
    required String driverPin,
    String driverName = '',
  }) {
    final int byPin = drivers.indexWhere(
      (Driver item) => item.pin == driverPin && driverPin.isNotEmpty,
    );
    if (byPin != -1) return byPin;
    final String needle = StaffMember.normalizeUsername(driverName);
    if (needle.isEmpty) return -1;
    return drivers.indexWhere(
      (Driver item) => StaffMember.normalizeUsername(item.name) == needle,
    );
  }
}

/// بوابة REST لنسخة العامل على الويب فقط — بدون أي عمليات لوحة المدير.
class WorkerWebService {
  WorkerWebService({required String databaseUrl, required String restaurantId})
      : _databaseUrl = databaseUrl.trim().replaceAll(RegExp(r'/$'), ''),
        _restaurantId = StaffMember.normalizeRestaurantId(restaurantId);

  final String _databaseUrl;
  final String _restaurantId;
  final WorkerLiveChannel _live = WorkerLiveChannel();
  Timer? _pollTimer;
  int _lastHeartbeat = 0;
  bool _watching = false;

  String get restaurantId => _restaurantId;
  String get databaseUrl => _databaseUrl;

  String get _basePath =>
      '$_databaseUrl/restaurants/${Uri.encodeComponent(_restaurantId)}';

  Future<StaffAuthResult> authenticate({
    required String username,
    required String secret,
  }) async {
    await AppSettings.setFirebaseDatabaseUrl(_databaseUrl);
    return StaffDirectoryService.authenticate(
      restaurantId: _restaurantId,
      username: username,
      secret: secret,
    );
  }

  Future<List<DeliveryOrder>> loadOrders({
    required String driverPin,
    String driverName = '',
  }) async {
    final RestaurantSnapshot snapshot = await _fetchSnapshot();
    return RestaurantSnapshot.ordersForDriver(
      snapshot.drivers,
      driverPin: driverPin,
      driverName: driverName,
    );
  }

  /// مزامنة لحظية: بث SSE على الويب + فحص heartbeat كل ثانيتين.
  void startLiveSync(void Function() onChange) {
    stopLiveSync();
    _watching = true;
    _live.start(
      streamUrl: '$_basePath/heartbeat.json',
      onChange: onChange,
    );
    _pollTimer = Timer.periodic(const Duration(seconds: 2), (_) async {
      if (!_watching) return;
      final bool changed = await _heartbeatChanged();
      if (changed) onChange();
    });
    unawaited(_heartbeatChanged().then((bool changed) {
      if (changed || _watching) onChange();
    }));
  }

  void stopLiveSync() {
    _watching = false;
    _pollTimer?.cancel();
    _pollTimer = null;
    _live.stop();
  }

  Future<bool> createOrder({
    required String driverPin,
    required String driverName,
    required String orderNumber,
    required double amount,
    required OrderPaymentType paymentType,
    String? proofImageData,
  }) {
    return _mutateDrivers((List<Driver> drivers) {
      final int driverIndex = RestaurantSnapshot.indexOfDriver(
        drivers,
        driverPin: driverPin,
        driverName: driverName,
      );
      if (driverIndex == -1) return false;
      final DeliveryOrder order = DeliveryOrder(
        orderNumber: orderNumber.trim(),
        amount: amount,
        paymentType: paymentType,
        driverPin: driverPin,
        driverName: driverName,
        proofImageData: proofImageData,
      );
      drivers[driverIndex] = drivers[driverIndex].addDeliveryOrder(order);
      return true;
    });
  }

  Future<bool> updateOrderStatus({
    required String driverPin,
    required String driverName,
    required String orderId,
    required OrderStatus status,
  }) {
    return _mutateDrivers((List<Driver> drivers) {
      final int driverIndex = RestaurantSnapshot.indexOfDriver(
        drivers,
        driverPin: driverPin,
        driverName: driverName,
      );
      if (driverIndex == -1) return false;
      final Driver driver = drivers[driverIndex];
      final int orderIndex =
          driver.orders.indexWhere((DeliveryOrder item) => item.id == orderId);
      if (orderIndex == -1) return false;
      final DeliveryOrder current = driver.orders[orderIndex];
      final DeliveryOrder changed = current.copyWith(
        status: status,
        pickedUpAt:
            status == OrderStatus.pickedUp ? DateTime.now() : current.pickedUpAt,
        deliveredAt: status == OrderStatus.delivered
            ? DateTime.now()
            : current.deliveredAt,
      );
      final List<DeliveryOrder> orders = List<DeliveryOrder>.of(driver.orders);
      orders[orderIndex] = changed;
      drivers[driverIndex] = driver.copyWith(orders: orders);
      return true;
    });
  }

  Future<bool> _mutateDrivers(bool Function(List<Driver> drivers) mutate) async {
    for (int attempt = 0; attempt < 3; attempt++) {
      final RestaurantSnapshot snapshot = await _fetchSnapshot();
      if (snapshot.data == null) return false;
      final List<Driver> drivers = List<Driver>.of(snapshot.drivers);
      if (!mutate(drivers)) return false;
      final bool ok = await _pushSnapshot(
        snapshot.data!,
        drivers,
        etag: snapshot.etag,
      );
      if (ok) return true;
    }
    return false;
  }

  Future<bool> _heartbeatChanged() async {
    try {
      final http.Response response = await http
          .get(Uri.parse('$_basePath/heartbeat.json'))
          .timeout(const Duration(seconds: 5));
      if (response.statusCode != 200) return false;
      final Object? raw = jsonDecode(response.body);
      final int heartbeat =
          raw is num ? raw.toInt() : int.tryParse('$raw') ?? 0;
      if (heartbeat != _lastHeartbeat && heartbeat > 0) {
        _lastHeartbeat = heartbeat;
        return true;
      }
      return false;
    } catch (_) {
      return false;
    }
  }

  Future<RestaurantSnapshot> _fetchSnapshot() async {
    try {
      final http.Response response = await http
          .get(
            Uri.parse('$_basePath/snapshot.json'),
            headers: <String, String>{'X-Firebase-ETag': 'true'},
          )
          .timeout(const Duration(seconds: 10));
      if (response.statusCode != 200 || response.body == 'null') {
        return const RestaurantSnapshot();
      }
      final Object? decoded = jsonDecode(response.body);
      if (decoded is! Map) return const RestaurantSnapshot();
      return RestaurantSnapshot(
        data: Map<String, dynamic>.from(decoded as Map<Object?, Object?>),
        etag: response.headers['etag'],
      );
    } catch (_) {
      return const RestaurantSnapshot();
    }
  }

  Future<bool> _pushSnapshot(
    Map<String, dynamic> snapshot,
    List<Driver> drivers, {
    String? etag,
  }) async {
    snapshot['restaurantId'] = _restaurantId;
    snapshot['updatedAt'] = DateTime.now().toIso8601String();
    snapshot['drivers'] =
        drivers.map((Driver driver) => driver.toJson()).toList();
    try {
      final Map<String, String> headers = <String, String>{
        'Content-Type': 'application/json',
        'X-Firebase-ETag': 'true',
      };
      if (etag != null && etag.isNotEmpty) {
        headers['If-Match'] = etag;
      }
      final http.Response response = await http
          .put(
            Uri.parse('$_basePath/snapshot.json'),
            headers: headers,
            body: jsonEncode(snapshot),
          )
          .timeout(const Duration(seconds: 12));
      if (response.statusCode == 412) return false;
      if (response.statusCode < 200 || response.statusCode >= 300) {
        return false;
      }
      await http.put(
        Uri.parse('$_basePath/heartbeat.json'),
        headers: <String, String>{'Content-Type': 'application/json'},
        body: DateTime.now().millisecondsSinceEpoch.toString(),
      );
      return true;
    } catch (_) {
      return false;
    }
  }
}
