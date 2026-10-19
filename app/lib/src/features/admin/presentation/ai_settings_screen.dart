import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cekdulu/src/core/widgets/common_widgets.dart';
import 'package:cekdulu/src/features/admin/data/admin_repository.dart';

/// Pengaturan AI pengenalan gambar (admin saja).
///
/// API key bersifat write-only: ditulis via Edge Function `save-ai-secret`,
/// dienkripsi server-side, dan tidak pernah ditampilkan kembali.
/// Model (mis. "gemini-3.5-flash") disimpan plaintext dan bisa diubah.
class AiSettingsScreen extends ConsumerStatefulWidget {
  const AiSettingsScreen({super.key});

  @override
  ConsumerState<AiSettingsScreen> createState() => _AiSettingsScreenState();
}

class _AiSettingsScreenState extends ConsumerState<AiSettingsScreen> {
  final _formKey = GlobalKey<FormState>();
  final _apiKey = TextEditingController();
  final _model = TextEditingController(text: 'gemini-3.5-flash');
  bool _loading = false;
  bool _loadingData = true;
  bool _keyConfigured = false;
  String? _error;
  String? _info;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _apiKey.dispose();
    _model.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final data =
          await ref.read(adminRepositoryProvider).fetchAiCredentials();
      if (mounted && data != null) {
        final model = (data['model'] ?? '').toString();
        if (model.isNotEmpty) _model.text = model;
        // api_key tidak pernah dibaca kembali (write-only); kita hanya tahu
        // barisnya ada → key pernah dikonfigurasi.
        _keyConfigured = true;
      }
    } catch (e) {
      _error = e.toString();
    } finally {
      if (mounted) setState(() => _loadingData = false);
    }
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _loading = true;
      _error = null;
      _info = null;
    });
    try {
      await ref.read(adminRepositoryProvider).saveAiSecret(
            apiKey: _apiKey.text.trim(),
            model: _model.text.trim(),
          );
      if (mounted) {
        setState(() {
          _info = 'API key tersimpan (terenkripsi di server).';
          _keyConfigured = true;
          _apiKey.clear();
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('AI Pengenalan Gambar')),
      body: _loadingData
          ? const LoadingView()
          : SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text('Gemini API',
                        style: Theme.of(context).textTheme.titleMedium),
                    const SizedBox(height: 8),
                    Text(
                      _keyConfigured
                          ? 'Status: API key sudah dikonfigurasi ✓\nTempel key baru untuk mengganti.'
                          : 'Status: API key belum dikonfigurasi.',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    const SizedBox(height: 12),
                    AppTextField(
                      controller: _apiKey,
                      label: 'API Key Gemini',
                      obscureText: true,
                      helperText:
                          'Write-only: dienkripsi di server dan tidak pernah ditampilkan kembali.',
                      validator: (v) => (v == null || v.trim().isEmpty)
                          ? 'Wajib diisi'
                          : null,
                    ),
                    AppTextField(
                      controller: _model,
                      label: 'Model',
                      helperText:
                          'Contoh: gemini-3.5-flash (disarankan), gemini-3.8-flash.',
                      validator: (v) => (v == null || v.trim().isEmpty)
                          ? 'Wajib diisi'
                          : null,
                    ),
                    if (_error != null) ...[
                      Text(_error!,
                          style: TextStyle(
                              color: Theme.of(context).colorScheme.error)),
                      const SizedBox(height: 8),
                    ],
                    if (_info != null) ...[
                      Text(_info!),
                      const SizedBox(height: 8),
                    ],
                    AppButton(
                        label: 'Simpan', loading: _loading, onPressed: _save),
                    const SizedBox(height: 24),
                    Text('Cara kerja',
                        style: Theme.of(context).textTheme.titleMedium),
                    const SizedBox(height: 8),
                    const Text(
                      'Saat pengguna memakai "Cari dari foto", aplikasi mengirim '
                      'foto ke server. Server memanggil Gemini dengan API key ini '
                      'untuk menebak nama produk, lalu mencocokkannya dengan '
                      'katalog. API key tidak pernah keluar dari server.',
                    ),
                  ],
                ),
              ),
            ),
    );
  }
}
