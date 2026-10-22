import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
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
      await ref
          .read(authRepositoryProvider)
          .signIn(email: creds.email, password: creds.password);
      await ref.read(authNotifierProvider).refresh();
    } on AuthException {
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
      if (mounted) {
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
      await ref.read(authRepositoryProvider).signIn(
            email: _email.text.trim(),
            password: _password.text,
          );
      await ref.read(authNotifierProvider).refresh();
    } on AuthException catch (e) {
      setState(() => _error = e.message);
    } on BackendNotConfiguredException catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Masuk ke CekDulu')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (!SupabaseConfig.isConfigured) const BackendWarningBanner(),
              if (!SupabaseConfig.isConfigured) const SizedBox(height: 16),
              AppTextField(
                controller: _email,
                label: 'Email',
                keyboardType: TextInputType.emailAddress,
                validator: (v) =>
                    (v == null || !v.contains('@')) ? 'Email tidak valid' : null,
              ),
              AppTextField(
                controller: _password,
                label: 'Kata sandi',
                obscureText: !_showPassword,
                suffixIcon: IconButton(
                  icon: Icon(
                    _showPassword
                        ? Icons.visibility_off_outlined
                        : Icons.visibility_outlined,
                  ),
                  tooltip: _showPassword
                      ? 'Sembunyikan kata sandi'
                      : 'Tampilkan kata sandi',
                  onPressed: () =>
                      setState(() => _showPassword = !_showPassword),
                ),
                validator: (v) =>
                    (v == null || v.isEmpty) ? 'Kata sandi wajib diisi' : null,
              ),
              if (_error != null) ...[
                Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
                const SizedBox(height: 8),
              ],
              AppButton(label: 'Masuk', loading: _loading, onPressed: _login),
              if (_biometricAvailable) ...[
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: _loading ? null : _loginWithBiometric,
                  icon: const Icon(Icons.fingerprint),
                  label: const Text('Masuk dengan Sidik Jari'),
                ),
              ],
              TextButton(
                onPressed: () => context.go('/register'),
                child: const Text('Belum punya akun? Daftar'),
              ),
              TextButton(
                onPressed: () => context.go('/forgot-password'),
                child: const Text('Lupa password?'),
              ),
              const SizedBox(height: 16),
              if (_version.isNotEmpty)
                Text(
                  'CekDulu $_version',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.outline,
                      ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
