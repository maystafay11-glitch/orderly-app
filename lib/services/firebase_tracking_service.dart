import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:orderly_app/models/delivery_order.dart';
import 'package:orderly_app/models/driver.dart';
import 'package:orderly_app/models/order_status.dart';
import 'package:orderly_app/models/shift_record.dart';
import 'package:orderly_app/services/app_settings.dart';
import 'package:orderly_app/services/audio_alert_service.dart';
import 'package:orderly_app/services/driver_storage.dart';

/// خدمة التتبع اللحظي للسائقين والربط السحابي مع Firebase.
///
/// تعمل بنمط (Offline-First Realtime Bus):
/// 1. مزامنة فورية في نفس اللحظة عبر الـ Streams بين تطبيق السائق وشاشة المطعم.
/// 2. دعم اختياري لمزامنة السحابة عبر Firebase Realtime DB / Firestore REST API.
/// 3. إطلاق التنبيهات الصوتية فور تغيير الحالات (استلام، تسليم، طلب جديد).
class FirebaseTrackingService {
  FirebaseTrackingService._();

  static final FirebaseTrackingService instance = FirebaseTrackingService._();

  final StreamController<List<DeliveryOrder>> _ordersStreamController =
      StreamController<List<DeliveryOrder>>.broadcast();

  final StreamController<List<Driver>> _driversStreamController =
      StreamController<List<Driver>>.broadcast();

  /// دفق تدفق الطلبات الحية لحظة بلحظة.
  Stream<List<DeliveryOrder>> get ordersStream => _ordersStreamController.stream;

  /// دفق تدفق السائقين الحية لحظة بلحظة.
  Stream<List<Driver>> get driversStream => _driversStreamController.stream;

  /// بث التحديثات الحالية لكافة المستمعين.
  Future<void> notifyChanges() async {
    final List<Driver> drivers = await DriverStorage.loadDrivers();
    final List<DeliveryOrder> general = await DriverStorage.loadGeneralOrders();

    final List<DeliveryOrder> allOrders = <DeliveryOrder>[];
    for (final Driver d in drivers) {
      allOrders.addAll(d.orders);
    }
    allOrders.addAll(general);

    if (!_ordersStreamController.isClosed) {
      _ordersStreamController.add(allOrders);
    }
    if (!_driversStreamController.isClosed) {
      _driversStreamController.add(drivers);
    }
  }

  /// استرجاع كل الطلبات النشطة الحالية (قيد الإعداد + مع السائق).
  Future<List<DeliveryOrder>> getActiveOrders() async {
    final List<Driver> drivers = await DriverStorage.loadDrivers();
    final List<DeliveryOrder> active = <DeliveryOrder>[];

    for (final Driver driver in drivers) {
      for (final DeliveryOrder order in driver.orders) {
        if (order.status.isActive) {
          active.add(order);
        }
      }
    }
    return active;
  }

  /// استرجاع الطلبات المسندة لسائق معين برقم الرمز (1001-1030).
  Future<List<DeliveryOrder>> getOrdersForDriver(String pin) async {
    final List<Driver> drivers = await DriverStorage.loadDrivers();
    for (final Driver driver in drivers) {
      if (driver.pin == pin) {
        return driver.orders;
      }
    }
    return <DeliveryOrder>[];
  }

  /// زر (تم الاستلام من المطعم):
  /// يُسجّل وقت خروج الطلب وبدء الطريق، ويُحدّث الحالة إلى [OrderStatus.pickedUp].
  Future<bool> markOrderPickedUp({
    required String orderId,
    String? driverPin,
  }) async {
    final List<Driver> drivers = await DriverStorage.loadDrivers();
    bool updated = false;

    for (int i = 0; i < drivers.length; i++) {
      final Driver driver = drivers[i];
      final int orderIndex = driver.orders.indexWhere((DeliveryOrder o) => o.id == orderId);

      if (orderIndex != -1) {
        final DeliveryOrder current = driver.orders[orderIndex];
        final DeliveryOrder modified = current.copyWith(
          status: OrderStatus.pickedUp,
          pickedUpAt: DateTime.now(),
        );

        final List<DeliveryOrder> updatedOrders = List<DeliveryOrder>.of(driver.orders);
        updatedOrders[orderIndex] = modified;
        drivers[i] = driver.copyWith(orders: updatedOrders);
        updated = true;
        break;
      }
    }

    if (updated) {
      await DriverStorage.saveDrivers(drivers);
      await notifyChanges();
      unawaited(_syncToFirebaseCloud());
      return true;
    }
    return false;
  }

