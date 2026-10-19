import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image/image.dart' as img;
import 'package:image_picker/image_picker.dart';
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
    } else {
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Scan Produk')),
      body: Stack(
        children: [
          Column(
            children: [
              Expanded(
                flex: 3,
                child: Stack(
                  children: [
                    _scanActive
                        ? CameraScanView(
                            key: ValueKey(_scanSession),
                            onCode: _onCodeDetected,
                          )
                        : const ColoredBox(
                            color: Colors.black,
                            child: Center(
                              child: Text(
                                'Kamera dijeda…',
                                style: TextStyle(color: Colors.white70),
                              ),
                            ),
                          ),
                    Align(
                      alignment: Alignment.bottomCenter,
                      child: Container(
                        width: double.infinity,
                        color: Colors.black54,
                        padding: const EdgeInsets.all(12),
                        child: const Text(
                          'Ketuk layar untuk fokus • Arahkan kamera ke barcode / QR produk',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: Colors.white),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                flex: 2,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Text('atau masukkan kode manual / upload gambar:'),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: _manualCode,
                              decoration: const InputDecoration(
                                labelText: 'Kode produk',
                                border: OutlineInputBorder(),
                              ),
                              onSubmitted: (_) => _onManualSubmit(),
                            ),
                          ),
                          const SizedBox(width: 8),
                          FilledButton(
                            onPressed: _onManualSubmit,
                            child: const Text('Cari'),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      FilledButton.tonalIcon(
                        onPressed: _onVisualSearch,
                        icon: const Icon(Icons.auto_awesome_outlined),
                        label: const Text('Foto AI'),
                      ),
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
