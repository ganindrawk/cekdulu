import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cekdulu/src/core/config/supabase_config.dart';
import 'package:cekdulu/src/features/auth/data/auth_repository.dart';
import 'package:cekdulu/src/features/catalog/data/product.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Akses katalog produk di Supabase.
class ProductRepository {
  ProductRepository(this._client);

  final SupabaseClient? _client;

  SupabaseClient get _c {
    final c = _client;
    if (c == null) throw const BackendNotConfiguredException();
    return c;
  }

  /// Daftar produk terurut "ulasan terbaik": rating DESC, review_count DESC.
  Future<List<Product>> fetchBestReviewed({int limit = 50}) async {
    final rows = await _c
        .from('products')
        .select()
        .order('rating', ascending: false, nullsFirst: false)
        .order('review_count', ascending: false)
        .limit(limit);
    return (rows as List).map((e) => Product.fromMap(e as Map<String, dynamic>)).toList();
  }

  /// Seluruh katalog (untuk pencocokan visual AI).
  Future<List<Product>> fetchAll({int limit = 500}) async {
    final rows = await _c
        .from('products')
        .select()
        .order('name')
        .limit(limit);
    return (rows as List).map((e) => Product.fromMap(e as Map<String, dynamic>)).toList();
  }

  /// Cari produk yang cocok dengan kode hasil scan (barcode/QR).
  /// Urutan: 1) cocok persis dengan kolom barcode (EAN-13/UPC fisik),
  /// 2) fallback: kode sebagai substring marketplace_url (QR berisi URL).
  /// Hasil tetap terurut "ulasan terbaik".
  Future<List<Product>> findByScannedCode(String code) async {
    final q = code.trim();
    if (q.isEmpty) return const [];

    final List<dynamic> byBarcode = await _c
        .from('products')
        .select()
        .eq('barcode', q)
        .order('rating', ascending: false, nullsFirst: false)
        .order('review_count', ascending: false);

    final List<dynamic> rows = byBarcode.isNotEmpty
        ? byBarcode
        : await _c
            .from('products')
            .select()
            .ilike('marketplace_url', '%$q%')
            .order('rating', ascending: false, nullsFirst: false)
            .order('review_count', ascending: false);

    return rows.map((e) => Product.fromMap(e as Map<String, dynamic>)).toList();
  }

  Future<Product?> fetchById(String id) async {
    final row =
        await _c.from('products').select().eq('id', id).maybeSingle();
    if (row == null) return null;
    return Product.fromMap(row);
  }

  /// Link affiliate aktif untuk sebuah produk.
  Future<List<AffiliateLink>> fetchAffiliateLinks(String productId) async {
    final rows = await _c
        .from('affiliate_links')
        .select()
        .eq('product_id', productId)
        .eq('status', 'active');
    return (rows as List)
        .map((e) => AffiliateLink.fromMap(e as Map<String, dynamic>))
        .toList();
  }

  /// Catat riwayat scan pengguna.
  Future<void> logScan({required String userId, String? productId, required String code}) async {
    await _c.from('scan_history').insert({
      'user_id': userId,
      'product_id': productId,
      'scanned_code': code,
    });
  }
}

final productRepositoryProvider = Provider<ProductRepository>((ref) {
  return ProductRepository(ref.watch(supabaseClientProvider));
});

/// Produk terbaik untuk beranda pengguna.
final bestProductsProvider = FutureProvider<List<Product>>((ref) async {
  return ref.watch(productRepositoryProvider).fetchBestReviewed();
});
