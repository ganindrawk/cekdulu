import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cekdulu/src/core/widgets/common_widgets.dart';
import 'package:cekdulu/src/features/admin/data/admin_repository.dart';

/// Pengaturan AI pengenalan gambar (admin saja).
///
/// API key bersifat write-only: ditulis via Edge Function `save-ai-secret`,
/// dienkripsi server-side, dan tidak pernah ditampilkan kembali.
/// Provider yang disimpan menjadi bagian rantai fallback (combo):
/// provider urutan pertama adalah default — bila kuotanya habis (429)
/// atau layanannya tidak tersedia (503), identify-product-image otomatis
/// mencoba provider berikutnya. Urutan bisa diubah dari menu admin di
/// bawah form (tombol naik/turun); urutan disimpan via `save-ai-order`.
/// Gemini memakai API generateContent; provider lain memakai format
/// OpenAI-compatible (chat completions + image_url).
class AiSettingsScreen extends ConsumerStatefulWidget {
  const AiSettingsScreen({super.key});

  @override
  ConsumerState<AiSettingsScreen> createState() => _AiSettingsScreenState();
}

class _AiSettingsScreenState extends ConsumerState<AiSettingsScreen> {
  final _formKey = GlobalKey<FormState>();
  final _apiKey = TextEditingController();
  final _modelText = TextEditingController();
  final _baseUrl = TextEditingController();
  String _provider = 'gemini';
  String? _model; // Gemini: dipilih dari dropdown
  bool _obscureKey = true;
  bool _loading = false;
  bool _loadingData = true;
  bool _keyConfigured = false;
  String? _activeProviderLabel;
  String? _error;
  String? _info;
  List<Map<String, dynamic>> _chain = [];
  bool _savingOrder = false;

  static const _geminiModels = [
    'gemini-3.8-flash',
    'gemini-3.5-flash-lite',
    'gemini-3.5-flash',
    'gemini-3.6-flash',
  ];

  static const _providers = [
    ('gemini', 'Gemini (Google)'),
    ('openai', 'OpenAI'),
    ('groq', 'Groq'),
    ('openrouter', 'OpenRouter'),
    ('custom', 'Kustom (OpenAI-compatible)'),
  ];

  /// Preset base URL provider OpenAI-compatible (bisa diubah di field).
  static const _presetBaseUrl = {
    'openai': 'https://api.openai.com/v1',
    'groq': 'https://api.groq.com/openai/v1',
    'openrouter': 'https://openrouter.ai/api/v1',
  };

  /// Saran model default saat provider dipilih (bisa diubah).
  static const _suggestedModel = {
    'openai': 'gpt-5-mini',
  };

