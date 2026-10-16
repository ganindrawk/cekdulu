import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:cekdulu/src/core/config/supabase_config.dart';
import 'package:cekdulu/src/core/widgets/common_widgets.dart';
import 'package:cekdulu/src/features/auth/data/auth_repository.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class RegisterScreen extends ConsumerStatefulWidget {
  const RegisterScreen({super.key});

  @override
  ConsumerState<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends ConsumerState<RegisterScreen> {
  final _formKey = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  bool _loading = false;
  String? _error;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _register() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await ref.read(authRepositoryProvider).signUp(
            email: _email.text.trim(),
            password: _password.text,
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Daftar CekDulu')),
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
                label: 'Kata sandi (min. 6 karakter)',
                obscureText: true,
                validator: (v) => (v == null || v.length < 6)
                    ? 'Minimal 6 karakter'
                    : null,
              ),
              AppTextField(
                controller: _confirm,
                label: 'Konfirmasi kata sandi',
                obscureText: true,
                validator: (v) =>
                    v != _password.text ? 'Konfirmasi tidak sama' : null,
              ),
              if (_error != null) ...[
                Text(_error!,
                    style:
                        TextStyle(color: Theme.of(context).colorScheme.error)),
                const SizedBox(height: 8),
              ],
              AppButton(label: 'Daftar', loading: _loading, onPressed: _register),
              TextButton(
                onPressed: () => context.go('/login'),
                child: const Text('Sudah punya akun? Masuk'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
