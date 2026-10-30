import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:share_plus/share_plus.dart';
import 'package:cekdulu/src/core/widgets/common_widgets.dart';
import 'package:cekdulu/src/features/catalog/data/product.dart';
import 'package:cekdulu/src/features/catalog/data/product_repository.dart';
import 'package:url_launcher/url_launcher.dart';

/// Detail produk ala mockup: header oranye, foto, harga, deskripsi
/// lipat, dan bilah aksi bawah. Logika tidak berubah: Beli Sekarang
/// membuka link affiliate aktif pertama (dulu ditampilkan sebagai
/// daftar link); sisanya mengikuti data produk yang benar-benar ada.
class ProductDetailScreen extends ConsumerStatefulWidget {
  const ProductDetailScreen({super.key, required this.productId});

  final String productId;

  @override
  ConsumerState<ProductDetailScreen> createState() =>
      _ProductDetailScreenState();
}

class _ProductDetailScreenState extends ConsumerState<ProductDetailScreen> {
  bool _expanded = false;

  Future<void> _openLink(BuildContext context, String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Link tidak valid')),
      );
      return;
    }
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Gagal membuka link')),
        );
      }
    }
  }

  void _snack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  /// Link pembelian: affiliate aktif pertama, atau null bila tidak ada.
  String? _buyUrl(List<AffiliateLink>? links) {
    if (links != null && links.isNotEmpty) return links.first.affiliateUrl;
    return null;
  }

  Future<void> _share(Product product, List<AffiliateLink>? links) async {
    final url = _buyUrl(links) ?? product.marketplaceUrl;
    if (url == null) {
      _snack('Belum ada link untuk dibagikan.');
      return;
    }
    await SharePlus.instance
        .share(ShareParams(text: '${product.name}\n$url'));
  }

  /// 1248 -> "1.248"; 189000 -> "Rp 189.000".
  String _groupDigits(String digits) {
    final buf = StringBuffer();
    for (var i = 0; i < digits.length; i++) {
      if (i > 0 && (digits.length - i) % 3 == 0) buf.write('.');
      buf.write(digits[i]);
    }
    return buf.toString();
  }

  String _formatRupiah(double price) =>
      'Rp ${_groupDigits(price.toStringAsFixed(0))}';

  @override
  Widget build(BuildContext context) {
    final productAsync = ref.watch(_productProvider(widget.productId));
    final links = ref.watch(_linksProvider(widget.productId)).valueOrNull;
    return Scaffold(
      backgroundColor: Colors.white,
      body: productAsync.when(
        loading: () => const LoadingView(),
        error: (e, _) => ErrorView(message: e.toString()),
        data: (product) {
          if (product == null) {
            return const Center(child: Text('Produk tidak ditemukan.'));
          }
          return Column(
            children: [
              _Header(
                onBack: () => context.pop(),
                onShare: () => _share(product, links),
                onCopyLink: () async {
                  final url = _buyUrl(links) ?? product.marketplaceUrl;
                  if (url == null) {
                    _snack('Belum ada link untuk disalin.');
                    return;
                  }
                  await Clipboard.setData(ClipboardData(text: url));
                  _snack('Link produk disalin.');
                },
                onOpenMarketplace: () {
                  final url = _buyUrl(links) ?? product.marketplaceUrl;
                  if (url == null) {
                    _snack('Belum ada link marketplace.');
                    return;
                  }
                  _openLink(context, url);
                },
              ),
              Expanded(
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                        child: Stack(
                          children: [
                            ClipRRect(
                              borderRadius: BorderRadius.circular(20),
                              child: product.imageUrl != null
                                  ? Image.network(
                                      product.imageUrl!,
                                      width: double.infinity,
                                      height: 240,
                                      fit: BoxFit.cover,
                                      errorBuilder: (_, _, _) =>
                                          const _ImagePlaceholder(),
                                    )
                                  : const _ImagePlaceholder(),
                            ),
                            Positioned(
                              left: 12,
                              top: 12,
                              child: Container(
                                width: 28,
                                height: 28,
                                decoration: BoxDecoration(
                                  color: product.marketplace == 'shopee'
                                      ? const Color(0xFFEE4D2D)
                                      : const Color(0xFF03AC0E),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                alignment: Alignment.center,
                                child: Text(
                                  product.marketplace == 'shopee' ? 'S' : 'T',
                                  style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 15,
                                      fontWeight: FontWeight.w800),
                                ),
                              ),
                            ),
                            Positioned(
                              right: 12,
                              bottom: 12,
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 10, vertical: 4),
                                decoration: BoxDecoration(
                                  color: Colors.black.withValues(alpha: 0.55),
                                  borderRadius: BorderRadius.circular(20),
                                ),
                                child: const Text('1/1',
                                    style: TextStyle(
                                        color: Colors.white,
                                        fontSize: 12,
                                        fontWeight: FontWeight.w700)),
                              ),
                            ),
                          ],
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(product.name,
                                style: const TextStyle(
                                    fontSize: 20,
                                    fontWeight: FontWeight.w700,
                                    color: Color(0xFF262626),
                                    height: 1.3)),
                            const SizedBox(height: 8),
                            Row(
                              children: [
                                if (product.rating != null) ...[
                                  const Icon(Icons.star,
                                      size: 18,
                                      color: Color(0xFFFFB020)),
                                  const SizedBox(width: 4),
                                  Text(
                                      product.rating!.toStringAsFixed(1),
                                      style: const TextStyle(
                                          fontSize: 15,
                                          fontWeight: FontWeight.w700,
                                          color: Color(0xFF262626))),
                                  const SizedBox(width: 8),
                                ],
                                Text(
                                  '(${_groupDigits(product.reviewCount.toString())} ulasan)',
                                  style: const TextStyle(
                                      fontSize: 14,
                                      color: Color(0xFF8A8A8A)),
                                ),
                              ],
                            ),
                            if (product.price != null) ...[
                              const SizedBox(height: 8),
                              Text(_formatRupiah(product.price!),
                                  style: const TextStyle(
                                      fontSize: 24,
                                      fontWeight: FontWeight.w800,
                                      color: Color(0xFFEE4D2D))),
                            ],
                          ],
                        ),
                      ),
                      if (product.description != null)
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                          child: Material(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(20),
                            elevation: 1,
                            shadowColor: const Color(0xFFEE4D2D)
                                .withValues(alpha: 0.08),
                            child: Padding(
                              padding: const EdgeInsets.all(16),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text('Deskripsi Produk',
                                      style: TextStyle(
                                          fontSize: 16,
                                          fontWeight: FontWeight.w700,
                                          color: Color(0xFF262626))),
                                  const SizedBox(height: 8),
                                  Text(product.description!,
                                      maxLines: _expanded ? null : 3,
                                      overflow: _expanded
                                          ? null
                                          : TextOverflow.ellipsis,
                                      style: const TextStyle(
                                          fontSize: 14,
                                          height: 1.5,
                                          color: Color(0xFF262626))),
                                  const SizedBox(height: 8),
                                  Center(
                                    child: InkWell(
                                      onTap: () => setState(
                                          () => _expanded = !_expanded),
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Text(
                                              _expanded
                                                  ? 'Sembunyikan'
                                                  : 'Lihat Selengkapnya',
                                              style: const TextStyle(
                                                  fontSize: 14,
                                                  fontWeight: FontWeight.w700,
                                                  color:
                                                      Color(0xFF262626))),
                                          Icon(
                                              _expanded
                                                  ? Icons.keyboard_arrow_up
                                                  : Icons
                                                      .keyboard_arrow_down,
                                              size: 18,
                                              color: const Color(0xFF262626)),
                                        ],
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      const SizedBox(height: 16),
                    ],
                  ),
                ),
              ),
              _BottomBar(
                onBuy: () {
                  final url = _buyUrl(links);
                  if (url == null) {
                    _snack(
                        'Belum ada link affiliate aktif untuk produk ini.');
                    return;
                  }
                  _openLink(context, url);
                },
              ),
            ],
          );
        },
      ),
    );
  }
}