  bool get _isGemini => _provider == 'gemini';

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _apiKey.dispose();
    _modelText.dispose();
    _baseUrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final data =
          await ref.read(adminRepositoryProvider).fetchAiCredentials();
      if (mounted && data != null) {
        final provider = (data['provider'] ?? 'gemini').toString();
        if (_providers.any((p) => p.$1 == provider)) _provider = provider;
        final model = (data['model'] ?? '').toString();
        if (_isGemini) {
          if (_geminiModels.contains(model)) _model = model;
        } else {
          _modelText.text = model;
        }
        _baseUrl.text = (data['base_url'] ?? '').toString();
        _activeProviderLabel =
            _providers.firstWhere((p) => p.$1 == _provider).$2;
        // api_key tidak pernah dibaca kembali (write-only); kita hanya tahu
        // barisnya ada → key pernah dikonfigurasi.
        _keyConfigured = true;
      }
    } catch (e) {
      _error = e.toString();
    } finally {
      if (mounted) setState(() => _loadingData = false);
    }
    await _loadChain();
  }

  /// Muat rantai fallback (semua provider tersimpan, urut priority).
  Future<void> _loadChain() async {
    try {
      final rows =
          await ref.read(adminRepositoryProvider).fetchAiCredentialsAll();
      if (mounted) setState(() => _chain = rows);
    } catch (_) {
      // Rantai gagal dimuat: form tetap bisa dipakai; urutan tidak tampil.
    }
  }

  /// Geser satu provider di rantai lalu simpan urutan baru ke server.
  Future<void> _moveProvider(int index, int delta) async {
    final newIndex = index + delta;
    if (newIndex < 0 || newIndex >= _chain.length || _savingOrder) return;
    final reordered = [..._chain];
    final item = reordered.removeAt(index);
    reordered.insert(newIndex, item);
    setState(() {
      _savingOrder = true;
      _chain = reordered;
      _error = null;
      _info = null;
    });
    try {
      final order =
          reordered.map((e) => (e['provider'] ?? '').toString()).toList();
      await ref.read(adminRepositoryProvider).saveAiOrder(order);
      if (mounted) {
        setState(() => _info =
            'Urutan fallback disimpan. Provider pertama adalah default.');
      }
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
      await _loadChain(); // kembalikan urutan dari server
    } finally {
      if (mounted) setState(() => _savingOrder = false);
    }
  }

  void _onProviderChanged(String? value) {
    if (value == null || value == _provider) return;
    setState(() {
      _provider = value;
      if (_isGemini) {
        _modelText.clear();
        _baseUrl.clear();
      } else {
        _model = null;
        _baseUrl.text = _presetBaseUrl[value] ?? '';
        _modelText.text = _suggestedModel[value] ?? '';
      }
    });
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _loading = true;
      _error = null;
      _info = null;
    });
    try {
      final model =
          _isGemini ? (_model ?? 'gemini-3.8-flash') : _modelText.text.trim();
      await ref.read(adminRepositoryProvider).saveAiSecret(
            apiKey: _apiKey.text.trim(),
            model: model,
            provider: _provider,
            baseUrl: _isGemini ? '' : _baseUrl.text.trim(),
          );
      if (mounted) {
        setState(() {
          _info = 'API key tersimpan (terenkripsi di server). '
              'Provider aktif sekarang: '
              '${_providers.firstWhere((p) => p.$1 == _provider).$2}.';
          _keyConfigured = true;
          _activeProviderLabel =
              _providers.firstWhere((p) => p.$1 == _provider).$2;
          _apiKey.clear();
        });
        await _loadChain();
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
                    Text('Provider AI',
                        style: Theme.of(context).textTheme.titleMedium),
                    const SizedBox(height: 8),
                    Text(
                      _keyConfigured
                          ? 'Status: API key sudah dikonfigurasi ✓\n'
                              'Provider aktif: ${_activeProviderLabel ?? '-'}\n'
                              'Tempel key baru untuk mengganti / berpindah provider.'
                          : 'Status: API key belum dikonfigurasi.',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      initialValue: _provider,
                      decoration: const InputDecoration(
                        labelText: 'Provider',
                        helperText:
                            'Provider yang disimpan menjadi provider aktif untuk pengenalan gambar.',
                        border: OutlineInputBorder(),
                      ),
                      items: _providers
                          .map((p) => DropdownMenuItem(
                                value: p.$1,
                                child: Text(p.$2),
                              ))
                          .toList(),
                      onChanged: _onProviderChanged,
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _apiKey,
                      obscureText: _obscureKey,
                      decoration: InputDecoration(
                        labelText: 'API Key',
                        helperText:
                            'Write-only: dienkripsi di server dan tidak pernah ditampilkan kembali. '
                            'Setiap provider memakai key-nya sendiri.',
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
                    const SizedBox(height: 16),
                    if (_isGemini)
                      DropdownButtonFormField<String>(
                        initialValue: _model,
                        decoration: const InputDecoration(
                          labelText: 'Model',
                          hintText: 'Pilih model',
                          helperText:
                              'gemini-3.8-flash disarankan (terbaru & stabil).',
                          border: OutlineInputBorder(),
                        ),
                        items: _geminiModels
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
                      )
                    else
                      TextFormField(
                        controller: _modelText,
                        decoration: InputDecoration(
                          labelText: 'Model',
                          hintText: _provider == 'openai'
                              ? 'mis. gpt-5-mini'
                              : 'isi nama model dari provider',
                          helperText: _provider == 'openai'
                              ? 'gpt-5-mini disarankan: murah dan sanggup volume tinggi.'
                              : 'Model harus mendukung input gambar (vision).',
                          border: const OutlineInputBorder(),
                        ),
                        validator: (v) => (v == null || v.trim().isEmpty)
                            ? 'Wajib diisi'
                            : null,
                      ),
                    if (!_isGemini) ...[
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: _baseUrl,
                        decoration: const InputDecoration(
                          labelText: 'Base URL API',
                          helperText:
                              'Terisi otomatis sesuai provider; ubah bila memakai endpoint lain.',
                          border: OutlineInputBorder(),
                        ),
                        validator: (v) => (_provider == 'custom' &&
                                (v == null || v.trim().isEmpty))
                            ? 'Wajib diisi untuk provider Kustom'
                            : null,
                      ),
                    ],
                    if (_error != null) ...[
                      const SizedBox(height: 16),
                      Text(_error!,
                          style: TextStyle(
                              color: Theme.of(context).colorScheme.error)),
                      const SizedBox(height: 8),
                    ],
                    if (_info != null) ...[
                      const SizedBox(height: 16),
                      Text(_info!),
                      const SizedBox(height: 8),
                    ],
                    const SizedBox(height: 16),
                    AppButton(
                        label: 'Simpan', loading: _loading, onPressed: _save),
                    const SizedBox(height: 24),
                    Text('Urutan fallback (combo)',
                        style: Theme.of(context).textTheme.titleMedium),
                    const SizedBox(height: 8),
                    const Text(
                      'Provider pertama adalah default. Bila kuotanya habis '
                      'atau layanannya tidak tersedia, sistem otomatis '
                      'mencoba provider berikutnya. Atur urutannya dengan '
                      'tombol naik/turun.',
                    ),
                    const SizedBox(height: 12),
                    if (_chain.isEmpty)
                      const Text(
                        'Belum ada provider tersimpan. Simpan satu provider '
                        'di atas untuk memulai rantai.',
                      )
                    else if (_chain.length == 1)
                      _ChainRow(
                        position: 1,
                        label: _providers
                            .firstWhere(
                              (p) =>
                                  p.$1 ==
                                  (_chain[0]['provider'] ?? '').toString(),
                              orElse: () => ('custom', 'Kustom'),
                            )
                            .$2,
                        model: (_chain[0]['model'] ?? '').toString(),
                        isDefault: true,
                        canUp: false,
                        canDown: false,
                        onUp: null,
                        onDown: null,
                      )
                    else
                      ..._chain.asMap().entries.map((entry) {
                        final index = entry.key;
                        final row = entry.value;
                        final providerCode = (row['provider'] ?? '').toString();
                        return _ChainRow(
                          position: index + 1,
                          label: _providers
                              .firstWhere(
                                (p) => p.$1 == providerCode,
                                orElse: () => ('custom', 'Kustom'),
                              )
                              .$2,
                          model: (row['model'] ?? '').toString(),
                          isDefault: index == 0,
                          canUp: index > 0 && !_savingOrder,
                          canDown:
                              index < _chain.length - 1 && !_savingOrder,
                          onUp: () => _moveProvider(index, -1),
                          onDown: () => _moveProvider(index, 1),
                        );
                      }),
                    const SizedBox(height: 24),
                    Text('Cara kerja',
                        style: Theme.of(context).textTheme.titleMedium),
                    const SizedBox(height: 8),
                    const Text(
                      'Saat pengguna memakai "Cari dari foto", aplikasi mengirim '
                      'foto ke server. Server memanggil provider AI yang aktif '
                      'dengan API key ini untuk menebak nama produk, lalu '
                      'mencocokkannya dengan katalog. API key tidak pernah '
                      'keluar dari server. Bila kuota provider pertama habis, '
                      'sistem otomatis mencoba provider berikutnya sesuai '
                      'urutan fallback di atas; bila semua habis, aplikasi '
                      'menampilkan "Kuota AI tercapai".',
                    ),
                  ],
                ),
              ),
            ),
    );
  }
}

