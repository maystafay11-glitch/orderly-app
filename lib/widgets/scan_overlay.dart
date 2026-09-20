import 'package:flutter/material.dart';

/// تعتيم شبه شفاف يُظلل باقي الشاشة ويُبرز نافذة مسح شفافة في المنتصف.
///
/// [scanBoxSize] حجم النافذة بالبكسل (العرض × الارتفاع).
/// يُستَخدم داخل شاشة الكاميرا فوق معاينة الفيديو.
class ScanBoxOverlay extends StatelessWidget {
  const ScanBoxOverlay({
    super.key,
    required this.scanBoxSize,
    this.instructions = '',
  });

  /// حجم مربع المسح في البكسل.
  final Size scanBoxSize;

  /// نص إرشادي يوضح الواجب للمستخدم.
  final String instructions;

  static const double _kCornerLength = 26;
  static const double _kCornerStroke = 3.5;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Center(
        child: Container(
          width: scanBoxSize.width,
          height: scanBoxSize.height,
          decoration: BoxDecoration(
            color: Colors.transparent,
            border: Border.all(color: Colors.transparent, width: 0),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Stack(
            children: <Widget>[
              // التعتيم حول النافذة باستخدام خلفية شبه شفافة.
              Positioned.fill(
                child: IgnorePointer(
                  child: CustomPaint(
                    painter: _DimmerPainter(
                      windowRect: Rect.fromLTWH(
                        0,
                        0,
                        scanBoxSize.width,
                        scanBoxSize.height,
                      ),
                      cornerRadius: 20,
                    ),
                  ),
                ),
              ),
              // أقواس الزوايا لتوجيه التركيز.
              Positioned.fill(
                child: CustomPaint(
                  painter: _CornerPainter(
                    cornerLength: _kCornerLength,
                    strokeWidth: _kCornerStroke,
                    cornerRadius: 20,
                  ),
                ),
              ),
              if (instructions.isNotEmpty)
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: -40,
                  child: Center(
                    child: Text(
                      instructions,
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Colors.white,
                        height: 1.5,
                        fontSize: 13,
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

/// يُظلّل (يداّن) كل الشاشة باستثناء نافذة [windowRect] المركزية.
class _DimmerPainter extends CustomPainter {
  _DimmerPainter({required this.windowRect, required this.cornerRadius});

  final Rect windowRect;
  final double cornerRadius;

  @override
  void paint(Canvas canvas, Size size) {
    final Paint dimPaint = Paint()..color = Colors.black54;

    final Path path = Path()
      ..addRect(Rect.fromLTWH(0, 0, size.width, size.height));
    final RRect windowRRect = RRect.fromRectAndRadius(
      windowRect,
      Radius.circular(cornerRadius),
    );
    path.addRRect(windowRRect);
    path.fillType = PathFillType.evenOdd;

    canvas.drawPath(path, dimPaint);
  }

  @override
  bool shouldRepaint(covariant _DimmerPainter old) =>
      old.windowRect != windowRect || old.cornerRadius != cornerRadius;
}

/// يرسم أربع أقواس زوايا بيضاء داخل مربع المسح لتوجيه الكاميرا.
class _CornerPainter extends CustomPainter {
  _CornerPainter({
    required this.cornerLength,
    required this.strokeWidth,
    required this.cornerRadius,
  });

  final double cornerLength;
  final double strokeWidth;
  final double cornerRadius;

  @override
  void paint(Canvas canvas, Size size) {
    final Paint bracketPaint = Paint()
      ..color = Colors.white70
      ..strokeWidth = strokeWidth
      ..style = PaintingStyle.stroke;

    final double left = 0.0;
    final double top = 0.0;
    final double right = size.width;
    final double bottom = size.height;

    void drawOuterBracket(Offset corner, bool isTop, bool isLeft) {
      final double dx = corner.dx;
      final double dy = corner.dy;
      canvas.drawLine(
        Offset(isLeft ? dx : dx - cornerLength, dy),
        Offset(isLeft ? dx + cornerLength : dx, dy),
        bracketPaint,
      );
      canvas.drawLine(
        Offset(dx, isTop ? dy : dy - cornerLength),
        Offset(dx, isTop ? dy + cornerLength : dy),
        bracketPaint,
      );
    }

    drawOuterBracket(Offset(left, top), true, true);
    drawOuterBracket(Offset(right, top), true, false);
    drawOuterBracket(Offset(left, bottom), false, true);
    drawOuterBracket(Offset(right, bottom), false, false);
  }

  @override
  bool shouldRepaint(covariant _CornerPainter old) =>
      old.cornerLength != cornerLength ||
      old.strokeWidth != strokeWidth ||
      old.cornerRadius != cornerRadius;
}

/// إشارة نجاح (✅) متحركة تظهر فوق الكاميرا بعد قراءة رقم ناجحة.
class ScanSuccessOverlay extends StatelessWidget {
  const ScanSuccessOverlay({
    super.key,
    required this.checkmarkKey,
    required this.message,
  });

  /// مفتاح اختبار للكشف عن الأيقونة في الاختبارات.
  final Key checkmarkKey;

  /// رسالة توضيحية بجانب علامة النجاح.
  final String message;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(
              Icons.check_circle,
              key: checkmarkKey,
              size: 96,
              color: Colors.greenAccent,
              shadows: <BoxShadow>[
                BoxShadow(
                  color: Colors.black45,
                  blurRadius: 12,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              message,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                color: Colors.white,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
