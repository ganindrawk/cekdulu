import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cekdulu/src/core/widgets/common_widgets.dart';
import 'package:cekdulu/src/features/catalog/data/product.dart';
import 'package:cekdulu/src/features/catalog/data/product_repository.dart';
import 'package:url_launcher/url_launcher.dart';

/// Detail produk + tombol buka link affiliate.
class ProductDetailScreen extends ConsumerWidget {
  const ProductDetailScreen({super.key, required this.productId});

  final String productId;

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

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final productAsync = ref.watch(_productProvider(productId));
    final linksAsync = ref.watch(_linksProvider(productId));

    return Scaffold(
      appBar: AppBar(title: const Text('Detail Produk')),
      body: productAsync.when(
        loading: () => const LoadingView(),
        error: (e, _) => ErrorView(message: e.toString()),
        data: (product) {
          if (product == null) {
            return const Center(child: Text('Produk tidak ditemukan.'));
          }
          return SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (product.imageUrl != null)
                  Center(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: Image.network(
                        product.imageUrl!,
                        height: 200,
                        fit: BoxFit.cover,
                        errorBuilder: (_, _, _) =>
                            const Icon(Icons.image_not_supported, size: 64),
                      ),
                    ),
                  ),
                const SizedBox(height: 16),
                Text(product.name,
                    style: Theme.of(context).textTheme.headlineSmall),
                const SizedBox(height: 8),
                Text(
                  '${product.marketplaceLabel}'
                  '${product.rating != null ? ' • ★ ${product.rating!.toStringAsFixed(1)}' : ''}'
                  ' • ${product.reviewCount} ulasan'
                  '${product.price != null ? ' • Rp${product.price!.toStringAsFixed(0)}' : ''}',
                ),
                if (product.description != null) ...[
                  const SizedBox(height: 12),
                  Text(product.description!),
                ],
                const SizedBox(height: 24),
                Text('Beli via link affiliate',
                    style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 8),
                linksAsync.when(
                  loading: () => const LoadingView(),
                  error: (e, _) => ErrorView(message: e.toString()),
                  data: (links) {
                    if (links.isEmpty) {
                      return const Text(
                          'Belum ada link affiliate aktif untuk produk ini.');
                    }
                    return Column(
                      children: links
                          .map((l) => Card(
                                child: ListTile(
                                  leading: const Icon(Icons.link),
                                  title: Text(l.marketplace == 'shopee'
                                      ? 'Shopee'
                                      : 'Tokopedia'),
                                  subtitle: const Text(
                                      'Link affiliate pemilik aplikasi'),
                                  trailing: const Icon(Icons.open_in_new),
                                  onTap: () => _openLink(context, l.affiliateUrl),
                                ),
                              ))
                          .toList(),
                    );
                  },
                ),
              ],
            ),
          );
        },
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
