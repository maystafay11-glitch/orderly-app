import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:orderly_app/services/license_service.dart';
import 'package:orderly_app/theme/app_theme.dart';

/// شاشة تفعيل الموزع — تظهر مرة واحدة فقط على كل جهاز جديد.
///
/// تطلب من المستخدم إدخال كلمة مرور الموزع (orderly77).
/// عند الإدخال الصحيح، يُحفظ الترخيص محلياً وتستدعي [onActivated].
class ActivationScreen extends StatefulWidget {
  const ActivationScreen({super.key, required this.onActivated});

  /// يُستدعى بعد نجاح التفعيل لإعادة توجيه التطبيق.
  final VoidCallback onActivated;

  @override
  State<ActivationScreen> createState() => _ActivationScreenState();
}

class _ActivationScreenState extends State<ActivationScreen>
    with SingleTickerProviderStateMixin {
  final TextEditingController _pwCtrl = TextEditingController();
  final FocusNode _focusNode = FocusNode();

  bool _obscure = true;
  bool _isLoading = false;
  String? _errorMessage;
  bool _activated = false;

  late final AnimationController _shakeCtrl;
  late final Animation<double> _shakeAnim;

  @override
  void initState() {
    super.initState();
    _shakeCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 450),
    );
    _shakeAnim = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(parent: _shakeCtrl, curve: Curves.elasticIn),
    );
  }

  @override
  void dispose() {
    _pwCtrl.dispose();
    _focusNode.dispose();
    _shakeCtrl.dispose();
    super.dispose();
  }

  Future<void> _tryActivate() async {
    final String password = _pwCtrl.text.trim();
    if (password.isEmpty) {
      setState(() => _errorMessage = 'يرجى إدخال كلمة مرور التفعيل');
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    final bool success = await LicenseService.activate(password);

    if (!mounted) return;

    if (success) {
      HapticFeedback.heavyImpact();
      setState(() {
        _activated = true;
        _isLoading = false;
      });
      // انتظر ثانية واحدة لعرض رسالة النجاح ثم أكمل
      await Future<void>.delayed(const Duration(milliseconds: 1200));
      if (mounted) {
        widget.onActivated();
      }
    } else {
      HapticFeedback.vibrate();
      await _shakeCtrl.forward(from: 0);
      if (mounted) {
        setState(() {
          _isLoading = false;
          _errorMessage = 'كلمة المرور غير صحيحة. يرجى التواصل مع الموزع.';
          _pwCtrl.clear();
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: Stack(
        children: <Widget>[
          // ── خلفية هندسية بسيطة ──────────────────────────────────
          CustomPaint(
            painter: _GeometricBgPainter(),
            child: const SizedBox.expand(),
          ),

          // ── المحتوى ────────────────────────────────────────────
          SafeArea(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 28),
                child: AnimatedBuilder(
                  animation: _shakeAnim,
                  builder: (BuildContext context, Widget? child) {
                    final double shake = math.sin(_shakeAnim.value * math.pi * 6) * 10;
                    return Transform.translate(
                      offset: Offset(shake, 0),
                      child: child,
                    );
                  },
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: <Widget>[
                      const SizedBox(height: 24),

                      // ── شعار التطبيق ──────────────────────────
                      Container(
                        width: 80,
                        height: 80,
                        decoration: BoxDecoration(
                          gradient: AppColors.primaryGradient,
                          borderRadius: BorderRadius.circular(24),
                          boxShadow: <BoxShadow>[
                            BoxShadow(
                              color: AppColors.primary.withValues(alpha: 0.4),
                              blurRadius: 24,
                              spreadRadius: 4,
                            ),
                          ],
                        ),
                        child: const Icon(
                          Icons.lock_person_rounded,
                          color: Colors.white,
                          size: 40,
                        ),
                      ),
                      const SizedBox(height: 24),

                      // ── العنوان ──────────────────────────────
                      const Text(
                        'تفعيل Orderly',
                        style: TextStyle(
                          fontSize: 26,
                          fontWeight: FontWeight.w900,
                          color: AppColors.textPrimary,
                          letterSpacing: 0.5,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'هذا التطبيق محمي بترخيص الموزع.\n'
                        'يرجى إدخال كلمة مرور التفعيل للمتابعة.',
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontSize: 13,
                          color: AppColors.textSecondary,
                          height: 1.6,
                        ),
                      ),
                      const SizedBox(height: 32),

                      // ── حقل كلمة المرور ──────────────────────
                      Container(
                        decoration: BoxDecoration(
                          color: AppColors.surface,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: _errorMessage != null
                                ? AppColors.danger
                                : AppColors.borderLight,
                          ),
                          boxShadow: <BoxShadow>[
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.2),
                              blurRadius: 12,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        child: TextField(
                          key: const ValueKey<String>('activation-password-field'),
                          controller: _pwCtrl,
                          focusNode: _focusNode,
                          obscureText: _obscure,
                          keyboardType: TextInputType.visiblePassword,
                          textInputAction: TextInputAction.done,
                          onSubmitted: (_) => _tryActivate(),
                          style: const TextStyle(
                            color: AppColors.textPrimary,
                            fontSize: 16,
                            letterSpacing: 2,
                          ),
                          decoration: InputDecoration(
                            hintText: 'كلمة مرور التفعيل',
                            hintStyle: const TextStyle(
                              color: AppColors.textMuted,
                              letterSpacing: 0,
                            ),
                            prefixIcon: const Icon(
                              Icons.vpn_key_rounded,
                              color: AppColors.primary,
                            ),
                            suffixIcon: IconButton(
                              icon: Icon(
                                _obscure
                                    ? Icons.visibility_outlined
                                    : Icons.visibility_off_outlined,
                                color: AppColors.textSecondary,
                              ),
                              onPressed: () =>
                                  setState(() => _obscure = !_obscure),
                            ),
                            border: InputBorder.none,
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 16,
                            ),
                          ),
                        ),
                      ),

                      // ── رسالة الخطأ ───────────────────────────
                      AnimatedSize(
                        duration: const Duration(milliseconds: 250),
                        child: _errorMessage != null
                            ? Padding(
                                padding: const EdgeInsets.only(top: 10),
                                child: Row(
                                  children: <Widget>[
                                    const Icon(
                                      Icons.error_outline_rounded,
                                      color: AppColors.danger,
                                      size: 16,
                                    ),
                                    const SizedBox(width: 6),
                                    Expanded(
                                      child: Text(
                                        _errorMessage!,
                                        style: const TextStyle(
                                          color: AppColors.dangerLight,
                                          fontSize: 12,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              )
                            : const SizedBox.shrink(),
                      ),

                      const SizedBox(height: 24),

                      // ── زر التفعيل ───────────────────────────
                      AnimatedSwitcher(
                        duration: const Duration(milliseconds: 300),
                        child: _activated
                            ? _SuccessBadge(key: const ValueKey<String>('success'))
                            : SizedBox(
                                key: const ValueKey<String>('activate-btn'),
                                width: double.infinity,
                                height: 54,
                                child: DecoratedBox(
                                  decoration: BoxDecoration(
                                    gradient: AppColors.primaryGradient,
                                    borderRadius: BorderRadius.circular(16),
                                    boxShadow: <BoxShadow>[
                                      BoxShadow(
                                        color: AppColors.primary
                                            .withValues(alpha: 0.35),
                                        blurRadius: 16,
                                        offset: const Offset(0, 6),
                                      ),
                                    ],
                                  ),
                                  child: Material(
                                    color: Colors.transparent,
                                    borderRadius: BorderRadius.circular(16),
                                    child: InkWell(
                                      key: const ValueKey<String>(
                                          'activation-submit-btn'),
                                      onTap: _isLoading ? null : _tryActivate,
                                      borderRadius: BorderRadius.circular(16),
                                      child: Center(
                                        child: _isLoading
                                            ? const SizedBox(
                                                width: 24,
                                                height: 24,
                                                child:
                                                    CircularProgressIndicator(
                                                  color: Colors.white,
                                                  strokeWidth: 2.5,
                                                ),
                                              )
                                            : const Row(
                                                mainAxisAlignment:
                                                    MainAxisAlignment.center,
                                                children: <Widget>[
                                                  Icon(
                                                    Icons.lock_open_rounded,
                                                    color: Colors.white,
                                                    size: 20,
                                                  ),
                                                  SizedBox(width: 10),
                                                  Text(
                                                    'تفعيل التطبيق',
                                                    style: TextStyle(
                                                      color: Colors.white,
                                                      fontWeight:
                                                          FontWeight.w700,
                                                      fontSize: 16,
                                                    ),
                                                  ),
                                                ],
                                              ),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                      ),

                      const SizedBox(height: 32),

                      // ── تذييل ────────────────────────────────
                      const Text(
                        'Orderly v1.0 • نظام إدارة التوصيل\nللتواصل مع الموزع الرجاء الاتصال',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 11,
                          color: AppColors.textMuted,
                          height: 1.6,
                        ),
                      ),
                      const SizedBox(height: 24),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── بادج النجاح ─────────────────────────────────────────────────────────────
class _SuccessBadge extends StatelessWidget {
  const _SuccessBadge({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 54,
      decoration: BoxDecoration(
        color: AppColors.success.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.success.withValues(alpha: 0.4)),
      ),
      child: const Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: <Widget>[
          Icon(Icons.verified_rounded, color: AppColors.success, size: 22),
          SizedBox(width: 10),
          Text(
            'تم التفعيل بنجاح! جاري الفتح...',
            style: TextStyle(
              color: AppColors.successLight,
              fontWeight: FontWeight.w700,
              fontSize: 15,
            ),
          ),
        ],
      ),
    );
  }
}

// ── رسام الخلفية الهندسية ───────────────────────────────────────────────────
class _GeometricBgPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final Paint paint = Paint()..style = PaintingStyle.stroke;

    // دوائر كبيرة شفافة في الزوايا
    paint
      ..color = AppColors.primary.withValues(alpha: 0.06)
      ..strokeWidth = 80;
    canvas.drawCircle(Offset(0, size.height * 0.15), 180, paint);

    paint
      ..color = AppColors.accent.withValues(alpha: 0.05)
      ..strokeWidth = 60;
    canvas.drawCircle(
        Offset(size.width, size.height * 0.75), 160, paint);

    // خطوط قطرية خفيفة
    paint
      ..color = AppColors.primary.withValues(alpha: 0.04)
      ..strokeWidth = 1;
    for (int i = 0; i < 8; i++) {
      final double x = size.width * i / 7;
      canvas.drawLine(Offset(x, 0), Offset(x - 80, size.height), paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
