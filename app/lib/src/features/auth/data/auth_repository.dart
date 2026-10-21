import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cekdulu/src/core/config/supabase_config.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Provider SupabaseClient; null saat backend belum dikonfigurasi.
final supabaseClientProvider = Provider<SupabaseClient?>((ref) {
  return SupabaseConfig.isConfigured ? SupabaseConfig.client : null;
});

/// Repository autentikasi memakai Supabase Auth.
class AuthRepository {
  AuthRepository(this._client);

  final SupabaseClient? _client;

  SupabaseClient get _c {
    final c = _client;
    if (c == null) throw const BackendNotConfiguredException();
    return c;
  }

  /// Daftar dengan email. Supabase mengirim email berisi kode OTP 6 digit;
  /// pengguna memasukkannya di layar verifikasi ([VerifyEmailScreen]).
  /// Sesi terbentuk otomatis setelah kode benar via [verifyEmailOtp].
  Future<void> signUp({required String email, required String password}) async {
    await _c.auth.signUp(email: email, password: password);
  }

  Future<void> signIn({required String email, required String password}) async {
    await _c.auth.signInWithPassword(email: email, password: password);
  }

  Future<void> signOut() async => _c.auth.signOut();

  Future<void> resendVerificationEmail(String email) async {
    await _c.auth.resend(type: OtpType.signup, email: email);
  }

  /// Verifikasi kode dari email. Berhasil = email terkonfirmasi
  /// dan sesi login terbentuk (didengar oleh AuthNotifier).
  Future<void> verifyEmailOtp({
    required String email,
    required String token,
  }) async {
    await _c.auth.verifyOTP(email: email, token: token, type: OtpType.signup);
  }

  /// Kirim email berisi kode OTP untuk reset password.
  /// Template email "Reset password" di Supabase harus menampilkan
  /// {{ .Token }} (seperti template signup) agar kode bisa dimasukkan
  /// manual di aplikasi.
  Future<void> sendPasswordResetOtp(String email) async {
    await _c.auth.resetPasswordForEmail(email);
  }

  /// Verifikasi kode reset dari email (tipe recovery), lalu langsung
  /// set password baru. Sesi recovery terbentuk otomatis setelah
  /// kode benar, sehingga updateUser diizinkan.
  Future<void> verifyRecoveryOtpAndSetPassword({
    required String email,
    required String token,
    required String newPassword,
  }) async {
    await _c.auth.verifyOTP(email: email, token: token, type: OtpType.recovery);
    await _c.auth.updateUser(UserAttributes(password: newPassword));
  }

  User? get currentUser => _client?.auth.currentUser;

  /// Ambil peran dari tabel profiles. Null jika belum ada / belum login.
  Future<String?> fetchRole() async {
    final user = currentUser;
    if (user == null) return null;
    final row = await _c
        .from('profiles')
        .select('role')
        .eq('id', user.id)
        .maybeSingle();
    return row?['role'] as String?;
  }
}

final authRepositoryProvider = Provider<AuthRepository>((ref) {
  return AuthRepository(ref.watch(supabaseClientProvider));
});
