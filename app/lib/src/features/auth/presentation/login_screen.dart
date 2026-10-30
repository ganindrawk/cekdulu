import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:go_router/go_router.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:cekdulu/src/core/config/supabase_config.dart';
import 'package:cekdulu/src/core/widgets/common_widgets.dart';
import 'package:cekdulu/src/features/auth/data/auth_repository.dart';
import 'package:cekdulu/src/features/auth/data/biometric_service.dart';
import 'package:cekdulu/src/features/auth/presentation/auth_notifier.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _loading = false;
  bool _showPassword = false;
  bool _biometricAvailable = false;
  String? _error;
  String _version = '';

  /// Pesan yang tampil bila login gagal karena tidak ada internet.
  static const _offlineMessage = 'Jaringan Internet anda tidak aktif';

  /// True bila error ini berasal dari jaringan (bukan dari server/auth).
  /// Supabase membungkus SocketException ke dalam AuthException, jadi
  /// deteksi dilakukan dari teks error, bukan dari tipenya saja.
  bool _isNetworkError(Object e) {
    final msg = e.toString().toLowerCase();
    return msg.contains('socketexception') ||
        msg.contains('failed host lookup') ||
        msg.contains('network is unreachable') ||
        msg.contains('connection failed') ||
        msg.contains('connection refused') ||
        msg.contains('connection timed out') ||
        msg.contains('timeoutexception') ||
        msg.contains('no address associated') ||
        msg.contains('connection aborted') ||
        (msg.contains('clientexception') &&
            msg.contains('connection'));
  }

  /// Cek koneksi sebelum memanggil server. Catatan: hasil "wifi/seluler"
  /// tidak menjamin internet benar-benar jalan (mis. wifi tanpa
  /// internet) — karena itu [_isNetworkError] tetap jadi jaring pengaman
  /// bila koneksi putus di tengah permintaan.
  Future<bool> _hasInternet() async {
    try {
      final results = await Connectivity().checkConnectivity();
      return results.isNotEmpty &&
          !results.contains(ConnectivityResult.none);
    } catch (_) {
      // Bila pengecekan sendiri gagal, biarkan permintaan jalan dan
      // biarkan _isNetworkError yang menilai hasilnya.
      return true;
    }
  }

  /// Pop-up gaya SweetAlert untuk kondisi tanpa internet: ikon besar,
  /// pesan di tengah, tombol OK. Dipakai khusus untuk kasus offline
  /// (bukan untuk semua error login) agar pesannya langsung terlihat.
  Future<void> _showOfflineDialog() async {
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: const BoxDecoration(
                color: Color(0xFFFFF0E8),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.wifi_off,
                size: 44,
                color: _Shopee.orange,
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              _offlineMessage,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Periksa koneksi internet anda lalu coba lagi.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Color(0xFF757575)),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text(
              'OK',
              style: TextStyle(
                color: _Shopee.orange,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  void initState() {
    super.initState();
    _loadVersion();
    _checkBiometric();
  }

  Future<void> _checkBiometric() async {
    final bio = ref.read(biometricServiceProvider);
    final available = await bio.isEnabled() && await bio.isDeviceSupported();
    if (mounted) setState(() => _biometricAvailable = available);
  }

  /// Masuk memakai sidik jari: verifikasi sistem, lalu pakai kredensial
  /// terenkripsi yang tersimpan untuk masuk ke Supabase.
  Future<void> _loginWithBiometric() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final bio = ref.read(biometricServiceProvider);
      final ok = await bio.authenticate('Masuk ke CekDulu dengan sidik jari');
      if (!ok) {
        if (mounted) setState(() => _error = 'Sidik jari tidak cocok.');
        return;
      }
      final creds = await bio.savedCredentials();
      if (creds == null) {
        if (mounted) {
          setState(() => _error =
              'Data login sidik jari tidak ditemukan. Masuk dengan kata sandi.');
        }
        return;
      }
      if (!await _hasInternet()) {
        await _showOfflineDialog();
        return;
      }
      await ref
          .read(authRepositoryProvider)
          .signIn(email: creds.email, password: creds.password);
      await ref.read(authNotifierProvider).refresh();
    } on AuthException catch (e) {
      // Error jaringan juga terbungkus AuthException: jangan sampai
      // disangka kata sandi berubah (yang akan mematikan sidik jari).
      if (_isNetworkError(e)) {
        await _showOfflineDialog();
        return;
      }
      // Kata sandi tersimpan sudah berubah: matikan sidik jari agar
      // pengguna mengaktifkannya ulang dengan kata sandi baru.
      await ref.read(biometricServiceProvider).disable();
      if (mounted) {
        setState(() {
          _biometricAvailable = false;
          _error = 'Kata sandi sudah berubah. Masuk dengan kata sandi baru, '
              'lalu aktifkan lagi sidik jari di halaman akun.';
        });
      }
    } on Exception catch (e) {
      if (_isNetworkError(e)) {
        await _showOfflineDialog();
      } else if (mounted) {
        setState(
            () => _error = e.toString().replaceFirst('Exception: ', ''));
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _loadVersion() async {
    try {
      final info = await PackageInfo.fromPlatform();
      if (mounted) setState(() => _version = 'v${info.version}+${info.buildNumber}');
    } catch (_) {}
  }

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      if (!await _hasInternet()) {
        await _showOfflineDialog();
        return;
      }
      await ref.read(authRepositoryProvider).signIn(
            email: _email.text.trim(),
            password: _password.text,
          );
      await ref.read(authNotifierProvider).refresh();
    } on AuthException catch (e) {
      if (_isNetworkError(e)) {
        await _showOfflineDialog();
      } else {
        setState(() => _error = e.message);
      }
    } on BackendNotConfiguredException catch (e) {
      setState(() => _error = e.toString());
    } on Exception catch (e) {
      if (_isNetworkError(e)) {
        await _showOfflineDialog();
      } else if (mounted) {
        setState(
            () => _error = e.toString().replaceFirst('Exception: ', ''));
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFFFF6F1),
      body: Stack(
        children: [
          // Dekorasi latar: lingkaran lembut + gelombang oranye di bawah.
          const Positioned(
            top: -70,
            right: -50,
            child: _SoftCircle(size: 190, color: Color(0xFFFFE3D3)),
          ),
          const Positioned(
            top: 90,
            left: -80,
            child: _SoftCircle(size: 150, color: Color(0xFFFFEEE6)),
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            height: 150,
            child: CustomPaint(painter: _WavePainter()),
          ),
          SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const SizedBox(height: 8),
                  Image.asset(
                    'assets/images/cekdulu_logo.png',
                    height: 130,
                  ),
                  const SizedBox(height: 4),
                  const Text.rich(
                    TextSpan(
                      style: TextStyle(
                        fontSize: 40,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.5,
                      ),
                      children: [
                        TextSpan(
                          text: 'Cek',
                          style: TextStyle(color: Color(0xFF262626)),
                        ),
                        TextSpan(
                          text: 'Dulu',
                          style: TextStyle(color: _Shopee.orange),
                        ),
                      ],
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'Cari produk, cek kualitas,\nlangsung ke keranjang belanja.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Color(0xFF757575), height: 1.35),
                  ),
                  const SizedBox(height: 22),
                  Container(
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(28),
                      boxShadow: [
                        BoxShadow(
                          color: _Shopee.orange.withValues(alpha: 0.12),
                          blurRadius: 24,
                          offset: const Offset(0, 10),
                        ),
                      ],
                    ),
                    padding: const EdgeInsets.fromLTRB(20, 24, 20, 20),
                    child: Form(
                      key: _formKey,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          if (!SupabaseConfig.isConfigured)
                            const BackendWarningBanner(),
                          if (!SupabaseConfig.isConfigured)
                            const SizedBox(height: 16),
                          TextFormField(
                            controller: _email,
                            keyboardType: TextInputType.emailAddress,
                            decoration: _pillDecoration(
                              hint: 'Email',
                              icon: Icons.mail_outline,
                            ),
                            validator: (v) => (v == null || !v.contains('@'))
                                ? 'Email tidak valid'
                                : null,
                          ),
                          const SizedBox(height: 14),
                          TextFormField(
                            controller: _password,
                            obscureText: !_showPassword,
                            decoration: _pillDecoration(
                              hint: 'Kata sandi',
                              icon: Icons.lock_outline,
                              suffix: IconButton(
                                icon: Icon(
                                  _showPassword
                                      ? Icons.visibility_off_outlined
                                      : Icons.visibility_outlined,
                                  color: const Color(0xFF9E9E9E),
                                ),
                                tooltip: _showPassword
                                    ? 'Sembunyikan kata sandi'
                                    : 'Tampilkan kata sandi',
                                onPressed: () => setState(
                                    () => _showPassword = !_showPassword),
                              ),
                            ),
                            validator: (v) => (v == null || v.isEmpty)
                                ? 'Kata sandi wajib diisi'
                                : null,
                          ),
                          if (_error != null) ...[
                            const SizedBox(height: 12),
                            Text(
                              _error!,
                              style: TextStyle(
                                color: Theme.of(context).colorScheme.error,
                              ),
                            ),
                          ],
                          const SizedBox(height: 20),
                          _GradientButton(
                            loading: _loading,
                            onPressed: _login,
                          ),
                          if (_biometricAvailable) ...[
                            const SizedBox(height: 12),
                            SizedBox(
                              height: 52,
                              child: OutlinedButton.icon(
                                onPressed:
                                    _loading ? null : _loginWithBiometric,
                                icon: const Icon(Icons.fingerprint),
                                label:
                                    const Text('Masuk dengan Sidik Jari'),
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: _Shopee.orange,
                                  side: const BorderSide(
                                    color: _Shopee.orange,
                                    width: 1.4,
                                  ),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(30),
                                  ),
                                ),
                              ),
                            ),
                          ],
                          const SizedBox(height: 18),
                          Row(
                            children: [
                              const Expanded(child: Divider()),
                              const SizedBox(width: 12),
                              const Text(
                                'Belum punya akun?',
                                style: TextStyle(color: Color(0xFF757575)),
                              ),
                              const SizedBox(width: 4),
                              InkWell(
                                onTap: () => context.go('/register'),
                                child: const Text(
                                  'Daftar',
                                  style: TextStyle(
                                    color: _Shopee.orange,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 12),
                              const Expanded(child: Divider()),
                            ],
                          ),
                          const SizedBox(height: 6),
                          TextButton(
                            onPressed: () => context.go('/forgot-password'),
                            child: const Text(
                              'Lupa password?',
                              style: TextStyle(
                                color: _Shopee.orange,
                                fontWeight: FontWeight.w600,
                                decoration: TextDecoration.underline,
                                decorationColor: _Shopee.orange,
                              ),
                            ),
                          ),
                          if (_version.isNotEmpty) ...[
                            const SizedBox(height: 4),
                            Text(
                              'CekDulu $_version',
                              textAlign: TextAlign.center,
                              style: Theme.of(context)
                                  .textTheme
                                  .bodySmall
                                  ?.copyWith(
                                    color:
                                        Theme.of(context).colorScheme.outline,
                                  ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Dekorasi field berbentuk pil ala mockup: ikon kiri oranye,
  /// latar abu sangat muda, sudut membulat penuh.
  InputDecoration _pillDecoration({
    required String hint,
    required IconData icon,
    Widget? suffix,
  }) {
    final border = OutlineInputBorder(
      borderRadius: BorderRadius.circular(30),
      borderSide: const BorderSide(color: Color(0xFFEEEEEE)),
    );
    return InputDecoration(
      hintText: hint,
      prefixIcon: Icon(icon, color: _Shopee.orange),
      suffixIcon: suffix,
      filled: true,
      fillColor: const Color(0xFFF8F8F8),
      border: border,
      enabledBorder: border,
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(30),
        borderSide: const BorderSide(color: _Shopee.orange, width: 1.5),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(30),
        borderSide: const BorderSide(color: Colors.redAccent),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(30),
        borderSide: const BorderSide(color: Colors.redAccent, width: 1.5),
      ),
      contentPadding:
          const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
    );
  }
}

/// Palet warna ala Shopee.
class _Shopee {
  static const orange = Color(0xFFEE4D2D);
  static const orangeLight = Color(0xFFFF7337);
}

/// Lingkaran dekorasi latar.
class _SoftCircle extends StatelessWidget {
  const _SoftCircle({required this.size, required this.color});

  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
    );
  }
}

/// Tombol utama gradasi oranye berbentuk pil.
class _GradientButton extends StatelessWidget {
  const _GradientButton({required this.loading, required this.onPressed});

  final bool loading;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 54,
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [_Shopee.orangeLight, _Shopee.orange],
        ),
        borderRadius: BorderRadius.circular(30),
        boxShadow: [
          BoxShadow(
            color: _Shopee.orange.withValues(alpha: 0.35),
            blurRadius: 12,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(30),
          onTap: loading ? null : onPressed,
          child: Center(
            child: loading
                ? const SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(
                      color: Colors.white,
                      strokeWidth: 2.5,
                    ),
                  )
                : const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'Masuk',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      SizedBox(width: 8),
                      Icon(Icons.arrow_forward, color: Colors.white, size: 20),
                    ],
                  ),
          ),
        ),
      ),
    );
  }
}

/// Gelombang oranye dua lapis di bagian bawah layar.
class _WavePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final back = Path()
      ..moveTo(0, size.height * 0.42)
      ..quadraticBezierTo(
        size.width * 0.30,
        size.height * 0.02,
        size.width * 0.62,
        size.height * 0.38,
      )
      ..quadraticBezierTo(
        size.width * 0.85,
        size.height * 0.62,
        size.width,
        size.height * 0.42,
      )
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();
    canvas.drawPath(back, Paint()..color = const Color(0xFFFFCDB8));

    final front = Path()
      ..moveTo(0, size.height * 0.66)
      ..quadraticBezierTo(
        size.width * 0.35,
        size.height * 0.26,
        size.width * 0.70,
        size.height * 0.58,
      )
      ..quadraticBezierTo(
        size.width * 0.88,
        size.height * 0.78,
        size.width,
        size.height * 0.64,
      )
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();
    final paint = Paint()
      ..shader = const LinearGradient(
        colors: [_Shopee.orangeLight, _Shopee.orange],
      ).createShader(Offset.zero & size);
    canvas.drawPath(front, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
