import 'package:flutter/material.dart';

/// Widget bersama form admin ala mockup: header oranye, baris field
/// berikon, tombol gradasi, dan kotak info. Dipakai Kelola Katalog,
/// Kredensial Affiliate (dan form admin berikutnya).
class ShopeePalette {
  static const orange = Color(0xFFEE4D2D);
  static const orangeLight = Color(0xFFFF7337);
  static const orangeTop = Color(0xFFFF6B35);
  static const cream = Color(0xFFFFF6F1);
  static const fieldFill = Color(0xFFF8F8F8);
  static const iconTile = Color(0xFFFFF0E8);
  static const dark = Color(0xFF262626);
  static const grey = Color(0xFF8A8A8A);
}

/// Header oranye form admin: tombol kembali, judul, subjudul,
/// dan ikon dekorasi samar di kanan atas.
class AdminFormHeader extends StatelessWidget {
  const AdminFormHeader({
    super.key,
    required this.title,
    required this.subtitle,
    required this.onBack,
    this.decorations = const [],
    this.trailing,
  });

  final String title;
  final String subtitle;
  final VoidCallback onBack;
  final List<Widget> decorations;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final trailingWidget = trailing;
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [ShopeePalette.orangeTop, ShopeePalette.orange],
        ),
        borderRadius: BorderRadius.only(
          bottomLeft: Radius.circular(28),
          bottomRight: Radius.circular(28),
        ),
      ),
      child: Stack(
        children: [
          ...decorations,
          SafeArea(
            bottom: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(8, 12, 12, 28),
              child: Row(
                children: [
                  IconButton(
                    tooltip: 'Kembali',
                    icon: const Icon(Icons.arrow_back, color: Colors.white),
                    onPressed: onBack,
                  ),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(title,
                            style: const TextStyle(
                                color: Colors.white,
                                fontSize: 22,
                                fontWeight: FontWeight.w800)),
                        const SizedBox(height: 2),
                        Text(subtitle,
                            style: const TextStyle(
                                color: Colors.white, fontSize: 15)),
                      ],
                    ),
                  ),
                  trailingWidget ?? const SizedBox.shrink(),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Satu baris field: ikon di tile krem, label tebal, lalu input.
/// [trailing] untuk tombol di kanan input (mis. kamera / pilih gambar).
/// [highlight] memberi latar krem pada baris (dipakai field barcode).
class AdminFieldRow extends StatelessWidget {
  const AdminFieldRow({
    super.key,
    required this.icon,
    required this.label,
    required this.child,
    this.required = false,
    this.helper,
    this.trailing,
    this.highlight = false,
  });

  final IconData icon;
  final String label;
  final Widget child;
  final bool required;
  final String? helper;
  final Widget? trailing;
  final bool highlight;

  @override
  Widget build(BuildContext context) {
    final trailingWidget = trailing;
    final content = Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: ShopeePalette.iconTile,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(icon, size: 24, color: ShopeePalette.orange),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              RichText(
                text: TextSpan(
                  text: label,
                  style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: ShopeePalette.dark),
                  children: [
                    if (required)
                      const TextSpan(
                          text: ' *',
                          style: TextStyle(color: ShopeePalette.orange)),
                  ],
                ),
              ),
              const SizedBox(height: 6),
              Row(
                children: [
                  Expanded(child: child),
                  const SizedBox(width: 8),
                  trailingWidget ?? const SizedBox.shrink(),
                ],
              ),
              if (helper != null) ...[
                const SizedBox(height: 6),
                Text(helper!,
                    style: const TextStyle(
                        fontSize: 12.5,
                        color: ShopeePalette.grey,
                        height: 1.3)),
              ],
            ],
          ),
        ),
      ],
    );
    if (!highlight) return content;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: ShopeePalette.iconTile.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(16),
      ),
      child: content,
    );
  }
}

