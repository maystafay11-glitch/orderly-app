import 'dart:async';
import 'dart:math' as math;

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';

// permission_handler غير مدعوم على الويب — نستورده شرطياً
import 'package:orderly_app/screens/_permission_stub.dart'
    if (dart.library.io) 'package:permission_handler/permission_handler.dart';

import 'package:orderly_app/services/ocr_service.dart';
import 'package:orderly_app/theme/app_theme.dart';
import 'package:orderly_app/utils/formatters.dart';
import 'package:orderly_app/utils/image_preprocess.dart';
import 'package:orderly_app/utils/jpeg_info.dart';
import 'package:orderly_app/utils/live_scan_payload.dart';
import 'package:orderly_app/utils/scan_geometry.dart';
import 'package:orderly_app/utils/web_image_barcode.dart';
import 'package:orderly_app/utils/web_text_ocr.dart';
import 'package:orderly_app/widgets/scan_overlay.dart';

/// خطوات الالتقاط المتتابع (Continuous Scan Flow):
/// يبدأ بمسح سعر الطلب، ثم ينتقل تلقائياً ضمن نفس جلسة الكاميرا لمسح رقم الطلب.
enum ScanStep {
  /// الخطوة الأولى: توجيه الكاميرا نحو سعر الطلب.
  price,

  /// الخطوة الثانية: توجيه الكاميرا نحو رقم الطلب أو الفاتورة.
  orderNumber,
}

/// سبب توقّف الكاميرا، ويُحدَّد منه الأزرار المعروضة للمستخدم.
enum CameraFailureKind {
  /// لا يوجد خطأ.
  none,

  /// إذن الكاميرا مرفوض أو محجوب من المتصفح/إعدادات النظام.
  permission,

  /// الكاميرا مستخدمة من تطبيق أو تبويب آخر (NotReadableError).
  busy,

  /// لا توجد كاميرا مطابقة على الجهاز.
  notFound,

  /// المتصفح/الجهاز لا يدعم الواجهة المطلوبة، أو الصفحة غير آمنة.
  unsupported,

  /// الصفحة تُخدم عبر بروتوكول غير آمن (http) فيمنع المتصفح الكاميرا.
  insecureContext,

  /// لم يستجب المتصفح خلال المهلة المحددة.
  timeout,

  /// خطأ غير معروف.
  unknown,
}

/// استثناء داخلي يُرمى عند انتهاء مهلة تهيئة الكاميرا.
class _CameraStartTimeoutException implements Exception {
  const _CameraStartTimeoutException();

  @override
  String toString() => '_CameraStartTimeoutException';
}

/// وصف فشل تشغيل الكاميرا: نوعه + الرسالة العربية + هل الإذن مرفوض نهائياً.
class _CameraFailure {
  const _CameraFailure({
    required this.kind,
    required this.message,
    this.permanentlyDenied = false,
  });

  final CameraFailureKind kind;
  final String message;
  final bool permanentlyDenied;
}

/// شاشة المسح بالكاميرا (OCR) مع الالتقاط المتتابع السريع (Continuous Scan Flow).
///
/// تعمل بشكل متواصل دون إغلاق وفتح الكاميرا يدوياً بين الحقول:
/// 1. يبدأ بمسح **سعر الطلب**.
/// 2. فور التعرف عليه وظهور علامة الصح (✅)، ينتقل تلقائياً وفورياً إلى مربع
///    **رقم الطلب** ضمن نفس جلسة الكاميرا النشطة.
/// 3. يدعم كشف السعر ورقم الطلب معاً في لقطة واحدة إن وُجدا في الفاتورة.
/// 4. يتيح زر «تخطي والاعتماد» إن رغب الكاشير في الاكتفاء بالسعر فقط دون رقم طلب.
///
/// **على الويب (Flutter Web)**:
/// * لا تُشغَّل الكاميرا تلقائياً عند فتح الشاشة؛ بل بعد فحص بيئة المتصفح
///   (سياق آمن https + حالة إذن الكاميرا) وبعد **نقرة صريحة** من المستخدم،
///   لأن متصفحات الجوال (Safari خصوصاً) ترفض تشغيل الكاميرا بدون تفاعل
///   مباشر فتظهر معاينة سوداء.
/// * عند أي فشل تُعرض رسالة دقيقة مع أزرار واضحة: «إعادة المحاولة»،
///   «كيف أسمح بالكاميرا؟»، و«الإدخال اليدوي»، مع زر «إعادة تشغيل الكاميرا»
///   داخل الشاشة بدون إغلاقها.
/// * قراءة الأرقام تلقائياً (OCR) غير متاحة في المتصفح (google_mlkit لا يدعم
///   Flutter Web)، فيُعرض تنبيه صريح بذلك مع إدخال يدوي بدل رسائل فشل مضللة.
class CameraScanScreen extends StatefulWidget {
  const CameraScanScreen({
    super.key,
    this.initialStep = ScanStep.price,
    this.initialPrice,
    this.initialOrderNumber,
  });

  /// الخطوة التي تبدأ بها الشاشة (افتراضياً سعر الطلب).
  final ScanStep initialStep;

  /// سعر مسجل مسبقاً في حال فتح الكاميرا لمسح رقم الطلب فقط.
  final double? initialPrice;

  /// رقم طلب مسجل مسبقاً في حال فتح الكاميرا لمسح السعر فقط.
  final String? initialOrderNumber;

  /// عنوان الشاشة (يُستخدم في الاختبارات أيضاً).
  static const String title = 'مسح الرقم بالكاميرا';

  @override
  State<CameraScanScreen> createState() => _CameraScanScreenState();
}

