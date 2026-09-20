import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:orderly_app/screens/app_auth_gate.dart';
import 'package:orderly_app/theme/app_theme.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.light,
    systemNavigationBarColor: AppColors.background,
    systemNavigationBarIconBrightness: Brightness.light,
  ));
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