/// Satu baris rantai fallback: nomor urut, nama provider + model,
/// lencana "Default" untuk urutan pertama, tombol naik/turun.
class _ChainRow extends StatelessWidget {
  const _ChainRow({
    required this.position,
    required this.label,
    required this.model,
    required this.isDefault,
    required this.canUp,
    required this.canDown,
    required this.onUp,
    required this.onDown,
  });

  final int position;
  final String label;
  final String model;
  final bool isDefault;
  final bool canUp;
  final bool canDown;
  final VoidCallback? onUp;
  final VoidCallback? onDown;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          children: [
            CircleAvatar(
              radius: 14,
              child: Text('$position',
                  style: const TextStyle(fontSize: 13)),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(label,
                            style: const TextStyle(
                                fontWeight: FontWeight.w700)),
                      ),
                      if (isDefault) ...[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: const Color(0xFFEE4D2D),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Text('Default',
                              style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                  color: Colors.white)),
                        ),
                      ],
                    ],
                  ),
                  if (model.isNotEmpty)
                    Text(model,
                        style: Theme.of(context).textTheme.bodySmall),
                ],
              ),
            ),
            IconButton(
              icon: const Icon(Icons.arrow_upward),
              tooltip: 'Naikkan (jadi lebih utama)',
              onPressed: canUp ? onUp : null,
            ),
            IconButton(
              icon: const Icon(Icons.arrow_downward),
              tooltip: 'Turunkan',
              onPressed: canDown ? onDown : null,
            ),
          ],
        ),
      ),
    );
  }
}
