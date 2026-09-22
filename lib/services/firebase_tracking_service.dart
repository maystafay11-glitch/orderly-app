import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:orderly_app/models/delivery_order.dart';
import 'package:orderly_app/models/driver.dart';
import 'package:orderly_app/models/order_status.dart';
import 'package:orderly_app/models/shift_record.dart';
import 'package:orderly_app/models/staff_member.dart';
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

  /// لحظة آخر لقطة سحابية قرأها/طبّقها هذا الجهاز.
  ///
  /// تُستخدم كعلامة مائية للتمييز بين «طلب جديد أضافه جهاز آخر ولم يُقرأ بعد»
  /// (يُدمج فلا يُفقد) و«طلب قديم حذفه المدير محلياً» (لا يُعاد إحياؤه).
  DateTime _lastCloudSnapshotAt = DateTime.fromMillisecondsSinceEpoch(0);

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
  ///
  /// **حماية من الفقدان:** `snapshot` مستند كامل، فاستبدال المحلي بالوارد
  /// قد يُلغي طلباً أضافه هذا الجهاز ولم يُنشر بعد. لذلك نُبقي أي طلب محلي
  /// أُضيف بعد آخر قراءة سحابية ([_lastCloudSnapshotAt]) بدل إسقاطه.
  Future<void> _applyRemoteSnapshot(Map<String, dynamic> snapshot) async {
    try {
      final List<Driver> remoteDrivers = _driversFromSnapshot(snapshot);
      if (remoteDrivers.isEmpty && snapshot['drivers'] is! List) return;

      final List<Driver> localDrivers = await DriverStorage.loadDrivers();
      final List<Driver> merged = _mergeOrders(
        base: remoteDrivers,
        other: localDrivers,
        since: _lastCloudSnapshotAt,
      );
      _lastCloudSnapshotAt = DateTime.now();

      // حفظ البيانات الواردة محلياً
      await DriverStorage.saveDrivers(merged);

      // الإعلام بالتحديث الجديد
      await notifyChanges();
      debugPrint(
          '[FirebaseTracking] بيانات مُطبَّقة من Firebase: ${merged.length} سائق');
    } catch (e) {
      debugPrint('[FirebaseTracking] _applyRemoteSnapshot خطأ: $e');
    }
  }

  /// استخراج قائمة العمال من لقطة سحابية.
  static List<Driver> _driversFromSnapshot(Map<String, dynamic> snapshot) {
    final Object? driversRaw = snapshot['drivers'];
    if (driversRaw is! List) return <Driver>[];
    return driversRaw
        .whereType<Map<Object?, Object?>>()
        .map((Map<Object?, Object?> item) =>
            Driver.fromJson(Map<String, dynamic>.from(item)))
        .toList();
  }

  /// دمج قائمة عمال مع أخرى مع الحفاظ على الطلبات الجديدة غير المقروءة.
  ///
  /// * [base] القائمة الأساس (التي سنكتبها أو التي سنطبّقها).
  /// * [other] القائمة الأخرى (السحابة عند الكتابة، أو الجهاز عند القراءة).
  /// * [since] علامة زمنية: الطلبات الأحدث منها فقط تُعدّ «جديدة» وتُدمج،
  ///   لذلك لا يعود طلب حذفه المدير إلى الظهور.
  static List<Driver> _mergeOrders({
    required List<Driver> base,
    required List<Driver> other,
    required DateTime since,
  }) {
    final List<Driver> result = List<Driver>.of(base);
    for (final Driver extra in other) {
      final int index = result.indexWhere(
        (Driver driver) =>
            (driver.pin.isNotEmpty && driver.pin == extra.pin) ||
            StaffMember.normalizeUsername(driver.name) ==
                StaffMember.normalizeUsername(extra.name),
      );
      if (index == -1) {
        // عامل غير موجود في الأساس: نضيفه فقط إن كان يحمل طلباً جديداً.
        if (extra.orders.any((DeliveryOrder o) => o.addedAt.isAfter(since))) {
          result.add(extra);
        }
        continue;
      }
      final Driver target = result[index];
      final Set<String> knownIds =
          target.orders.map((DeliveryOrder order) => order.id).toSet();
      final List<DeliveryOrder> newcomers = extra.orders
          .where((DeliveryOrder order) =>
              !knownIds.contains(order.id) && order.addedAt.isAfter(since))
          .toList();
      if (newcomers.isEmpty) continue;
      result[index] = target.copyWith(
        orders: <DeliveryOrder>[...target.orders, ...newcomers],
      );
    }
    return result;
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
  ///
  /// **حماية من الكتابة فوق العامل:** قبل الكتابة تُقرأ اللقطة السحابية
  /// وتُضم طلبات الأجهزة الأخرى الجديدة ([_mergeOrders])، وتُكتب محمية
  /// بـ `ETag`؛ فإن تغيّر المستند في اللحظة الفاصلة (412) نُعيد القراءة
  /// والدمج ثم نحاول مرة أخرى.
  Future<void> _syncToFirebase(List<Driver> drivers) async {
    if (!FirebaseRealtimeService.instance.isConfigured) return;

    try {
      List<Driver> outgoing = List<Driver>.of(drivers);

      for (int attempt = 0; attempt < 2; attempt++) {
        final Map<String, dynamic>? remote =
            await FirebaseRealtimeService.instance.fetchSnapshot();
        if (remote != null) {
          outgoing = _mergeOrders(
            base: outgoing,
            other: _driversFromSnapshot(remote),
            since: _lastCloudSnapshotAt,
          );
        }

        final Map<String, dynamic> snapshot = <String, dynamic>{
          'restaurantId': RestaurantService.restaurantId,
          'updatedAt': DateTime.now().toIso8601String(),
          'drivers': outgoing.map((Driver d) => d.toJson()).toList(),
        };

        final SnapshotPushOutcome outcome = await FirebaseRealtimeService
            .instance
            .pushSnapshotGuarded(snapshot);

        if (outcome == SnapshotPushOutcome.success) {
          // إثبات الدمج محلياً حتى تتفق الواجهة مع السحابة.
          await DriverStorage.saveDrivers(outgoing);
          await notifyChanges();
          debugPrint('[FirebaseTracking] sync ✅ — ${outgoing.length} سائق');
          return;
        }
        if (outcome == SnapshotPushOutcome.failure) {
          debugPrint('[FirebaseTracking] sync فشل — سيُعاد في الدورة القادمة');
          return;
        }
        // conflict: جهاز آخر كتب مستنداً أحدث → أعِد القراءة والدمج.
        debugPrint('[FirebaseTracking] تعارض — إعادة المحاولة بعد الدمج');
      }
    } catch (e) {
      debugPrint('[FirebaseTracking] _syncToFirebase خطأ: $e');
    }
  }
}