/// Dekorasi input teks/dropdown form admin: isi abu muda, sudut 12.
InputDecoration adminInputDecoration({String? hintText}) {
  return InputDecoration(
    hintText: hintText,
    hintStyle: const TextStyle(color: Color(0xFFB0B0B0), fontSize: 14),
    filled: true,
    fillColor: ShopeePalette.fieldFill,
    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: BorderSide.none,
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: BorderSide.none,
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: const BorderSide(color: ShopeePalette.orange, width: 1.5),
    ),
    errorBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: const BorderSide(color: Colors.red, width: 1),
    ),
  );
}

/// Tombol kecil di kanan input (kamera / pilih gambar).
class AdminInputAction extends StatelessWidget {
  const AdminInputAction({
    super.key,
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: ShopeePalette.iconTile,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 20, color: ShopeePalette.orange),
              if (label.isNotEmpty) ...[
                const SizedBox(width: 4),
                Text(label,
                    style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: ShopeePalette.orange)),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Tombol simpan gradasi oranye penuh lebar.
class AdminGradientButton extends StatelessWidget {
  const AdminGradientButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.loading = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 52,
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [ShopeePalette.orangeLight, ShopeePalette.orange],
          ),
          borderRadius: BorderRadius.circular(30),
        ),
        child: ElevatedButton(
          onPressed: loading ? null : onPressed,
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.transparent,
            shadowColor: Colors.transparent,
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(30)),
          ),
          child: loading
              ? const SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(
                      color: Colors.white, strokeWidth: 2.5),
                )
              : Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    if (icon != null) ...[
                      Icon(icon, color: Colors.white, size: 22),
                      const SizedBox(width: 8),
                    ],
                    Text(label,
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 17,
                            fontWeight: FontWeight.w700)),
                    if (icon == null) ...[
                      const SizedBox(width: 8),
                      const Icon(Icons.arrow_forward,
                          color: Colors.white, size: 22),
                    ],
                  ],
                ),
        ),
      ),
    );
  }
}

/// Kotak langkah bernomor krem (dipakai "Cara Mendapatkan ..." dll).
class AdminStepsBox extends StatelessWidget {
  const AdminStepsBox({
    super.key,
    required this.title,
    required this.steps,
  });

  final String title;
  final List<String> steps;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: ShopeePalette.iconTile,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: const BoxDecoration(
                  color: ShopeePalette.orange,
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.info, size: 20, color: Colors.white),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(title,
                    style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: ShopeePalette.dark)),
              ),
            ],
          ),
          const SizedBox(height: 12),
          for (var i = 0; i < steps.length; i++) ...[
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 24,
                  height: 24,
                  decoration: const BoxDecoration(
                    color: ShopeePalette.orange,
                    shape: BoxShape.circle,
                  ),
                  alignment: Alignment.center,
                  child: Text('${i + 1}',
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 13,
                          fontWeight: FontWeight.w700)),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(steps[i],
                        style: const TextStyle(
                            fontSize: 13.5,
                            color: Color(0xFF5A5A5A),
                            height: 1.4)),
                  ),
                ),
              ],
            ),
            if (i < steps.length - 1) const SizedBox(height: 8),
          ],
        ],
      ),
    );
  }
}
class AdminInfoBox extends StatelessWidget {
  const AdminInfoBox({
    super.key,
    required this.title,
    required this.body,
  });

  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: ShopeePalette.iconTile,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Stack(
        children: [
          const Positioned(
            right: 0,
            top: 0,
            child: Icon(Icons.link, size: 52, color: Color(0xFFFFD9C7)),
          ),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: const BoxDecoration(
                  color: ShopeePalette.orange,
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.info,
                    size: 20, color: Colors.white),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title,
                        style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            color: ShopeePalette.dark)),
                    const SizedBox(height: 4),
                    Text(body,
                        style: const TextStyle(
                            fontSize: 13.5,
                            color: Color(0xFF5A5A5A),
                            height: 1.4)),
                  ],
                ),
              ),
              const SizedBox(width: 40),
            ],
          ),
        ],
      ),
    );
  }
}
