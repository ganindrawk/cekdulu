import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cekdulu/src/core/widgets/common_widgets.dart';
import 'package:cekdulu/src/features/admin/data/admin_repository.dart';

/// Form pengaturan akun affiliate (admin saja).
///
/// Shopee: App ID, Secret (write-only via Edge Function), ID affiliate,
/// SubID default. Tokopedia tidak punya API publik — link ditempel manual
/// di menu "Link Tokopedia".
class CredentialsFormScreen extends ConsumerStatefulWidget {
  const CredentialsFormScreen({super.key});

  @override
  ConsumerState<CredentialsFormScreen> createState() =>
      _CredentialsFormScreenState();
}

class _CredentialsFormScreenState extends ConsumerState<CredentialsFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final _appId = TextEditingController();
  final _secret = TextEditingController();
  final _affiliateId = TextEditingController();
  final _subId = TextEditingController();
  bool _loading = false;
  bool _loadingData = true;
  String? _error;
  String? _info;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _appId.dispose();
    _secret.dispose();
    _affiliateId.dispose();
    _subId.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final data =
          await ref.read(adminRepositoryProvider).fetchShopeeCredentials();
      final creds = data?['credentials'] as Map<String, dynamic>?;
      if (mounted && creds != null) {
        _appId.text = (creds['app_id'] ?? '').toString();
        _affiliateId.text = (creds['affiliate_id'] ?? '').toString();
        _subId.text = (creds['default_sub_id'] ?? '').toString();
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
      await ref.read(adminRepositoryProvider).saveShopeeCredentials(
            appId: _appId.text.trim(),
            affiliateId: _affiliateId.text.trim(),
            defaultSubId: _subId.text.trim(),
          );
      // Secret hanya ditulis via Edge Function (belum tersedia).
      if (_secret.text.trim().isNotEmpty) {
        setState(() => _info =
            'Catatan: penyimpanan Secret via Edge Function belum diimplementasikan; Secret belum tersimpan.');
      } else {
        setState(() => _info = 'Kredensial Shopee tersimpan.');
      }
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Kredensial Affiliate')),
      body: _loadingData
          ? const LoadingView()
          : SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text('Shopee',
                        style: Theme.of(context).textTheme.titleMedium),
                    const SizedBox(height: 12),
                    AppTextField(
                      controller: _appId,
                      label: 'App ID (Shopee Open Platform)',
                      validator: (v) => (v == null || v.trim().isEmpty)
                          ? 'Wajib diisi'
                          : null,
                    ),
                    AppTextField(
                      controller: _secret,
                      label: 'Secret (write-only)',
                      obscureText: true,
                      helperText:
                          'Hanya ditulis sekali via Edge Function dan tidak pernah ditampilkan kembali.',
                    ),
                    AppTextField(
                      controller: _affiliateId,
                      label: 'ID Affiliate',
                      validator: (v) => (v == null || v.trim().isEmpty)
                          ? 'Wajib diisi'
                          : null,
                    ),
                    AppTextField(
                      controller: _subId,
                      label: 'SubID default (tracking)',
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
                    Text('Tokopedia',
                        style: Theme.of(context).textTheme.titleMedium),
                    const SizedBox(height: 8),
                    const Text(
                      'Tokopedia tidak menyediakan API publik untuk affiliate. '
                      'Buat link affiliate manual di dashboard Tokopedia, lalu tempelkan '
                      'per produk di menu "Link Tokopedia".',
                    ),
                  ],
                ),
              ),
            ),
    );
  }
}