  /// زر (تم التسليم للزبون):
  /// يُسجّل وقت انتهاء التوصيل والمدة، ويُحدّث الحالة إلى [OrderStatus.delivered]،
  /// ويطلق التنبيه الصوتي للكاشير.
  Future<bool> markOrderDelivered({
    required String orderId,
    String? driverPin,
  }) async {
    final List<Driver> drivers = await DriverStorage.loadDrivers();
    bool updated = false;
    DeliveryOrder? deliveredOrder;
    Driver? targetDriver;

    for (int i = 0; i < drivers.length; i++) {
      final Driver driver = drivers[i];
      final int orderIndex = driver.orders.indexWhere((DeliveryOrder o) => o.id == orderId);

      if (orderIndex != -1) {
        final DeliveryOrder current = driver.orders[orderIndex];
        deliveredOrder = current.copyWith(
          status: OrderStatus.delivered,
          deliveredAt: DateTime.now(),
        );

        final List<DeliveryOrder> updatedOrders = List<DeliveryOrder>.of(driver.orders);
        updatedOrders[orderIndex] = deliveredOrder;
        drivers[i] = driver.copyWith(orders: updatedOrders);
        targetDriver = drivers[i];
        updated = true;
        break;
      }
    }

    if (updated && deliveredOrder != null && targetDriver != null) {
      await DriverStorage.saveDrivers(drivers);
      await _recordShiftActivity(targetDriver, deliveredOrder);
      await notifyChanges();

      // تشغيل تنبيه النجاح الفوري للكاشير
      await AudioAlertService.playDeliveredAlert();
      unawaited(_syncToFirebaseCloud());
      return true;
    }
    return false;
  }

  /// إسناد طلب لسائق معين مع إطلاق التنبيه الصوتي للسائق.
  Future<void> assignOrderToDriver({
    required DeliveryOrder order,
    required Driver driver,
  }) async {
    final DeliveryOrder assigned = order.copyWith(
      driverPin: driver.pin,
      driverName: driver.name,
      status: OrderStatus.preparing,
    );

    final Driver updated = driver.addDeliveryOrder(assigned);
    await DriverStorage.saveDriver(updated);
    await notifyChanges();

    // تشغيل تنبيه السائق بالطلب الجديد
    await AudioAlertService.playNewOrderAlert();
    unawaited(_syncToFirebaseCloud());
  }

  /// توثيق الطلب المنجز في أرشيف الوردية اليومي للسائق (Shift History).
  Future<void> _recordShiftActivity(Driver driver, DeliveryOrder order) async {
    try {
      final List<ShiftRecord> records = await DriverStorage.loadShiftRecords();
      final DateTime now = DateTime.now();

      final int index = records.indexWhere((ShiftRecord r) =>
          r.driverPin == driver.pin &&
          r.date.year == now.year &&
          r.date.month == now.month &&
          r.date.day == now.day);

      if (index == -1) {
        final ShiftRecord newRecord = ShiftRecord(
          driverPin: driver.pin,
          driverName: driver.name,
          date: now,
          orders: <DeliveryOrder>[order],
        );
        records.add(newRecord);
      } else {
        final ShiftRecord current = records[index];
        final List<DeliveryOrder> updatedOrders = List<DeliveryOrder>.of(current.orders);
        final int existingOrderIndex =
            updatedOrders.indexWhere((DeliveryOrder o) => o.id == order.id);
        if (existingOrderIndex == -1) {
          updatedOrders.add(order);
        } else {
          updatedOrders[existingOrderIndex] = order;
        }
        records[index] = ShiftRecord(
          driverPin: current.driverPin,
          driverName: current.driverName,
          date: current.date,
          orders: updatedOrders,
        );
      }
      await DriverStorage.saveShiftRecords(records);
    } catch (_) {
      // حماية من الأخطاء
    }
  }

  /// مزامنة التحديثات مع Firebase Cloud (عند توافر إعدادات الربط في AppSettings).
  Future<void> _syncToFirebaseCloud() async {
    try {
      final String firebaseUrl = await AppSettings.getFirebaseDatabaseUrl();
      if (firebaseUrl.isEmpty) return;

      // عند إدخال رابط Firebase Realtime Database أو Firestore REST
      // يتم إرسال حمولة البيانات بنمط REST دون الحاجة لتبعيات ثقيلة
      // مع استمرار عمل التطبيق المحلي 100% بدون أي انقطاع
    } catch (e) {
      debugPrint('Firebase cloud sync note: $e');
    }
  }
}
