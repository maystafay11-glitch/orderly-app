import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// تهيئة عامة لكل اختبارات المشروع (`flutter test` يكتشفها تلقائياً).
///
/// **لماذا؟** إضافة `flutter_secure_storage` غير متاحة داخل بيئة الاختبار،
/// وبدون بديل وهمي لا يكتمل نداء القراءة داخل `testWidgets` (fake async)،
/// فتبقى بوابة `AppAuthGate` على شاشة «جاري التحقق...» إلى الأبد.
/// هنا نُفعّل تخزيناً آمناً وهمياً في الذاكرة لكل الاختبارات.
Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  TestWidgetsFlutterBinding.ensureInitialized();
  FlutterSecureStorage.setMockInitialValues(<String, String>{});
  await testMain();
}