class _ImagePlaceholder extends StatelessWidget {
  const _ImagePlaceholder();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      height: 240,
      color: const Color(0xFFF8F8F8),
      child: const Icon(Icons.shopping_bag_outlined,
          size: 56, color: Color(0xFF8A8A8A)),
    );
  }
}

/// Header oranye: kembali, judul, bagikan, dan menu lainnya.
class _Header extends StatelessWidget {
  const _Header({
    required this.onBack,
    required this.onShare,
    required this.onCopyLink,
    required this.onOpenMarketplace,
  });

  final VoidCallback onBack;
  final VoidCallback onShare;
  final VoidCallback onCopyLink;
  final VoidCallback onOpenMarketplace;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFFFF6B35), Color(0xFFEE4D2D)],
        ),
        borderRadius: BorderRadius.only(
          bottomLeft: Radius.circular(28),
          bottomRight: Radius.circular(28),
        ),
      ),
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(8, 12, 8, 24),
          child: Row(
            children: [
              IconButton(
                tooltip: 'Kembali',
                icon: const Icon(Icons.arrow_back, color: Colors.white),
                onPressed: onBack,
              ),
              const Expanded(
                child: Text('Detail Produk',
                    style: TextStyle(
                        color: Colors.white,
                        fontSize: 22,
                        fontWeight: FontWeight.w800)),
              ),
              IconButton(
                tooltip: 'Bagikan',
                icon: const Icon(Icons.share_outlined, color: Colors.white),
                onPressed: onShare,
              ),
              PopupMenuButton<String>(
                icon: const Icon(Icons.more_vert, color: Colors.white),
                tooltip: 'Lainnya',
                onSelected: (value) {
                  if (value == 'copy') {
                    onCopyLink();
                  } else {
                    onOpenMarketplace();
                  }
                },
                itemBuilder: (context) => const [
                  PopupMenuItem(
                      value: 'copy', child: Text('Salin link produk')),
                  PopupMenuItem(
                      value: 'open', child: Text('Buka di marketplace')),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Bilah aksi bawah: Toko / Chat / Favorit + Keranjang + Beli Sekarang.
/// Bilah aksi bawah: hanya tombol Beli Sekarang (Toko / Chat /
/// Favorit / Tambah Keranjang dihapus atas permintaan Kan).
class _BottomBar extends StatelessWidget {
  const _BottomBar({required this.onBuy});

  final VoidCallback onBuy;

  @override
  Widget build(BuildContext context) {
    const orange = Color(0xFFEE4D2D);
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
              color: Color(0x14000000), blurRadius: 12, offset: Offset(0, -2)),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
          child: SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: onBuy,
              style: FilledButton.styleFrom(
                backgroundColor: orange,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(24)),
                padding: const EdgeInsets.symmetric(vertical: 16),
              ),
              child: const Text('Beli Sekarang',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
            ),
          ),
        ),
      ),
    );
  }
}

final _productProvider =
    FutureProvider.family<Product?, String>((ref, id) async {
  return ref.watch(productRepositoryProvider).fetchById(id);
});

final _linksProvider =
    FutureProvider.family<List<AffiliateLink>, String>((ref, id) async {
  return ref.watch(productRepositoryProvider).fetchAffiliateLinks(id);
});
