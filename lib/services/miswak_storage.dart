/// حفظ واسترجاع دفعات حساب المسواگ محلياً عبر shared_preferences.
///
/// تُخزَّن الدفعات كقائمة JSON واحدة، وتُرجع القائمة مرتّبة من الأحدث للأقدم،
/// وأي بيانات تالفة تُتجاهل بدل إسقاط التطبيق.
library;

import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'package:orderly_app/models/miswak_calculation.dart';

class MiswakStorage {
  const MiswakStorage._();

  /// مفتاح التخزين المحلي لقائمة دفعات المسواگ.
  static const String miswakKey = 'miswak_batches';

  static Future<SharedPreferences> get _prefs => SharedPreferences.getInstance();

  /// استرجاع كل الدفعات المحفوظة (من الأحدث إلى الأقدم).
  static Future<List<MiswakCalculation>> load() async {
    final SharedPreferences prefs = await _prefs;
    try {
      final String? raw = prefs.getString(miswakKey);
      if (raw == null || raw.trim().isEmpty) {
        return <MiswakCalculation>[];
      }
      final Object? decoded = jsonDecode(raw);
      if (decoded is! List) {
        return <MiswakCalculation>[];
      }
      return decoded
          .whereType<Map<Object?, Object?>>()
          .map(
            (Map<Object?, Object?> item) => MiswakCalculation.fromJson(
              Map<String, dynamic>.from(item),
            ),
          )
          .toList()
        ..sort(
          (MiswakCalculation a, MiswakCalculation b) =>
              b.createdAt.compareTo(a.createdAt),
        );
    } catch (_) {
      return <MiswakCalculation>[];
    }
  }

  /// حفظ/استبدال كل الدفعات (تُحذف القائمة من التخزين إذا كانت فارغة).
  static Future<void> save(List<MiswakCalculation> items) async {
    final SharedPreferences prefs = await _prefs;
    if (items.isEmpty) {
      await prefs.remove(miswakKey);
      return;
    }
    final String payload = jsonEncode(
      items.map((MiswakCalculation item) => item.toJson()).toList(),
    );
    await prefs.setString(miswakKey, payload);
  }

  /// إضافة دفعة جديدة إلى المحفوظات، وتُرجع القائمة المحدَّثة.
  static Future<List<MiswakCalculation>> add(MiswakCalculation item) async {
    final List<MiswakCalculation> items = <MiswakCalculation>[...await load()];
    items.insert(0, item);
    await save(items);
    return items;
  }

  /// حذف دفعة بموقعها في القائمة، وتُرجع القائمة المحدَّثة.
  static Future<List<MiswakCalculation>> removeAt(int index) async {
    final List<MiswakCalculation> items = <MiswakCalculation>[...await load()];
    if (index < 0 || index >= items.length) {
      return items;
    }
    items.removeAt(index);
    await save(items);
    return items;
  }

  /// حذف كل الدفعات المحفوظة.
  static Future<void> clear() async {
    final SharedPreferences prefs = await _prefs;
    await prefs.remove(miswakKey);
  }

  /// إجماليات الدفعات المحفوظة (للأرقام الكلية في الصفحة).
  static Future<MiswakTotals> totals() async =>
      MiswakTotals.of(await load());
}