import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:orderly_app/models/delivery_order.dart';
import 'package:orderly_app/models/driver.dart';
import 'package:orderly_app/models/order_status.dart';
import 'package:orderly_app/models/shift_record.dart';
import 'package:orderly_app/services/app_settings.dart';
import 'package:orderly_app/services/audio_alert_service.dart';
import 'package:orderly_app/services/driver_storage.dart';
import 'package:orderly_app/services/firebase_realtime_service.dart';
import 'package:orderly_app/services/restaurant_service.dart';

/// خدمة التتبع اللحظي للسائقين والربط السحابي مع Firebase Realtime Database.
///
/// تعمل بنمط **Offline-First + Cloud Sync**:
///
/// 1. **محلياً أولاً**: كل تغيير يُحفظ فوراً في SharedPreferences.
/// 2. **سحابياً لاحقاً**: يُرسل snapshot مشفر إلى Firebase تحت:
///    `restaurants/{restaurantId}/snapshot` لمزامنة الأجهزة الأخرى.
/// 3. **عزل تام**: كل مطعم يُكتب ويُقرأ تحت [restaurantId] الخاص به فقط.
/// 4. **تنبيهات صوتية**: تُطلَق فور تغيير الحالات (استلام / تسليم / طلب جديد).
///
/// **للعمل بدون Firebase**: يكفي عدم إدخال Database URL في الإعدادات.
///   التطبيق يعمل بالكامل محلياً بدون أي رسائل خطأ.
class FirebaseTrackingService {
  FirebaseTrackingService._();

  static final FirebaseTrackingService instance = FirebaseTrackingService._();

  final StreamController<List<DeliveryOrder>> _ordersStreamController =
      StreamController<List<DeliveryOrder>>.broadcast();

  final StreamController<List<Driver>> _driversStreamController =
      StreamController<List<Driver>>.broadcast();

  StreamSubscription<Map<String, dynamic>>? _remoteSubscription;

  bool _listeningToRemote = false;

  // ─── الواجهة العامة ───────────────────────────────────────────────────────

  /// دفق تدفق الطلبات الحية لحظة بلحظة.
  Stream<List<DeliveryOrder>> get ordersStream =>
      _ordersStreamController.stream;

  /// دفق تدفق السائقين الحية لحظة بلحظة.
  Stream<List<Driver>> get driversStream => _driversStreamController.stream;

  /// تهيئة الخدمة وبدء الاستماع للتحديثات السحابية.
  ///
  /// يُستدعى مرة واحدة عند فتح التطبيق (من [AppAuthGate] أو [main]).
  Future<void> initialize() async {
    final String firebaseUrl = await AppSettings.getFirebaseDatabaseUrl();
    if (firebaseUrl.isNotEmpty && RestaurantService.isInitialized) {
      await FirebaseRealtimeService.instance.initialize(firebaseUrl);
      _startListeningToRemote();
    }
    // إرسال البيانات المحلية الحالية للمستمعين
    await notifyChanges();
  }

  /// إعادة تهيئة Firebase عند تغيير URL في الإعدادات.
  Future<void> reinitializeFirebase() async {
    _remoteSubscription?.cancel();
    _listeningToRemote = false;
    FirebaseRealtimeService.instance.dispose();
    await initialize();
  }

  // ─── بث التحديثات ─────────────────────────────────────────────────────────

  /// بث التحديثات الحالية لكافة المستمعين المحليين.
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

  // ─── استرجاع البيانات ─────────────────────────────────────────────────────

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

  // ─── تحديث حالات الطلبات ─────────────────────────────────────────────────

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
      final int orderIndex =
          driver.orders.indexWhere((DeliveryOrder o) => o.id == orderId);

