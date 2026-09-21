import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:orderly_app/models/driver.dart';
import 'package:orderly_app/screens/app_auth_gate.dart';
import 'package:orderly_app/screens/driver_dashboard_screen.dart';
import 'package:orderly_app/screens/home_screen.dart';
import 'package:orderly_app/screens/unified_login_screen.dart';
import 'package:orderly_app/services/app_settings.dart';
import 'package:orderly_app/services/auth_session_service.dart';
import 'package:orderly_app/services/driver_storage.dart';
import 'package:orderly_app/services/license_service.dart';
import 'package:orderly_app/services/restaurant_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// مساعد: يُجري pump كافٍ لإنهاء الانتقالات القصيرة دون أن ينتظر
/// الجسيمات المتكررة لا نهاية.
Future<void> _settle(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 500));
  await tester.pump(const Duration(milliseconds: 500));
}

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    await AppSettings.clearAll();
    await DriverStorage.clear();
    await AuthSessionService.logout();
    await RestaurantService.init();
  });

  group('AuthSessionService tests', () {
    test('Admin login with default PIN 7777 succeeds and persists', () async {
      final AuthResult result = await AuthSessionService.loginWithPin('7777');
      expect(result.success, isTrue);
      expect(result.role, equals(UserRole.admin));
      expect(await AuthSessionService.isAdminLoggedIn(), isTrue);
      expect(await AuthSessionService.getActiveRole(), equals(UserRole.admin));
      expect(await AuthSessionService.hasActiveSession(), isTrue);
    });

    test('Driver login with PIN succeeds and persists driver context', () async {
      await DriverStorage.loadOrCreate('أحمد خليل');
      final List<Driver> drivers = await DriverStorage.loadDrivers();
      expect(drivers, isNotEmpty);
      final String driverPin = drivers.first.pin;
      expect(driverPin, isNotEmpty);

      final AuthResult result = await AuthSessionService.loginWithPin(driverPin);
      expect(result.success, isTrue);
      expect(result.role, equals(UserRole.driver));
      expect(result.driver?.name, equals('أحمد خليل'));
      expect(await AuthSessionService.getActiveRole(), equals(UserRole.driver));
      final Driver? activeDriver = await AuthSessionService.getActiveDriver();
      expect(activeDriver?.name, equals('أحمد خليل'));

      await AuthSessionService.logout();
      expect(await AuthSessionService.hasActiveSession(), isFalse);
      expect(await AuthSessionService.getActiveRole(), isNull);
    });

    test('Invalid PIN fails with appropriate message', () async {
      final AuthResult result = await AuthSessionService.loginWithPin('0000');
      expect(result.success, isFalse);
      expect(result.role, isNull);
      expect(result.message, contains('غير صحيح'));
    });
  });

  group('PIN Management in AppSettings and DriverStorage', () {
    test('Admin PIN can be changed and verified', () async {
      expect(await AppSettings.getAdminPin(), equals('7777'));
      expect(await AppSettings.verifyAdminPin('7777'), isTrue);

      await AppSettings.setAdminPin('8888');
      expect(await AppSettings.getAdminPin(), equals('8888'));
      expect(await AppSettings.verifyAdminPin('8888'), isTrue);
      expect(await AppSettings.verifyAdminPin('7777'), isFalse);
    });

    test('Driver PIN can be customized without conflict', () async {
      await DriverStorage.loadOrCreate('سعيد الشامي');
      final String? error = await DriverStorage.updateDriverPin(
        driverName: 'سعيد الشامي',
        newPin: '1025',
      );
      expect(error, isNull);

      final Driver? found = await DriverStorage.loadDriverByPin('1025');
      expect(found, isNotNull);
      expect(found?.name, equals('سعيد الشامي'));

      // Conflict with admin PIN
      final String? conflictAdmin = await DriverStorage.updateDriverPin(
        driverName: 'سعيد الشامي',
        newPin: '7777',
      );
      expect(conflictAdmin, isNotNull);
      expect(conflictAdmin, contains('محجوز لمدير المطعم'));
    });
  });

  group('UnifiedLoginScreen widget tests', () {
    testWidgets('Selecting admin then entering PIN routes to HomeScreen', (
      WidgetTester tester,
    ) async {
      tester.view.physicalSize = const Size(800, 1000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(
        const MaterialApp(
          home: UnifiedLoginScreen(),
        ),
      );
      await _settle(tester);

      // Phase 1: role selection screen is shown
      expect(find.byKey(const ValueKey<String>('login-admin-btn')), findsOneWidget);
      expect(find.byKey(const ValueKey<String>('login-driver-btn')), findsOneWidget);

      // Select admin role
      await tester.tap(find.byKey(const ValueKey<String>('login-admin-btn')));
      await _settle(tester);

      // Phase 2: keypad is now visible
      expect(find.byKey(const ValueKey<String>('pin-digit-0')), findsOneWidget);

      // Tap 7 four times
      final Finder key7 = find.byKey(const ValueKey<String>('keypad-7'));
      await tester.tap(key7);
      await tester.pump();
      await tester.tap(key7);
      await tester.pump();
      await tester.tap(key7);
      await tester.pump();
      await tester.tap(key7);
      await _settle(tester);

      // Should authenticate as admin and navigate to HomeScreen
      expect(find.byType(HomeScreen), findsOneWidget);
    });

    testWidgets('Invalid PIN shows error and keypad stays visible', (
      WidgetTester tester,
    ) async {
      tester.view.physicalSize = const Size(800, 1000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(
        const MaterialApp(
          home: UnifiedLoginScreen(),
        ),
      );
      await _settle(tester);

      // Select admin role to reveal keypad
      await tester.tap(find.byKey(const ValueKey<String>('login-admin-btn')));
      await _settle(tester);

      // Enter 9999 (invalid default)
      final Finder key9 = find.byKey(const ValueKey<String>('keypad-9'));
      for (int i = 0; i < 4; i++) {
        await tester.tap(key9);
        await tester.pump();
      }
      await _settle(tester);

      expect(find.textContaining('الرمز غير صحيح'), findsOneWidget);
      expect(find.byType(HomeScreen), findsNothing);
    });

    testWidgets('Back button returns to role selection', (
      WidgetTester tester,
    ) async {
      tester.view.physicalSize = const Size(800, 1000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(
        const MaterialApp(
          home: UnifiedLoginScreen(),
        ),
      );
      await _settle(tester);

      // Select driver role
      await tester.tap(find.byKey(const ValueKey<String>('login-driver-btn')));
      await _settle(tester);

      expect(find.byKey(const ValueKey<String>('pin-back-btn')), findsOneWidget);

      // Go back
      await tester.tap(find.byKey(const ValueKey<String>('pin-back-btn')));
      await _settle(tester);

      // Should be back on selection screen
      expect(find.byKey(const ValueKey<String>('login-admin-btn')), findsOneWidget);
      expect(find.byKey(const ValueKey<String>('login-driver-btn')), findsOneWidget);
    });
  });

  group('AppAuthGate widget tests', () {
    setUp(() async {
      // يجب تفعيل الترخيص قبل اختبار AppAuthGate حتى لا تظهر ActivationScreen
      await LicenseService.activate('orderly77');
    });

    testWidgets('Shows UnifiedLoginScreen when unauthenticated', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: AppAuthGate(),
        ),
      );
      await _settle(tester);

      expect(find.byType(UnifiedLoginScreen), findsOneWidget);
      expect(find.byType(HomeScreen), findsNothing);
    });

    testWidgets('Shows HomeScreen immediately when admin session exists', (
      WidgetTester tester,
    ) async {
      await AuthSessionService.loginWithPin('7777');

      await tester.pumpWidget(
        const MaterialApp(
          home: AppAuthGate(),
        ),
      );
      await _settle(tester);

      expect(find.byType(HomeScreen), findsOneWidget);
      expect(find.byType(UnifiedLoginScreen), isNotFound);
    });

    testWidgets('Shows DriverDashboardScreen when driver session exists', (
      WidgetTester tester,
    ) async {
      await DriverStorage.loadOrCreate('عمر التوصيل');
      final Driver? driver = await DriverStorage.loadDriverByPin('1001');
      expect(driver, isNotNull);
      await AuthSessionService.loginWithPin('1001');

      await tester.pumpWidget(
        const MaterialApp(
          home: AppAuthGate(),
        ),
      );
      await _settle(tester);

      expect(find.byType(DriverDashboardScreen), findsOneWidget);
      expect(find.byType(HomeScreen), isNotFound);
    });
  });
}

/// Matcher مساعد: يكافئ `findsNothing` للوضوح.
Matcher get isNotFound => findsNothing;
