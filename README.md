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

نسخة الويب مخصّصة للعامل فقط ولا تعرض لوحة المدير حتى عند البناء الافتراضي
(`lib/main.dart` على الويب يفتح بوابة العامل حصراً). المزامنة تتم على نفس مسار
الـ APK: `restaurants/{Restaurant ID}/snapshot` و`heartbeat`، عبر بث SSE مع
فحص heartbeat كل ثانيتين في الاتجاهين.

```bash
flutter build web --target lib/worker_web_main.dart --dart-define=FIREBASE_DATABASE_URL=https://YOUR_DATABASE.firebaseio.com
```

انشر `build/web` على HTTPS (مطلوب لكاميرا آيفون). يدخل العامل `Restaurant ID`
واسم المستخدم وكلمة المرور أو PIN. إن لم يُضمَّن الرابط عند البناء يمكن تمريره
بـ `?db=` أو إدخاله في شاشة الدخول. التقاط الصورة يستخدم `capture=environment`
المناسب لسفاري. الحساب يجب أن يوجد تحت:
`restaurants/{Restaurant ID}/staff/{staffId}`.

## اختبارات التكامل الشبكي (Firebase)

يشغّل `test/worker_firebase_integration_test.dart` خادم HTTP محلياً يحاكي
Firebase Realtime Database بعقوده الحقيقية (REST + `ETag`/`If-Match` + بث
`SSE`)، ثم يمرّر عليه **نفس كود الطرفين**: خدمة العامل على الويب
(`WorkerWebService`) وتطبيق المدير (`FirebaseTrackingService` +
`FirebaseRealtimeService`) عبر HTTP فعلي، ويتحقق من:

- تسجيل دخول العامل بالشبكة مع عزل تام بين مطعمين بنفس الاسم وكلمة المرور.
- المزامنة الاتجاهية: طلب المدير يظهر عند العامل، وطلب العامل يظهر عند المدير.
- عقد `ETag/If-Match`: رفض الكتابة القديمة بـ 412 ثم نجاح إعادة محاولة العامل
  دون فقدان أي طلب.
- عقد بث `SSE` (`event: put` على `heartbeat.json`) الذي يستهلكه `EventSource`
  في متصفح الآيفون.

```bash
flutter test test/worker_firebase_integration_test.dart
```

خادم المحاكاة موجود في `test/support/fake_firebase_rtdb.dart` (لا يُشغَّل في
اختبارات الوحدة العادية).

## حماية الطلبات من التضارب (Conflict Safety)

`snapshot` في Firebase مستند كامل، فأي كتابة تُلغي محتواه السابق. لذلك:

- **العامل** يكتب بـ `If-Match` مع `ETag`، وعند `412` يُعيد القراءة والكتابة
  (٣ محاولات) فلا يفقد طلباً أضافه المدير.
- **المدير** يقرأ اللقطة قبل الكتابة ويضم طلبات الأجهزة الأخرى الجديدة
  (العلامة الزمنية `_lastCloudSnapshotAt` تفصل «الجديد غير المقروء» عن
  «المحذوف محلياً» فلا يعود طلب محذوف للظهور)، ثم يكتب محمياً بـ `ETag`،
  وعند `412` يُعيد القراءة والدمج ثم الكتابة.
- طلب أضافه المدير محلياً ولم يُنشر بعد لا يُسقطه تطبيق لقطة واردة.

الاختبارات التي تثبت ذلك: `test/worker_firebase_integration_test.dart`
(`دمج + ETag 412` و`العلامة الزمنية`).

## ملاحظات

- **iOS**: الحد الأدنى للإصدار 15.5 (متطلب ML Kit) في `ios/Podfile` و
  `AppFrameworkInfo.plist`/`project.pbxproj`، مع `PERMISSION_CAMERA=1`.
- **Android**: أذونات `CAMERA` و`INTERNET` في `AndroidManifest.xml`،
  وذاكرة Gradle مضبوطة لجهاز بذاكرة 8GB في `android/gradle.properties`.
- **الخطوط**: تُجلب خطوط GoogleFonts عند أول تشغيل (تحتاج إنترنت مرة واحدة)،
  ثم تُحفظ في الجهاز. لتشغيلها دون إنترنت دائماً: أضف ملفات الخط إلى
  `assets/` وعرّفها في `pubspec.yaml`.