      if (orderIndex != -1) {
        final DeliveryOrder current = driver.orders[orderIndex];
        final DeliveryOrder modified = current.copyWith(
          status: OrderStatus.pickedUp,
          pickedUpAt: DateTime.now(),
        );

        final List<DeliveryOrder> updatedOrders =
            List<DeliveryOrder>.of(driver.orders);
        updatedOrders[orderIndex] = modified;
        drivers[i] = driver.copyWith(orders: updatedOrders);
        updated = true;
        break;
      }
    }

    if (updated) {
      await DriverStorage.saveDrivers(drivers);
      await notifyChanges();
      unawaited(_syncToFirebase(drivers));
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
      final int orderIndex =
          driver.orders.indexWhere((DeliveryOrder o) => o.id == orderId);

      if (orderIndex != -1) {
        final DeliveryOrder current = driver.orders[orderIndex];
        deliveredOrder = current.copyWith(
          status: OrderStatus.delivered,
          deliveredAt: DateTime.now(),
        );

        final List<DeliveryOrder> updatedOrders =
            List<DeliveryOrder>.of(driver.orders);
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
      unawaited(_syncToFirebase(drivers));
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

    final List<Driver> allDrivers = await DriverStorage.loadDrivers();
    unawaited(_syncToFirebase(allDrivers));
  }

  // ─── الاستماع للتحديثات السحابية ─────────────────────────────────────────

  /// بدء الاستماع لتحديثات Firebase الواردة من أجهزة أخرى.
  void _startListeningToRemote() {
    if (_listeningToRemote) return;
    _listeningToRemote = true;

    _remoteSubscription =
        FirebaseRealtimeService.instance.snapshotStream.listen(
      (Map<String, dynamic> snapshot) async {
        await _applyRemoteSnapshot(snapshot);
      },
      onError: (Object e) {
        debugPrint('[FirebaseTracking] خطأ في الاستماع: $e');
      },
    );
  }

  /// تطبيق snapshot وارد من Firebase على البيانات المحلية.
  Future<void> _applyRemoteSnapshot(Map<String, dynamic> snapshot) async {
    try {
      // استخراج قائمة السائقين من الـ snapshot
      final Object? driversRaw = snapshot['drivers'];
      if (driversRaw is! List) return;

      final List<Driver> remoteDrivers = driversRaw
          .whereType<Map<Object?, Object?>>()
          .map((Map<Object?, Object?> item) =>
              Driver.fromJson(Map<String, dynamic>.from(item)))
          .toList();

      // حفظ البيانات الواردة محلياً
      await DriverStorage.saveDrivers(remoteDrivers);

      // الإعلام بالتحديث الجديد
      await notifyChanges();
      debugPrint(
          '[FirebaseTracking] بيانات مُطبَّقة من Firebase: ${remoteDrivers.length} سائق');
    } catch (e) {
      debugPrint('[FirebaseTracking] _applyRemoteSnapshot خطأ: $e');
    }
  }

  // ─── المنطق الداخلي ───────────────────────────────────────────────────────

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
        final List<DeliveryOrder> updatedOrders =
            List<DeliveryOrder>.of(current.orders);
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

  /// مزامنة البيانات الكاملة مع Firebase Realtime Database.
  ///
  /// يُرسل snapshot شامل يحتوي على قائمة السائقين كاملة، مع:
  /// - [restaurantId] لضمان العزل التام
  /// - timestamp للإعلام بوجود تغيير
  Future<void> _syncToFirebase(List<Driver> drivers) async {
    if (!FirebaseRealtimeService.instance.isConfigured) return;

    try {
      final Map<String, dynamic> snapshot = <String, dynamic>{
        'restaurantId': RestaurantService.restaurantId,
        'updatedAt': DateTime.now().toIso8601String(),
        'drivers': drivers.map((Driver d) => d.toJson()).toList(),
      };

      final bool ok =
          await FirebaseRealtimeService.instance.pushSnapshot(snapshot);
      if (ok) {
        debugPrint('[FirebaseTracking] sync ✅ — ${drivers.length} سائق');
      }
    } catch (e) {
      debugPrint('[FirebaseTracking] _syncToFirebase خطأ: $e');
    }
  }
}
