import 'dart:typed_data';
import 'dart:ui' show Size;

import 'package:flutter_test/flutter_test.dart';

import 'package:orderly_app/utils/jpeg_info.dart';

void main() {
  group('JpegInfo', () {
    test('parse returns null for non-JPEG bytes', () {
      final Uint8List bytes = Uint8List.fromList(<int>[0x00, 0x00, 0x00, 0x00]);
      expect(JpegInfo.parse(bytes), isNull);
    });

    test('parse returns null for empty bytes', () {
      expect(JpegInfo.parse(Uint8List(0)), isNull);
    });

    test('parse reads normal orientation JPEG dimensions', () {
      // JPEG مبسط: SOI (FFD8) + SOF0 (FFC0) مع أبعاد 640×480.
      final Uint8List bytes = _buildMinimalJpeg(640, 480, 1);
      final JpegInfo? info = JpegInfo.parse(bytes);
      expect(info, isNotNull);
      expect(info!.width, 640);
      expect(info.height, 480);
      expect(info.orientation, 1);
      expect(info.swapsAxes, isFalse);
      expect(info.displaySize, const Size(640, 480));
      expect(info.isValid, isTrue);
    });

    test('parse reads rotated JPEG dimensions', () {
      // JPEG مبدوء: أبعاد 480×640 مع اتجاه 6 (90°).
      final Uint8List bytes = _buildMinimalJpegWithOrientation(480, 640, 6);
      final JpegInfo? info = JpegInfo.parse(bytes);
      expect(info, isNotNull);
      expect(info!.swapsAxes, isTrue);
      expect(info.displaySize, const Size(640, 480));
    });
  });
}

/// بناء JPEG صالح جزئياً بسيط مع SOF وأبعاد محددة.
Uint8List _buildMinimalJpeg(int width, int height, int orientation) {
  // SOI
  final List<int> bytes = <int>[0xFF, 0xD8];

  // SOF0: طول 11، نوع 8 بت، ارتفاع، عرض.
  bytes.addAll(<int>[
    0xFF, 0xC0, // SOF0 marker
    0x00, 0x0B, // length = 11
    0x08, // precision 8
    (height >> 8) & 0xFF, height & 0xFF,
    (width >> 8) & 0xFF, width & 0xFF,
    0x01, // 1 component
    0x01, 0x11, 0x00,
  ]);

  return Uint8List.fromList(bytes);
}

/// بناء JPEG مع بيانات EXIF التي تحتوي على اتجاه محدد.
Uint8List _buildMinimalJpegWithOrientation(int width, int height, int orientation) {
  // SOI
  final List<int> bytes = <int>[0xFF, 0xD8];

  // APP1 مع توقيع EXIF
  final List<int> exifPayload = _buildExifTiff(orientation);
  bytes.addAll(<int>[0xFF, 0xE1]);
  bytes.addAll(_toBytesBigEndian(exifPayload.length + 8)); // "Exif\0\0" + TIFF
  bytes.addAll(<int>[0x45, 0x78, 0x69, 0x66, 0x00, 0x00]); // "Exif\0\0"
  bytes.addAll(exifPayload);

  // SOF0
  bytes.addAll(<int>[
    0xFF, 0xC0, 0x00, 0x0B, 0x08,
    (height >> 8) & 0xFF, height & 0xFF,
    (width >> 8) & 0xFF, width & 0xFF,
    0x01, 0x01, 0x11, 0x00,
  ]);

  return Uint8List.fromList(bytes);
}

List<int> _toBytesBigEndian(int value) {
  return <int>[(value >> 8) & 0xFF, value & 0xFF];
}

/// بناء بيانات TIFF بسيطة تحتوي على اتجاه EXIF واحد.
List<int> _buildExifTiff(int orientation) {
  final List<int> tiff = <int>[
    0x4D, 0x4D, // Big-endian (MM)
    0x00, 0x2A, // TIFF magic
    0x00, 0x00, 0x00, 0x08, // IFD offset (8 = مباشرة بعد هذا)
    0x00, 0x01, // 1 entry
    // Entry: اتجاه (0x0112)، نوع 3 (SHORT)، عدد 1، القيمة في 2 بايت.
    0x01, 0x12, 0x00, 0x03, 0x00, 0x00, 0x00, 0x01,
    (orientation >> 8) & 0xFF, orientation & 0xFF, 0x00, 0x00,
    0x00, 0x00, // no next IFD
  ];
  return tiff;
}
