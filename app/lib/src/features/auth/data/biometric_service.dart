import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:local_auth/local_auth.dart';

/// Kredensial yang tersimpan aman untuk login sidik jari.
class SavedCredentials {
  const SavedCredentials({required this.email, required this.password});

  final String email;
  final String password;
}

final biometricServiceProvider =
    Provider<BiometricService>((_) => BiometricService());

/// Login sidik jari.
///
/// Cara kerja: sidik jari diverifikasi oleh sistem Android (data sidik
/// jari TIDAK pernah keluar dari HP / tidak disimpan di server).
/// Bila cocok, aplikasi memakai email + kata sandi yang tersimpan
/// terenkripsi (Android Keystore via flutter_secure_storage) untuk
/// masuk ke Supabase.
class BiometricService {
  BiometricService();

  final LocalAuthentication _auth = LocalAuthentication();
  final FlutterSecureStorage _storage = const FlutterSecureStorage();

  static const _kEnabled = 'biometric_enabled';
  static const _kEmail = 'biometric_email';
  static const _kPassword = 'biometric_password';

  /// HP mendukung biometrik dan ada sidik jari terdaftar di sistem.
  Future<bool> isDeviceSupported() async {
    try {
      if (!await _auth.isDeviceSupported()) return false;
      if (!await _auth.canCheckBiometrics) return false;
      final available = await _auth.getAvailableBiometrics();
      return available.isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  Future<bool> isEnabled() async =>
      (await _storage.read(key: _kEnabled)) == '1';

  /// Tampilkan dialog sidik jari sistem. true bila cocok.
  /// Melempar [Exception] berpesan ramah untuk kasus terkunci /
  /// belum terdaftar / tidak tersedia.
  Future<bool> authenticate(String reason) async {
    try {
      return await _auth.authenticate(
        localizedReason: reason,
        options: const AuthenticationOptions(
          stickyAuth: true,
          biometricOnly: true,
        ),
      );
    } on PlatformException catch (e) {
      throw Exception(_friendlyAuthError(e.code));
    }
  }

  String _friendlyAuthError(String code) {
    switch (code) {
      case 'NotEnrolled':
        return 'Belum ada sidik jari terdaftar di HP ini. '
            'Daftarkan dulu lewat Pengaturan Android.';
      case 'LockedOut':
      case 'PermanentlyLockedOut':
        return 'Sidik jari terkunci sementara. '
            'Coba lagi nanti atau masuk dengan kata sandi.';
      case 'NotAvailable':
      case 'OtherOperatingSystem':
        return 'Sidik jari tidak tersedia di HP ini.';
      case 'PasscodeNotSet':
        return 'Aktifkan kunci layar HP dulu untuk memakai sidik jari.';
      default:
        return 'Verifikasi sidik jari gagal. Coba lagi.';
    }
  }

  /// Simpan kredensial terenkripsi & aktifkan login sidik jari.
  Future<void> enable({
    required String email,
    required String password,
  }) async {
    await _storage.write(key: _kEmail, value: email);
    await _storage.write(key: _kPassword, value: password);
    await _storage.write(key: _kEnabled, value: '1');
  }

  /// Nonaktifkan & hapus kredensial tersimpan.
  Future<void> disable() async {
    await _storage.delete(key: _kEmail);
    await _storage.delete(key: _kPassword);
    await _storage.delete(key: _kEnabled);
  }

  Future<SavedCredentials?> savedCredentials() async {
    final email = await _storage.read(key: _kEmail);
    final password = await _storage.read(key: _kPassword);
    if (email == null || password == null) return null;
    return SavedCredentials(email: email, password: password);
  }
}
