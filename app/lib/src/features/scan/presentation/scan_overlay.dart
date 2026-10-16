import 'package:flutter/material.dart';

/// Overlay di atas preview kamera:
/// - bingkai bidik (sudut-sudut merah, jadi hijau saat barcode terkunci)
/// - kotak hijau mengelilingi setiap barcode yang terdeteksi ML Kit.
class ScanOverlayPainter extends CustomPainter {
  ScanOverlayPainter({
    required this.boxes,
    required this.imageSize,
    required this.rotationDegrees,
    required this.locked,
  });

  /// Bounding box barcode dalam koordinat gambar asli (belum dirotasi).
  final List<Rect> boxes;

  /// Ukuran frame gambar asli (mis. 1280x720).
  final Size imageSize;

  /// Rotasi yang diterapkan agar gambar tampil tegak (0/90/180/270).
  final int rotationDegrees;

  /// True saat sebuah kode sedang dikunci (sebentar lagi dinavigasi).
  final bool locked;

  @override
  void paint(Canvas canvas, Size size) {
    _paintViewfinder(canvas, size);
    if (boxes.isEmpty || imageSize.isEmpty) return;
    final paint = Paint()
      ..color = Colors.greenAccent
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3;
    for (final box in boxes) {
      canvas.drawRect(_mapRect(box, imageSize, size, rotationDegrees), paint);
    }
  }

  void _paintViewfinder(Canvas canvas, Size size) {
    final w = size.width * 0.72;
    final h = w * 0.62;
    final rect = Rect.fromCenter(
      center: size.center(Offset.zero),
      width: w,
      height: h,
    );
    final paint = Paint()
      ..color = locked ? Colors.greenAccent : Colors.redAccent
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4
      ..strokeCap = StrokeCap.round;
    const armFactor = 0.16;
    final arm = w * armFactor;
    final corners = <List<Object>>[
      [rect.topLeft, const Offset(1, 0), const Offset(0, 1)],
      [rect.topRight, const Offset(-1, 0), const Offset(0, 1)],
      [rect.bottomLeft, const Offset(1, 0), const Offset(0, -1)],
      [rect.bottomRight, const Offset(-1, 0), const Offset(0, -1)],
    ];
    for (final c in corners) {
      final p = c[0] as Offset;
      final d1 = c[1] as Offset;
      final d2 = c[2] as Offset;
      canvas.drawLine(p, p + d1 * arm, paint);
      canvas.drawLine(p, p + d2 * arm, paint);
    }
  }

  /// Petakan koordinat gambar (belum dirotasi) ke koordinat overlay.
  Rect _mapRect(Rect r, Size img, Size display, int rotation) {
    Offset map(Offset p) {
      final x = p.dx, y = p.dy;
      final iw = img.width, ih = img.height;
      final w = display.width, h = display.height;
      switch (rotation) {
        case 90:
          return Offset((1 - y / ih) * w, (x / iw) * h);
        case 180:
          return Offset((1 - x / iw) * w, (1 - y / ih) * h);
        case 270:
          return Offset((y / ih) * w, (1 - x / iw) * h);
        default:
          return Offset((x / iw) * w, (y / ih) * h);
      }
    }

    return Rect.fromPoints(map(r.topLeft), map(r.bottomRight));
  }

  @override
  bool shouldRepaint(covariant ScanOverlayPainter old) =>
      old.locked != locked ||
      old.rotationDegrees != rotationDegrees ||
      old.imageSize != imageSize ||
      !identical(old.boxes, boxes);
}