class _CameraScanScreenState extends State<CameraScanScreen>
    with WidgetsBindingObserver {
      CameraController? _controller;
    Timer? _webScanTimer;
    bool _waitingForUserStart = true;
  bool _isInitializing = true;
  bool _isProcessing = false;
  bool _isTorchOn = false;
  bool _permissionPermanentlyDenied = false;
  String? _error;
  String? _notice;

  /// نوع الفشل الحالي، ويُحدَّد منه الأزرار والنصائح المعروضة.
  CameraFailureKind _failureKind = CameraFailureKind.none;

  /// دقة الكاميرا المطلوبة (تُخفَّض تلقائياً إذا رفضها المتصفح).
  ResolutionPreset _resolutionPreset = ResolutionPreset.high;

  /// هل جرّبنا خفض الدقة بعد رفض الدقة الأعلى من قِبَل المتصفح؟
  bool _didDowngradeResolution = false;

  // ─── الويب: مسار الصورة الثابتة (Snapshot) ──────────────────────────────

  /// منتقي الصور: يفتح كاميرا الجهاز أو معرض الصور بلا أي بث فيديو مباشر.
  final ImagePicker _imagePicker = ImagePicker();

  /// بايتات الصورة الملتقطة حالياً (تُعرض داخل إطار المسح للمراجعة).
  Uint8List? _snapshotBytes;

  /// أبعاد الصورة الملتقطة بالبكسل (لتحويل إطار المسح إلى منطقة داخلها).
  Size? _snapshotSize;

  /// هل يجري فكّ الصورة وقراءة الأرقام منها الآن؟
  bool _isReadingSnapshot = false;

  /// أبعاد منطقة المعاينة الحالية (تُستخدم لحساب إطار المسح).
  Size? _previewSize;

  /// الخطوة الحالية في الالتقاط المتتابع.
  late ScanStep _currentStep;

  /// السعر الذي تم التقاطه وتأكيده.
  double? _capturedPrice;

  /// رقم الطلب الذي تم التقاطه وتأكيده.
  String? _capturedOrderNumber;

  /// قائمة المبالغ المجمّعة للاقتراحات والبدائل.
  List<double> _accumulatedAmounts = <double>[];

  /// قائمة أرقام الطلبات المجمّعة للاقتراحات والبدائل.
  List<String> _accumulatedNumbers = <String>[];

  /// هل تم إظهار إشارة النجاح (✅) للخطوة الحالية؟
  bool _stepSucceeded = false;

  /// نص رسالة النجاح المعروضة مع إشارة ✅.
  String _successMessage = '';

  /// مفتاح للكشف عن أيقونة النجاح في الاختبارات.
  static const Key successKey = Key('scan-success-checkmark');

  /// حجم مربع المسح بالبكسل.
  static const Size scanBoxSize = Size(280, 170);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _currentStep = widget.initialStep;
    _capturedPrice = widget.initialPrice;
    _capturedOrderNumber = widget.initialOrderNumber;
    _bootstrapCamera();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _controller?.dispose();
    _controller = null;
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // على الويب لا توجد جلسة كاميرا مباشرة نُديرها (الالتقاط يتم عبر كاميرا
    // الجهاز عند الطلب)، فلا حاجة لأي معالجة هنا.
    if (kIsWeb) {
      return;
    }

    if (_controller == null || !_controller!.value.isInitialized) {
      return;
    }

    if (state == AppLifecycleState.inactive) {
      _controller?.dispose();
      _controller = null;
      if (mounted) {
        setState(() {});
      }
    } else if (state == AppLifecycleState.resumed) {
      _initializeCamera();
    }
  }

  /// تهيئة الشاشة بحسب المنصة:
  ///
  /// * Android/iOS: طلب إذن الكاميرا ثم تشغيل الكاميرا وقراءة الأرقام (OCR).
     /// * الويب: البث المباشر (Live Stream) — ننتظر نقرة مستخدم على
  ///   «ابدأ المسح بالكاميرا» لتفعيد الكاميرا (يطلب الإذن من المتصفح).
  Future<void> _bootstrapCamera() async {
    if (!kIsWeb) {
      await _initializeCamera();
      return;
    }

    // ✅ على الويب: لا شيء للفعله الآن — نعرض زر البدء للمستخدم
    if (mounted) {
      setState(() {
        _isInitializing = false;
        _waitingForUserStart = true;
      });
    }
  }
  /// مهلة تهيئة الكاميرا.
  ///
  /// على الويب قد تبقى المعاينة سوداء دون أي استجابة، فلا نترك الشاشة
  /// معلّقة بلا نهاية على زر التحميل.
  Duration get _initializeTimeout => kIsWeb
      ? const Duration(seconds: 25)
      : const Duration(seconds: 15);

  /// طلب إذن الكاميرا ثم تشغيل الكاميرا الخلفية.
  ///
  /// [fromUserGesture] يكون `true` عندما يأتي التشغيل من نقرة مباشرة
  /// (زر «السماح وتشغيل الكاميرا» أو «إعادة المحاولة»)، وهو شرط أساسي
  /// لتشغيل الكاميرا في متصفحات الجوال على الويب.
  Future<void> _initializeCamera({bool fromUserGesture = false}) async {
    if (mounted) {
      setState(() {
        _isInitializing = true;
        _error = null;
        _notice = null;
        _failureKind = CameraFailureKind.none;
        _permissionPermanentlyDenied = false;
      });
    }

    // تنظيف أي جلسة سابقة قبل إعادة المحاولة (تمنع تعارض الكاميرا مع نفسها).
    await _disposeController();

    try {
      // 1) إذن الكاميرا:
      //    * Android/iOS: عبر permission_handler.
      //    * الويب: لا نستدعي permission_handler (غير مدعوم)؛ المتصفح نفسه
      //      يطلب الإذن عند أول getUserMedia، وقد فُحصت حالته في _bootstrapCamera.
      if (!kIsWeb) {
        final PermissionStatus status = await Permission.camera.request();
        if (!status.isGranted) {
          _applyFailure(
            _CameraFailure(
              kind: CameraFailureKind.permission,
              permanentlyDenied: status.isPermanentlyDenied,
              message: status.isPermanentlyDenied
                  ? 'تم رفض إذن الكاميرا نهائياً. افتح إعدادات التطبيق وامنح '
                        'إذن الكاميرا ثم أعد المحاولة.'
                  : 'لا يمكن المسح بالكاميرا دون السماح باستخدام الكاميرا.',
            ),
          );
          return;
        }
      }

      // 2) البحث عن الكاميرات المتاحة في الجهاز.
      final List<CameraDescription> cameras = await availableCameras();
      if (cameras.isEmpty) {
        _applyFailure(
          const _CameraFailure(
            kind: CameraFailureKind.notFound,
            message: 'لم يتم العثور على كاميرا في هذا الجهاز.',
          ),
        );
        return;
      }

      // 3) تفضيل الكاميرا الخلفية (الأنسب لقراءة الأرقام والأسعار).
      final CameraDescription description = cameras.firstWhere(
        (CameraDescription camera) =>
            camera.lensDirection == CameraLensDirection.back,
        orElse: () => cameras.first,
      );

      // 4) إعدادات البدء الصحيحة للمتصفحات والجوال:
      //    * enableAudio: false — الفيديو غير المكتوم قد يُمنع من التشغيل
      //      تلقائياً على الويب فيبقى العنصر أسود.
      //    * ResolutionPreset — يُخفَّض تلقائياً إلى medium إذا رفض المتصفح
      //      الدقة المطلوبة (cameraOverconstrained).
      final CameraController controller = CameraController(
        description,
        _resolutionPreset,
        enableAudio: false,
      );

      // 5) initialize() هي نقطة البدء الصحيحة في مكتبة camera الحديثة:
      //    لا يوجد أسلوب start() في CameraController (0.12+)؛ فعلى الويب
      //    يُنشئ initialize() عنصر <video> ويستدعي video.play() داخلياً،
      //    وعند توقف المعاينة لاحقاً يُستخدم resumePreview() وهو البديل
      //    المتوافق مع كل المتصفحات.
      final Future<void> initializing = controller.initialize();
      try {
        await initializing.timeout(_initializeTimeout);
      } on TimeoutException {
        // إذا اكتمل التشغيل بعد انتهاء المهلة نُحرّر الكاميرا فوراً
        // حتى لا تبقى مفتوحة في الخلفية.
        unawaited(
          initializing
              .then((_) => controller.dispose())
              .catchError((Object _) {}),
        );
        throw const _CameraStartTimeoutException();
      }

      if (!mounted) {
        await controller.dispose();
        return;
      }

      // 6) التأكد من وجود معاينة حقيقية (يمنع «الشاشة السوداء» الصامتة).
      if (kIsWeb && controller.value.previewSize == null) {
        await controller.dispose();
        _applyFailure(
          const _CameraFailure(
            kind: CameraFailureKind.unsupported,
            message:
                'لم تُرجع الكاميرا صورة معاينة. تأكد من عدم استخدام الكاميرا في '
                'تطبيق أو تبويب آخر، ثم أعد المحاولة.',
          ),
        );
        return;
      }

      setState(() {
        _controller = controller;
        _isInitializing = false;
        _failureKind = CameraFailureKind.none;
      });

      // 7) تشغيل المعاينة إن كانت متوقفة.
      await _ensurePreviewRunning();
    } catch (error) {
      if (!mounted) {
        return;
      }

      // دقة غير مدعومة: نُعيد المحاولة مرة واحدة بدقة أقل قبل إظهار خطأ.
      if (kIsWeb &&
          !_didDowngradeResolution &&
          error is CameraException &&
          (error.code == 'cameraOverconstrained' ||
              error.code == 'cameraNotSupported')) {
        _didDowngradeResolution = true;
        _resolutionPreset = ResolutionPreset.medium;
        await _initializeCamera(fromUserGesture: fromUserGesture);
        return;
      }

      _applyFailure(_describeFailure(error));
    }
  }

  /// عرض رسالة الفشل مع تحديد نوعه والأزرار المناسبة للإصلاح.
  void _applyFailure(_CameraFailure failure) {
    if (!mounted) {
      return;
    }
    setState(() {
      _isInitializing = false;
      _failureKind = failure.kind;
      _permissionPermanentlyDenied = failure.permanentlyDenied;
      _error = failure.message;
    });
  }

  /// إيقاف وتحرير الكاميرا الحالية.
  ///
  /// يُستدعى قبل كل إعادة محاولة وعند إغلاق الشاشة، لأن تشغيل كاميرا جديدة
  /// فوق جلسة قديمة هو أكثر أسباب «الشاشة السوداء» على الويب (الكاميرا تكون
  /// مشغولة بالتسجيل السابق).
  Future<void> _disposeController() async {
    final CameraController? controller = _controller;
    _controller = null;
    if (controller == null) {
      return;
    }
    try {
      await controller.dispose();
    } catch (_) {
      // نتجاهل أخطاء الإغلاق: الجلسة قد تكون منتهية أصلاً.
    }
  }

  /// إعادة تشغيل المعاينة إن كانت متوقفة.
  ///
  /// على الويب `resumePreview()` هي البديل المتوافق لأسلوب `start()` في
  /// النسخ القديمة من المكتبة: تُعيد استدعاء `video.play()` على نفس البث
  /// دون طلب إذن جديد ودون إعادة تهيئة كاملة.
  Future<void> _ensurePreviewRunning() async {
    final CameraController? controller = _controller;
    if (controller == null || !controller.value.isInitialized) {
      return;
    }
    if (controller.value.isPreviewPaused) {
      try {
        await controller.resumePreview();
      } catch (_) {
        // إن فشل الاستئناف يبقى زر «إعادة تشغيل الكاميرا» متاحاً للمستخدم.
      }
    }
  }

  /// زر احتياطي في الشريط العلوي.
  ///
  /// * الويب: يمسح الصورة الحالية للبدء من جديد (لا يوجد بث فيديو لإعادة تشغيله).
  /// * الأجهزة الأصلية: يجرّب استئناف المعاينة على نفس الجلسة ثم يعيد التهيئة.
  Future<void> _restartCamera() async {
    if (kIsWeb) {
      _resetSnapshot();
      return;
    }

    if (_isInitializing) {
      return;
    }

    final CameraController? controller = _controller;
    if (controller != null && controller.value.isInitialized) {
      try {
        await controller.resumePreview();
        if (!mounted) {
          return;
        }
        setState(() {
          _error = null;
          _notice = 'تم إعادة تشغيل الكاميرا.';
          _failureKind = CameraFailureKind.none;
        });
        return;
      } catch (_) {
        // فشل الاستئناف → ننتقل لإعادة التهيئة الكاملة أدناه.
      }
    }

    await _initializeCamera(fromUserGesture: true);
  }
  /// تحويل خطأ المكتبة/المتصفح إلى رسالة عربية واضحة ونوع فشل معروف.
  ///
  /// أسماء الأخطاء تأتي من `camera_web` (مثل `CameraAccessDenied` و
  /// `cameraNotFound`) ومن `permission_handler` على الأجهزة الأصلية.
  _CameraFailure _describeFailure(Object error) {
    if (error is _CameraStartTimeoutException) {
      return _CameraFailure(
        kind: CameraFailureKind.timeout,
        message: kIsWeb
            ? 'لم يستجب المتصفح خلال المهلة المحددة. تأكد من السماح بالكاميرا، '
                  'وأغلق التطبيقات أو التبويبات الأخرى التي تستخدمها، ثم أعد المحاولة.'
            : 'تأخّر تشغيل الكاميرا. أغلق التطبيقات التي تستخدم الكاميرا '
                  'ثم أعد المحاولة.',
      );
    }

    if (error is! CameraException) {
      return const _CameraFailure(
        kind: CameraFailureKind.unknown,
        message: 'حدث خطأ غير متوقع أثناء تشغيل الكاميرا.',
      );
    }

    switch (error.code) {
      case 'CameraAccessDenied':
      case 'CameraAccessDeniedWithoutPrompt':
      case 'CameraAccessRestricted':
        return _CameraFailure(
          kind: CameraFailureKind.permission,
          permanentlyDenied: true,
          message: kIsWeb
              ? 'إذن الكاميرا غير ممنوح لهذا الموقع، ولن يعرض المتصفح نافذة '
                    'الطلب مرة أخرى.\n\n'
                    'اضغط «كيف أسمح بالكاميرا؟» لمعرفة طريقة تفعيلها من إعدادات '
                    'المتصفح، ثم أعد المحاولة.'
              : 'تم رفض إذن الكاميرا. افتح إعدادات التطبيق وامنح إذن الكاميرا '
                    'ثم أعد المحاولة.',
        );
      case 'AudioAccessDenied':
      case 'AudioAccessDeniedWithoutPrompt':
      case 'AudioAccessRestricted':
        return const _CameraFailure(
          kind: CameraFailureKind.permission,
          permanentlyDenied: true,
          message: 'تم رفض إذن الميكروفون، وهو مطلوب لهذه الكاميرا. امنح الإذن '
              'ثم أعد المحاولة.',
        );

      case 'cameraNotReadable':
        return const _CameraFailure(
          kind: CameraFailureKind.busy,
          message: 'الكاميرا مستخدمة حالياً من تطبيق أو تبويب آخر.\n\n'
              'أغلق التطبيقات والتبويبات الأخرى التي تستخدم الكاميرا ثم أعد المحاولة.',
        );
      case 'cameraNotFound':
        return const _CameraFailure(
          kind: CameraFailureKind.notFound,
          message: 'لم يتم العثور على كاميرا مطابقة في هذا الجهاز.',
        );
      case 'cameraOverconstrained':
        return const _CameraFailure(
          kind: CameraFailureKind.unsupported,
          message: 'دقة الكاميرا المطلوبة غير مدعومة في هذا المتصفح أو الجهاز. '
              'أعد المحاولة وسيُستخدم إعداد أدنى تلقائياً.',
        );
      case 'cameraNotSupported':
      case 'cameraMissingMetadata':
        return const _CameraFailure(
          kind: CameraFailureKind.unsupported,
          message: 'هذا المتصفح أو الجهاز لا يدعم تشغيل الكاميرا بالطريقة '
              'المطلوبة. استخدم Chrome أو Safari بإصدار حديث.',
        );
      case 'cameraType':
      case 'cameraSecurity':
        return const _CameraFailure(
          kind: CameraFailureKind.unsupported,
          message: 'رفض النظام تشغيل الكاميرا. تحقق من أذونات الكاميرا في إعدادات '
              'الجهاز.',
        );
      case 'cameraAbort':
        return const _CameraFailure(
          kind: CameraFailureKind.busy,
          message: 'توقّف تشغيل الكاميرا بسبب مشكلة مؤقتة في الجهاز. أعد المحاولة.',
        );
      default:
        return _CameraFailure(
          kind: CameraFailureKind.unknown,
          message: 'تعذّر تشغيل الكاميرا (${error.code}).',
        );
    }
  }
  /// خطوات السماح بالكاميرا لكل متصفح (تُعرض في نافذة المساعدة).
  static const String _permissionHelpText =
      'متصفح Chrome / Edge (أندرويد أو كمبيوتر):\n'
      '• اضغط أيقونة الإعدادات (🔒 أو ⓘ) بجانب عنوان الموقع.\n'
      '• اختر «الأذونات» ← «الكاميرا» ← «السماح».\n'
      '• أعد تحميل الصفحة ثم اضغط «إعادة المحاولة».\n\n'
      'متصفح Safari على iPhone/iPad:\n'
      '• الإعدادات ← Safari ← الكاميرا ← «اسأل» أو «السماح».\n'
      '• وفي الموقع: اضغط «أأ» بجانب العنوان ← «إعدادات موقع الويب» ← '
      '«الكاميرا» ← «السماح».\n\n'
      'عند استخدام التطبيق من الشاشة الرئيسية (PWA):\n'
      '• احذف الأيقونة من الشاشة الرئيسية، ثم أضِفها مرة أخرى بعد منح الإذن.\n\n'
      'ملاحظات مهمة:\n'
      '• تشغيل الكاميرا يحتاج اتصالاً آمناً https:// وليس http://.\n'
      '• لا بد من الضغط على زر التشغيل يدوياً؛ المتصفح لا يسمح بالتشغيل التلقائي.\n'
      '• تأكد من عدم استخدام الكاميرا في تطبيق آخر (واتساب، تحرير الفيديو…).';

  /// إظهار نافذة مساعدة توضح طريقة منح إذن الكاميرا في المتصفح.
  Future<void> _showCameraPermissionHelp() async {
    await showDialog<void>(
      context: context,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          backgroundColor: AppColors.surface,
          title: const Text(
            'كيف أسمح بالكاميرا؟',
            style: TextStyle(color: AppColors.textPrimary),
          ),
          content: SingleChildScrollView(
            child: Text(
              _permissionHelpText,
              style: const TextStyle(
                color: AppColors.textSecondary,
                height: 1.8,
                fontSize: 13,
              ),
            ),
          ),
          actions: <Widget>[
            TextButton(
              key: const ValueKey<String>('camera-help-close-button'),
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('حسناً'),
            ),
            FilledButton.icon(
              key: const ValueKey<String>('camera-help-retry-button'),
              onPressed: () {
                Navigator.of(dialogContext).pop();
                _retrySnapshot();
              },
              icon: const Icon(Icons.refresh, size: 18),
              label: const Text('إعادة المحاولة'),
            ),
          ],
        );
      },
    );
  }

  /// الخروج إلى الإدخال اليدوي مع الحفاظ على أي قيم تم التقاطها أو تمريرها.
  void _exitWithManualEntry() {
    _finishFlow();
  }

  Future<void> _toggleTorch() async {
    final CameraController? controller = _controller;
    if (controller == null) {
      return;
    }
    final bool nextValue = !_isTorchOn;
    try {
      await controller.setFlashMode(
        nextValue ? FlashMode.torch : FlashMode.off,
      );
      if (mounted) {
        setState(() => _isTorchOn = nextValue);
      }
    } on CameraException {
      if (mounted) {
        setState(() => _notice = 'الفلاش غير مدعوم على هذه الكاميرا.');
      }
    }
  }

  /// حساب منطقة مربع المسح بالإحداثيات الخاصة بالصورة المقطوعة.
  Future<Rect> _regionInImageCoords(XFile photo) async {
    final CameraController? controller = _controller;
    final Size? previewSize = controller?.value.previewSize;
    final Size screenSize = MediaQuery.of(context).size;
    final Size? imageSize = await _imageSize(photo);
    if (previewSize == null || imageSize == null) {
      return Rect.fromLTWH(0, 0, scanBoxSize.width, scanBoxSize.height);
    }

    final Rect scanBox = Rect.fromLTWH(
      (screenSize.width - scanBoxSize.width) / 2,
      (screenSize.height - scanBoxSize.height) / 2,
      scanBoxSize.width,
      scanBoxSize.height,
    );
    return ScanGeometry.mapToImage(
          scanBox: scanBox,
          viewSize: screenSize,
          imageSize: imageSize,
        ) ??
        Rect.fromLTWH(0, 0, scanBoxSize.width, scanBoxSize.height);
  }

  static Future<Size?> _imageSize(XFile photo) async {
    try {
      final Uint8List bytes = await photo.readAsBytes();
      if (bytes.length < 4) {
        return null;
      }
      final JpegInfo? info = JpegInfo.parse(bytes);
      return info?.displaySize;
    } catch (_) {
      return null;
    }
  }

  /// تنفيذ الالتقاط ومعالجة النص بحسب الخطوة الحالية.
  Future<void> _captureAndRecognize() async {
    final CameraController? controller = _controller;
    if (controller == null ||
        !controller.value.isInitialized ||
        _isProcessing ||
        _stepSucceeded) {
      return;
    }

    setState(() {
      _isProcessing = true;
      _notice = null;
    });

    try {
      final XFile photo = await controller.takePicture();
      final Rect region = await _regionInImageCoords(photo);
      OcrResult result = await OcrService.readRegion(
        photo.path,
        region: region,
      );

      // قراءة مقصورة كلياً على الكتابة الواقعة داخل المربع المخصص
      if (result.isEmpty) {
        if (!mounted) {
          return;
        }
        setState(() {
          _isProcessing = false;
          _notice =
              'لم يتم العثور على أرقام داخل المربع. ضع الرقم في منتصف المربع بدقة.';
        });
        return;
      }

      if (!mounted) {
        return;
      }

      if (_currentStep == ScanStep.price) {
        _handlePriceStepResult(result);
      } else {
        _handleOrderNumberStepResult(result);
      }
    } catch (_) {
      if (!mounted) {
        return;
      }
      setState(() {
        _isProcessing = false;
        _notice = 'تعذّر التعرف على النص من الصورة، حاول مرة أخرى.';
      });
    }
  }

  /// معالجة نتيجة مسح سعر الطلب (الخطوة 1).
  void _handlePriceStepResult(OcrResult result) {
    // تجميع البدائل
    _accumulatedAmounts = <double>[
      ..._accumulatedAmounts,
      ...result.amounts,
    ];
    _accumulatedNumbers = <String>[
      ..._accumulatedNumbers,
      ...result.orderNumbers,
    ];

    final double? price = result.best;
    final String? orderNum = result.bestOrderNumber;

    // حالة 1: تم التعرف على السعر ورقم الطلب معاً في نفس الصورة!
    if (price != null && orderNum != null) {
      _capturedPrice = price;
      _capturedOrderNumber = orderNum;
      setState(() {
        _stepSucceeded = true;
        _successMessage = 'تم التعرف على السعر (${formatAmount(price)})\nورقم الطلب (#$orderNum) معاً بنجاح!';
      });
      HapticFeedback.mediumImpact();
      Future.delayed(const Duration(milliseconds: 750), () {
        if (mounted) {
          _finishFlow(price: price, orderNumber: orderNum);
        }
      });
      return;
    }

    // حالة 2: تم التعرف على السعر فقط
    if (price != null) {
      _capturedPrice = price;
      setState(() {
        _stepSucceeded = true;
        _successMessage = 'تم التعرف على السعر: ${formatAmount(price)} ✅\nجاري الانتقال لمسح رقم الطلب…';
      });
      HapticFeedback.lightImpact();

      // انتقال تلقائي وفوري للخطوة 2 دون إغلاق الكاميرا
      Future.delayed(const Duration(milliseconds: 700), () {
        if (mounted) {
          setState(() {
            _currentStep = ScanStep.orderNumber;
            _stepSucceeded = false;
            _isProcessing = false;
            _notice = null;
          });
        }
      });
      return;
    }

    // حالة 3: التقط رقماً يشبه رقم الطلب ولكن لم يجد سعراً
    if (orderNum != null) {
      _capturedOrderNumber = orderNum;
      setState(() {
        _isProcessing = false;
        _notice = 'تم التقاط رقم الطلب (#$orderNum). وجّه المربع نحو السعر الآن.';
      });
      return;
    }

    // حالة 4: لم يعثر على أرقام
    setState(() {
      _isProcessing = false;
      _notice = 'لم يتم التعرف على السعر داخل المربع. قرّب الكاميرا وحاول ثانية.';
    });
  }

  /// معالجة نتيجة مسح رقم الطلب (الخطوة 2).
  void _handleOrderNumberStepResult(OcrResult result) {
    _accumulatedNumbers = <String>[
      ..._accumulatedNumbers,
      ...result.orderNumbers,
    ];

    // استخراج أفضل رقم طلب
    String? detected = result.bestOrderNumber;

    // إذا لم يجد كلمة "طلب" أو "#"، نبحث عن أي تسلسل أرقام مستقل
    if (detected == null || detected.isEmpty) {
      final RegExp digitReg = RegExp(r'\b\d{1,8}\b');
      final Match? match = digitReg.firstMatch(result.rawText);
      if (match != null) {
        detected = match.group(0);
      } else if (result.amounts.isNotEmpty) {
        detected = result.amounts.first.round().toString();
      }
    }

    if (detected != null && detected.isNotEmpty) {
      _capturedOrderNumber = detected;
      setState(() {
        _stepSucceeded = true;
        _successMessage = 'تم التعرف على رقم الطلب: #$detected ✅';
      });
      HapticFeedback.lightImpact();
      Future.delayed(const Duration(milliseconds: 700), () {
        if (mounted) {
          _finishFlow(orderNumber: detected);
        }
      });
      return;
    }

    setState(() {
      _isProcessing = false;
      _notice = 'لم يتم التعرف على رقم الطلب. قرّب الكاميرا أو اضغط «تخطي والاعتماد».';
    });
  }

  /// إنهاء جلسة الكاميرا وإرجاع النتيجة الكاملة للشاشة السابقة.
  void _finishFlow({double? price, String? orderNumber}) {
    final double? finalPrice = price ?? _capturedPrice;
    final String? finalNumber = orderNumber ?? _capturedOrderNumber;

    final List<double> distinctAmounts = <double>[
      if (finalPrice != null) finalPrice,
      ..._accumulatedAmounts.where((double a) => a != finalPrice),
    ];

    final List<String> distinctNumbers = <String>[
      if (finalNumber != null && finalNumber.isNotEmpty) finalNumber,
      ..._accumulatedNumbers.where((String n) => n != finalNumber),
    ];

    final OcrResult result = OcrResult(
      rawText: 'Price: $finalPrice, Order: $finalNumber',
      amounts: distinctAmounts,
      orderNumbers: distinctNumbers,
    );

    Navigator.of(context).pop(result);
  }

  /// العودة إلى خطوة مسح السعر إن رغب المستخدم بإعادة مسحه.
  void _rescanPrice() {
    setState(() {
      _currentStep = ScanStep.price;
      _stepSucceeded = false;
      _isProcessing = false;
      _notice = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: const Text(CameraScanScreen.title),
        actions: <Widget>[
          // زر احتياطي: إعادة تشغيل الكاميرا بدون إغلاق الشاشة.
          IconButton(
            key: const ValueKey<String>('camera-restart-button'),
            onPressed: _isInitializing ? null : _restartCamera,
            tooltip: 'إعادة تشغيل الكاميرا',
            icon: const Icon(Icons.refresh_rounded),
          ),
          IconButton(
            // الفلاش غير مدعوم على الويب (بث الفيديو لا يوفّر torch).
            onPressed: (_controller == null || kIsWeb) ? null : _toggleTorch,
            tooltip: 'الفلاش',
            icon: Icon(_isTorchOn ? Icons.flash_on : Icons.flash_off),
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: _buildBody(),
    );
  }

  // ─── الويب: واجهة الالتقاط (صورة ثابتة داخل إطار التحديد) ──────────────

  /// واجهة المسح على الويب: صورة ثابتة داخل إطار التحديد + أزرار الالتقاط.
  // ignore: unused_element
  Widget _buildSnapshotView() {
    final Uint8List? bytes = _snapshotBytes;
    final String? notice = _notice;
    final bool isOrderNumberStep = _currentStep == ScanStep.orderNumber;

    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        // نحفظ أبعاد منطقة المعاينة لحساب إطار المسح داخل الصورة الملتقطة.
        _previewSize = constraints.biggest;

        return Stack(
          fit: StackFit.expand,
          children: <Widget>[
            // 1) الصورة الملتقطة (أو مكان فارغ يوضح الخطوة المطلوبة).
            _buildSnapshotPreview(bytes),

            // 2) إطار التحديد نفسه (نفس شكل الشاشة الحالية).
            ScanBoxOverlay(
              scanBoxSize: scanBoxSize,
              instructions: isOrderNumberStep
                  ? 'التقط صورة لرقم الطلب أو الباركود'
                  : 'التقط صورة لسعر الطلب',
            ),

            // 3) شريط خطوات الالتقاط المتتابع.
            Positioned(
              top: 14,
              left: 16,
              right: 16,
              child: _buildStepperHeader(),
            ),

            // 4) علامة النجاح عند قراءة قيمة.
            if (_stepSucceeded)
              ScanSuccessOverlay(
                checkmarkKey: successKey,
                message: _successMessage,
              ),

            // 5) التنبيهات النصية.
            if (notice != null && !_stepSucceeded)
              Positioned(
                left: 20,
                right: 20,
                bottom: isOrderNumberStep ? 258 : 206,
                child: _ScanHint(text: notice, isWarning: true),
              ),

            // 6) مؤشر القراءة أثناء تحليل الصورة.
            if (_isProcessing)
              const Positioned(
                top: 66,
                left: 0,
                right: 0,
                child: Center(child: _SnapshotReadingChip()),
              ),

            // 7) أزرار الالتقاط + الإدخال اليدوي.
            Positioned(
              left: 0,
              right: 0,
              bottom: 24,
              child: _buildSnapshotControls(),
            ),
          ],
        );
      },
    );
  }

  /// معاينة الصورة الملتقطة (أو حالة فارغة واضحة قبل الالتقاط).
  Widget _buildSnapshotPreview(Uint8List? bytes) {
    if (bytes == null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 30),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              const Icon(
                Icons.photo_camera_outlined,
                size: 54,
                color: Colors.white54,
              ),
              const SizedBox(height: 12),
              Text(
                'لا توجد صورة بعد',
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(color: Colors.white70),
              ),
              const SizedBox(height: 6),
              Text(
                'اضغط «التقاط صورة» لفتح كاميرا جهازك وتصوير السعر أو رقم '
                'الطلب، ثم تُقرأ الأرقام تلقائياً.',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Colors.white54,
                  height: 1.6,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return ColoredBox(
      color: Colors.black,
      child: Image.memory(
        bytes,
        fit: BoxFit.cover,
        gaplessPlayback: true,
        filterQuality: FilterQuality.medium,
      ),
    );
  }

  /// أزرار شاشة الالتقاط: كاميرا الجهاز + الصور + الإدخال اليدوي (بارز).
  Widget _buildSnapshotControls() {
    final bool isOrderNumberStep = _currentStep == ScanStep.orderNumber;
    final bool busy = _isReadingSnapshot || _isProcessing;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        // في خطوة رقم الطلب: إعادة مسح السعر + تخطي والاعتماد.
        if (isOrderNumberStep) ...<Widget>[
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: <Widget>[
                TextButton.icon(
                  onPressed: _rescanPrice,
                  style: TextButton.styleFrom(
                    foregroundColor: Colors.white70,
                    backgroundColor: Colors.black45,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 6,
                    ),
                  ),
                  icon: const Icon(Icons.undo_rounded, size: 16),
                  label: const Text(
                    'إعادة مسح السعر',
                    style: TextStyle(fontSize: 12),
                  ),
                ),
                FilledButton.icon(
                  key: const ValueKey<String>('skip-order-number-button'),
                  onPressed: () => _finishFlow(),
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 8,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  icon: const Icon(Icons.check_rounded, size: 18),
                  label: const Text(
                    'تخطي والاعتماد الآن',
                    style: TextStyle(fontSize: 12),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
        ],

        // زرّا الالتقاط: كاميرا الجهاز + اختيار صورة محفوظة.
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Row(
            children: <Widget>[
              Expanded(
                child: FilledButton.icon(
                  key: const ValueKey<String>('snapshot-camera-button'),
                  onPressed: busy ? null : () => _pickSnapshot(fromCamera: true),
                  icon: const Icon(Icons.photo_camera_rounded, size: 20),
                  label: const Text('التقاط صورة'),
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: OutlinedButton.icon(
                  key: const ValueKey<String>('snapshot-gallery-button'),
                  onPressed: busy ? null : () => _pickSnapshot(fromCamera: false),
                  icon: const Icon(Icons.photo_library_outlined, size: 20),
                  label: const Text('من الصور'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    side: const BorderSide(color: Colors.white54),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),

        const SizedBox(height: 10),

        // الإدخال اليدوي: خيار بديل بارز دائماً في أسفل الشاشة.
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              key: const ValueKey<String>('camera-manual-entry-button'),
              onPressed: _isProcessing ? null : _exitWithManualEntry,
              icon: const Icon(Icons.keyboard_alt_outlined, size: 18),
              label: const Text('الإدخال اليدوي (السعر ورقم الطلب)'),
              style: FilledButton.styleFrom(
                backgroundColor: Colors.white,
                foregroundColor: Colors.black87,
                padding: const EdgeInsets.symmetric(vertical: 13),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  /// مؤشر تحميل موحّد أثناء تهيئة الكاميرا.
  Widget _buildLoadingIndicator() {
    final TextStyle? style = Theme.of(
      context,
    ).textTheme.bodyMedium?.copyWith(color: Colors.white70);

    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          const CircularProgressIndicator(color: Colors.white),
          const SizedBox(height: 14),
          Text('جاري تشغيل الكاميرا…', style: style),
          const SizedBox(height: 6),
          Text(
            kIsWeb ? 'اسمح بالكاميرا من نافذة المتصفح إن ظهرت.' : '',
            textAlign: TextAlign.center,
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: Colors.white54),
          ),
        ],
      ),
    );
  }

  // ─── الويب: التقاط صورة ثابتة وقراءة الأرقام منها ─────────────────────

  /// فتح **كاميرا الجهاز** لالتقاط صورة، أو اختيار صورة من ملفات/معرض الجهاز.
  ///
  /// على الويب يُنفَّذ هذا عبر عنصر إدخال ملفات مخصّص (`capture` للكاميرا)
  /// يوفّره المتصفح: الكاميرا تُدار بواسطة نظام الجهاز نفسه، ولا نفتح أي بث
  /// فيديو مباشر داخل الصفحة، فلا شاشة سوداء ولا تعليق.
  Future<void> _pickSnapshot({required bool fromCamera}) async {
    if (_isReadingSnapshot) {
      return;
    }

    if (mounted) {
      setState(() {
        _isReadingSnapshot = true;
        _error = null;
        _failureKind = CameraFailureKind.none;
        _notice = fromCamera
            ? 'التقط صورة واضحة للفاتورة، وسيُقرأ الرقم تلقائياً.'
            : 'اختر صورة واضحة لسعر الطلب أو رقم الطلب.';
      });
    }

    try {
      final XFile? file = await _imagePicker.pickImage(
        source: fromCamera ? ImageSource.camera : ImageSource.gallery,
        imageQuality: 95,
        maxWidth: 2400,
      );

      if (file == null) {
        // ألغى المستخدم الالتقاط — ليست حالة خطأ.
        if (mounted) {
          setState(() => _notice = 'لم يتم اختيار صورة. يمكنك الإدخال يدوياً.');
        }
        return;
      }

      final Uint8List bytes = await file.readAsBytes();
      final ({int width, int height})? dimensions =
          ScanImagePreprocessor.dimensionsOf(bytes);

      if (bytes.isEmpty || dimensions == null) {
        _failSnapshot(
          'تعذّر قراءة الصورة الملتقطة (ملف غير صالح).\n\n'
          'أعد الالتقاط أو أدخل السعر ورقم الطلب يدوياً.',
        );
        return;
      }

      if (!mounted) {
        return;
      }
      setState(() {
        _snapshotBytes = bytes;
        _snapshotSize = Size(
          dimensions.width.toDouble(),
          dimensions.height.toDouble(),
        );
      });

      await _readSnapshotDigits(bytes);
    } on PlatformException catch (error) {
      _failSnapshot(_snapshotFailureMessage(error));
    } catch (_) {
      _failSnapshot(
        'تعذّر فتح الكاميرا أو الوصول إلى الصورة.\n\n'
        'جرّب «من الصور» لاختيار صورة محفوظة، أو أدخل القيم يدوياً.',
      );
    } finally {
      if (mounted) {
        setState(() => _isReadingSnapshot = false);
      }
    }
  }

  /// قراءة الأرقام من الصورة: الباركود أولاً (أسرع وأدق) ثم النص المطبوع.
  Future<void> _readSnapshotDigits(Uint8List bytes) async {
    if (mounted) {
      setState(() {
        _isProcessing = true;
        _notice = 'جاري قراءة الأرقام من الصورة…';
      });
    }

    try {
      // 1) تجهيز الصورة: قصّ منطقة إطار المسح + تكبير + رفع تباين.
      final Rect? region = _scanRegionInImage(_snapshotSize, _previewSize);
      final PreparedScanImage? prepared = ScanImagePreprocessor.prepare(
        bytes,
        region: region,
      );
      final Uint8List readBytes = prepared?.bytes ?? bytes;

      // 2) الباركود/QR: من الصورة الكاملة أولاً ثم من منطقة الإطار.
      final List<String> payloads = <String>[];
      for (final Uint8List candidate in <Uint8List>[bytes, readBytes]) {
        final WebImageBarcodeResult result = await readBarcodesFromImage(
          candidate,
        );
        if (result.status == WebImageBarcodeStatus.ok &&
            result.payloads.isNotEmpty) {
          payloads.addAll(result.payloads);
          break;
        }
      }

      // 3) النص المطبوع داخل منطقة الإطار (لقراءة السعر المكتوب).
      final WebTextOcrResult ocr = await recognizeTextFromImage(readBytes);

      if (!mounted) {
        return;
      }

      // 4) تحويل ما قُرئ إلى سعر و/أو رقم طلب بحسب الخطوة الحالية.
      final LiveScanTarget target = _currentStep == ScanStep.price
          ? LiveScanTarget.price
          : LiveScanTarget.orderNumber;

      LiveScanPayload? parsed;
      for (final String payload in payloads) {
        final LiveScanPayload candidate = LiveScanPayload.parse(
          payload,
          target: target,
        );
        if (!candidate.isEmpty) {
          parsed = candidate;
          break;
        }
      }
      if (parsed == null && (ocr.text ?? '').trim().isNotEmpty) {
        final LiveScanPayload fromText = LiveScanPayload.parse(
          ocr.text,
          target: target,
        );
        if (!fromText.isEmpty) {
          parsed = fromText;
        }
      }

      if (parsed == null || parsed.isEmpty) {
        setState(() {
          _isProcessing = false;
          _notice = _emptyReadNotice(ocr);
        });
        return;
      }

      final OcrResult result = OcrResult(
        rawText: payloads.isNotEmpty
            ? payloads.join(' ')
            : (ocr.text ?? '').trim(),
        amounts: parsed.amount == null
            ? const <double>[]
            : <double>[parsed.amount!],
        orderNumbers: parsed.orderNumber == null
            ? const <String>[]
            : <String>[parsed.orderNumber!],
      );

      setState(() => _isProcessing = false);

      if (_currentStep == ScanStep.price) {
        _handlePriceStepResult(result);
      } else {
        _handleOrderNumberStepResult(result);
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _isProcessing = false;
          _notice = 'تعذّرت قراءة الصورة. جرّب صورة أوضح أو أدخل القيم يدوياً.';
        });
      }
    }
  }

  /// منطقة إطار المسح داخل الصورة الملتقطة (بالبكسل).
  ///
  /// تُستخدم نفس هندسة `BoxFit.cover` المتمركزة المستخدمة في المعاينة، حتى
  /// تُقرأ الأرقام من داخل الإطار فقط.
  Rect? _scanRegionInImage(Size? imageSize, Size? previewSize) {
    if (imageSize == null || previewSize == null) {
      return null;
    }
    if (previewSize.width <= 0 || previewSize.height <= 0) {
      return null;
    }

    final Rect scanBox = Rect.fromCenter(
      center: Offset(previewSize.width / 2, previewSize.height / 2),
      width: scanBoxSize.width,
      height: scanBoxSize.height,
    );

    return ScanGeometry.mapToImage(
      scanBox: scanBox,
      viewSize: previewSize,
      imageSize: imageSize,
    );
  }

  /// إعادة المحاولة: يقرأ الصورة الحالية، أو يفتح الكاميرا إن لم توجد صورة.
  Future<void> _retrySnapshot() async {
    final Uint8List? bytes = _snapshotBytes;
    if (bytes == null || bytes.isEmpty) {
      await _pickSnapshot(fromCamera: true);
      return;
    }

    if (mounted) {
      setState(() {
        _error = null;
        _failureKind = CameraFailureKind.none;
      });
    }
    await _readSnapshotDigits(bytes);
  }

  /// البدء من جديد على الويب: مسح الصورة الحالية والاستعداد لالتقاط أخرى.
  void _resetSnapshot() {
    if (!mounted) {
      return;
    }
    setState(() {
      _snapshotBytes = null;
      _snapshotSize = null;
      _isProcessing = false;
      _isReadingSnapshot = false;
      _error = null;
      _failureKind = CameraFailureKind.none;
      _notice = 'اضغط «التقاط صورة» لفتح كاميرا جهازك.';
    });
  }

  /// رسالة واضحة عندما لا تُقرأ أي قيمة من الصورة.
  String _emptyReadNotice(WebTextOcrResult ocr) {
    switch (ocr.status) {
      case WebTextOcrStatus.offline:
        return 'تعذّر تحميل محرّك قراءة النص (تحقّق من الاتصال بالإنترنت).\n\n'
            'أدخل السعر ورقم الطلب يدوياً.';
      case WebTextOcrStatus.failed:
        return 'لم يُقرأ أي رقم واضح من الصورة.\n\n'
            'جرّب صورة أقرب وأوضح، أو أدخل القيم يدوياً.';
      case WebTextOcrStatus.ok:
        return 'لم يُعثر على سعر أو رقم طلب واضح داخل الإطار.\n\n'
            'وجّه الصورة نحو الرقم بدقة، أو أدخل القيم يدوياً.';
      case WebTextOcrStatus.notApplicable:
        return 'أدخل السعر ورقم الطلب يدوياً.';
    }
  }

  /// رسالة عربية لأخطاء منتقي الصور (رفض إذن الكاميرا مثلاً).
  String _snapshotFailureMessage(PlatformException error) {
    final String code = error.code.toLowerCase();
    if (code.contains('denied') || code.contains('permission')) {
      return 'لم يُسمح باستخدام الكاميرا أو الصور.\n\n'
          'امنح الإذن من إعدادات المتصفح/الجهاز ثم أعد المحاولة، '
          'أو أدخل السعر ورقم الطلب يدوياً.';
    }
    return 'تعذّر فتح الكاميرا أو اختيار الصورة (${error.code}).\n\n'
        'أعد المحاولة أو أدخل القيم يدوياً.';
  }

  /// عرض فشل الالتقاط/المعالجة مع إبقاء الإدخال اليدوي متاحاً.
  void _failSnapshot(String message) {
    if (!mounted) {
      return;
    }
    setState(() {
      _isProcessing = false;
      _isReadingSnapshot = false;
      _failureKind = CameraFailureKind.unknown;
      _error = message;
    });
  }

  /// بطاقة الفشل: رسالة واضحة + أزرار الإصلاح + بديل الإدخال اليدوي.
  Widget _buildFailureCard(String error) {
    final bool isWebPermissionIssue =
        kIsWeb &&
        (_failureKind == CameraFailureKind.permission ||
            _failureKind == CameraFailureKind.insecureContext);
    final bool canOpenSettings = !kIsWeb && _permissionPermanentlyDenied;

    return _ScanMessage(
      icon: _failureKind == CameraFailureKind.insecureContext
          ? Icons.lock_outline_rounded
          : Icons.no_photography_outlined,
      message: error,
      primaryLabel: 'إعادة المحاولة',
      onPrimary: _retrySnapshot,
      secondaryLabel: isWebPermissionIssue
          ? 'كيف أسمح بالكاميرا؟'
          : (canOpenSettings ? 'فتح الإعدادات' : null),
      onSecondary: isWebPermissionIssue
          ? _showCameraPermissionHelp
          : (canOpenSettings ? () => openAppSettings() : null),
      manualLabel: 'الإدخال اليدوي',
      onManual: _exitWithManualEntry,
    );
  }

  Widget _buildBody() {
    final String? error = _error;
    if (error != null) {
      return _buildFailureCard(error);
    }

        // ─── الويب: البث المباشر (Live Stream) + زر التقاط سريع ────────────────
    if (kIsWeb) {
      // الحالة 1: لم يُبدأ بعد → نعرض زر البدء
      if (_waitingForUserStart && _controller == null) {
        return _buildWebStartButton();
      }

      // الحالة 2: جاري التشغيل أو فشل → مؤشّر تحميل
      if (_isInitializing || _controller == null) {
        return _buildLoadingIndicator();
      }

      // الحالة 3: الكاميرا شغّالة → البث المباشر + إطار المسح
      return _buildLiveWebPreview();
    }

    // ─── الأجهزة الأصلية: الكاميرا + قراءة الأرقام (OCR) ────────────────
    if (_isInitializing) {
      return _buildLoadingIndicator();
    }

    final CameraController? controller = _controller;
    if (controller == null || !controller.value.isInitialized) {
      return _buildLoadingIndicator();
    }

    final String? notice = _notice;
    final bool isOrderNumberStep = _currentStep == ScanStep.orderNumber;

    return Stack(
      fit: StackFit.expand,
      children: <Widget>[
        _CameraPreviewBox(controller: controller),

        // إطار المسح والتعتيم مع التعليمات
        ScanBoxOverlay(
          scanBoxSize: scanBoxSize,
          instructions: isOrderNumberStep
              ? 'ضع رقم الطلب أو الفاتورة داخل المربع'
              : 'ضع سعر الطلب داخل المربع',
        ),

        // شريط الخطوات المتتابعة في الأعلى
        Positioned(
          top: 14,
          left: 16,
          right: 16,
          child: _buildStepperHeader(),
        ),

        // علامة النجاح الخضراء عند قراءة الحقل
        if (_stepSucceeded)
          ScanSuccessOverlay(
            checkmarkKey: successKey,
            message: _successMessage,
          ),

        // تنبيه نصي في حال عدم وضوح الرقم
        if (notice != null && !_stepSucceeded)
          Positioned(
            left: 20,
            right: 20,
            bottom: isOrderNumberStep ? 190 : 140,
            child: _ScanHint(text: notice, isWarning: true),
          ),

        // شريط الأزرار والتحكم أسفل الشاشة
        Positioned(
          left: 0,
          right: 0,
          bottom: 24,
          child: _buildBottomControls(),
        ),
      ],
    );
  }

  
  // ─── الويب: بث مباشر + التحليل الفوري ──────────────────────────────────────

  /// ✅ معالجة نتيجة باركود/نص: استخراج السعر ورقم الطلب
  void _handleBarcode({required String raw}) {
    final LiveScanPayload parsed = LiveScanPayload.parse(
      raw,
      target: _currentStep == ScanStep.price
          ? LiveScanTarget.price
          : LiveScanTarget.orderNumber,
    );
    if (parsed.isEmpty) return;

    final OcrResult result = OcrResult(
      rawText: raw,
      amounts: parsed.amount == null ? [] : [parsed.amount!],
      orderNumbers: parsed.orderNumber == null ? [] : [parsed.orderNumber!],
    );

    if (_currentStep == ScanStep.price) {
      _handlePriceStepResult(result);
    } else {
      _handleOrderNumberStepResult(result);
    }
  }


  /// ✅ زر البدء على الويب — يُظهره المستخدم لتفعيد الكاميرا.
  Widget _buildWebStartButton() {
    return Center(
      child: FilledButton.icon(
        key: const ValueKey<String>('camera-permission-button'),
        onPressed: _isInitializing ? null : _startWebCamera,
        icon: const Icon(Icons.camera_alt, size: 24),
        label: const Text(
          'ابدأ المسح بالكاميرا',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        style: FilledButton.styleFrom(
          backgroundColor: AppColors.primary,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
        ),
      ),
    );
  }

  /// ✅ تشغيل الكاميرا على الويب بعد نقرة المستخدم.
  Future<void> _startWebCamera() async {
    setState(() {
      _isInitializing = true;
      _error = null;
      _failureKind = CameraFailureKind.none;
      _permissionPermanentlyDenied = false;
      _waitingForUserStart = false;
    });
    try {
      await _initializeCamera(fromUserGesture: true);
      if (mounted) {
        setState(() => _isInitializing = false);
        _startWebFrameAnalysis();
      }
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _isInitializing = false;
        _error = _webCameraErrorMessage(error);
        _failureKind = CameraFailureKind.permission;
        _waitingForUserStart = true;
      });
    }
  }

  /// ✅ بدء التحليل الفوري للكاميرا — فحص دوري + قراءة باركود
  void _startWebFrameAnalysis() {
    if (_webScanTimer != null) return;
    _webScanTimer = Timer.periodic(const Duration(milliseconds: 1200), (_) {
      if (!mounted ||
          _controller?.value.isInitialized != true ||
          _isProcessing ||
          _stepSucceeded) {
        return;
      }
      _captureAndAnalyze();
    });
  }

  /// رسائل خطأ عربية واضحة للكاميرا على الويب.
  String _webCameraErrorMessage(Object error) {
    final String msg = error.toString();
    if (msg.contains('NotAllowedError') || msg.contains('permission')) {
      return 'تم رفض إذن الكاميرا. تأكد من السماح بالكاميرا في إعدادات المتصفح، ثم أعد المحاولة.';
    }
    if (msg.contains('NotFoundError')) {
      return 'لم يتم العثور على كاميرا في هذا الجهاز.';
    }
    if (msg.contains('OverconstrainedError') ||
        msg.contains('NotReadableError')) {
      return 'الكاميرا مشغولة. أغلق التطبيقات الأخرى ثم أعد المحاولة.';
    }
    return 'تعذّر تشغيل الكاميرا في هذا متصفح. جرّب Chrome أو Safari بإصدار حديث.';
  }


  /// ✅ واجهة البث المباشر على الويب — نفس تجربة Android/iOS الأصلية
  Widget _buildLiveWebPreview() {
    final String? notice = _notice;
    final bool isOrderNumberStep = _currentStep == ScanStep.orderNumber;
    return Stack(
      fit: StackFit.expand,
      children: <Widget>[
        // البث المباشر (CameraController → <video>)
        _CameraPreviewBox(controller: _controller!),

        // إطار المسح نفسه — موحد مع الأصلية تماماً
        ScanBoxOverlay(
          scanBoxSize: scanBoxSize,
          instructions: isOrderNumberStep
              ? 'ضع رقم الطلب أو الباركود داخل المربع'
              : 'ضع سعر الطلب أو الباركود داخل المربع',
        ),

        // شريط الخطوات العلوي
        Positioned(
          top: 14, left: 16, right: 16,
          child: _buildStepperHeader(),
        ),

        // علامة النجاح
        if (_stepSucceeded)
          ScanSuccessOverlay(
            checkmarkKey: successKey,
            message: _successMessage,
          ),

        // التنويهات
        if (notice != null && !_stepSucceeded)
          Positioned(
            left: 20, right: 20,
            bottom: isOrderNumberStep ? 190 : 140,
            child: _ScanHint(text: notice, isWarning: true),
          ),

        // ✅ زر التقاط صورة سريع (Fast Capture) — بديل يدوي فوري
        Positioned(
          left: 0, right: 0, bottom: 24,
          child: _buildFastCaptureButton(),
        ),
      ],
    );
  }

  /// ✅ زر التقاط صورة سريع — يلتقط صورة ويقرأ الباركود/النص منها
  Widget _buildFastCaptureButton() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: FilledButton.icon(
        key: const ValueKey<String>('fast-capture-button'),
        onPressed:
            (_isProcessing || _controller == null) ? null : _captureAndAnalyze,
        icon: _isProcessing
            ? const SizedBox(
                width: 18, height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Icon(Icons.camera_rounded, size: 22),
        label: Text(
          _isProcessing ? 'جاري القراءة...' : 'التقاط صورة سريعة',
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        style: FilledButton.styleFrom(
          backgroundColor: AppColors.primary,
          foregroundColor: Colors.white,
          minimumSize: const Size.fromHeight(56),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
    );
  }

  /// ✅ التقاط صورة واحدة وقراءتها — خيار سريع إذا لم يلتقط البث التلقائي
  Future<void> _captureAndAnalyze() async {
    if (_isProcessing || _controller == null) return;
    if (!mounted) return;
    setState(() => _isProcessing = true);

    try {
      final Uint8List? imageBytes =
          await _controller!.takePicture().then((XFile f) => f.readAsBytes());
      if (imageBytes == null || imageBytes.isEmpty) return;

      final WebImageBarcodeResult result =
          await readBarcodesFromImage(imageBytes);
      if (result.status == WebImageBarcodeStatus.ok &&
          result.payloads.isNotEmpty &&
          mounted) {
        for (final String payload in result.payloads) {
          _handleBarcode(raw: payload);
          if (_stepSucceeded) break;
        }
      }
    } catch (e) {
      // لا شيء — نعيد المحاولة في المرة الكاشرة
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }


  /// شريط مؤشر الخطوات التتابعية في أعلى شاشة الكاميرا.
  Widget _buildStepperHeader() {
    final bool isPriceStep = _currentStep == ScanStep.price;
    final bool hasPrice = _capturedPrice != null;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.75),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white24),
      ),
      child: Row(
        children: <Widget>[
          // الخطوة 1: سعر الطلب
          Expanded(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: isPriceStep
                    ? AppColors.primary.withValues(alpha: 0.4)
                    : (hasPrice
                        ? AppColors.success.withValues(alpha: 0.25)
                        : Colors.white10),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: isPriceStep
                      ? AppColors.primary
                      : (hasPrice ? AppColors.success : Colors.transparent),
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: <Widget>[
                  Icon(
                    hasPrice ? Icons.check_circle : Icons.payments_outlined,
                    size: 15,
                    color: hasPrice ? AppColors.success : Colors.white,
                  ),
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text(
                      hasPrice
                          ? formatAmount(_capturedPrice!)
                          : '١. سعر الطلب',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight:
                            isPriceStep || hasPrice ? FontWeight.bold : FontWeight.normal,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 8),
            child: Icon(Icons.arrow_back_ios_new, size: 12, color: Colors.white54),
          ),
          // الخطوة 2: رقم الطلب
          Expanded(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: !isPriceStep
                    ? AppColors.accent.withValues(alpha: 0.35)
                    : Colors.white10,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: !isPriceStep ? AppColors.accent : Colors.transparent,
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: <Widget>[
                  Icon(
                    Icons.tag_rounded,
                    size: 15,
                    color: !isPriceStep ? AppColors.accent : Colors.white70,
                  ),
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text(
                      _capturedOrderNumber != null
                          ? '#$_capturedOrderNumber'
                          : '٢. رقم الطلب',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: !isPriceStep ? FontWeight.bold : FontWeight.normal,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// أدوات التحكم والالتقاط أسفل الشاشة.
  Widget _buildBottomControls() {
    final bool isOrderNumberStep = _currentStep == ScanStep.orderNumber;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        // عند خطوة رقم الطلب: زر تخطي ورقم السعر المحفوظ
        if (isOrderNumberStep) ...<Widget>[
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: <Widget>[
                TextButton.icon(
                  onPressed: _rescanPrice,
                  style: TextButton.styleFrom(
                    foregroundColor: Colors.white70,
                    backgroundColor: Colors.black45,
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  ),
                  icon: const Icon(Icons.undo_rounded, size: 16),
                  label: const Text('إعادة مسح السعر', style: TextStyle(fontSize: 12)),
                ),
                FilledButton.icon(
                  key: const ValueKey<String>('skip-order-number-button'),
                  onPressed: () => _finishFlow(),
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  icon: const Icon(Icons.check_rounded, size: 18),
                  label: const Text('تخطي والاعتماد الآن', style: TextStyle(fontSize: 12)),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
        ],

        // زر التصوير المركزي مع حلقة التحميل (الأجهزة الأصلية).
        _CaptureBar(
          isProcessing: _isProcessing,
          onCapture: _captureAndRecognize,
          stepLabel: isOrderNumberStep ? 'التقاط رقم الطلب' : 'التقاط السعر',
        ),
      ],
    );
  }
}

/// معاينة الكاميرا ممتدة على كامل الشاشة مع الحفاظ على نسبة الصورة.
class _CameraPreviewBox extends StatelessWidget {
  const _CameraPreviewBox({required this.controller});

  final CameraController controller;

  @override
  Widget build(BuildContext context) {
    final Size? previewSize = controller.value.previewSize;
    if (previewSize == null) {
      return const ColoredBox(color: Colors.black);
    }

    // مكتبة camera تُرجع أبعاد المعاينة بالوضع الأفقي، فنبدّل العرض والارتفاع
    // لتظهر المعاينة بالوضع الرأسي الصحيح على الجوال.
    final double videoWidth = previewSize.height;
    final double videoHeight = previewSize.width;

    if (!kIsWeb) {
      return ClipRect(
        child: OverflowBox(
          alignment: Alignment.center,
          child: FittedBox(
            fit: BoxFit.cover,
            child: SizedBox(
              width: videoWidth,
              height: videoHeight,
              child: CameraPreview(controller),
            ),
          ),
        ),
      );
    }

    // ─── الويب ──────────────────────────────────────────────────────────
    // عنصر <video> في camera_web هو Platform View داخل الصفحة، وتمريره عبر
    // FittedBox/Transform يُنتج معاينة سوداء على بعض المتصفحات (Safari في
    // iOS خصوصاً). لذلك نحسب مقاس «الغلاف» (BoxFit.cover) يدوياً ونمرّره
    // كحجم فعلي للعنصر، فيبقى الفيديو ممتداً بلا أي تحويل CSS.
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final double viewWidth = constraints.maxWidth;
        final double viewHeight = constraints.maxHeight;
        if (viewWidth <= 0 || viewHeight <= 0) {
          return const ColoredBox(color: Colors.black);
        }

        final double scale = math.max(
          viewWidth / videoWidth,
          viewHeight / videoHeight,
        );

        return ClipRect(
          child: Center(
            child: SizedBox(
              width: videoWidth * scale,
              height: videoHeight * scale,
              child: CameraPreview(controller),
            ),
          ),
        );
      },
    );
  }
}

/// شريط نصي إرشادي فوق الكاميرا (تنبيه أو إرشاد).
class _ScanHint extends StatelessWidget {
  const _ScanHint({required this.text, this.isWarning = false});

  final String text;
  final bool isWarning;

  @override
  Widget build(BuildContext context) {
    final TextStyle? style = Theme.of(context).textTheme.bodyMedium?.copyWith(
      color: Colors.white,
      height: 1.5,
      fontSize: 13,
    );

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isWarning
            ? AppColors.accent.withValues(alpha: 0.92)
            : Colors.black54,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: <Widget>[
          Icon(
            isWarning ? Icons.info_outline : Icons.center_focus_weak,
            size: 18,
            color: Colors.white,
          ),
          const SizedBox(width: 8),
          Expanded(child: Text(text, style: style)),
        ],
      ),
    );
  }
}

/// زر التصوير أسفل الشاشة مع مؤشر أثناء التعرف على النص.
class _CaptureBar extends StatelessWidget {
  const _CaptureBar({
    required this.isProcessing,
    required this.onCapture,
    this.stepLabel = '',
  });

  final bool isProcessing;
  final VoidCallback onCapture;
  final String stepLabel;

  @override
  Widget build(BuildContext context) {
    final TextStyle? style = Theme.of(
      context,
    ).textTheme.bodyMedium?.copyWith(color: Colors.white);

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        if (isProcessing) ...<Widget>[
          Text('جاري التعرف على الأرقام…', style: style),
          const SizedBox(height: 10),
        ] else if (stepLabel.isNotEmpty) ...<Widget>[
          Text(
            stepLabel,
            style: const TextStyle(
              color: Colors.white70,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
        ],
        Center(
          child: SizedBox(
            width: 76,
            height: 76,
            child: Material(
              color: Colors.white24,
              shape: const CircleBorder(),
              child: InkWell(
                key: const ValueKey<String>('capture-button'),
                customBorder: const CircleBorder(),
                onTap: isProcessing ? null : onCapture,
                child: Center(
                  child: isProcessing
                      ? const SizedBox(
                          width: 30,
                          height: 30,
                          child: CircularProgressIndicator(
                            strokeWidth: 3,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(
                          Icons.photo_camera,
                          color: Colors.white,
                          size: 34,
                        ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// مؤشر «جاري قراءة الأرقام» أعلى شاشة الالتقاط على الويب.
class _SnapshotReadingChip extends StatelessWidget {
  const _SnapshotReadingChip();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.65),
        borderRadius: BorderRadius.circular(30),
      ),
      child: const Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          SizedBox(
            width: 14,
            height: 14,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: Colors.white,
            ),
          ),
          SizedBox(width: 10),
          Text(
            'جاري قراءة الأرقام…',
            style: TextStyle(color: Colors.white, fontSize: 12),
          ),
        ],
      ),
    );
  }
}

/// رسالة خطأ (أو مشكلة إذن) مع أزرار الإجراءات.
class _ScanMessage extends StatelessWidget {
  const _ScanMessage({
    required this.icon,
    required this.message,
    required this.primaryLabel,
    required this.onPrimary,
    this.secondaryLabel,
    this.onSecondary,
    this.manualLabel,
    this.onManual,
  });

  final IconData icon;
  final String message;
  final String primaryLabel;
  final VoidCallback onPrimary;
  final String? secondaryLabel;
  final VoidCallback? onSecondary;

  /// زر احتياطي للخروج إلى الإدخال اليدوي (يظهر دائماً عند توفره).
  final String? manualLabel;
  final VoidCallback? onManual;

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    final String? secondary = secondaryLabel;
    final String? manual = manualLabel;

    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(icon, size: 56, color: Colors.white54),
            const SizedBox(height: 18),
            Text(
              message,
              textAlign: TextAlign.center,
              style: text.bodyMedium?.copyWith(
                color: Colors.white70,
                height: 1.7,
              ),
            ),
            const SizedBox(height: 22),
            FilledButton.icon(
              onPressed: onPrimary,
              icon: const Icon(Icons.refresh, size: 18),
              label: Text(primaryLabel),
            ),
            if (secondary != null) ...<Widget>[
              const SizedBox(height: 6),
              TextButton(
                onPressed: onSecondary,
                child: Text(
                  secondary,
                  style: text.bodyMedium?.copyWith(color: Colors.white70),
                ),
              ),
            ],
            if (manual != null) ...<Widget>[
              const SizedBox(height: 6),
              TextButton.icon(
                key: const ValueKey<String>('camera-manual-entry-button'),
                onPressed: onManual,
                icon: const Icon(
                  Icons.keyboard_alt_outlined,
                  size: 18,
                  color: Colors.white54,
                ),
                label: Text(
                  manual,
                  style: text.bodyMedium?.copyWith(color: Colors.white54),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
