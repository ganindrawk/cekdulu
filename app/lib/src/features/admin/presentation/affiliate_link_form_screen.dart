import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:cekdulu/src/core/widgets/common_widgets.dart';
import 'package:cekdulu/src/features/admin/data/admin_repository.dart';
import 'package:cekdulu/src/features/admin/presentation/admin_form_widgets.dart';
import 'package:cekdulu/src/features/catalog/data/product.dart';

/// Form menempelkan link affiliate manual per produk (admin).
/// Mendukung Shopee (manual, karena akses Open Platform API dibatasi)
/// dan Tokopedia.
class AffiliateLinkFormScreen extends ConsumerStatefulWidget {
  const AffiliateLinkFormScreen({super.key});

  @override
  ConsumerState<AffiliateLinkFormScreen> createState() =>
      _AffiliateLinkFormScreenState();
}

class _AffiliateLinkFormScreenState
    extends ConsumerState<AffiliateLinkFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final _originalUrl = TextEditingController();
  final _affiliateUrl = TextEditingController();
  String _marketplace = 'shopee';
  String? _selectedProductId;
  bool _loading = false;
  String? _error;
  String? _info;

  static const _marketplaces = ['shopee', 'tokopedia'];

  String get _marketplaceLabel =>
      _marketplace == 'shopee' ? 'Shopee' : 'Tokopedia';

  @override
  void dispose() {
    _originalUrl.dispose();
    _affiliateUrl.dispose();
    super.dispose();
  }

  Future<void> _pasteOriginalUrl() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text?.trim() ?? '';
    if (text.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Clipboard kosong.')),
        );
      }
      return;
    }
    setState(() => _originalUrl.text = text);
  }

  Future<void> _copyAffiliateUrl() async {
    final text = _affiliateUrl.text.trim();
    if (text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Link affiliate masih kosong.')),
      );
      return;
    }
    await Clipboard.setData(ClipboardData(text: text));
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Link affiliate disalin.')),
      );
    }
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    if (_selectedProductId == null) {
      setState(() => _error = 'Pilih produk dulu.');
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
      _info = null;
    });
    try {
      await ref.read(adminRepositoryProvider).addAffiliateLink(
            productId: _selectedProductId!,
            marketplace: _marketplace,
            originalUrl: _originalUrl.text.trim(),
            affiliateUrl: _affiliateUrl.text.trim(),
          );
      setState(() {
        _info = 'Link affiliate $_marketplaceLabel tersimpan.';
        _originalUrl.clear();
        _affiliateUrl.clear();
        _selectedProductId = null;
      });
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final productsAsync =
        ref.watch(adminRepositoryProvider).fetchAllProducts();
    return Scaffold(
      backgroundColor: ShopeePalette.cream,
      body: Column(
        children: [
          AdminFormHeader(
            title: 'Link Affiliate',
            subtitle: 'Bagikan link, dapatkan komisi!',
            onBack: () => context.go('/admin'),
            decorations: const [
              Positioned(
                right: 16,
                top: 18,
                child: Icon(Icons.link, size: 72, color: Colors.white24),
              ),
              Positioned(
                right: 84,
                top: 62,
                child: Icon(Icons.star, size: 20, color: Colors.white24),
              ),
            ],
          ),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
              child: Column(
                children: [
                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(24),
                      boxShadow: const [
                        BoxShadow(
                            color: Color(0x14000000),
                            blurRadius: 16,
                            offset: Offset(0, 4)),
                      ],
                    ),
                    child: Form(
                      key: _formKey,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          AdminFieldRow(
                            icon: Icons.store_outlined,
                            label: 'Marketplace',
                            child: DropdownButtonFormField<String>(
                              initialValue: _marketplace,
                              decoration: adminInputDecoration(),
                              items: _marketplaces
                                  .map((m) => DropdownMenuItem(
                                        value: m,
                                        child: Text(m == 'shopee'
                                            ? 'Shopee'
                                            : 'Tokopedia'),
                                      ))
                                  .toList(),
                              onChanged: (v) {
                                if (v == null) return;
                                setState(() {
                                  _marketplace = v;
                                  _info = null;
                                });
                              },
                            ),
                          ),
                          const SizedBox(height: 20),
                          AdminFieldRow(
                            icon: Icons.local_offer_outlined,
                            label: 'Produk / Katalog',
                            child: FutureBuilder<List<Product>>(
                              future: productsAsync,
                              builder: (context, snap) {
                                if (snap.connectionState ==
                                    ConnectionState.waiting) {
                                  return const LoadingView(
                                      message: 'Memuat produk...');
                                }
                                if (snap.hasError) {
                                  return ErrorView(
                                      message: snap.error.toString());
                                }
                                final products = snap.data ?? [];
                                return DropdownButtonFormField<String>(
                                  initialValue: _selectedProductId,
                                  decoration: adminInputDecoration(),
                                  hint: const Text(
                                      'Masukkan nama produk atau pilih dari katalog'),
                                  items: products
                                      .map((p) => DropdownMenuItem(
                                            value: p.id,
                                            child: Text(p.name,
                                                overflow:
                                                    TextOverflow.ellipsis),
                                          ))
                                      .toList(),
                                  onChanged: (v) => setState(
                                      () => _selectedProductId = v),
                                  validator: (v) =>
                                      v == null ? 'Pilih produk' : null,
                                );
                              },
                            ),
                          ),
                          const SizedBox(height: 20),
                          AdminFieldRow(
                            icon: Icons.link,
                            label: 'URL produk asli ($_marketplaceLabel)',
                            trailing: AdminInputAction(
                              icon: Icons.content_paste_outlined,
                              label: '',
                              onTap: _pasteOriginalUrl,
                            ),
                            child: TextFormField(
                              controller: _originalUrl,
                              keyboardType: TextInputType.url,
                              decoration: adminInputDecoration(
                                  hintText:
                                      'Tempel link produk dari $_marketplaceLabel'),
                              validator: (v) =>
                                  (v == null || v.trim().isEmpty)
                                      ? 'Wajib diisi'
                                      : null,
                            ),
                          ),
                          const SizedBox(height: 20),
                          AdminFieldRow(
                            icon: Icons.link,
                            label: 'Link affiliate ($_marketplaceLabel)',
                            trailing: AdminInputAction(
                              icon: Icons.copy_outlined,
                              label: '',
                              onTap: _copyAffiliateUrl,
                            ),
                            child: TextFormField(
                              controller: _affiliateUrl,
                              keyboardType: TextInputType.url,
                              decoration: adminInputDecoration(
                                  hintText:
                                      'Link akan otomatis muncul di sini'),
                              validator: (v) =>
                                  (v == null || v.trim().isEmpty)
                                      ? 'Wajib diisi'
                                      : null,
                            ),
                          ),
                          const SizedBox(height: 24),
                          if (_error != null) ...[
                            Text(_error!,
                                style:
                                    const TextStyle(color: Colors.red)),
                            const SizedBox(height: 8),
                          ],
                          if (_info != null) ...[
                            Text(_info!),
                            const SizedBox(height: 8),
                          ],
                          AdminGradientButton(
                            label: 'Simpan Link',
                            icon: Icons.link,
                            loading: _loading,
                            onPressed: _save,
                          ),
                          const SizedBox(height: 20),
                          const AdminStepsBox(
                            title: 'Cara Mendapatkan Link Affiliate',
                            steps: [
                              'Pilih marketplace Shopee',
                              'Cari produk yang ingin dibagikan',
                              'Tempel link produk asli, lalu generate link affiliate',
                              'Bagikan link ke media sosial atau teman',
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                  const _LinkHillsDecoration(height: 130),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Bukit oranye dekoratif di bawah form, dengan ikon samar.
class _LinkHillsDecoration extends StatelessWidget {
  const _LinkHillsDecoration({required this.height});

  final double height;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: height,
      child: Stack(
        children: [
          CustomPaint(
            size: Size.infinite,
            painter: _LinkHillsPainter(),
          ),
          const Positioned(
            left: 16,
            bottom: 40,
            child: Icon(Icons.campaign_outlined,
                size: 52, color: Colors.white38),
          ),
          const Positioned(
            left: 84,
            bottom: 18,
            child: Icon(Icons.star, size: 22, color: Colors.white38),
          ),
          const Positioned(
            left: 118,
            bottom: 44,
            child: Icon(Icons.share_outlined,
                size: 34, color: Colors.white38),
          ),
          const Positioned(
            right: 96,
            bottom: 36,
            child: Icon(Icons.link, size: 44, color: Colors.white38),
          ),
          Positioned(
            right: 16,
            bottom: 30,
            child: Container(
              width: 44,
              height: 44,
              decoration: const BoxDecoration(
                color: Color(0xFFFFB020),
                shape: BoxShape.circle,
              ),
              alignment: Alignment.center,
              child: const Text('Rp',
                  style: TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w800)),
            ),
          ),
        ],
      ),
    );
  }
}

class _LinkHillsPainter extends CustomPainter {
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
