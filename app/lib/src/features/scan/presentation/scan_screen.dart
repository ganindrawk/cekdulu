import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image/image.dart' as img;
import 'package:image_picker/image_picker.dart';
import 'package:cekdulu/src/features/admin/presentation/admin_form_widgets.dart';
import 'package:cekdulu/src/features/auth/data/auth_repository.dart';
import 'package:cekdulu/src/features/catalog/data/product.dart';
import 'package:cekdulu/src/features/catalog/data/product_repository.dart';
import 'package:cekdulu/src/features/scan/data/visual_search_repository.dart';
import 'package:cekdulu/src/features/scan/presentation/camera_scan_view.dart';

/// Layar scan barcode/QR produk.
///
/// Setiap hasil pindaian membuka layar hasil; saat kembali, sesi scan baru
/// dimulai (kamera diinisialisasi ulang) lewat [CameraScanView].
class ScanScreen extends ConsumerStatefulWidget {
  const ScanScreen({super.key});

  @override
  ConsumerState<ScanScreen> createState() => _ScanScreenState();
}

class _ScanScreenState extends ConsumerState<ScanScreen> {
  final _manualCode = TextEditingController();
  bool _handling = false;
  bool _lookingUp = false;
  int _scanSession = 0;
  bool _scanActive = true; // false = kamera dijeda (mis. saat Foto AI)
  bool _aiLive = false; // mode AI Live: kamera dianalisis AI berkala
  bool _aiBusy = false;
  String? _aiLiveStatus;

  @override
  void dispose() {
    _manualCode.dispose();
    super.dispose();
  }

