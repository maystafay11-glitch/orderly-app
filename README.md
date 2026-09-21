# Orderly — حساب أجور عمال التوصيل

تطبيق Flutter عربي (RTL) لإدارة طلبات عمال الديليفري وحساب أجورهم وصافي المبلغ
المطلوب تسليمه للمطعم، مع إمكانية مسح أسعار الطلبات بالكاميرا.

## المعادلات المستخدمة (مصدر واحد للحقيقة: `lib/models/driver.dart`)

| القيمة | المعادلة |
| --- | --- |
| أجرة العامل | عدد الطلبات × 1000 دينار (`wagePerOrder`) |
| صافي المطعم للعامل | إجمالي مبالغ الطلبات − أجرة العامل |

## المزايا

- **الشاشة الرئيسية**: بطاقات العمال (عدد الطلبات، إجمالي المبالغ، الأجرة،
  صافي المطعم) + بطاقة «ملخص اليوم» بإجماليات كل العمال.
- **تسجيل طلب بسرعة**: النقر على بطاقة العامل يفتح حواراً لإدخال سعر الطلب،
  مع معاينة فورية للأرقام قبل الحفظ.
- **مسح بالكاميرا**: التعرّف على الأرقام في صورة الرقم/الفاتورة عبر
  Google ML Kit وملء حقل السعر تلقائياً (مع إمكانية التعديل يدوياً).
- **إدارة الأسماء**: شاشة إعدادات للإضافة والحذف (مع تأكيد) وتحديث فوري.
- **تصفير الحسابات**: بدء يوم جديد بتصفير الأرقام مع الاحتفاظ بالأسماء.
- **حفظ محلي تلقائي**: كل تعديل يُخزَّن في `shared_preferences` فوراً،
  فلا تُفقد البيانات بعد إغلاق التطبيق.

## بنية المشروع

```
lib/
├── main.dart                        نقطة الدخول + فرض اتجاه RTL
├── models/driver.dart               النموذج + الحسابات (أجرة/صافي)
├── services/
│   ├── driver_storage.dart          حفظ/استرجاع عبر shared_preferences
│   └── ocr_service.dart             استخراج الأرقام من نص الصورة (ML Kit)
├── screens/
│   ├── home_screen.dart             الشاشة الرئيسية + ملخص اليوم
│   ├── manage_drivers_screen.dart   إدارة أسماء العمال
│   └── camera_scan_screen.dart      الكاميرا والمسح الضوئي
├── theme/app_theme.dart             الألوان + خطوط GoogleFonts (Cairo)
├── utils/formatters.dart            تنسيق الأرقام والمبالغ بالعربية
└── widgets/                         بطاقات، مربّعات الأرقام، الحوارات
```

## الحزم المستخدمة

- `google_fonts` — الخطوط العربية الأنيقة (Cairo).
- `shared_preferences` — حفظ البيانات محلياً.
- `google_mlkit_text_recognition` + `google_mlkit_commons` — التعرف على النصوص.
- `camera` + `permission_handler` — الكاميرا وأذوناتها.

## التشغيل

```bash
flutter pub get
flutter test     # اختبارات النموذج + التخزين + منطق OCR + الواجهة
flutter run      # يحتاج جهازاً/محاكياً بكاميرا لتجربة المسح الضوئي
```

## Worker Web App (iPhone)

هذه نسخة ويب مستقلة للعامل فقط؛ لا تحتوي على لوحة المدير أو إعداداته. تستخدم
نفس مسار Firebase الخاص بالـ APK (`restaurants/{Restaurant ID}/snapshot`) كي
تتزامن الطلبات وحالاتها كل 3 ثوانٍ تقريباً في الاتجاهين.

```bash
flutter build web --target lib/worker_web_main.dart --dart-define=FIREBASE_DATABASE_URL=https://YOUR_DATABASE.firebaseio.com
```

انشر محتويات `build/web` على أي استضافة HTTPS. يدخل العامل `Restaurant ID`
واسم المستخدم وكلمة المرور أو PIN، ويمكنه إنشاء طلب وإرفاق صورة من كاميرا
iPhone. يجب أن يكون حساب العامل موجوداً في Firebase تحت:
`restaurants/{Restaurant ID}/staff/{staffId}`، وأن تسمح قواعد Firebase بالوصول
المناسب للمطعم.

## ملاحظات

- **iOS**: الحد الأدنى للإصدار 15.5 (متطلب ML Kit) في `ios/Podfile` و
  `AppFrameworkInfo.plist`/`project.pbxproj`، مع `PERMISSION_CAMERA=1`.
- **Android**: أذونات `CAMERA` و`INTERNET` في `AndroidManifest.xml`،
  وذاكرة Gradle مضبوطة لجهاز بذاكرة 8GB في `android/gradle.properties`.
- **الخطوط**: تُجلب خطوط GoogleFonts عند أول تشغيل (تحتاج إنترنت مرة واحدة)،
  ثم تُحفظ في الجهاز. لتشغيلها دون إنترنت دائماً: أضف ملفات الخط إلى
  `assets/` وعرّفها في `pubspec.yaml`.