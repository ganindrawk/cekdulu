import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:cekdulu/src/core/config/supabase_config.dart';
import 'package:cekdulu/src/core/widgets/common_widgets.dart';
import 'package:cekdulu/src/features/auth/data/auth_repository.dart';
import 'package:cekdulu/src/features/catalog/data/product.dart';
import 'package:cekdulu/src/features/catalog/data/product_repository.dart';

/// Beranda pengguna: katalog produk terurut ulasan terbaik.
class ProductListScreen extends ConsumerWidget {
  const ProductListScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final products = ref.watch(bestProductsProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text('CekDulu'),
        actions: [
          IconButton(
            tooltip: 'Akun & Sidik Jari',
            icon: const Icon(Icons.fingerprint),
            onPressed: () => context.push('/account'),
          ),
          IconButton(
            tooltip: 'Keluar',
            icon: const Icon(Icons.logout),
            onPressed: () async {
              await ref.read(authRepositoryProvider).signOut();
            },
          ),
        ],
      ),
      body: Column(
        children: [
          if (!SupabaseConfig.isConfigured) const BackendWarningBanner(),
          Expanded(
            child: products.when(
              loading: () => const LoadingView(message: 'Memuat produk...'),
              error: (e, _) => ErrorView(
                message: e.toString(),
                onRetry: () => ref.invalidate(bestProductsProvider),
              ),
              data: (list) {
                if (list.isEmpty) {
                  return const Center(
                    child: Text('Belum ada produk di katalog.'),
                  );
                }
                return ListView.builder(
                  itemCount: list.length,
                  itemBuilder: (context, i) =>
                      _ProductCard(product: list[i], isBest: i == 0),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _ProductCard extends StatelessWidget {
  const _ProductCard({required this.product, required this.isBest});

  final Product product;
  final bool isBest;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      child: ListTile(
        leading: product.imageUrl != null
            ? ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Image.network(
                  product.imageUrl!,
                  width: 56,
                  height: 56,
                  fit: BoxFit.cover,
                  errorBuilder: (_, _, _) =>
                      const Icon(Icons.image_not_supported),
                ),
              )
            : const Icon(Icons.shopping_bag_outlined, size: 40),
        title: Row(
          children: [
            Expanded(child: Text(product.name, maxLines: 2, overflow: TextOverflow.ellipsis)),
            if (isBest)
              Container(
                margin: const EdgeInsets.only(left: 8),
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
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
          '${product.marketplaceLabel}'
          '${product.rating != null ? ' • ★ ${product.rating!.toStringAsFixed(1)}' : ''}'
          ' • ${product.reviewCount} ulasan',
        ),
        trailing: const Icon(Icons.chevron_right),
        onTap: () => context.push('/product/${product.id}'),
      ),
    );
  }
}
