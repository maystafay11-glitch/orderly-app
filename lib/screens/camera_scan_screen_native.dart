import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

// permission_handler غير مدعوم على الويب — نستورده شرطياً
import 'package:orderly_app/screens/_permission_stub.dart'
    if (dart.library.io) 'package:permission_handler/permission_handler.dart';

import 'package:orderly_app/services/ocr_service.dart';
import 'package:orderly_app/theme/app_theme.dart';
import 'package:orderly_app/utils/formatters.dart';
import 'package:orderly_app/utils/jpeg_info.dart';
import 'package:orderly_app/utils/scan_geometry.dart';
import 'package:orderly_app/widgets/scan_overlay.dart';

/// خطوات الالتقاط المتتابع (Continuous Scan Flow):
/// يبدأ بمسح سعر الطلب، ثم ينتقل تلقائياً ضمن نفس جلسة الكاميرا لمسح رقم الطلب.
enum ScanStep {
  /// الخطوة الأولى: توجيه الكاميرا نحو سعر الطلب.
  price,

  /// الخطوة الثانية: توجيه الكاميرا نحو رقم الطلب أو الفاتورة.
  orderNumber,
}

/// شاشة المسح بالكاميرا (OCR) مع الالتقاط المتتابع السريع (Continuous Scan Flow).
///
/// تعمل بشكل متواصل دون إغلاق وفتح الكاميرا يدوياً بين الحقول:
/// 1. يبدأ بمسح **سعر الطلب**.
/// 2. فور التعرف عليه وظهور علامة الصح (✅)، ينتقل تلقائياً وفورياً إلى مربع
///    **رقم الطلب** ضمن نفس جلسة الكاميرا النشطة.
/// 3. يدعم كشف السعر ورقم الطلب معاً في لقطة واحدة إن وُجدا في الفاتورة.
/// 4. يتيح زر «تخطي والاعتماد» إن رغب الكاشير في الاكتفاء بالسعر فقط دون رقم طلب.
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
  bool _isInitializing = true;
  bool _isProcessing = false;
  bool _isTorchOn = false;
  bool _permissionPermanentlyDenied = false;
  String? _error;
  String? _notice;

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
    _initializeCamera();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _controller?.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
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

  /// طلب إذن الكاميرا ثم تشغيل الكاميرا الخلفية.
  Future<void> _initializeCamera() async {
    if (mounted) {
      setState(() {
        _isInitializing = true;
        _error = null;
        _notice = null;
      });
    }

    try {
      final PermissionStatus status = await Permission.camera.request();
      if (!status.isGranted) {
        if (!mounted) {
          return;
        }
        setState(() {
          _isInitializing = false;
          _permissionPermanentlyDenied = status.isPermanentlyDenied;
          _error = status.isPermanentlyDenied
              ? 'تم رفض إذن الكاميرا نهائياً. افتح إعدادات التطبيق وامنح '
                    'إذن الكاميرا ثم أعد المحاولة.'
              : 'لا يمكن المسح بالكاميرا دون السماح باستخدام الكاميرا.';
        });
        return;
      }

      final List<CameraDescription> cameras = await availableCameras();
      if (cameras.isEmpty) {
        if (!mounted) {
          return;
        }
        setState(() {
          _isInitializing = false;
          _error = 'لم يتم العثور على كاميرا في هذا الجهاز.';
        });
        return;
      }

      final CameraDescription description = cameras.firstWhere(
        (CameraDescription camera) =>
            camera.lensDirection == CameraLensDirection.back,
        orElse: () => cameras.first,
      );

      final CameraController controller = CameraController(
        description,
        ResolutionPreset.high,
        enableAudio: false,
      );
      await controller.initialize();

      if (!mounted) {
        await controller.dispose();
        return;
      }

      setState(() {
        _controller = controller;
        _isInitializing = false;
      });
    } on CameraException catch (exception) {
      if (!mounted) {
        return;
      }
      setState(() {
        _isInitializing = false;
        _error = 'تعذّر تشغيل الكاميرا (${exception.code}).';
      });
    } catch (_) {
      if (!mounted) {
        return;
      }
      setState(() {
        _isInitializing = false;
        _error = 'حدث خطأ غير متوقع أثناء تشغيل الكاميرا.';
      });
    }
  }

  /// تبديل الفلاش لتسهيل القراءة في الإضاءة الخافتة.
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
          IconButton(
            onPressed: _controller == null ? null : _toggleTorch,
            tooltip: 'الفلاش',
            icon: Icon(_isTorchOn ? Icons.flash_on : Icons.flash_off),
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_isInitializing) {
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
          ],
        ),
      );
    }

    final String? error = _error;
    if (error != null) {
      return _ScanMessage(
        icon: Icons.no_photography_outlined,
        message: error,
        primaryLabel: 'إعادة المحاولة',
        onPrimary: _initializeCamera,
        secondaryLabel: _permissionPermanentlyDenied ? 'فتح الإعدادات' : null,
        onSecondary: _permissionPermanentlyDenied ? () => openAppSettings() : null,
      );
    }

    final CameraController? controller = _controller;
    if (controller == null || !controller.value.isInitialized) {
      return const Center(
        child: CircularProgressIndicator(color: Colors.white),
      );
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

        // زر التصوير المركزي مع حلقة التحميل
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

    return ClipRect(
      child: OverflowBox(
        alignment: Alignment.center,
        child: FittedBox(
          fit: BoxFit.cover,
          child: SizedBox(
            width: previewSize.height,
            height: previewSize.width,
            child: CameraPreview(controller),
          ),
        ),
      ),
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

/// رسالة خطأ (أو مشكلة إذن) مع أزرار الإجراءات.
class _ScanMessage extends StatelessWidget {
  const _ScanMessage({
    required this.icon,
    required this.message,
    required this.primaryLabel,
    required this.onPrimary,
    this.secondaryLabel,
    this.onSecondary,
  });

  final IconData icon;
  final String message;
  final String primaryLabel;
  final VoidCallback onPrimary;
  final String? secondaryLabel;
  final VoidCallback? onSecondary;

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    final String? secondary = secondaryLabel;

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
          ],
        ),
      ),
    );
  }
}
