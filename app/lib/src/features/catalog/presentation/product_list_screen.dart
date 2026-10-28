import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:cekdulu/src/core/config/supabase_config.dart';
import 'package:cekdulu/src/core/widgets/common_widgets.dart';
import 'package:cekdulu/src/features/auth/data/auth_repository.dart';
import 'package:cekdulu/src/features/catalog/data/product.dart';
import 'package:cekdulu/src/features/catalog/data/product_repository.dart';

/// Beranda pengguna ala mockup: header oranye, kolom cari, pil kategori,
/// dan kartu produk. Logika tidak berubah: daftar tetap dari
/// bestProductsProvider (rating & ulasan terbaik), ketuk kartu tetap
/// membuka detail produk.
class ProductListScreen extends ConsumerStatefulWidget {
  const ProductListScreen({super.key});

  @override
  ConsumerState<ProductListScreen> createState() => _ProductListScreenState();
}

class _ProductListScreenState extends ConsumerState<ProductListScreen> {
  String _query = '';

  void _onCategoryTap(String label) {
    if (label == 'Semua') return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          'Filter kategori belum tersedia — produk belum punya data kategori.',
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final products = ref.watch(bestProductsProvider);
    return Scaffold(
      backgroundColor: Colors.white,
      body: Column(
        children: [
          _Header(
            onAccount: () => context.push('/account'),
            onLogout: () async {
              await ref.read(authRepositoryProvider).signOut();
            },
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
            child: TextField(
              decoration: InputDecoration(
                hintText: 'Cari produk di katalog...',
                hintStyle: const TextStyle(color: Color(0xFF8A8A8A)),
                prefixIcon:
                    const Icon(Icons.search, color: Color(0xFFEE4D2D)),
                filled: true,
                fillColor: const Color(0xFFF8F8F8),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(24),
                  borderSide: BorderSide.none,
                ),
                contentPadding: const EdgeInsets.symmetric(vertical: 14),
              ),
              onChanged: (value) => setState(() => _query = value),
            ),
          ),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                _CategoryPill(
                  icon: Icons.grid_view_rounded,
                  label: 'Semua',
                  selected: true,
                  onTap: () => _onCategoryTap('Semua'),
                ),
                _CategoryPill(
                  icon: Icons.checkroom_outlined,
                  label: 'Fashion',
                  selected: false,
                  onTap: () => _onCategoryTap('Fashion'),
                ),
                _CategoryPill(
                  icon: Icons.smartphone_outlined,
                  label: 'Elektronik',
                  selected: false,
                  onTap: () => _onCategoryTap('Elektronik'),
                ),
                _CategoryPill(
                  icon: Icons.home_outlined,
                  label: 'Rumah Tangga',
                  selected: false,
                  onTap: () => _onCategoryTap('Rumah Tangga'),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          if (!SupabaseConfig.isConfigured) const BackendWarningBanner(),
          Expanded(
            child: products.when(
              loading: () => const LoadingView(message: 'Memuat produk...'),
              error: (e, _) => ErrorView(
                message: e.toString(),
                onRetry: () => ref.invalidate(bestProductsProvider),
              ),
              data: (list) {
                final q = _query.trim().toLowerCase();
                final filtered = q.isEmpty
                    ? list
                    : list
                        .where((p) => p.name.toLowerCase().contains(q))
                        .toList();
                if (filtered.isEmpty) {
                  return Center(
                    child: Text(
                      q.isEmpty
                          ? 'Belum ada produk di katalog.'
                          : 'Tidak ada produk yang cocok.',
                    ),
                  );
                }
                return ListView.builder(
                  padding: const EdgeInsets.only(bottom: 16),
                  itemCount: filtered.length,
                  itemBuilder: (context, i) => _ProductCard(
                    product: filtered[i],
                    isBest: i == 0,
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

/// Header oranye: tile logo, nama aplikasi, tagline, dan tombol akun/keluar.
class _Header extends StatelessWidget {
  const _Header({required this.onAccount, required this.onLogout});

  final VoidCallback onAccount;
  final VoidCallback onLogout;

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
      child: Stack(
        children: [
          Positioned(
            right: -24,
            top: -48,
            child: Container(
              width: 150,
              height: 150,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
            ),
          ),
          Positioned(
            right: 84,
            top: 44,
            child: Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.10),
                shape: BoxShape.circle,
              ),
            ),
          ),
          SafeArea(
            bottom: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 8, 24),
              child: Row(
                children: [
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: const Icon(Icons.shopping_bag,
                        size: 28, color: Color(0xFFEE4D2D)),
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('CekDulu',
                            style: TextStyle(
                                color: Colors.white,
                                fontSize: 24,
                                fontWeight: FontWeight.w800)),
                        SizedBox(height: 2),
                        Text('Temukan produk terbaik untukmu',
                            style: TextStyle(
                                color: Colors.white, fontSize: 14)),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: 'Akun & Sidik Jari',
                    icon: const Icon(Icons.fingerprint, color: Colors.white),
                    onPressed: onAccount,
                  ),
                  IconButton(
                    tooltip: 'Keluar',
                    icon: const Icon(Icons.logout, color: Colors.white),
                    onPressed: onLogout,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Satu pil kategori: terpilih = oranye penuh, sisanya putih berbingkai.
class _CategoryPill extends StatelessWidget {
  const _CategoryPill({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = selected ? Colors.white : const Color(0xFF262626);
    final iconColor =
        selected ? Colors.white : const Color(0xFF262626);
    return Padding(
      padding: const EdgeInsets.only(right: 10),
      child: Material(
        color: selected ? const Color(0xFFEE4D2D) : Colors.white,
        borderRadius: BorderRadius.circular(24),
        elevation: selected ? 2 : 0,
        shadowColor: const Color(0xFFEE4D2D).withValues(alpha: 0.25),
        child: InkWell(
          borderRadius: BorderRadius.circular(24),
          onTap: onTap,
          child: Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(24),
              border: selected
                  ? null
                  : Border.all(color: const Color(0xFFE8E8E8)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 20, color: iconColor),
                const SizedBox(width: 8),
                Text(label,
                    style: TextStyle(
                        fontSize: 14,
                        fontWeight:
                            selected ? FontWeight.w700 : FontWeight.w500,
                        color: color)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Satu kartu produk: foto + badge marketplace, nama, marketplace •
/// jumlah ulasan, dan lencana Produk Populer / Tersedia.
class _ProductCard extends StatelessWidget {
  const _ProductCard({required this.product, required this.isBest});

  final Product product;
  final bool isBest;

  @override
  Widget build(BuildContext context) {
    final isShopee = product.marketplace == 'shopee';
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      child: Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        elevation: 2,
        shadowColor: const Color(0xFFEE4D2D).withValues(alpha: 0.08),
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: () => context.push('/product/${product.id}'),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Stack(
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(16),
                      child: product.imageUrl != null
                          ? Image.network(
                              product.imageUrl!,
                              width: 112,
                              height: 112,
                              fit: BoxFit.cover,
                              errorBuilder: (_, _, _) =>
                                  const _ImagePlaceholder(),
                            )
                          : const _ImagePlaceholder(),
                    ),
                    Positioned(
                      left: 6,
                      top: 6,
                      child: Container(
                        width: 24,
                        height: 24,
                        decoration: BoxDecoration(
                          color: isShopee
                              ? const Color(0xFFEE4D2D)
                              : const Color(0xFF03AC0E),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        alignment: Alignment.center,
                        child: Text(
                          isShopee ? 'S' : 'T',
                          style: const TextStyle(
                              color: Colors.white,
                              fontSize: 13,
                              fontWeight: FontWeight.w800),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(product.name,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                              color: Color(0xFF262626),
                              height: 1.3)),
                      const SizedBox(height: 4),
                      Text(
                        '${product.marketplaceLabel} • ${product.reviewCount} ulasan',
                        style: const TextStyle(
                            fontSize: 13, color: Color(0xFF8A8A8A)),
                      ),
                      const SizedBox(height: 10),
                      if (isBest)
                        const _Badge(
                          icon: Icons.local_fire_department,
                          label: 'Produk Populer',
                          background: Color(0xFFFFF0E8),
                          foreground: Color(0xFFEE4D2D),
                        )
                      else
                        const _Badge(
                          icon: Icons.verified,
                          label: 'Tersedia',
                          background: Color(0xFFEAF7EE),
                          foreground: Color(0xFF2E9E57),
                        ),
                    ],
                  ),
                ),
                const Icon(Icons.chevron_right, color: Color(0xFF8A8A8A)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ImagePlaceholder extends StatelessWidget {
  const _ImagePlaceholder();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 112,
      height: 112,
      color: const Color(0xFFF8F8F8),
      child: const Icon(Icons.shopping_bag_outlined,
          size: 40, color: Color(0xFF8A8A8A)),
    );
  }
}

/// Lencana kecil di bawah nama produk.
class _Badge extends StatelessWidget {
  const _Badge({
    required this.icon,
    required this.label,
    required this.background,
    required this.foreground,
  });

  final IconData icon;
  final String label;
  final Color background;
  final Color foreground;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 15, color: foreground),
          const SizedBox(width: 4),
          Text(label,
              style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: foreground)),
        ],
      ),
    );
  }
}
