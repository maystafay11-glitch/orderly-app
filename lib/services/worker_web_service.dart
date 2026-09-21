import 'dart:convert';

import 'package:http/http.dart' as http;

import 'package:orderly_app/models/delivery_order.dart';
import 'package:orderly_app/models/driver.dart';
import 'package:orderly_app/models/order_payment_type.dart';
import 'package:orderly_app/models/order_status.dart';
import 'package:orderly_app/models/staff_member.dart';
import 'package:orderly_app/services/app_settings.dart';
import 'package:orderly_app/services/staff_directory_service.dart';

/// REST gateway used only by the standalone worker web app.
/// It shares the APK snapshot contract and never exposes manager operations.
class WorkerWebService {
  WorkerWebService({required String databaseUrl, required String restaurantId})
      : _databaseUrl = databaseUrl.trim().replaceAll(RegExp(r'/$'), ''),
        _restaurantId = StaffMember.normalizeRestaurantId(restaurantId);

  final String _databaseUrl;
  final String _restaurantId;

  String get restaurantId => _restaurantId;

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

  Future<List<DeliveryOrder>> loadOrders(String driverPin) async {
    final Map<String, dynamic>? snapshot = await _fetchSnapshot();
    if (snapshot == null) return <DeliveryOrder>[];
    final List<Driver> drivers = _readDrivers(snapshot);
    for (final Driver driver in drivers) {
      if (driver.pin == driverPin) return driver.orders;
    }
    return <DeliveryOrder>[];
  }

  Future<bool> createOrder({
    required String driverPin,
    required String driverName,
    required String orderNumber,
    required double amount,
    required OrderPaymentType paymentType,
    String? proofImageData,
  }) async {
    final Map<String, dynamic>? snapshot = await _fetchSnapshot();
    if (snapshot == null) return false;
    final List<Driver> drivers = _readDrivers(snapshot);
    final int driverIndex = drivers.indexWhere((Driver item) => item.pin == driverPin);
    if (driverIndex == -1) return false;

    final DeliveryOrder order = DeliveryOrder(
      orderNumber: orderNumber.trim(),
      amount: amount,
      paymentType: paymentType,
      driverPin: driverPin,
      driverName: driverName,
      proofImageData: proofImageData,
    );
    final Driver driver = drivers[driverIndex];
    drivers[driverIndex] = driver.addDeliveryOrder(order);
    return _pushSnapshot(snapshot, drivers);
  }

  Future<bool> updateOrderStatus({
    required String driverPin,
    required String orderId,
    required OrderStatus status,
  }) async {
    final Map<String, dynamic>? snapshot = await _fetchSnapshot();
    if (snapshot == null) return false;
    final List<Driver> drivers = _readDrivers(snapshot);
    final int driverIndex = drivers.indexWhere((Driver item) => item.pin == driverPin);
    if (driverIndex == -1) return false;
    final Driver driver = drivers[driverIndex];
    final int orderIndex = driver.orders.indexWhere((DeliveryOrder item) => item.id == orderId);
    if (orderIndex == -1) return false;
    final DeliveryOrder current = driver.orders[orderIndex];
    final DeliveryOrder changed = current.copyWith(
      status: status,
      pickedUpAt: status == OrderStatus.pickedUp ? DateTime.now() : current.pickedUpAt,
      deliveredAt: status == OrderStatus.delivered ? DateTime.now() : current.deliveredAt,
    );
    final List<DeliveryOrder> orders = List<DeliveryOrder>.of(driver.orders);
    orders[orderIndex] = changed;
    drivers[driverIndex] = driver.copyWith(orders: orders);
    return _pushSnapshot(snapshot, drivers);
  }

  Future<Map<String, dynamic>?> _fetchSnapshot() async {
    try {
      final http.Response response = await http
          .get(Uri.parse('$_databaseUrl/restaurants/$_restaurantId/snapshot.json'))
          .timeout(const Duration(seconds: 10));
      if (response.statusCode != 200 || response.body == 'null') return null;
      final Object? decoded = jsonDecode(response.body);
      return decoded is Map
          ? Map<String, dynamic>.from(decoded as Map<Object?, Object?>)
          : null;
    } catch (_) {
      return null;
    }
  }

  List<Driver> _readDrivers(Map<String, dynamic> snapshot) {
    final Object? raw = snapshot['drivers'];
    if (raw is! List) return <Driver>[];
    return raw
        .whereType<Map<Object?, Object?>>()
        .map((Map<Object?, Object?> item) => Driver.fromJson(Map<String, dynamic>.from(item)))
        .toList();
  }

  Future<bool> _pushSnapshot(
    Map<String, dynamic> snapshot,
    List<Driver> drivers,
  ) async {
    snapshot['restaurantId'] = _restaurantId;
    snapshot['updatedAt'] = DateTime.now().toIso8601String();
    snapshot['drivers'] = drivers.map((Driver driver) => driver.toJson()).toList();
    try {
      final String base = '$_databaseUrl/restaurants/$_restaurantId';
      final http.Response response = await http
          .put(
            Uri.parse('$base/snapshot.json'),
            headers: <String, String>{'Content-Type': 'application/json'},
            body: jsonEncode(snapshot),
          )
          .timeout(const Duration(seconds: 10));
      if (response.statusCode < 200 || response.statusCode >= 300) return false;
      await http.put(
        Uri.parse('$base/heartbeat.json'),
        headers: <String, String>{'Content-Type': 'application/json'},
        body: DateTime.now().millisecondsSinceEpoch.toString(),
      );
      return true;
    } catch (_) {
      return false;
    }
  }
}
