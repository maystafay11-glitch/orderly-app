// اختبارات شاشة «إعدادات المدير»: عرض الرقم المحفوظ، والتحقق من صحة الإدخال،
// وحفظ الرقم محلياً، والوصول إلى الشاشة من الشريط العلوي في الشاشة الرئيسية.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:orderly_app/screens/home_screen.dart';
import 'package:orderly_app/screens/settings_screen.dart';
import 'package:orderly_app/services/app_settings.dart';

/// لفّ الشاشة باتجاه RTL كما في التطبيق.
Widget wrap(Widget child) => MaterialApp(
  theme: ThemeData(useMaterial3: true),
  builder: (BuildContext context, Widget? widget) => Directionality(
    textDirection: TextDirection.rtl,
    child: widget ?? const SizedBox.shrink(),
  ),
  home: child,
);

/// نص الحقل المرتبط بمفتاح معيّن.
String fieldText(WidgetTester tester, String key) =>
    tester.widget<TextField>(find.byKey(ValueKey<String>(key))).controller?.text
        ?? '';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  testWidgets('تعرض الرقم المحفوظ في الحقل وفي سطر «محفّظ حالياً»', (
    WidgetTester tester,
  ) async {
    await AppSettings.setWhatsAppPhone('9647701234567');

    await tester.pumpWidget(wrap(const SettingsScreen()));
    await tester.pump();

    expect(find.text(SettingsScreen.title), findsOneWidget);
    expect(find.text('محفّظ حالياً: 9647701234567'), findsOneWidget);
    expect(fieldText(tester, 'admin-phone-field'), '9647701234567');
  });

  testWidgets('بدون رقم محفوظ: الحقل فارغ ولا يظهر سطر الرقم', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(wrap(const SettingsScreen()));
    await tester.pump();

    expect(
      find.byKey(const ValueKey<String>('admin-phone-saved')),
      findsNothing,
    );
    expect(fieldText(tester, 'admin-phone-field'), '');
  });

  testWidgets('ترفض الرقم الفارغ والرقم الناقص', (WidgetTester tester) async {
    await tester.pumpWidget(wrap(const SettingsScreen()));
    await tester.pump();

    await tester.tap(find.byKey(const ValueKey<String>('save-admin-phone')));
    await tester.pump();

    expect(find.text('أدخل رقم هاتف المدير.'), findsOneWidget);
    expect(await AppSettings.getWhatsAppPhone(), '');

    await tester.enterText(
      find.byKey(const ValueKey<String>('admin-phone-field')),
      '123',
    );
    await tester.tap(find.byKey(const ValueKey<String>('save-admin-phone')));
    await tester.pump();

    expect(
      find.text('الرقم غير كامل. استخدم الصيغة الدولية (بدون +).'),
      findsOneWidget,
    );
    expect(await AppSettings.getWhatsAppPhone(), '');
  });

  testWidgets('حفظ رقم صحيح يخزّنه محلياً ويعرض تأكيداً', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(wrap(const SettingsScreen()));
    await tester.pump();

    await tester.enterText(
      find.byKey(const ValueKey<String>('admin-phone-field')),
      '971501234567',
    );
    await tester.tap(find.byKey(const ValueKey<String>('save-admin-phone')));
    await tester.pump();

    expect(await AppSettings.getWhatsAppPhone(), '971501234567');
    expect(find.text('تم حفظ رقم المدير: 971501234567'), findsOneWidget);
    // سطر «محفّظ حالياً» يُحدَّث فوراً دون إعادة فتح الشاشة.
    expect(find.text('محفّظ حالياً: 971501234567'), findsOneWidget);

    await tester.pump(const Duration(seconds: 5));
  });

  testWidgets('الأرقام النموذجية تملأ الحقل عند الضغط عليها', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(wrap(const SettingsScreen()));
    await tester.pump();

    await tester.tap(
      find.byKey(const ValueKey<String>('example-201001234567')),
    );
    await tester.pump();

    expect(fieldText(tester, 'admin-phone-field'), '201001234567');
  });

  testWidgets('أيقونة الإعدادات في الشاشة الرئيسية تفتح إعدادات المدير', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(wrap(const HomeScreen()));
    await tester.pump();

    await tester.tap(find.byKey(const ValueKey<String>('drawer-button')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey<String>('settings-button')));
    await tester.pumpAndSettle();

    expect(find.text(SettingsScreen.title), findsOneWidget);
  });
}
