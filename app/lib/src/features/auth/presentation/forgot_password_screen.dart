import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:cekdulu/src/features/admin/presentation/admin_form_widgets.dart';
import 'package:cekdulu/src/features/auth/data/auth_repository.dart';
import 'package:cekdulu/src/features/auth/presentation/auth_form_widgets.dart';

/// Layar "Lupa password": masukkan email, kirim kode reset via email.
class ForgotPasswordScreen extends ConsumerStatefulWidget {
  const ForgotPasswordScreen({super.key});

  @override
  ConsumerState<ForgotPasswordScreen> createState() =>
      _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends ConsumerState<ForgotPasswordScreen> {
  final _formKey = GlobalKey<FormState>();
  final _email = TextEditingController();
  bool _sending = false;
  String? _error;

  @override
  void dispose() {
    _email.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _sending = true;
      _error = null;
    });
    try {
      await ref
          .read(authRepositoryProvider)
          .sendPasswordResetOtp(_email.text.trim());
      if (mounted) {
        context.push('/forgot-password/reset', extra: _email.text.trim());
      }
    } catch (e) {
      setState(() => _error = 'Gagal mengirim email: $e');
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: ShopeePalette.cream,
      body: Column(
        children: [
          AdminFormHeader(
            title: 'Lupa Password',
            subtitle: 'Masukkan email Anda untuk mengatur ulang password.',
            onBack: () => context.go('/login'),
            decorations: const [
              Positioned(
                right: 48,
                top: 14,
                child: Icon(Icons.mail_outlined,
                    size: 72, color: Colors.white24),
              ),
              Positioned(
                right: 16,
                top: 58,
                child: Icon(Icons.refresh, size: 28, color: Colors.white24),
              ),
            ],
          ),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 28, 20, 0),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Ilustrasi amplop + badge refresh.
                    Center(
                      child: Stack(
                        clipBehavior: Clip.none,
                        children: [
                          Container(
                            width: 150,
                            height: 150,
                            decoration: const BoxDecoration(
                              color: Color(0xFFFFF0E8),
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(Icons.mail_outline,
                                size: 76, color: ShopeePalette.orange),
                          ),
                          Positioned(
                            right: -2,
                            bottom: 8,
                            child: Container(
                              width: 52,
                              height: 52,
                              decoration: const BoxDecoration(
                                color: ShopeePalette.orange,
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(Icons.refresh,
                                  size: 30, color: Colors.white),
                            ),
                          ),
                          const Positioned(
                            left: -14,
                            top: 22,
                            child: Icon(Icons.star,
                                size: 20, color: Color(0xFFFFB020)),
                          ),
                          const Positioned(
                            right: -10,
                            top: 8,
                            child: Icon(Icons.star,
                                size: 16, color: Color(0xFFFFB020)),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 28),
                    AdminFieldRow(
                      icon: Icons.mail_outline,
                      label: 'Email',
                      child: TextFormField(
                        controller: _email,
                        keyboardType: TextInputType.emailAddress,
                        decoration: adminInputDecoration(
                            hintText: 'Masukkan email yang terdaftar'),
                        validator: (v) => (v == null || !v.contains('@'))
                            ? 'Email tidak valid'
                            : null,
                      ),
                    ),
                    if (_error != null) ...[
                      const SizedBox(height: 12),
                      Text(_error!,
                          textAlign: TextAlign.center,
                          style: const TextStyle(color: Colors.red)),
                    ],
                    const SizedBox(height: 20),
                    AdminGradientButton(
                      label: 'Kirim Kode Reset',
                      showArrow: false,
                      loading: _sending,
                      onPressed: _send,
                    ),
                    const SizedBox(height: 20),
                    const OrDivider(text: 'Atau'),
                    const SizedBox(height: 20),
                    SizedBox(
                      height: 52,
                      child: OutlinedButton.icon(
                        onPressed: () => context.go('/login'),
                        icon: const Icon(Icons.arrow_back,
                            color: ShopeePalette.orange),
                        label: const Text('Kembali ke Masuk',
                            style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w700,
                                color: ShopeePalette.orange)),
                        style: OutlinedButton.styleFrom(
                          side: const BorderSide(
                              color: ShopeePalette.orange, width: 1.5),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(30)),
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),
                    const Text(
                      'Kami akan mengirimkan kode reset password melalui email Anda.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                          fontSize: 13.5,
                          color: ShopeePalette.grey,
                          height: 1.4),
                    ),
                    const SizedBox(height: 8),
                    const AuthHills(
                      height: 130,
                      icons: [
                        Positioned(
                          left: 24,
                          bottom: 40,
                          child: Icon(Icons.shopping_cart_outlined,
                              size: 44, color: Colors.white38),
                        ),
                        Positioned(
                          left: 88,
                          bottom: 18,
                          child: Icon(Icons.shopping_bag_outlined,
                              size: 40, color: Colors.white38),
                        ),
                        Positioned(
                          right: 24,
                          bottom: 44,
                          child: Icon(Icons.lock_outline,
                              size: 52, color: Colors.white38),
                        ),
                        Positioned(
                          right: 88,
                          bottom: 20,
                          child: Icon(Icons.star,
                              size: 20, color: Colors.white38),
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
