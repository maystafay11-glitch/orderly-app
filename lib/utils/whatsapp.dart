import 'package:url_launcher/url_launcher.dart';

import 'package:orderly_app/models/driver.dart';
import 'package:orderly_app/services/app_settings.dart';
import 'package:orderly_app/utils/formatters.dart';

/// رابط `wa.me` لفتح محادثة مع رقم الهاتف المخزّن (بدون + وبدون مسافات).
///
/// [message] يُرسل كنص مشاركة مباشرة؛ يُشفّر تلقائياً ليتوافق مع رابط wa.me.
class WhatsAppLink {
  WhatsAppLink._();

  /// بناء رابط الواتساب من رقم المدير المحفوظ.
  ///
  /// إذا لم يُحفظ رقم، تُرجع null لتفادي فتح تطبيق الواتساب بلا رقم.
  static Future<Uri?> build({required String message}) async {
    final String phone = await AppSettings.getWhatsAppPhone();
    if (phone.isEmpty) {
      return null;
    }
    String digits = phone.replaceAll(RegExp(r'[^0-9]'), '');
    if (digits.isEmpty) {
      return null;
    }
    if (digits.startsWith('00')) {
      digits = digits.substring(2);
    } else if (digits.startsWith('07') && digits.length == 11) {
      digits = '964${digits.substring(1)}';
    }
    final String body = Uri.encodeComponent(message);
    return Uri.https('wa.me', '/$digits', <String, String>{'text': body});
  }

  /// فتح تطبيق الواتساب مباشرة مع الرسالة المنسقة وموجهة للرقم المحدد.
  static Future<bool> launch({required String message}) async {
    final String phone = await AppSettings.getWhatsAppPhone();
    String digits = phone.replaceAll(RegExp(r'[^0-9]'), '');
    if (digits.isEmpty) {
      return false;
    }
    if (digits.startsWith('00')) {
      digits = digits.substring(2);
    } else if (digits.startsWith('07') && digits.length == 11) {
      digits = '964${digits.substring(1)}';
    }

    final Uri appUri = Uri.parse(
      'whatsapp://send?phone=$digits&text=${Uri.encodeComponent(message)}',
    );

    try {
      if (await canLaunchUrl(appUri)) {
        final bool launched = await launchUrl(
          appUri,
          mode: LaunchMode.externalNonBrowserApplication,
        );
        if (launched) {
          return true;
        }
      }
    } catch (_) {}

    try {
      final bool launched = await launchUrl(
        appUri,
        mode: LaunchMode.externalNonBrowserApplication,
      );
      if (launched) {
        return true;
      }
    } catch (_) {}

    final Uri webUri = Uri.parse(
      'https://wa.me/$digits?text=${Uri.encodeComponent(message)}',
    );

    try {
      final bool launched = await launchUrl(
        webUri,
        mode: LaunchMode.externalApplication,
      );
      if (launched) {
        return true;
      }
    } catch (_) {}

    try {
      return await launchUrl(webUri, mode: LaunchMode.platformDefault);
    } catch (_) {
      return false;
    }
  }

  /// صياغة رسالة مرتبة واحترافية للملخص الأسبوعي جاهزة للإرسال عبر الواتساب.
  static String formatWeeklySummaryMessage({
    required DateTime periodStart,
    required DateTime periodEnd,
    required int totalOrders,
    required double totalAmount,
    required double totalWage,
    required double netAmount,
    List<Driver>? drivers,
  }) {
    final StringBuffer buf = StringBuffer();
    buf.writeln('📊 *تقرير الملخص الأسبوعي للمطعم*');
    buf.writeln('━━━━━━━━━━━━━━━━━━━━');
    buf.writeln(
      '📅 *الفترة:* من ${formatDate(periodStart)} إلى ${formatDate(periodEnd)}',
    );
    buf.writeln('');
    buf.writeln('📦 *إجمالي الطلبات:* ${formatNumber(totalOrders)} طلب');
    buf.writeln('💰 *إجمالي المبيعات:* ${formatAmount(totalAmount)}');
    buf.writeln('🛵 *أجور عمال التوصيل:* ${formatAmount(totalWage)}');
    buf.writeln('💵 *صافي أرباح المطعم:* ${formatAmount(netAmount)}');
    buf.writeln('━━━━━━━━━━━━━━━━━━━━');
    if (drivers != null && drivers.isNotEmpty) {
      final List<Driver> activeDrivers =
          drivers.where((Driver d) => d.ordersCount > 0).toList();
      if (activeDrivers.isNotEmpty) {
        buf.writeln('👥 *تفاصيل عمال التوصيل:*');
        for (final Driver d in activeDrivers) {
          buf.writeln(
            '• *${d.name}:* ${formatNumber(d.ordersCount)} طلبات (${formatAmount(d.totalOrdersAmount)})',
          );
        }
        buf.writeln('━━━━━━━━━━━━━━━━━━━━');
      }
    }
    buf.write('✨ _تم إنشاء التقرير عبر تطبيق Orderly_');
    return buf.toString();
  }
}
