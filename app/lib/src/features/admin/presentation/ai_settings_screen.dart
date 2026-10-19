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
  String? _model; // null = belum dipilih; muncul setelah API key diisi
  bool _obscureKey = true;
  bool _loading = false;
  bool _loadingData = true;
  bool _keyConfigured = false;
  String? _error;
  String? _info;

  static const _models = [
    'gemini-3.5-flash',
    'gemini-3.6-flash',
    'gemini-3.8-flash',
    'gemini-3.5-flash-lite',
  ];

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _apiKey.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final data =
          await ref.read(adminRepositoryProvider).fetchAiCredentials();
      if (mounted && data != null) {
        final model = (data['model'] ?? '').toString();
        if (model.isNotEmpty && _models.contains(model)) _model = model;
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
    if (!_formKey.currentState!.validate()) return;    setState(() {
      _loading = true;
      _error = null;
      _info = null;
    });
    try {
      await ref.read(adminRepositoryProvider).saveAiSecret(
            apiKey: _apiKey.text.trim(),
            model: _model ?? 'gemini-3.5-flash',
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
                    TextFormField(
                      controller: _apiKey,
                      obscureText: _obscureKey,
                      decoration: InputDecoration(
                        labelText: 'API Key Gemini',
                        helperText:
                            'Write-only: dienkripsi di server dan tidak pernah ditampilkan kembali.',
                        border: const OutlineInputBorder(),
                        suffixIcon: IconButton(
                          icon: Icon(
                            _obscureKey
                                ? Icons.visibility_off
                                : Icons.visibility,
                          ),
                          onPressed: () => setState(
                            () => _obscureKey = !_obscureKey,
                          ),
                        ),
                      ),
                      validator: (v) => (v == null || v.trim().isEmpty)
                          ? 'Wajib diisi'
                          : null,
                    ),
                    ValueListenableBuilder<TextEditingValue>(
                      valueListenable: _apiKey,
                      builder: (context, value, _) {
                        if (value.text.trim().isEmpty) {
                          return const SizedBox.shrink();
                        }
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            DropdownButtonFormField<String>(
                              initialValue: _model,
                              decoration: const InputDecoration(
                                labelText: 'Model',
                                hintText: 'Pilih model',
                                helperText:
                                    'gemini-3.5-flash disarankan (murah & akurat).',
                                border: OutlineInputBorder(),
                              ),
                              items: _models
                                  .map((m) => DropdownMenuItem(
                                        value: m,
                                        child: Text(m),
                                      ))
                                  .toList(),
                              onChanged: (v) {
                                if (v != null) setState(() => _model = v);
                              },
                              validator: (v) =>
                                  v == null ? 'Pilih model dulu' : null,
                            ),
                            const SizedBox(height: 16),
                          ],
                        );
                      },
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
