import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:cekdulu/src/features/auth/data/auth_repository.dart';
import 'package:cekdulu/src/features/auth/data/biometric_service.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Setting sidik jari ala mockup (admin & user): saklar login sidik
/// jari, status sidik jari perangkat, keamanan, dan tips.
///
/// Logika tidak berubah: saklar memakai alur lama (konfirmasi kata
/// sandi -> pindai sekali -> kredensial tersimpan terenkripsi di HP).
/// "Pendaftaran sidik jari" di sini = mengaktifkan login sidik jari;
/// data sidik jari sendiri dikelola sistem Android, tidak disimpan
/// aplikasi/server — dan Android tidak memberi tahu aplikasi daftar
/// sidik jari per jari beserta tanggalnya, jadi kartu daftar
/// menampilkan status perangkat yang benar-benar bisa dibaca, bukan
/// daftar jari per jari seperti contoh di mockup.
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

  /// Tambah sidik jari: bila login belum aktif, jalankan alur
  /// pengaktifan; bila sudah aktif, penambahan jari lain hanya bisa
  /// lewat Pengaturan Android.
  Future<void> _addFingerprint() async {
    if (!_enabled) {
      await _enable();
      return;
    }
    _snack('Untuk menambah sidik jari lain, daftarkan lewat '
        'Pengaturan Android > Keamanan > Sidik jari.');
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
    return Scaffold(
      backgroundColor: Colors.white,
      body: Column(
        children: [
          _Header(onBack: () => context.pop()),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : SingleChildScrollView(
                    child: Column(
                      children: [
                        _LoginCard(
                          enabled: _enabled,
                          busy: _busy,
                          onToggle: _toggle,
                        ),
                        if (!_supported)
                          const Padding(
                            padding:
                                EdgeInsets.fromLTRB(16, 0, 16, 12),
                            child: Text(
                              'Catatan: HP ini belum ada sidik jari terdaftar. '
                              'Daftarkan lewat Pengaturan Android > Keamanan > '
                              'Sidik jari, lalu kembali ke sini.',
                              style: TextStyle(
                                  fontSize: 12,
                                  color: Color(0xFF8A8A8A)),
                            ),
                          ),
                        _ListCard(
                          supported: _supported,
                          enabled: _enabled,
                          onToggle: _toggle,
                          onAdd: _addFingerprint,
                        ),
                        const _SecurityCard(),
                        const _Decoration(),
                        const _TipsCard(),
                        const SizedBox(height: 16),
                      ],
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

/// Header oranye: kembali dan judul.
class _Header extends StatelessWidget {
  const _Header({required this.onBack});

  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFFFF6B35), Color(0xFFEE4D2D)],
        ),
        borderRadius: BorderRadius.only(
          bottomLeft: Radius.circular(28),
          bottomRight: Radius.circular(28),
        ),
      ),
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(8, 12, 16, 28),
          child: Row(
            children: [
              IconButton(
                tooltip: 'Kembali',
                icon: const Icon(Icons.arrow_back, color: Colors.white),
                onPressed: onBack,
              ),
              const Expanded(
                child: Text('Setting Sidik Jari',
                    style: TextStyle(
                        color: Colors.white,
                        fontSize: 22,
                        fontWeight: FontWeight.w800)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Kartu saklar login sidik jari.
class _LoginCard extends StatelessWidget {
  const _LoginCard({
    required this.enabled,
    required this.busy,
    required this.onToggle,
  });

  final bool enabled;
  final bool busy;
  final Future<void> Function(bool value) onToggle;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
      child: Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        elevation: 2,
        shadowColor: const Color(0xFFEE4D2D).withValues(alpha: 0.08),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Container(
                width: 56,
                height: 56,
                decoration: const BoxDecoration(
                  color: Color(0xFFFFF0E8),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.fingerprint,
                    size: 32, color: Color(0xFFEE4D2D)),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Login Sidik Jari',
                        style: TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFF262626))),
                    SizedBox(height: 2),
                    Text(
                        'Aktifkan sidik jari untuk masuk lebih cepat dan aman.',
                        style: TextStyle(
                            fontSize: 13, color: Color(0xFF8A8A8A))),
                  ],
                ),
              ),
              Switch(
                value: enabled,
                activeThumbColor: const Color(0xFFEE4D2D),
                onChanged: busy ? null : onToggle,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Kartu daftar sidik jari perangkat + tombol tambah.
class _ListCard extends StatelessWidget {
  const _ListCard({
    required this.supported,
    required this.enabled,
    required this.onToggle,
    required this.onAdd,
  });

  final bool supported;
  final bool enabled;
  final Future<void> Function(bool value) onToggle;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      child: Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        elevation: 2,
        shadowColor: const Color(0xFFEE4D2D).withValues(alpha: 0.08),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Daftar Sidik Jari',
                  style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF262626))),
              const SizedBox(height: 2),
              const Text(
                  'Kelola sidik jari yang terdaftar di perangkat ini.',
                  style:
                      TextStyle(fontSize: 13, color: Color(0xFF8A8A8A))),
              const SizedBox(height: 12),
              if (supported)
                Row(
                  children: [
                    Container(
                      width: 48,
                      height: 48,
                      decoration: const BoxDecoration(
                        color: Color(0xFFFFF0E8),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.fingerprint,
                          size: 26, color: Color(0xFFEE4D2D)),
                    ),
                    const SizedBox(width: 12),
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Sidik Jari Perangkat',
                              style: TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w700,
                                  color: Color(0xFF262626))),
                          SizedBox(height: 2),
                          Text('Terdeteksi di perangkat ini',
                              style: TextStyle(
                                  fontSize: 13,
                                  color: Color(0xFF8A8A8A))),
                        ],
                      ),
                    ),
                    PopupMenuButton<String>(
                      icon: const Icon(Icons.more_vert,
                          color: Color(0xFF8A8A8A)),
                      tooltip: 'Lainnya',
                      onSelected: (value) {
                        if (value == 'toggle') {
                          onToggle(!enabled);
                        }
                      },
                      itemBuilder: (context) => [
                        PopupMenuItem(
                          value: 'toggle',
                          child: Text(enabled
                              ? 'Nonaktifkan login sidik jari'
                              : 'Aktifkan login sidik jari'),
                        ),
                      ],
                    ),
                  ],
                )
              else
                const Text(
                  'Belum ada sidik jari terdaftar di perangkat ini. '
                  'Daftarkan lewat Pengaturan Android > Keamanan > '
                  'Sidik jari.',
                  style:
                      TextStyle(fontSize: 13, color: Color(0xFF8A8A8A)),
                ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: onAdd,
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('Tambah Sidik Jari',
                      style: TextStyle(fontWeight: FontWeight.w700)),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFFEE4D2D),
                    side: const BorderSide(color: Color(0xFFEE4D2D)),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Kartu keamanan (hanya tampil).
