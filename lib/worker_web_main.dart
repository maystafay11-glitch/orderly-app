import 'package:flutter/material.dart';

import 'package:orderly_app/screens/worker_web_screen.dart';

/// نقطة دخول مستقلة لواجهة العامل على الويب فقط.
/// البناء: `flutter build web --target lib/worker_web_main.dart`
void main() => runWorkerWebApp();

void runWorkerWebApp() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const WorkerWebApp());
}

class WorkerWebApp extends StatelessWidget {
  const WorkerWebApp({super.key});

  static const String databaseUrl = String.fromEnvironment(
    'FIREBASE_DATABASE_URL',
  );

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Orderly Worker',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF13795B)),
        useMaterial3: true,
        inputDecorationTheme: const InputDecorationTheme(
          border: OutlineInputBorder(),
        ),
      ),
      builder: (BuildContext context, Widget? child) => Directionality(
        textDirection: TextDirection.rtl,
        child: child ?? const SizedBox.shrink(),
      ),
      home: const WorkerWebScreen(databaseUrl: databaseUrl),
    );
  }
}
