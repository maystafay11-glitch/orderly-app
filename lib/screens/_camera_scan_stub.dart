// شاشة بديلة للويب — تُستخدم عند تجميع Flutter Web
// تُعلم المستخدم أن المسح بالكاميرا غير متاح في المتصفح

import 'package:flutter/material.dart';

import 'package:orderly_app/theme/app_theme.dart';

/// خطوات الالتقاط (نفس enum الملف الأصلي لضمان التوافق)
enum ScanStep {
  /// الخطوة الأولى: توجيه الكاميرا نحو سعر الطلب.
  price,

  /// الخطوة الثانية: توجيه الكاميرا نحو رقم الطلب أو الفاتورة.
  orderNumber,
}

/// شاشة بديلة تظهر على الويب بدلاً من شاشة الكاميرا الحقيقية.
///
/// تُعلم المستخدم أن المسح بالكاميرا غير مدعوم في متصفح الويب،
/// مع توفير زر للإغلاق والعودة للإدخال اليدوي.
class CameraScanScreen extends StatelessWidget {
  const CameraScanScreen({
    super.key,
    this.initialStep = ScanStep.price,
    this.initialPrice,
    this.initialOrderNumber,
  });

  final ScanStep initialStep;
  final double? initialPrice;
  final String? initialOrderNumber;

  static const String title = 'مسح الرقم بالكاميرا';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.surface,
        leading: IconButton(
          icon: const Icon(Icons.close, color: AppColors.textPrimary),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: const Text(
          'مسح بالكاميرا',
          style: TextStyle(color: AppColors.textPrimary, fontSize: 16),
        ),
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              // أيقونة
              Container(
                width: 100,
                height: 100,
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: AppColors.primary.withOpacity(0.3),
                    width: 2,
                  ),
                ),
                child: const Icon(
                  Icons.no_photography_outlined,
                  size: 50,
                  color: AppColors.textSecondary,
                ),
              ),
              const SizedBox(height: 24),

              // العنوان
              const Text(
                'المسح بالكاميرا\nغير متاح على الويب',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 12),

              // الوصف
              Text(
                'ميزة المسح الضوئي تعتمد على مكتبات الكاميرا الأصلية\n'
                'غير المتاحة في متصفح الويب.\n\n'
                'يُمكنك إدخال السعر ورقم الطلب يدوياً.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 14,
                  height: 1.6,
                ),
              ),
              const SizedBox(height: 32),

              // زر الإغلاق
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.edit_outlined),
                  label: const Text('إدخال يدوي'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
