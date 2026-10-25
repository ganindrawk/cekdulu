import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:cekdulu/src/core/widgets/common_widgets.dart';
import 'package:cekdulu/src/features/admin/data/admin_repository.dart';
import 'package:cekdulu/src/features/admin/presentation/admin_form_widgets.dart';

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
      backgroundColor: ShopeePalette.cream,
      body: Column(
        children: [
          AdminFormHeader(
            title: 'Kredensial Affiliate',
            subtitle: 'Hubungkan akun affiliate Anda',
            onBack: () => context.go('/admin'),
            decorations: const [
              Positioned(
                right: 96,
                top: 14,
                child: Icon(Icons.link, size: 64, color: Colors.white24),
              ),
              Positioned(
                right: 44,
                top: 52,
                child: Icon(Icons.person, size: 40, color: Colors.white24),
              ),
              Positioned(
                right: 8,
                top: 30,
                child: Icon(Icons.campaign_outlined,
                    size: 48, color: Colors.white24),
              ),
            ],
          ),
          Expanded(
            child: _loadingData
                ? const LoadingView()
                : SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
                    child: Container(
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(24),
                        boxShadow: const [
                          BoxShadow(
                              color: Color(0x14000000),
                              blurRadius: 16,
                              offset: Offset(0, 4)),
                        ],
                      ),
                      child: Form(
                        key: _formKey,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            AdminFieldRow(
                              icon: Icons.shopping_bag_outlined,
                              label: 'App ID (Shopee Open Platform)',
                              child: TextFormField(
                                controller: _appId,
                                decoration: adminInputDecoration(
                                    hintText: 'Masukkan App ID Anda'),
                                validator: (v) =>
                                    (v == null || v.trim().isEmpty)
                                        ? 'Wajib diisi'
                                        : null,
                              ),
                            ),
                            const Divider(height: 32),
                            AdminFieldRow(
                              icon: Icons.description_outlined,
                              label: 'Secret (write-only)',
                              helper:
                                  'Hanya ditulis sekali via Edge Function dan tidak pernah ditampilkan kembali.',
                              child: TextFormField(
                                controller: _secret,
                                obscureText: true,
                                decoration: adminInputDecoration(
                                    hintText: 'Masukkan Secret Anda'),
                              ),
                            ),
                            const Divider(height: 32),
                            AdminFieldRow(
                              icon: Icons.person_outline,
                              label: 'ID Affiliate',
                              child: TextFormField(
                                controller: _affiliateId,
                                decoration: adminInputDecoration(
                                    hintText: 'Masukkan ID Affiliate Anda'),
                                validator: (v) =>
                                    (v == null || v.trim().isEmpty)
                                        ? 'Wajib diisi'
                                        : null,
                              ),
                            ),
                            const Divider(height: 32),
                            AdminFieldRow(
                              icon: Icons.link,
                              label: 'SubID default (tracking)',
                              child: TextFormField(
                                controller: _subId,
                                decoration: adminInputDecoration(
                                    hintText:
                                        'Masukkan SubID default (opsional)'),
                              ),
                            ),
                            const SizedBox(height: 24),
                            if (_error != null) ...[
                              Text(_error!,
                                  style: const TextStyle(color: Colors.red)),
                              const SizedBox(height: 8),
                            ],
                            if (_info != null) ...[
                              Text(_info!),
                              const SizedBox(height: 8),
                            ],
                            AdminGradientButton(
                              label: 'Simpan',
                              loading: _loading,
                              onPressed: _save,
                            ),
                            const SizedBox(height: 20),
                            const AdminInfoBox(
                              title: 'Tentang',
                              body: 'Kredensial ini digunakan untuk mengakses '
                                  'API publik Shopee affiliate. Pastikan Anda '
                                  'memasukkan data dengan benar. Setelah '
                                  'disimpan, link affiliate akan muncul di '
                                  'dashboard Tokopedia, lalu tempelkan per '
                                  'produk di menu "Link Tokopedia".',
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}
