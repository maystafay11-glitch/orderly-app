import 'dart:async';
import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'package:orderly_app/models/delivery_order.dart';
import 'package:orderly_app/models/driver.dart';
import 'package:orderly_app/models/shift_record.dart';
import 'package:orderly_app/services/app_settings.dart';

/// حفظ واسترجاع بيانات العوامل محلياً باستخدام `shared_preferences`.
///
/// تُخزَّن كل العوامل في مفتاح واحد ([driversKey]) بصيغة JSON، مع إسناد
/// رموز PIN تسلسلية (1001 إلى 1030) تلقائياً لكل سائق.
class DriverStorage {
  /// الصنف يحتوي دوالاً ثابتة فقط، فلا حاجة لإنشاء كائن منه.
  const DriverStorage._();

  /// مفتاح تخزين بيانات العوامل داخل `SharedPreferences`.
  static const String driversKey = 'orderly.drivers';

  /// مفتاح تخزين سجلات الورديات اليومية للسائقين.
  static const String shiftRecordsKey = 'orderly.shift_records';

  /// الوصول إلى مخزن التفضيلات.
  static Future<SharedPreferences> get _prefs =>
      SharedPreferences.getInstance();

  /// حفظ كل العوامل (يستبدل المحفوظ سابقاً).
  static Future<void> saveDrivers(List<Driver> drivers) async {
    final SharedPreferences prefs = await _prefs;
    if (drivers.isEmpty) {
      await prefs.remove(driversKey);
      return;
    }
    final String payload = jsonEncode(
      drivers.map((Driver driver) => driver.toJson()).toList(),
    );
    await prefs.setString(driversKey, payload);
  }

  /// استرجاع كل العوامل المحفوظة، مع ضمان وجود رمز PIN مخصص لكل سائق (1001-1030).
  static Future<List<Driver>> loadDrivers() async {
    final SharedPreferences prefs = await _prefs;
    try {
      final String? raw = prefs.getString(driversKey);
      if (raw == null || raw.trim().isEmpty) {
        return <Driver>[];
      }
      final Object? decoded = jsonDecode(raw);
      if (decoded is! List) {
        return <Driver>[];
      }
      final List<Driver> loaded = decoded
          .whereType<Map<Object?, Object?>>()
          .map(
            (Map<Object?, Object?> item) =>
                Driver.fromJson(Map<String, dynamic>.from(item)),
          )
          .toList();

      bool needsSave = false;
      final List<Driver> normalized = <Driver>[];
      for (final Driver d in loaded) {
        if (d.pin.isEmpty) {
          final String autoPin = Driver.findNextAvailablePin(normalized);
          normalized.add(d.copyWith(pin: autoPin));
          needsSave = true;
        } else {
          normalized.add(d);
        }
      }

      if (needsSave) {
        unawaited(saveDrivers(normalized));
      }
      return normalized;
    } catch (_) {
      return <Driver>[];
    }
  }

  /// حفظ عامل واحد: يُضاف إذا كان جديداً، أو يُحدَّث إذا كان اسمه محفوظاً،
  /// مع توليد رمز PIN تلقائياً إن لم يكن محدداً.
  static Future<void> saveDriver(Driver driver) async {
    final List<Driver> drivers = List<Driver>.of(await loadDrivers());
    final int index = drivers.indexWhere(
      (Driver item) => item.name == driver.name,
    );

    Driver toSave = driver;
    if (toSave.pin.isEmpty) {
      toSave = toSave.copyWith(pin: Driver.findNextAvailablePin(drivers));
    }

    if (index == -1) {
      drivers.add(toSave);
    } else {
      drivers[index] = toSave;
    }
    await saveDrivers(drivers);
  }

  /// تحديث وتخصيص رمز السائق (PIN) مع التحقق من عدم التكرار وعدم تطابقه مع رمز المدير.
  ///
  /// يُرجع `null` عند النجاح، أو نص رسالة الخطأ عند فشل التحقق.
  static Future<String?> updateDriverPin({
    required String driverName,
    required String newPin,
  }) async {
    final String cleanPin = newPin.trim();
    if (cleanPin.isEmpty) {
      return 'الرمز السري لا يمكن أن يكون فارغاً';
    }
    if (cleanPin.length < 4) {
      return 'الرمز يجب أن يتكون من 4 أرقام على الأقل';
    }

    // التأكد من عدم تطابقه مع رمز المدير
    final String adminPin = await AppSettings.getAdminPin();
    if (cleanPin == adminPin) {
      return 'هذا الرمز محجوز لمدير المطعم، يرجى اختيار رمز آخر';
    }

    final List<Driver> drivers = List<Driver>.of(await loadDrivers());
    final int targetIndex = drivers.indexWhere((Driver d) => d.name == driverName);
    if (targetIndex == -1) {
      return 'العامل غير موجود في النظام';
    }

    // التأكد من عدم تكرار الرمز مع سائق آخر
    final bool isDuplicate = drivers.any(
      (Driver d) => d.name != driverName && d.pin == cleanPin,
    );
    if (isDuplicate) {
      return 'هذا الرمز ($cleanPin) مستخدم بالفعل لسائق آخر';
    }

    drivers[targetIndex] = drivers[targetIndex].copyWith(pin: cleanPin);
    await saveDrivers(drivers);
    return null;
  }

  /// استرجاع عامل بالاسم، أو `null` إذا لم يكن محفوظاً.
  static Future<Driver?> loadDriver(String name) async {
    final List<Driver> drivers = await loadDrivers();
    for (final Driver driver in drivers) {
      if (driver.name == name) {
        return driver;
      }
    }
    return null;
  }