class _SecurityCard extends StatelessWidget {
  const _SecurityCard();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      child: Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        elevation: 2,
        shadowColor: const Color(0xFFEE4D2D).withValues(alpha: 0.08),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: const BoxDecoration(
                  color: Color(0xFFFFF0E8),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.shield_outlined,
                    size: 26, color: Color(0xFFEE4D2D)),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Keamanan',
                        style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFF262626))),
                    SizedBox(height: 2),
                    Text(
                        'Sidik jari hanya digunakan untuk login ke aplikasi CekDulu.',
                        style: TextStyle(
                            fontSize: 13, color: Color(0xFF8A8A8A))),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right, color: Color(0xFF8A8A8A)),
            ],
          ),
        ),
      ),
    );
  }
}

/// Dekorasi: sidik jari + gembok di atas bukit samar.
class _Decoration extends StatelessWidget {
  const _Decoration();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 110,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Positioned(
            left: 40,
            bottom: 16,
            child: Container(
              width: 130,
              height: 130,
              decoration: BoxDecoration(
                color: const Color(0xFFFFF0E8).withValues(alpha: 0.7),
                shape: BoxShape.circle,
              ),
            ),
          ),
          Positioned(
            right: 48,
            bottom: 8,
            child: Container(
              width: 100,
              height: 100,
              decoration: BoxDecoration(
                color: const Color(0xFFFFF0E8).withValues(alpha: 0.5),
                shape: BoxShape.circle,
              ),
            ),
          ),
          const Positioned(
            left: 56,
            top: 12,
            child: Icon(Icons.auto_awesome,
                size: 20, color: Color(0xFFFFB020)),
          ),
          const Positioned(
            right: 64,
            top: 20,
            child: Icon(Icons.star, size: 16, color: Color(0xFFFFB020)),
          ),
          Stack(
            clipBehavior: Clip.none,
            children: [
              Container(
                width: 72,
                height: 72,
                decoration: BoxDecoration(
                  color: Colors.white,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFFEE4D2D).withValues(alpha: 0.12),
                      blurRadius: 16,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: const Icon(Icons.fingerprint,
                    size: 40, color: Color(0xFFEE4D2D)),
              ),
              Positioned(
                right: -6,
                bottom: -2,
                child: Container(
                  width: 30,
                  height: 30,
                  decoration: const BoxDecoration(
                    color: Color(0xFFEE4D2D),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.lock,
                      size: 16, color: Colors.white),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Kartu tips.
class _TipsCard extends StatelessWidget {
  const _TipsCard();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      child: Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        elevation: 2,
        shadowColor: const Color(0xFFEE4D2D).withValues(alpha: 0.08),
        child: const Padding(
          padding: EdgeInsets.all(16),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.info_outline,
                  size: 24, color: Color(0xFFEE4D2D)),
              SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Tips',
                        style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFF262626))),
                    SizedBox(height: 2),
                    Text(
                        'Pastikan jari Anda bersih dan kering agar proses pengenalan lebih cepat dan akurat.',
                        style: TextStyle(
                            fontSize: 13, color: Color(0xFF8A8A8A))),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
