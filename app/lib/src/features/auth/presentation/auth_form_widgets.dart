import 'package:flutter/material.dart';
import 'package:cekdulu/src/features/admin/presentation/admin_form_widgets.dart';

/// Widget bersama layar auth ala mockup: bukit oranye dekoratif,
/// tombol sosial, dan pembatas "Atau".
class AuthHills extends StatelessWidget {
  const AuthHills({super.key, required this.height, this.icons = const []});

  final double height;
  final List<Widget> icons;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: height,
      child: Stack(
        children: [
          CustomPaint(size: Size.infinite, painter: _AuthHillsPainter()),
          ...icons,
        ],
      ),
    );
  }
}

class _AuthHillsPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final back = Paint()..color = const Color(0xFFFFCDB8);
    final front = Paint()..color = const Color(0xFFFF8A50);
    final w = size.width;
    final h = size.height;
    canvas.drawPath(
      Path()
        ..moveTo(0, h * 0.55)
        ..quadraticBezierTo(w * 0.25, h * 0.05, w * 0.55, h * 0.5)
        ..quadraticBezierTo(w * 0.8, h * 0.85, w, h * 0.4)
        ..lineTo(w, h)
        ..lineTo(0, h)
        ..close(),
      back,
    );
    canvas.drawPath(
      Path()
        ..moveTo(0, h * 0.75)
        ..quadraticBezierTo(w * 0.3, h * 0.3, w * 0.6, h * 0.7)
        ..quadraticBezierTo(w * 0.85, h * 0.95, w, h * 0.6)
        ..lineTo(w, h)
        ..lineTo(0, h)
        ..close(),
      front,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// Tombol masuk/daftar sosial (Google / Apple): putih, border abu.
class SocialButton extends StatelessWidget {
  const SocialButton({
    super.key,
    required this.leading,
    required this.label,
    required this.onTap,
  });

  final Widget leading;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: onTap,
          child: Container(
            height: 50,
            decoration: BoxDecoration(
              border: Border.all(color: const Color(0xFFE5E5E5)),
              borderRadius: BorderRadius.circular(14),
            ),
            alignment: Alignment.center,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                leading,
                const SizedBox(width: 8),
                Text(label,
                    style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: ShopeePalette.dark)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Pembatas garis–teks–garis ("Atau ...").
class OrDivider extends StatelessWidget {
  const OrDivider({super.key, required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const Expanded(child: Divider()),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Text(text,
              style: const TextStyle(
                  fontSize: 13, color: ShopeePalette.grey)),
        ),
        const Expanded(child: Divider()),
      ],
    );
  }
}
