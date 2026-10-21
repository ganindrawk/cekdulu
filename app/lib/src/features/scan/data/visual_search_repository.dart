import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cekdulu/src/core/config/supabase_config.dart';
import 'package:cekdulu/src/features/auth/data/auth_repository.dart';
import 'package:cekdulu/src/features/catalog/data/product.dart';
import 'package:cekdulu/src/features/catalog/data/product_repository.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Hasil identifikasi visual dari AI.
class VisualIdentification {
  VisualIdentification({this.brand, this.productName, this.variant});

  final String? brand;
  final String? productName;
  final String? variant;

  /// Gabungan kata kunci untuk pencocokan, sudah dinormalisasi.
  String get keywords =>
      [brand, productName, variant].whereType<String>().join(' ');
}

/// Produk katalog beserta skor kecocokan visual (0.0 – 1.0).
class VisualMatch {
  VisualMatch(this.product, this.score);

  final Product product;
  final double score;
}

/// Kuota/rate limit AI tercapai (Gemini balas 429).
class AiRateLimitException implements Exception {
  const AiRateLimitException();

  @override
  String toString() =>
      'Kuota AI tercapai. Tunggu beberapa menit lalu coba lagi.';
}

/// Pencarian visual produk via AI (Edge Function `identify-product-image`).
///
/// Alur: foto (base64) → Edge Function → Gemini menebak merek/nama produk →
/// dicocokkan (fuzzy) dengan nama produk di katalog.
class VisualSearchRepository {
  VisualSearchRepository(this._client, this._products);

  final SupabaseClient? _client;
  final ProductRepository _products;

  SupabaseClient get _c {
    final c = _client;
    if (c == null) throw const BackendNotConfiguredException();
    return c;
  }

  /// Kirim foto ke Edge Function, kembalikan identifikasi AI.
  /// Melempar [Exception] dengan pesan ramah bila gagal.
  Future<VisualIdentification> identify(String imageBase64,
      {String mimeType = 'image/jpeg'}) async {
    try {
      final res = await _c.functions.invoke(
        'identify-product-image',
        body: {'image_base64': imageBase64, 'mime_type': mimeType},
      );
      final data = res.data as Map<String, dynamic>?;
      if (res.status != 200 || data == null || data['ok'] != true) {
        throw Exception(_friendlyError(data?['error']?.toString()));
      }
      return VisualIdentification(
        brand: _str(data['brand']),
        productName: _str(data['product_name']),
        variant: _str(data['variant']),
      );
    } on FunctionException catch (e) {
      // Ambil kode error + provider_status dari body respons untuk diagnostik.
      String? code;
      int? providerStatus;
      try {
        final details = e.details;
        if (details is Map) {
          if (details['error'] is String) code = details['error'] as String;
          if (details['provider_status'] is int) {
            providerStatus = details['provider_status'] as int;
          }
        } else if (details is String && details.isNotEmpty) {
          final m = RegExp(r'"error"\s*:\s*"([^"]+)"').firstMatch(details);
          if (m != null) code = m.group(1)!;
          final p = RegExp(r'"provider_status"\s*:\s*(\d+)').firstMatch(details);
          if (p != null) providerStatus = int.tryParse(p.group(1)!);
        }
      } catch (_) {}
      if (code == 'ai_provider_error' && providerStatus != null) {
        if (providerStatus == 429) {
          throw const AiRateLimitException();
        }
        throw Exception(
          'Layanan AI tidak merespons (502; Gemini: $providerStatus).',
        );
      }
      throw Exception('Layanan AI tidak merespons (${e.status}).');
    } catch (e) {
      if (e is AiRateLimitException) rethrow;
      if (e is Exception && e.toString().startsWith('Exception: ')) rethrow;
      throw Exception('Gagal mengenali gambar: $e');
    }
  }

  /// Cocokkan identifikasi AI dengan katalog. Kembalikan maksimal [limit]
  /// produk dengan skor >= [minScore], terurut skor tertinggi dulu.
  Future<List<VisualMatch>> match(VisualIdentification id,
      {int limit = 5, double minScore = 0.25}) async {
    final keywords = _tokens(id.keywords);
    if (keywords.isEmpty) return const [];
    final products = await _products.fetchAll();
    final scored = <VisualMatch>[];
    for (final p in products) {
      final score = _score(keywords, _tokens(p.name));
      if (score >= minScore) scored.add(VisualMatch(p, score));
    }
    scored.sort((a, b) => b.score.compareTo(a.score));
    return scored.take(limit).toList();
  }

  // --- Pencocokan fuzzy sederhana berbasis kata ---

  static String? _str(Object? v) =>
      v is String && v.trim().isNotEmpty ? v.trim() : null;

  /// Normalisasi: huruf kecil, hanya alfanumerik, pecah per kata,
  /// buang kata umum yang tidak membedakan produk.
  static Set<String> _tokens(String text) {
    const stopwords = {
      'pack',
      'pcs',
      'gram',
      'gr',
      'ml',
      'dengan',
      'dan',
      'yang',
      'isi',
    };
    return text
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9 ]'), ' ')
        .split(RegExp(r'\s+'))
        .where((w) => w.length > 1 && !stopwords.contains(w))
        .toSet();
  }

  /// Skor = F1 dari irisan kata (0.0–1.0).
  static double _score(Set<String> query, Set<String> candidate) {
    if (query.isEmpty || candidate.isEmpty) return 0;
    final inter = query.intersection(candidate).length;
    if (inter == 0) return 0;
    final precision = inter / candidate.length;
    final recall = inter / query.length;
    return 2 * precision * recall / (precision + recall);
  }

  static String _friendlyError(String? code) {
    switch (code) {
      case 'ai_not_configured':
        return 'Pengenalan gambar belum dikonfigurasi admin.';
      case 'ai_provider_error':
        return 'Layanan AI sedang bermasalah, coba lagi.';
      case 'image_too_large':
        return 'Gambar terlalu besar.';
      default:
        return 'Gagal mengenali gambar.';
    }
  }
}

final visualSearchRepositoryProvider =
    Provider<VisualSearchRepository>((ref) {
  return VisualSearchRepository(
    ref.watch(supabaseClientProvider),
    ref.watch(productRepositoryProvider),
  );
});
