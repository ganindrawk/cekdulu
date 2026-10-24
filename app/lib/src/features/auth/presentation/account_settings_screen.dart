import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cekdulu/src/features/auth/data/auth_repository.dart';
import 'package:cekdulu/src/features/auth/data/biometric_service.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Pengaturan akun pengguna (admin & user): info akun, pendaftaran
/// login sidik jari, dan keluar.
///
/// "Pendaftaran sidik jari" di sini = mengaktifkan login sidik jari:
/// pengguna mengonfirmasi kata sandi, memindai sidik jari sekali,
/// lalu kredensial tersimpan terenkripsi di HP. Data sidik jari
/// sendiri dikelola sistem Android, tidak disimpan aplikasi/server.
class AccountSettingsScreen extends ConsumerStatefulWidget {
  const AccountSettingsScreen({super.key});

  @override
  ConsumerState<AccountSettingsScreen> createState() =>
      _AccountSettingsScreenState();
}

class _AccountSettingsScreenState
    extends ConsumerState<AccountSettingsScreen> {
  bool _loading = true;
  bool _supported = false;
  bool _enabled = false;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final bio = ref.read(biometricServiceProvider);
    final supported = await bio.isDeviceSupported();
    final enabled = await bio.isEnabled();
    if (mounted) {
      setState(() {
        _supported = supported;
        _enabled = enabled;
        _loading = false;
      });
    }
  }

  void _snack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _toggle(bool value) async {
    if (value) {
      await _enable();
    } else {
      await ref.read(biometricServiceProvider).disable();
      if (mounted) setState(() => _enabled = false);
      _snack('Login sidik jari dinonaktifkan.');
    }
  }

  Future<void> _enable() async {
    final bio = ref.read(biometricServiceProvider);
    if (!_supported) {
      _snack('HP ini belum mendukung / belum ada sidik jari terdaftar. '
          'Daftarkan sidik jari di Pengaturan Android dulu.');
      return;
    }
    final email = ref.read(authRepositoryProvider).currentUser?.email;
    if (email == null) {
      _snack('Email pengguna tidak ditemukan. Coba masuk ulang.');
      return;
    }
    // Konfirmasi kata sandi dulu agar yang disimpan benar.
    final password = await _askPassword();
    if (password == null || !mounted) return;
    setState(() => _busy = true);
    try {
      await ref
          .read(authRepositoryProvider)
          .signIn(email: email, password: password);
      final ok = await bio.authenticate(
          'Aktifkan login sidik jari untuk CekDulu');
      if (!ok) {
        _snack('Sidik jari tidak cocok — pengaktifan dibatalkan.');
        return;
      }
      await bio.enable(email: email, password: password);
      if (mounted) setState(() => _enabled = true);
      _snack('Login sidik jari aktif. Lain kali bisa masuk tanpa kata sandi.');
    } on AuthException {
      _snack('Kata sandi salah. Coba lagi.');
    } on Exception catch (e) {
      _snack(e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Dialog konfirmasi kata sandi (dengan icon mata untuk mengintip).
  Future<String?> _askPassword() {
    final controller = TextEditingController();
    var show = false;
    return showDialog<String>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          title: const Text('Konfirmasi Kata Sandi'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Masukkan kata sandi akunmu untuk mengaktifkan '
                'login sidik jari.',
              ),
              const SizedBox(height: 12),
              TextField(
                controller: controller,
                obscureText: !show,
                autofocus: true,
                decoration: InputDecoration(
                  labelText: 'Kata sandi',
                  border: const OutlineInputBorder(),
                  suffixIcon: IconButton(
                    icon: Icon(show
                        ? Icons.visibility_off_outlined
                        : Icons.visibility_outlined),
                    onPressed: () => setLocal(() => show = !show),
                  ),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('Batal'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(ctx).pop(controller.text),
              child: const Text('Lanjut'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(authRepositoryProvider).currentUser;
    return Scaffold(
      appBar: AppBar(title: const Text('Akun & Sidik Jari')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              children: [
                ListTile(
                  leading: const Icon(Icons.account_circle_outlined),
                  title: Text(user?.email ?? '-'),
                  subtitle: const Text('Email akun yang sedang masuk'),
                ),
                const Divider(),
                SwitchListTile(
                  secondary: const Icon(Icons.fingerprint),
                  title: const Text('Login Sidik Jari'),
                  subtitle: Text(
                    _enabled
                        ? 'Aktif — masuk cukup dengan sidik jari.'
                        : 'Nonaktif — aktifkan untuk masuk tanpa kata sandi.',
                  ),
                  value: _enabled,
                  onChanged: _busy ? null : _toggle,
                ),
                if (!_supported)
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 16),
                    child: Text(
                      'Catatan: HP ini belum ada sidik jari terdaftar. '
                      'Daftarkan lewat Pengaturan Android > Keamanan > '
                      'Sidik jari, lalu kembali ke sini.',
                      style: TextStyle(fontSize: 12),
                    ),
                  ),
                const Divider(),
                ListTile(
                  leading: const Icon(Icons.logout),
                  title: const Text('Keluar'),
                  onTap: () async {
                    await ref.read(authRepositoryProvider).signOut();
                  },
                ),
              ],
            ),
    );
  }
}
