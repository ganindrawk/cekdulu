// Smoke test dasar CekDulu: model produk dan konfigurasi backend.

import 'package:flutter_test/flutter_test.dart';
import 'package:cekdulu/src/core/config/supabase_config.dart';
import 'package:cekdulu/src/features/catalog/data/product.dart';

void main() {
  test('Product.fromMap memetakan kolom database dengan benar', () {
    final product = Product.fromMap({
      'id': 'abc-123',
      'name': 'Kopi Susu 1L',
      'description': 'Kopi susu gula aren',
      'image_url': 'https://example.com/kopi.jpg',
      'marketplace': 'shopee',
      'marketplace_url': 'https://shopee.co.id/kopi-123',
      'price': 25000,
      'rating': 4.8,
      'review_count': 1200,
    });

    expect(product.id, 'abc-123');
    expect(product.name, 'Kopi Susu 1L');
    expect(product.marketplaceLabel, 'Shopee');
    expect(product.price, 25000);
    expect(product.rating, 4.8);
    expect(product.reviewCount, 1200);
  });

  test('Supabase belum terkonfigurasi tanpa --dart-define', () {
    // Nilai default kosong -> mode scaffold.
    expect(SupabaseConfig.isConfigured, isFalse);
  });
}
