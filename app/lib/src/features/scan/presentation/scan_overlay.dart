import 'package:flutter/material.dart';

/// Overlay di atas preview kamera:
/// - bingkai bidik (sudut-sudut merah, jadi hijau saat barcode terkunci)
/// - kotak hijau mengelilingi setiap barcode yang terdeteksi ML Kit
/// - garis pindai beranimasi selagi mencari (scanT 0..1; null = sembunyi)
/// - cincin fokus sesaat saat pengguna mengetuk layar (focusPoint relatif 0..1)
class ScanOverlayPainter extends CustomPainter {
  ScanOverlayPainter({
    required this.boxes,
    required this.imageSize,
    required this.rotationDegrees,
    required this.locked,
    this.scanT,
    this.focusPoint,
  });

  /// Bounding box barcode dalam koordinat gambar asli (belum dirotasi).
  final List<Rect> boxes;

  /// Ukuran frame gambar asli (mis. 1280x720).
  final Size imageSize;

  /// Rotasi yang diterapkan agar gambar tampil tegak (0/90/180/270).
  final int rotationDegrees;

  /// True saat sebuah kode sedang dikunci (sebentar lagi dinavigasi).
  final bool locked;

  /// Posisi garis pindai dalam bingkai bidik (0 = atas, 1 = bawah).
  final double? scanT;

  /// Titik fokus manual terakhir (koordinat relatif 0..1 dalam preview).
  final Offset? focusPoint;

  @override
  void paint(Canvas canvas, Size size) {
    final viewfinder = _paintViewfinder(canvas, size);
    if (scanT != null) _paintScanLine(canvas, viewfinder, scanT!);
    if (focusPoint != null) _paintFocusRing(canvas, size, focusPoint!);
    if (boxes.isEmpty || imageSize.isEmpty) return;
    final paint = Paint()
      ..color = Colors.greenAccent
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3;
    for (final box in boxes) {
      canvas.drawRect(_mapRect(box, imageSize, size, rotationDegrees), paint);
    }
  }

  /// Gambar bingkai bidik; kembalikan rect-nya untuk dipakai garis pindai.
  Rect _paintViewfinder(Canvas canvas, Size size) {
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
    return rect;
  }

  /// Garis pindai hijau yang bergerak naik-turun di dalam bingkai bidik.
  void _paintScanLine(Canvas canvas, Rect viewfinder, double t) {
    final y = viewfinder.top + t * viewfinder.height;
    final paint = Paint()
      ..color = Colors.greenAccent.withValues(alpha: 0.9)
      ..strokeWidth = 2.5
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(
      Offset(viewfinder.left + 10, y),
      Offset(viewfinder.right - 10, y),
      paint,
    );
    // Kilau lembut di sekitar garis.
    final glow = Paint()
      ..color = Colors.greenAccent.withValues(alpha: 0.18)
      ..strokeWidth = 14
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(
      Offset(viewfinder.left + 10, y),
      Offset(viewfinder.right - 10, y),
      glow,
    );
  }

  /// Cincin fokus di titik yang diketuk pengguna.
  void _paintFocusRing(Canvas canvas, Size size, Offset rel) {
    final center = Offset(rel.dx * size.width, rel.dy * size.height);
    final paint = Paint()
      ..color = Colors.yellowAccent
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5;
    canvas.drawCircle(center, 30, paint);
    canvas.drawCircle(center, 4, paint..style = PaintingStyle.fill);
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
      old.scanT != scanT ||
      old.focusPoint != focusPoint ||
      !identical(old.boxes, boxes);
}
