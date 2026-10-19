import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:cekdulu/src/core/widgets/common_widgets.dart';
import 'package:cekdulu/src/features/auth/data/auth_repository.dart';

/// Layar reset password: masukkan kode dari email + password baru.
///
/// Sesi recovery terbentuk otomatis setelah kode benar, lalu password
/// langsung diperbarui.
class ResetPasswordScreen extends ConsumerStatefulWidget {
  const ResetPasswordScreen({super.key, this.email});

  final String? email;

  @override
  ConsumerState<ResetPasswordScreen> createState() =>
      _ResetPasswordScreenState();
}

class _ResetPasswordScreenState extends ConsumerState<ResetPasswordScreen> {
  final _formKey = GlobalKey<FormState>();
  final _code = TextEditingController();
  final _password = TextEditingController();
  final _passwordConfirm = TextEditingController();
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _code.dispose();
    _password.dispose();
    _passwordConfirm.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    final email = widget.email;
    if (email == null || email.isEmpty) {
      setState(() => _error = 'Email tidak diketahui. Ulangi dari awal.');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await ref.read(authRepositoryProvider).verifyRecoveryOtpAndSetPassword(
            email: email,
            token: _code.text.trim(),
            newPassword: _password.text,
          );
      // Sesi terbentuk -> AuthNotifier -> GoRouter mengarahkan otomatis.
      if (mounted) context.go('/login');
    } catch (e) {
      setState(() => _error =
          'Kode salah atau kedaluwarsa. Periksa lagi atau kirim ulang kode.');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Reset Password')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Masukkan kode dari email yang dikirim ke ${widget.email ?? 'email kamu'}, lalu buat password baru.',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              TextField(
                controller: _code,
                keyboardType: TextInputType.text,
                textAlign: TextAlign.center,
                maxLength: 16,
                autocorrect: false,
                enableSuggestions: false,
                textCapitalization: TextCapitalization.characters,
                style: const TextStyle(
                  fontSize: 24,
                  letterSpacing: 6,
                  fontWeight: FontWeight.bold,
                ),
                decoration: const InputDecoration(
                  labelText: 'Kode dari email',
                  hintText: '••••••••',
                  counterText: '',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 16),
              AppTextField(
                controller: _password,
                label: 'Password baru',
                obscureText: true,
                validator: (v) => (v == null || v.length < 6)
                    ? 'Minimal 6 karakter'
                    : null,
              ),
              AppTextField(
                controller: _passwordConfirm,
                label: 'Ulangi password baru',
                obscureText: true,
                validator: (v) => v != _password.text
                    ? 'Password tidak sama'
                    : null,
              ),
              if (_error != null) ...[
                Text(_error!,
                    textAlign: TextAlign.center,
                    style:
                        TextStyle(color: Theme.of(context).colorScheme.error)),
                const SizedBox(height: 8),
              ],
              AppButton(
                label: 'Simpan password baru',
                loading: _saving,
                onPressed: _save,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
