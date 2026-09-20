import 'dart:typed_data';
import 'dart:ui' show Size;

/// معلومات صورة JPEG تُقرأ من رأس الملف فقط (بدون فك الصورة أو تحميلها كاملة).
///
/// نحتاج هذه المعلومات قبل تمرير الصورة إلى ML Kit لأن الحدود (bounding boxes)
/// التي يُرجعها التعرف على النصوص تكون في فضاء الصورة **بعد** تطبيق اتجاه EXIF،
/// فنحتاج الأبعاد الصحيحة لتحويل مربع المسح المعروض إلى منطقة داخل الصورة
/// (انظر `lib/utils/scan_geometry.dart`).
class JpegInfo {
  const JpegInfo({
    required this.width,
    required this.height,
    this.orientation = normalOrientation,
  });

  /// اتجاه EXIF الطبيعي (بدون تدوير).
  static const int normalOrientation = 1;

  /// العرض المسجَّل داخل الملف بالبكسل.
  final int width;

  /// الارتفاع المسجَّل داخل الملف بالبكسل.
  final int height;

  /// اتجاه EXIF (من 1 إلى 8)، والقيمة [normalOrientation] تعني بلا تدوير.
  final int orientation;

  /// هل يبدّل اتجاه EXIF المحورين (تدوير 90° أو 270°)؟
  bool get swapsAxes => orientation >= 5 && orientation <= 8;

  /// هل الأبعاد صالحة للاستخدام؟
  bool get isValid => width > 0 && height > 0;

  /// الأبعاد كما تظهر للمستخدم بعد تطبيق اتجاه EXIF.
  Size get displaySize => swapsAxes
      ? Size(height.toDouble(), width.toDouble())
      : Size(width.toDouble(), height.toDouble());

  /// قراءة رأس JPEG من [bytes] (يكفي تمرير أول جزء من الملف).
  ///
  /// تُرجع `null` إذا لم تكن البيانات صورة JPEG صالحة أو لم يُعثر على أبعاد.
  static JpegInfo? parse(Uint8List bytes) {
    if (bytes.length < 4 || bytes[0] != 0xFF || bytes[1] != 0xD8) {
      return null;
    }

    int width = 0;
    int height = 0;
    int orientation = normalOrientation;
    int offset = 2;

    while (offset + 3 < bytes.length) {
      if (bytes[offset] != 0xFF) {
        // بايت غير متوقع: نتقدّم خطوة واحدة للبحث عن بداية وسم جديد.
        offset++;
        continue;
      }

      final int marker = bytes[offset + 1];
      offset += 2;

      // حشو أو بداية صورة جديدة: لا تحمل طولاً.
      if (marker == 0xFF || marker == 0x00) {
        continue;
      }
      // نهاية الرأس: بعدها تبدأ بيانات الضغط.
      if (marker == _sosMarker) {
        break;
      }
      // وسوم بلا حقل طول (RST/TEM).
      if (marker >= 0xD0 && marker <= 0xD9) {
        continue;
      }

      final int length = (bytes[offset] << 8) | bytes[offset + 1];
      if (length < 2) {
        break;
      }
      final int segmentStart = offset + 2;
      final int segmentEnd = offset + length;
      if (segmentEnd > bytes.length) {
        break;
      }

      if (marker == _app1Marker) {
        orientation =
            _readExifOrientation(bytes, segmentStart, segmentEnd) ?? orientation;
      } else if (_sofMarkers.contains(marker) && segmentStart + 5 <= segmentEnd) {
        height = (bytes[segmentStart + 1] << 8) | bytes[segmentStart + 2];
        width = (bytes[segmentStart + 3] << 8) | bytes[segmentStart + 4];
      }

      offset = segmentEnd;
    }

    final JpegInfo info = JpegInfo(
      width: width,
      height: height,
      orientation: orientation,
    );
    return info.isValid ? info : null;
  }

  /// قراءة وسم اتجاه EXIF (0x0112) من مقطع APP1 الواقع بين [start] و[end].
  static int? _readExifOrientation(Uint8List bytes, int start, int end) {
    const int tagOrientation = 0x0112;
    // توقيع Exif: "Exif\0\0" ثم رأس TIFF.
    if (start + 14 > end) {
      return null;
    }
    if (bytes[start] != 0x45 ||
        bytes[start + 1] != 0x78 ||
        bytes[start + 2] != 0x69 ||
        bytes[start + 3] != 0x66) {
      return null;
    }

    final int tiff = start + 6;
    final bool littleEndian;
    if (bytes[tiff] == 0x49 && bytes[tiff + 1] == 0x49) {
      littleEndian = true;
    } else if (bytes[tiff] == 0x4D && bytes[tiff + 1] == 0x4D) {
      littleEndian = false;
    } else {
      return null;
    }

    int read16(int index) => littleEndian
        ? bytes[index] | (bytes[index + 1] << 8)
        : (bytes[index] << 8) | bytes[index + 1];

    int read32(int index) => littleEndian
        ? bytes[index] |
              (bytes[index + 1] << 8) |
              (bytes[index + 2] << 16) |
              (bytes[index + 3] << 24)
        : (bytes[index] << 24) |
              (bytes[index + 1] << 16) |
              (bytes[index + 2] << 8) |
              bytes[index + 3];

    if (read16(tiff + 2) != 0x002A) {
      return null;
    }

    final int ifd = tiff + read32(tiff + 4);
    if (ifd + 2 > end) {
      return null;
    }
    final int entries = read16(ifd);
    for (int i = 0; i < entries; i++) {
      final int entry = ifd + 2 + (i * 12);
      if (entry + 12 > end) {
        return null;
      }
      if (read16(entry) == tagOrientation) {
        final int value = read16(entry + 8);
        return (value >= 1 && value <= 8) ? value : null;
      }
    }
    return null;
  }

  /// وسم APP1 (بيانات EXIF) — البايت الثاني من الوسم (0xFFE1).
  static const int _app1Marker = 0xE1;

  /// وسم بداية البيانات المضغوطة (نهاية الرأس) — البايت الثاني (0xFFDA).
  static const int _sosMarker = 0xDA;

  /// وسوم SOF التي تحتوي أبعاد الصورة.
  static const Set<int> _sofMarkers = <int>{
    0xC0,
    0xC1,
    0xC2,
    0xC3,
    0xC5,
    0xC6,
    0xC7,
    0xC9,
    0xCA,
    0xCB,
    0xCD,
    0xCE,
    0xCF,
  };
}