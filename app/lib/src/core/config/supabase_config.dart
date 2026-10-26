import 'package:supabase_flutter/supabase_flutter.dart';

/// Konfigurasi Supabase.
///
/// Nilai diambil dari `--dart-define`; default kosong (mode scaffold tanpa
/// backend). JANGAN pernah hardcode URL/key di source code.
///
/// Contoh menjalankan aplikasi:
/// ```sh
/// flutter run \
///   --dart-define=SUPABASE_URL=https://xyz.supabase.co \
///   --dart-define=SUPABASE_ANON_KEY=eyJhbGciOi...
/// ```
class SupabaseConfig {
  static const String url =
      String.fromEnvironment('SUPABASE_URL', defaultValue: '');
  static const String anonKey =
      String.fromEnvironment('SUPABASE_ANON_KEY', defaultValue: '');

  /// True jika kredensial backend tersedia.
  static bool get isConfigured => url.isNotEmpty && anonKey.isNotEmpty;

  static Future<void> initialize() async {
    if (!isConfigured) {
      // Mode scaffold: UI bisa dibuka tanpa backend.
      return;
    }
    await Supabase.initialize(url: url, publishableKey: anonKey);
  }

  static SupabaseClient get client => Supabase.instance.client;
}

/// Dilempar repository ketika backend belum dikonfigurasi.
class BackendNotConfiguredException implements Exception {
  const BackendNotConfiguredException();

  @override
  String toString() =>
      'Backend belum dikonfigurasi. Jalankan dengan --dart-define=SUPABASE_URL dan --dart-define=SUPABASE_ANON_KEY.';
}