  Future<void> _onCodeDetected(String code) async {
    if (_handling) return;
    _handling = true;
    if (mounted) setState(() => _lookingUp = true);

    List<Product> matches = [];
    String? error;
    try {
      matches =
          await ref.read(productRepositoryProvider).findByScannedCode(code);
      final userId = ref.read(authRepositoryProvider).currentUser?.id;
      if (userId != null) {
        await ref.read(productRepositoryProvider).logScan(
              userId: userId,
              productId: matches.isNotEmpty ? matches.first.id : null,
              code: code,
            );
      }
    } catch (e) {
      error = e.toString();
    } finally {
      if (mounted) setState(() => _lookingUp = false);
    }

    if (!mounted) return;
    if (error != null) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(error)));
    } else if (matches.isEmpty) {
      // Barcode tidak ada di katalog — tawarkan identifikasi via AI.
      if (!mounted) return;
      final tryAi = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Produk tidak ditemukan'),
          content: Text(
            'Kode "$code" tidak ada di katalog.\nCoba identifikasi produk dengan AI dari foto?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Nanti'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('Coba dengan AI'),
            ),
          ],
        ),
      );
      if (tryAi == true) {
        if (!mounted) return;
        _handling = false;
        setState(() => _scanSession++);
        await _onVisualSearch();
        return;
      }
      if (!mounted) return;
      await context.push('/scan/result',
          extra: ScanResultArgs(code: code, products: matches));
    } else {
      if (!mounted) return;
      await context.push('/scan/result',
          extra: ScanResultArgs(code: code, products: matches));
    }
    _handling = false;
    // Mulai sesi scan baru (kamera diinisialisasi ulang).
    if (mounted) setState(() => _scanSession++);
  }

  void _onManualSubmit() {
    final code = _manualCode.text.trim();
    if (code.isNotEmpty) _onCodeDetected(code);
  }

  /// Pencarian visual via AI: foto produk dikenali oleh Gemini,
  /// hasilnya dicocokkan dengan katalog.
  Future<void> _onVisualSearch() async {
    if (_handling) return;
    // Nonaktifkan fitur scan kamera selama alur Foto AI.
    _handling = true;
    if (mounted) setState(() => _scanActive = false);
    try {
      await _runVisualSearch();
    } finally {
      // Aktifkan kembali fitur scan kamera.
      _handling = false;
      if (mounted) {
        setState(() {
          _scanActive = true;
          _scanSession++;
        });
      }
    }
  }

  Future<void> _runVisualSearch() async {
      // Pilih sumber foto: kamera atau galeri.
      final source = await showModalBottomSheet<ImageSource>(
        context: context,
        builder: (ctx) => SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.camera_alt_outlined),
                title: const Text('Ambil foto'),
                onTap: () => Navigator.of(ctx).pop(ImageSource.camera),
              ),
              ListTile(
                leading: const Icon(Icons.photo_library_outlined),
                title: const Text('Pilih dari galeri'),
                onTap: () => Navigator.of(ctx).pop(ImageSource.gallery),
              ),
            ],
          ),
        ),
      );
      if (source == null || !mounted) return;
      final file = await ImagePicker().pickImage(source: source);
      if (file == null || !mounted) return;
      setState(() => _lookingUp = true);
    try {
      // Kecilkan gambar agar payload base64 tidak terlalu besar.
      final bytes = await file.readAsBytes();
      img.Image? decoded = img.decodeImage(bytes);
      if (decoded == null) {
        throw Exception('Format gambar tidak didukung.');
      }
      decoded = img.bakeOrientation(decoded);
      const maxSide = 1024;
      if (decoded.width > maxSide || decoded.height > maxSide) {
        decoded = decoded.width >= decoded.height
            ? img.copyResize(decoded, width: maxSide)
            : img.copyResize(decoded, height: maxSide);
      }
      final jpeg = img.encodeJpg(decoded, quality: 85);
      final b64 = base64Encode(jpeg);

      final repo = ref.read(visualSearchRepositoryProvider);
      final id = await repo.identify(b64);
      final guess = id.keywords.trim();
      if (!mounted) return;
      if (guess.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('AI tidak mengenali produk di foto ini.'),
          ),
        );
        return;
      }
      final matches = await repo.match(id);
      if (!mounted) return;
      if (matches.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'AI menebak "$guess", tapi tidak ada yang cocok di katalog.',
            ),
          ),
        );
        return;
      }
      // Log sebagai scan visual.
      final userId = ref.read(authRepositoryProvider).currentUser?.id;
      if (userId != null) {
        await ref.read(productRepositoryProvider).logScan(
              userId: userId,
              productId: matches.first.product.id,
              code: 'ai:$guess',
            );
      }
      if (!mounted) return;
      context.push(
        '/scan/result',
        extra: ScanResultArgs(
          code: 'AI: $guess',
          products: matches.map((m) => m.product).toList(),
        ),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))),
        );
      }
    } finally {
      if (mounted) setState(() => _lookingUp = false);
    }
  }

  /// AI Live: frame kamera berkala diidentifikasi AI. Bila produk cocok
  /// dengan katalog, langsung buka layar hasil; selain itu tampilkan
  /// status tebakan tanpa mengganggu.
  ///
  /// Selama AI memproses, scan dinonaktifkan (kamera dijeda) dan area
  /// scan ditutupi progress bar agar pengguna tidak bingung; setelah
  /// selesai, kamera diaktifkan lagi (kecuali produk ketemu → navigasi).
  Future<void> _onAiLiveFrame(Uint8List jpeg) async {
    if (_aiBusy || _handling || !_aiLive || !mounted) return;
    setState(() {
      _aiBusy = true;
      _scanActive = false; // jeda scan selama AI memproses
    });
    try {
      final repo = ref.read(visualSearchRepositoryProvider);
      final id = await repo.identify(base64Encode(jpeg));
      if (!mounted || !_aiLive || _handling) return;
      final guess = id.keywords.trim();
      if (guess.isEmpty) {
        setState(() =>
            _aiLiveStatus = 'Produk tidak tersedia — AI tidak mengenali produknya.');
        return;
      }
      final matches = await repo.match(id);
      if (!mounted || !_aiLive || _handling) return;
      if (matches.isEmpty) {
        setState(() => _aiLiveStatus =
            'Produk tidak tersedia di katalog (AI menebak: "$guess")');
        return;
      }
      // Produk ketemu: matikan AI Live, catat scan, buka hasil.
      setState(() {
        _aiLive = false;
        _aiLiveStatus = null;
      });
      final userId = ref.read(authRepositoryProvider).currentUser?.id;
      if (userId != null) {
        await ref.read(productRepositoryProvider).logScan(
              userId: userId,
              productId: matches.first.product.id,
              code: 'ai:$guess',
            );
      }
      if (!mounted) return;
      _handling = true;
      await context.push(
        '/scan/result',
        extra: ScanResultArgs(
          code: 'AI: $guess',
          products: matches.map((m) => m.product).toList(),
        ),
      );
      _handling = false;
    } on AiRateLimitException {
      // Kuota Gemini tercapai: matikan Scan AI agar berhenti memanggil,
      // beri tahu pengguna dengan bahasa yang jelas.
      if (mounted) {
        setState(() {
          _aiLive = false;
          _aiLiveStatus =
              'Kuota AI tercapai (429) — Scan AI berhenti. Tunggu beberapa menit lalu coba lagi.';
        });
      }
    } catch (e) {
      if (mounted && _aiLive) {
        setState(() => _aiLiveStatus =
            'AI Live: ${e.toString().replaceFirst('Exception: ', '')}');
      }
    } finally {
      // Proses selesai: aktifkan kembali scan dengan sesi kamera baru.
      if (mounted) {
        setState(() {
          _aiBusy = false;
          _scanActive = true;
          _scanSession++;
        });
      }
    }
  }

  /// Pilihan mode kamera ala mockup: pil Barcode / AI.
  Widget _modePill(bool aiMode, String label, IconData icon) {
    final selected = _aiLive == aiMode;
    return Material(
      color: selected ? ShopeePalette.orange : Colors.white,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: () => setState(() {
          _aiLive = aiMode;
          _aiLiveStatus =
              aiMode ? 'AI Live: arahkan ke produk & tahan stabil…' : null;
        }),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            border: Border.all(
                color: selected
                    ? Colors.transparent
                    : const Color(0xFFE5E5E5)),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon,
                  size: 18,
                  color: selected ? Colors.white : ShopeePalette.grey),
              const SizedBox(width: 4),
              Text(label,
                  style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: selected ? Colors.white : ShopeePalette.dark)),
            ],
          ),
        ),
      ),
    );
  }

  /// Tombol oranye kecil (mis. "Cari" di samping input manual).
  Widget _smallOrangeButton({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Container(
          height: 52,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [ShopeePalette.orangeLight, ShopeePalette.orange],
            ),
            borderRadius: BorderRadius.all(Radius.circular(14)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, color: Colors.white, size: 20),
              const SizedBox(width: 6),
              Text(label,
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 15,
                      fontWeight: FontWeight.w700)),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: ShopeePalette.cream,
      body: Stack(
        children: [
          Column(
            children: [
              AdminFormHeader(
                title: 'Scan Produk',
                subtitle:
                    'Temukan informasi produk dengan scan barcode atau AI.',
                onBack: () => context.go('/home'),
                decorations: const [
                  Positioned(
                    right: 24,
                    top: 14,
                    child: Icon(Icons.qr_code_scanner,
                        size: 72, color: Colors.white24),
                  ),
                  Positioned(
                    right: 88,
                    top: 56,
                    child: Icon(Icons.star, size: 20, color: Colors.white24),
                  ),
                ],
              ),
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // Kartu preview kamera.
                      ClipRRect(
                        borderRadius: BorderRadius.circular(24),
                        child: AspectRatio(
                          aspectRatio: 16 / 10,
                          child: Stack(
                            fit: StackFit.expand,
                            children: [
                              _scanActive
                                  ? CameraScanView(
                                      key: ValueKey(_scanSession),
                                      onCode: _onCodeDetected,
                                      aiLiveEnabled: _aiLive,
                                      onAiFrame: _onAiLiveFrame,
                                    )
                                  : const ColoredBox(
                                      color: Colors.black,
                                      child: Center(
                                        child: Text(
                                          'Kamera dijeda…',
                                          style: TextStyle(
                                              color: Colors.white70),
                                        ),
                                      ),
                                    ),
                              // Pil status kamera.
                              Positioned(
                                top: 12,
                                right: 12,
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 12, vertical: 6),
                                  decoration: BoxDecoration(
                                    color: Colors.black54,
                                    borderRadius: BorderRadius.circular(20),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Container(
                                        width: 8,
                                        height: 8,
                                        decoration: BoxDecoration(
                                          color: _scanActive
                                              ? Colors.greenAccent
                                              : Colors.white54,
                                          shape: BoxShape.circle,
                                        ),
                                      ),
                                      const SizedBox(width: 6),
                                      Text(
                                        _scanActive
                                            ? 'Kamera aktif'
                                            : 'Kamera dijeda',
                                        style: const TextStyle(
                                            color: Colors.white,
                                            fontSize: 13),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                              // Bilah petunjuk di bawah preview.
                              Positioned(
                                left: 12,
                                right: 12,
                                bottom: 12,
                                child: Container(
                                  padding: const EdgeInsets.all(12),
                                  decoration: BoxDecoration(
                                    color: Colors.black54,
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: const Row(
                                    children: [
                                      Icon(Icons.lightbulb_outline,
                                          color: Colors.white),
                                      SizedBox(width: 8),
                                      Expanded(
                                        child: Text(
                                          'Arahkan kamera ke barcode produk dengan jarak 10–15 cm.',
                                          style: TextStyle(
                                              color: Colors.white,
                                              fontSize: 13),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                              // Saat AI memproses: tutupi preview yang
                              // nonaktif dengan progress bar.
                              if (_aiBusy)
                                Positioned.fill(
                                  child: Container(
                                    color: Colors.black87,
                                    alignment: Alignment.center,
                                    child: const Padding(
                                      padding: EdgeInsets.symmetric(
                                          horizontal: 40),
                                      child: Column(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          LinearProgressIndicator(),
                                          SizedBox(height: 16),
                                          Text(
                                            'Mencari data produk…',
                                            style: TextStyle(
                                                color: Colors.white),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      // Kartu input kode manual.
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(20),
                          boxShadow: const [
                            BoxShadow(
                                color: Color(0x14000000),
                                blurRadius: 16,
                                offset: Offset(0, 4)),
                          ],
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Atau masukkan kode produk manual',
                              style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w700,
                                  color: ShopeePalette.dark),
                            ),
                            const SizedBox(height: 12),
                            Row(
                              children: [
                                Expanded(
                                  child: SizedBox(
                                    height: 52,
                                    child: TextField(
                                      controller: _manualCode,
                                      decoration: adminInputDecoration(
                                              hintText:
                                                  'Contoh: 8997203456789')
                                          .copyWith(
                                        prefixIcon: const Icon(
                                            Icons.barcode_reader,
                                            color: Color(0xFF5A5A5A)),
                                      ),
                                      onSubmitted: (_) => _onManualSubmit(),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                _smallOrangeButton(
                                  icon: Icons.qr_code_scanner,
                                  label: 'Cari',
                                  onTap: _onManualSubmit,
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),
                      // Kartu Scan dengan AI (alur Foto AI).
                      Material(
                        color: ShopeePalette.iconTile,
                        borderRadius: BorderRadius.circular(20),
                        child: InkWell(
                          borderRadius: BorderRadius.circular(20),
                          onTap: _aiBusy ? null : _onVisualSearch,
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Row(
                              children: [
                                const Icon(Icons.auto_awesome,
                                    color: ShopeePalette.orange, size: 26),
                                const SizedBox(width: 12),
                                const Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text('Scan dengan AI',
                                          style: TextStyle(
                                              fontSize: 16,
                                              fontWeight: FontWeight.w700,
                                              color: ShopeePalette.orange)),
                                      SizedBox(height: 2),
                                      Text('Deteksi produk dari foto',
                                          style: TextStyle(
                                              fontSize: 13,
                                              color: ShopeePalette.grey)),
                                    ],
                                  ),
                                ),
                                const Icon(Icons.chevron_right,
                                    color: ShopeePalette.orange),
                              ],
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      // Kartu Mode Scan.
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(20),
                          boxShadow: const [
                            BoxShadow(
                                color: Color(0x14000000),
                                blurRadius: 16,
                                offset: Offset(0, 4)),
                          ],
                        ),
                        child: Row(
                          children: [
                            Container(
                              width: 44,
                              height: 44,
                              decoration: BoxDecoration(
                                color: ShopeePalette.iconTile,
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: const Icon(Icons.camera_alt,
                                  size: 24, color: ShopeePalette.orange),
                            ),
                            const SizedBox(width: 12),
                            const Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text('Mode Scan',
                                      style: TextStyle(
                                          fontSize: 16,
                                          fontWeight: FontWeight.w700,
                                          color: ShopeePalette.dark)),
                                  SizedBox(height: 2),
                                  Text(
                                      'Pilih cara scan sesuai kebutuhanmu',
                                      style: TextStyle(
                                          fontSize: 12.5,
                                          color: ShopeePalette.grey)),
                                ],
                              ),
                            ),
                            _modePill(
                                false, 'Barcode', Icons.barcode_reader),
                            const SizedBox(width: 8),
                            _modePill(true, 'AI', Icons.qr_code_scanner),
                          ],
                        ),
                      ),
                      if (!_aiBusy && _aiLiveStatus != null) ...[
                        const SizedBox(height: 8),
                        Text(
                          _aiLiveStatus!,
                          style: const TextStyle(
                              fontSize: 12, color: ShopeePalette.grey),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ],
          ),
          // Indikator loading selagi kode yang terbaca dicari di database.
          if (_lookingUp)
            Container(
              color: Colors.black54,
              alignment: Alignment.center,
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 24, vertical: 20),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: const [
                      CircularProgressIndicator(),
                      SizedBox(width: 16),
                      Text('Mencari produk…'),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Argumen navigasi ke layar hasil scan.
class ScanResultArgs {
  ScanResultArgs({required this.code, required this.products});

  final String code;
  final List<Product> products;
}

/// Layar hasil scan: produk terurut ulasan terbaik.
class ScanResultScreen extends StatelessWidget {
  const ScanResultScreen({super.key, required this.code, required this.products});

  final String code;
  final List<Product> products;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Hasil Scan')),
      body: products.isEmpty
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  'Tidak ada produk yang cocok untuk kode "$code".',
                  textAlign: TextAlign.center,
                ),
              ),
            )
          : ListView.builder(
              itemCount: products.length,
              itemBuilder: (context, i) {
                final p = products[i];
                final scheme = Theme.of(context).colorScheme;
                return Card(
                  child: ListTile(
                    leading: const Icon(Icons.shopping_bag_outlined, size: 40),
                    title: Row(
                      children: [
                        Expanded(child: Text(p.name, maxLines: 2, overflow: TextOverflow.ellipsis)),
                        if (i == 0)
                          Container(
                            margin: const EdgeInsets.only(left: 8),
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: scheme.primaryContainer,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Text(
                              'Ulasan terbaik',
                              style: TextStyle(
                                fontSize: 11,
                                color: scheme.onPrimaryContainer,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                      ],
                    ),
                    subtitle: Text(
                      '${p.marketplaceLabel}'
                      '${p.rating != null ? ' • ★ ${p.rating!.toStringAsFixed(1)}' : ''}'
                      ' • ${p.reviewCount} ulasan',
                    ),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => context.push('/product/${p.id}'),
                  ),
                );
              },
            ),
    );
  }
}
