import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cekdulu/src/core/widgets/common_widgets.dart';
import 'package:cekdulu/src/features/auth/data/auth_repository.dart';

/// Layar verifikasi email dengan kode dari email setelah registrasi.
///
/// Supabase mengirim kode verifikasi ke email pengguna (bukan tautan),
/// sehingga tidak butuh domain/Site URL. Kode dimasukkan di sini,
/// lalu sesi login terbentuk otomatis.
class VerifyEmailScreen extends ConsumerStatefulWidget {
  const VerifyEmailScreen({super.key, this.email});

  final String? email;

  @override
  ConsumerState<VerifyEmailScreen> createState() => _VerifyEmailScreenState();
}

class _VerifyEmailScreenState extends ConsumerState<VerifyEmailScreen> {
  final _codeController = TextEditingController();
  bool _verifying = false;
  bool _sending = false;
  String? _info;
  String? _error;

  @override
  void dispose() {
    _codeController.dispose();
    super.dispose();
  }

  Future<void> _verify() async {
    final email = widget.email;
    final code = _codeController.text.trim();
    if (email == null || email.isEmpty) {
      setState(() => _error = 'Email tidak diketahui. Silakan daftar ulang.');
      return;
    }
    if (code.length < 6) {
      setState(() => _error = 'Kode verifikasi minimal 6 karakter.');
      return;
    }
    setState(() {
      _verifying = true;
      _error = null;
      _info = null;
    });
    try {
      await ref
          .read(authRepositoryProvider)
          .verifyEmailOtp(email: email, token: code);
      // Sesi terbentuk -> AuthNotifier -> GoRouter mengarahkan otomatis
      // ke /home atau /admin.
    } catch (e) {
      setState(() => _error =
          'Kode salah atau kedaluwarsa. Periksa lagi atau kirim ulang kode.');
    } finally {
      if (mounted) setState(() => _verifying = false);
    }
  }

  Future<void> _resend() async {
    final email = widget.email;
    if (email == null || email.isEmpty) {
      setState(() => _error = 'Email tidak diketahui. Silakan daftar ulang.');
      return;
    }
    setState(() {
      _sending = true;
      _error = null;
      _info = null;
    });
    try {
      await ref.read(authRepositoryProvider).resendVerificationEmail(email);
      setState(() => _info = 'Kode baru dikirim ke $email.');
    } catch (e) {
      setState(() => _error = 'Gagal mengirim ulang: $e');
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Verifikasi Email')),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Icon(Icons.mark_email_read_outlined, size: 72),
            const SizedBox(height: 16),
            Text(
              'Masukkan kode verifikasi yang dikirim ke ${widget.email ?? 'email kamu'}.',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            TextField(
              controller: _codeController,
              keyboardType: TextInputType.text,
              textAlign: TextAlign.center,
              maxLength: 16,
              autocorrect: false,
              enableSuggestions: false,
              textCapitalization: TextCapitalization.characters,
              style: const TextStyle(
                fontSize: 28,
                letterSpacing: 8,
                fontWeight: FontWeight.bold,
              ),
              decoration: const InputDecoration(
                hintText: '••••••••',
                counterText: '',
                border: OutlineInputBorder(),
              ),
              onChanged: (_) {
                if (_error != null) setState(() => _error = null);
              },
            ),
            const SizedBox(height: 16),
            if (_error != null) ...[
              Text(
                _error!,
                textAlign: TextAlign.center,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
              const SizedBox(height: 12),
            ],
            if (_info != null) ...[
              Text(_info!, textAlign: TextAlign.center),
              const SizedBox(height: 12),
            ],
            AppButton(
              label: 'Verifikasi',
              loading: _verifying,
              onPressed: _verify,
            ),
            const SizedBox(height: 8),
            AppButton(
              label: 'Kirim ulang kode',
              loading: _sending,
              onPressed: _resend,
            ),
          ],
        ),
      ),
    );
  }
}