  /// استرجاع عامل برمز الـ PIN (1001-1030).
  static Future<Driver?> loadDriverByPin(String pin) async {
    final List<Driver> drivers = await loadDrivers();
    final String clean = pin.trim();
    for (final Driver driver in drivers) {
      if (driver.pin == clean) {
        return driver;
      }
    }
    return null;
  }

  /// استرجاع عامل بالاسم، وإن لم يكن محفوظاً يُنشأ عامل جديد برمز PIN تلقائي.
  static Future<Driver> loadOrCreate(String name) async {
    final Driver? saved = await loadDriver(name);
    if (saved != null) {
      return saved;
    }
    final List<Driver> current = await loadDrivers();
    final String nextPin = Driver.findNextAvailablePin(current);
    final Driver created = Driver(name: name, pin: nextPin);
    await saveDriver(created);
    return created;
  }

  /// حذف عامل بالاسم، وتُرجع `true` إذا تم الحذف فعلاً.
  static Future<bool> deleteDriver(String name) async {
    final List<Driver> drivers = await loadDrivers();
    final List<Driver> remaining = drivers
        .where((Driver driver) => driver.name != name)
        .toList();
    if (remaining.length == drivers.length) {
      return false;
    }
    await saveDrivers(remaining);
    return true;
  }

  /// حذف كل بيانات العوامل المحفوظة.
  static Future<void> clear() async {
    final SharedPreferences prefs = await _prefs;
    await prefs.remove(driversKey);
    await prefs.remove(shiftRecordsKey);
  }

  // --- إدارة سجلات الورديات (Shift Records) ---

  /// استرجاع كل سجلات الورديات اليومية المحفوظة.
  static Future<List<ShiftRecord>> loadShiftRecords() async {
    final SharedPreferences prefs = await _prefs;
    try {
      final String? raw = prefs.getString(shiftRecordsKey);
      if (raw == null || raw.trim().isEmpty) {
        return <ShiftRecord>[];
      }
      final Object? decoded = jsonDecode(raw);
      if (decoded is! List) {
        return <ShiftRecord>[];
      }
      return decoded
          .whereType<Map<Object?, Object?>>()
          .map((Map<Object?, Object?> item) =>
              ShiftRecord.fromJson(Map<String, dynamic>.from(item)))
          .toList();
    } catch (_) {
      return <ShiftRecord>[];
    }
  }

  /// حفظ قائمة سجلات الورديات.
  static Future<void> saveShiftRecords(List<ShiftRecord> records) async {
    final SharedPreferences prefs = await _prefs;
    if (records.isEmpty) {
      await prefs.remove(shiftRecordsKey);
      return;
    }
    final String payload = jsonEncode(
      records.map((ShiftRecord r) => r.toJson()).toList(),
    );
    await prefs.setString(shiftRecordsKey, payload);
  }

  /// مفتاح تخزين بيانات الطلبات العامة / السفري داخل `SharedPreferences`.
  static const String generalOrdersKey = 'orderly.general_orders';

  /// استرجاع قائمة الطلبات العامة والسفري المسجَّلة اليوم.
  static Future<List<DeliveryOrder>> loadGeneralOrders() async {
    final SharedPreferences prefs = await _prefs;
    try {
      final String? raw = prefs.getString(generalOrdersKey);
      if (raw == null || raw.trim().isEmpty) {
        return <DeliveryOrder>[];
      }
      final Object? decoded = jsonDecode(raw);
      if (decoded is! List) {
        return <DeliveryOrder>[];
      }
      return decoded
          .whereType<Map<Object?, Object?>>()
          .map(
            (Map<Object?, Object?> item) =>
                DeliveryOrder.fromJson(Map<String, dynamic>.from(item)),
          )
          .toList();
    } catch (_) {
      return <DeliveryOrder>[];
    }
  }

  /// حفظ قائمة الطلبات العامة والسفري (يستبدل المحفوظ).
  static Future<void> saveGeneralOrders(List<DeliveryOrder> orders) async {
    final SharedPreferences prefs = await _prefs;
    if (orders.isEmpty) {
      await prefs.remove(generalOrdersKey);
      return;
    }
    final String payload = jsonEncode(
      orders.map((DeliveryOrder order) => order.toJson()).toList(),
    );
    await prefs.setString(generalOrdersKey, payload);
  }

  /// إضافة طلب عام / سفري جديد وحفظه فوراً في التخزين المحلي.
  static Future<void> addGeneralOrder(DeliveryOrder order) async {
    final List<DeliveryOrder> current = await loadGeneralOrders();
    current.add(order);
    await saveGeneralOrders(current);
  }

  /// حذف طلب عام محدد بالترتيب الزمني.
  static Future<void> removeGeneralOrderAt(int index) async {
    final List<DeliveryOrder> current = await loadGeneralOrders();
    if (index >= 0 && index < current.length) {
      current.removeAt(index);
      await saveGeneralOrders(current);
    }
  }

  /// تصفير الطلبات العامة لليوم.
  static Future<void> clearGeneralOrders() async {
    final SharedPreferences prefs = await _prefs;
    await prefs.remove(generalOrdersKey);
  }

  /// هل توجد بيانات عوامل محفوظة؟
  static Future<bool> hasSavedDrivers() async =>
      (await loadDrivers()).isNotEmpty;
}

/// اختصارات للحفظ التلقائي مباشرة من كائن [Driver].
extension DriverPersistence on Driver {
  /// حفظ هذا العامل محلياً (إضافة أو تحديث) بعد أي تعديل على بياناته.
  Future<void> save() => DriverStorage.saveDriver(this);

  /// حذف هذا العامل من التخزين المحلي.
  Future<bool> delete() => DriverStorage.deleteDriver(name);
}
