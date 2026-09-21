import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:orderly_app/screens/app_auth_gate.dart';
import 'package:orderly_app/services/firebase_tracking_service.dart';
import 'package:orderly_app/services/restaurant_service.dart';
import 'package:orderly_app/theme/app_theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // ── تهيئة إلزامية قبل runApp ──────────────────────────────────────────────

  // 1. توليد/تحميل Restaurant ID الفريد (Multi-tenant isolation)
  await RestaurantService.init();

  // 2. تهيئة خدمة التتبع وربط Firebase إذا كان URL مُعدَّداً
  await FirebaseTrackingService.instance.initialize();

  // ── إعدادات واجهة النظام (شريط الحالة) ─────────────────────────────────
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.light,
    systemNavigationBarColor: AppColors.background,
    systemNavigationBarIconBrightness: Brightness.light,
  ));

  // ── منع تدوير الشاشة (Android: portrait فقط لتجربة أفضل) ───────────────
  await SystemChrome.setPreferredOrientations(<DeviceOrientation>[
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);

  runApp(const OrderlyApp());
}

/// تطبيق Orderly: واجهة عربية (RTL) لحساب أجور عمال التوصيل وصافي المطعم.
class OrderlyApp extends StatelessWidget {
  const OrderlyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Orderly — أجور العمال',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.dark(),
      builder: (BuildContext context, Widget? child) => Directionality(
        textDirection: TextDirection.rtl,
        child: child ?? const SizedBox.shrink(),
      ),
      home: const AppAuthGate(),
    );
  }
}
