import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:cekdulu/src/core/config/supabase_config.dart';
import 'package:cekdulu/src/core/widgets/common_widgets.dart';
import 'package:cekdulu/src/features/admin/presentation/admin_form_widgets.dart';
import 'package:cekdulu/src/features/auth/data/auth_repository.dart';
import 'package:cekdulu/src/features/auth/presentation/auth_form_widgets.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class RegisterScreen extends ConsumerStatefulWidget {
  const RegisterScreen({super.key});

  @override
  ConsumerState<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends ConsumerState<RegisterScreen> {
  final _formKey = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _name = TextEditingController();
  final _phone = TextEditingController();
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  bool _loading = false;
  bool _obscurePassword = true;
  bool _obscureConfirm = true;
  bool _agreed = true;
  String? _error;

  @override
  void dispose() {
    _email.dispose();
    _name.dispose();
    _phone.dispose();
    _password.dispose();
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _register() async {
    if (!_agreed) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Setujui Syarat & Ketentuan dulu ya.')),
      );
      return;
    }
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await ref.read(authRepositoryProvider).signUp(
            email: _email.text.trim(),
            password: _password.text,
            fullName: _name.text.trim(),
            phone: _phone.text.trim(),
          );
      if (mounted) context.go('/verify-email', extra: _email.text.trim());
    } on AuthException catch (e) {
      setState(() => _error = e.message);
    } on BackendNotConfiguredException catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _socialComingSoon(String provider) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Daftar dengan $provider belum tersedia.')),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: ShopeePalette.cream,
      body: Column(
        children: [
          AdminFormHeader(
            title: 'Daftar',
            subtitle: 'Buat akun CekDulu sekarang dan nikmati semua fiturnya!',
            onBack: () => context.go('/login'),
            decorations: const [
              Positioned(
                right: 40,
                top: 16,
                child: Icon(Icons.contact_page_outlined,
                    size: 72, color: Colors.white24),
              ),
              Positioned(
                right: 14,
                top: 62,
                child: Icon(Icons.add_circle,
                    size: 30, color: Colors.white24),
              ),
            ],
          ),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (!SupabaseConfig.isConfigured)
                      const BackendWarningBanner(),
                    if (!SupabaseConfig.isConfigured)
                      const SizedBox(height: 16),
                    AdminFieldRow(
                      icon: Icons.mail_outline,
                      label: 'Email',
                      child: TextFormField(
                        controller: _email,
                        keyboardType: TextInputType.emailAddress,
                        decoration: adminInputDecoration(
                            hintText: 'Masukkan email aktif Anda'),
                        validator: (v) => (v == null || !v.contains('@'))
                            ? 'Email tidak valid'
                            : null,
                      ),
                    ),
                    const SizedBox(height: 16),
                    AdminFieldRow(
                      icon: Icons.person_outline,
                      label: 'Nama Lengkap',
                      child: TextFormField(
                        controller: _name,
                        decoration: adminInputDecoration(
                            hintText: 'Contoh: Budi Santoso'),
                      ),
                    ),
                    const SizedBox(height: 16),
                    AdminFieldRow(
                      icon: Icons.phone_android_outlined,
                      label: 'No. Handphone',
                      child: TextFormField(
                        controller: _phone,
                        keyboardType: TextInputType.phone,
                        decoration: adminInputDecoration(
                            hintText: 'Contoh: 0812 3456 7890'),
                      ),
                    ),
                    const SizedBox(height: 16),
                    AdminFieldRow(
                      icon: Icons.lock_outline,
                      label: 'Password',
                      child: TextFormField(
                        controller: _password,
                        obscureText: _obscurePassword,
                        decoration: adminInputDecoration(
                                hintText: 'Minimal 6 karakter')
                            .copyWith(
                          suffixIcon: IconButton(
                            icon: Icon(
                                _obscurePassword
                                    ? Icons.visibility_off_outlined
                                    : Icons.visibility_outlined,
                                color: ShopeePalette.grey),
                            onPressed: () => setState(() =>
                                _obscurePassword = !_obscurePassword),
                          ),
                        ),
                        validator: (v) => (v == null || v.length < 6)
                            ? 'Minimal 6 karakter'
                            : null,
                      ),
                    ),
                    const SizedBox(height: 16),
                    AdminFieldRow(
                      icon: Icons.lock_outline,
                      label: 'Konfirmasi Password',
                      child: TextFormField(
                        controller: _confirm,
                        obscureText: _obscureConfirm,
                        decoration: adminInputDecoration(
                                hintText: 'Ulangi password Anda')
                            .copyWith(
                          suffixIcon: IconButton(
                            icon: Icon(
                                _obscureConfirm
                                    ? Icons.visibility_off_outlined
                                    : Icons.visibility_outlined,
                                color: ShopeePalette.grey),
                            onPressed: () => setState(
                                () => _obscureConfirm = !_obscureConfirm),
                          ),
                        ),
                        validator: (v) => v != _password.text
                            ? 'Konfirmasi tidak sama'
                            : null,
                      ),
                    ),
                    const SizedBox(height: 16),
                    InkWell(
                      borderRadius: BorderRadius.circular(8),
                      onTap: () =>
                          setState(() => _agreed = !_agreed),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          SizedBox(
                            width: 24,
                            height: 24,
                            child: Checkbox(
                              value: _agreed,
                              activeColor: ShopeePalette.orange,
                              materialTapTargetSize:
                                  MaterialTapTargetSize.shrinkWrap,
                              onChanged: (v) =>
                                  setState(() => _agreed = v ?? false),
                            ),
                          ),
                          const SizedBox(width: 8),
                          const Expanded(
                            child: Text.rich(
                              TextSpan(
                                text: 'Saya menyetujui ',
                                style: TextStyle(
                                    fontSize: 14,
                                    color: ShopeePalette.dark),
                                children: [
                                  TextSpan(
                                      text: 'Syarat & Ketentuan',
                                      style: TextStyle(
                                          color: ShopeePalette.orange,
                                          fontWeight: FontWeight.w700)),
                                  TextSpan(text: ' dan '),
                                  TextSpan(
                                      text: 'Kebijakan Privasi',
                                      style: TextStyle(
                                          color: ShopeePalette.orange,
                                          fontWeight: FontWeight.w700)),
                                  TextSpan(text: ' CekDulu'),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (_error != null) ...[
                      const SizedBox(height: 12),
                      Text(_error!,
                          style: const TextStyle(color: Colors.red)),
                    ],
                    const SizedBox(height: 20),
                    AdminGradientButton(
                      label: 'Daftar',
                      showArrow: false,
                      loading: _loading,
                      onPressed: _register,
                    ),
                    const SizedBox(height: 20),
                    const OrDivider(text: 'Atau daftar dengan'),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        SocialButton(
                          leading: const Text('G',
                              style: TextStyle(
                                  fontSize: 22,
                                  fontWeight: FontWeight.w800,
                                  color: Color(0xFF4285F5))),
                          label: 'Google',
                          onTap: () => _socialComingSoon('Google'),
                        ),
                        const SizedBox(width: 12),
                        SocialButton(
                          leading: const Icon(Icons.apple,
                              size: 24, color: Colors.black),
                          label: 'Apple',
                          onTap: () => _socialComingSoon('Apple'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Text('Sudah punya akun? ',
                            style: TextStyle(
                                fontSize: 14, color: ShopeePalette.grey)),
                        GestureDetector(
                          onTap: () => context.go('/login'),
                          child: const Text('Masuk',
                              style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w700,
                                  color: ShopeePalette.orange)),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    const AuthHills(
                      height: 110,
                      icons: [
                        Positioned(
                          left: 20,
                          bottom: 36,
                          child: Icon(Icons.shopping_cart_outlined,
                              size: 44, color: Colors.white38),
                        ),
                        Positioned(
                          left: 84,
                          bottom: 16,
                          child: Icon(Icons.shopping_bag_outlined,
                              size: 40, color: Colors.white38),
                        ),
                        Positioned(
                          right: 24,
                          bottom: 22,
                          child: Icon(Icons.percent_outlined,
                              size: 30, color: Colors.white38),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
