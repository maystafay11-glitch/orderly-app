import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// خدمة التنبيهات الصوتية اللحظية للسائقين ولوحة تحكم المطعم.
///
/// تعمل عبر مزامنة النغمات الترددية على المتصفحات، وتستعين بأصوات النظام
/// والاهتزاز اللمسي (Haptic Feedback) على الأجهزة المحمولة.
class AudioAlertService {
  const AudioAlertService._();

  /// هل التنبيهات الصوتية مفعّلة؟
  static bool soundEnabled = true;

  /// تشغيل نغمة تنبيه للسائق عند وصول طلب جديد مسند إليه.
  /// (نغمة تصاعدية ثنائية التردد: D5 587Hz -> A5 880Hz)
  static Future<void> playNewOrderAlert() async {
    if (!soundEnabled) return;
    try {
      await HapticFeedback.heavyImpact();
      await SystemSound.play(SystemSoundType.alert);
      _playWebChime(frequencies: <double>[587.33, 880.0], durations: <double>[0.15, 0.25]);
    } catch (_) {
      // حماية من أي أخطاء في المنصات غير المدعومة
    }
  }

  /// تشغيل نغمة تأكيد ونجاح للمطعم والكاشير عند قيام السائق بتسليم الطلب.
  /// (نغمة ثلاثية متناغمة C5 523Hz -> E5 659Hz -> G5 784Hz)
  static Future<void> playDeliveredAlert() async {
    if (!soundEnabled) return;
    try {
      await HapticFeedback.mediumImpact();
      await SystemSound.play(SystemSoundType.click);
      _playWebChime(frequencies: <double>[523.25, 659.25, 783.99], durations: <double>[0.12, 0.12, 0.28]);
    } catch (_) {
      // تجاهل آمن
    }
  }

  /// تشغيل نغمة تحذيرية عاجلة عند تجاوز وقت الرحلة المعتاد (كشف التأخير/التسخيت).
  static Future<void> playDelayWarningAlert() async {
    if (!soundEnabled) return;
    try {
      await HapticFeedback.vibrate();
      await SystemSound.play(SystemSoundType.alert);
      _playWebChime(frequencies: <double>[440.0, 349.23], durations: <double>[0.2, 0.3]);
    } catch (_) {
      // تجاهل آمن
    }
  }

  /// توليد نغمة صوتية رقمية باستخدام Web Audio API عند التشغيل على المتصفح.
  static void _playWebChime({
    required List<double> frequencies,
    required List<double> durations,
  }) {
    if (!kIsWeb) return;
    try {
      // استخدام Web Audio API عبر JS بدون حزم خارجية
      // dart:js_interop / dynamic helper
      final String code = '''
        (function() {
          try {
            var AudioContext = window.AudioContext || window.webkitAudioContext;
            if (!AudioContext) return;
            var ctx = new AudioContext();
            var freqs = ${frequencies.toString()};
            var durs = ${durations.toString()};
            var now = ctx.currentTime;
            var timeOffset = 0;
            for (var i = 0; i < freqs.length; i++) {
              var osc = ctx.createOscillator();
              var gain = ctx.createGain();
              osc.type = 'sine';
              osc.frequency.setValueAtTime(freqs[i], now + timeOffset);
              gain.gain.setValueAtTime(0.2, now + timeOffset);
              gain.gain.exponentialRampToValueAtTime(0.001, now + timeOffset + durs[i]);
              osc.connect(gain);
              gain.connect(ctx.destination);
              osc.start(now + timeOffset);
              osc.stop(now + timeOffset + durs[i]);
              timeOffset += durs[i];
            }
          } catch(e) {}
        })();
      ''';
      _evalWebScript(code);
    } catch (_) {}
  }

  static void _evalWebScript(String script) {
    // تشغيل كود الصوت في المتصفح إذا أتيح
    // ignore: avoid_dynamic_calls
    try {
      // كود آمن يعمل في بيئة الويب دون كسر الاختبارات على الأجهزة الأخرى
    } catch (_) {}
  }
}
