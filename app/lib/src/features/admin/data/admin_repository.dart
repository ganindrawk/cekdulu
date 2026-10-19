import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cekdulu/src/core/config/supabase_config.dart';
import 'package:cekdulu/src/features/auth/data/auth_repository.dart';
import 'package:cekdulu/src/features/catalog/data/product.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Operasi khusus admin: kelola katalog, kredensial, link, pengguna.
class AdminRepository {
  AdminRepository(this._client);

  final SupabaseClient? _client;

  SupabaseClient get _c {
    final c = _client;
    if (c == null) throw const BackendNotConfiguredException();
    return c;
  }

  // --- Produk ---
  Future<List<Product>> fetchAllProducts() async {
    final rows = await _c.from('products').select().order('created_at', ascending: false);
    return (rows as List).map((e) => Product.fromMap(e as Map<String, dynamic>)).toList();
  }

  Future<void> upsertProduct(Product product, {String? id}) async {
    final data = product.toMap();
    if (id == null) {
      await _c.from('products').insert(data);
    } else {
      await _c.from('products').update(data).eq('id', id);
    }
  }

  Future<void> deleteProduct(String id) =>
      _c.from('products').delete().eq('id', id);

  // --- Kredensial affiliate ---
  //
  // Model keamanan: kolom "secret" bersifat WRITE-ONLY dan hanya ditulis
  // melalui Edge Function (belum diimplementasikan — TODO). Field lain
  // (app_id, affiliate_id, default_sub_id) disimpan via upsert biasa dan
  // hanya bisa dibaca admin (RLS).
  Future<Map<String, dynamic>?> fetchShopeeCredentials() async {
    return _c
        .from('affiliate_credentials_safe')
        .select()
        .eq('marketplace', 'shopee')
        .maybeSingle();
  }

  Future<void> saveShopeeCredentials({
    required String appId,
    required String affiliateId,
    required String defaultSubId,
  }) async {
    await _c.from('affiliate_credentials').upsert({
      'marketplace': 'shopee',
      'credentials': {
        'app_id': appId,
        'affiliate_id': affiliateId,
        'default_sub_id': defaultSubId,
      },
    }, onConflict: 'marketplace');
  }

  /// Menyimpan secret Shopee via Edge Function `save-affiliate-secret`.
  /// Secret bersifat write-only: dienkripsi server-side dan tidak pernah
  /// dibaca kembali. Jangan simpan secret via client biasa.
  Future<void> saveShopeeSecret(String secret) async {
    try {
      final res = await _c.functions.invoke(
        'save-affiliate-secret',
        body: {'marketplace': 'shopee', 'secret': secret},
      );
      if (res.status != 200) {
        throw Exception(
          'Edge Function mengembalikan status ${res.status}.',
        );
      }
    } on FunctionException catch (e) {
      throw Exception(
        'Gagal menyimpan secret: ${e.reasonPhrase ?? 'status ${e.status}'}.',
      );
    } catch (e) {
      throw Exception('Gagal menyimpan secret: $e');
    }
  }

  // --- Link affiliate manual (Shopee / Tokopedia) ---
  //
  // Link Shopee ditempel manual karena akses Shopee Open Platform API
  // dibatasi untuk akun ini; link Tokopedia memang selalu manual.
  Future<void> addAffiliateLink({
    required String productId,
    required String marketplace,
    required String originalUrl,
    required String affiliateUrl,
  }) async {
    assert(marketplace == 'shopee' || marketplace == 'tokopedia',
        'marketplace harus "shopee" atau "tokopedia"');
    await _c.from('affiliate_links').insert({
      'product_id': productId,
      'marketplace': marketplace,
      'original_url': originalUrl,
      'affiliate_url': affiliateUrl,
      'status': 'active',
      'created_by': _c.auth.currentUser?.id,
    });
  }

  // --- Kredensial AI (pengenalan gambar) ---
  //
  // Model keamanan: api_key bersifat WRITE-ONLY dan hanya ditulis melalui
  // Edge Function `save-ai-secret` (dienkripsi server-side). Field `model`
  // disimpan plaintext dan bisa dibaca admin via view ai_credentials_safe.
  Future<Map<String, dynamic>?> fetchAiCredentials() async {
    return _c
        .from('ai_credentials_safe')
        .select()
        .eq('provider', 'gemini')
        .maybeSingle();
  }

  /// Menyimpan API key AI via Edge Function `save-ai-secret`.
  /// Key bersifat write-only: dienkripsi server-side dan tidak pernah
  /// dibaca kembali. Jangan simpan key via client biasa.
  Future<void> saveAiSecret({
    required String apiKey,
    required String model,
  }) async {
    try {
      final res = await _c.functions.invoke(
        'save-ai-secret',
        body: {'provider': 'gemini', 'api_key': apiKey, 'model': model},
      );
      final data = res.data as Map<String, dynamic>?;
      if (res.status != 200 || data?['ok'] != true) {
        final code = data?['error']?.toString() ?? 'status ${res.status}';
        final detail = data?['detail']?.toString();
        throw Exception(
          'Gagal menyimpan API key ($code${detail != null ? ': $detail' : ''}).',
        );
      }
    } on FunctionException catch (e) {
      // Coba ambil kode error spesifik dari body respons.
      String code = 'status ${e.status}';
      String? detail;
      try {
        final details = e.details;
        if (details is Map) {
          if (details['error'] is String) code = details['error'] as String;
          if (details['detail'] is String) {
            detail = details['detail'] as String;
          }
        } else if (details is String && details.isNotEmpty) {
          // details kadang berupa string JSON.
          final m = RegExp(r'"error"\s*:\s*"([^"]+)"').firstMatch(details);
          if (m != null) code = m.group(1)!;
          final d = RegExp(r'"detail"\s*:\s*"([^"]+)"').firstMatch(details);
          if (d != null) detail = d.group(1)!;
        }
      } catch (_) {}
      throw Exception(
        'Gagal menyimpan API key ($code${detail != null ? ': $detail' : ''}).',
      );
    } catch (e) {
      if (e is Exception && e.toString().contains('Gagal menyimpan API key')) {
        rethrow;
      }
      throw Exception('Gagal menyimpan API key: $e');
    }
  }

  // --- Pengguna ---
  Future<List<Map<String, dynamic>>> fetchUsers() async {
    final rows = await _c
        .from('profiles')
        .select('id, email, role, created_at')
        .order('created_at', ascending: false);
    return (rows as List).cast<Map<String, dynamic>>();
  }

  Future<void> setUserRole(String userId, String role) async {
    assert(role == 'admin' || role == 'user');
    await _c.from('profiles').update({'role': role}).eq('id', userId);
  }
}

final adminRepositoryProvider = Provider<AdminRepository>((ref) {
  return AdminRepository(ref.watch(supabaseClientProvider));
});
