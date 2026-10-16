import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cekdulu/src/core/widgets/common_widgets.dart';
import 'package:cekdulu/src/features/admin/data/admin_repository.dart';
import 'package:cekdulu/src/features/catalog/data/product.dart';

/// Form menempelkan link affiliate manual per produk (admin).
/// Mendukung Shopee (manual, karena akses Open Platform API dibatasi)
/// dan Tokopedia.
class AffiliateLinkFormScreen extends ConsumerStatefulWidget {
  const AffiliateLinkFormScreen({super.key});

  @override
  ConsumerState<AffiliateLinkFormScreen> createState() =>
      _AffiliateLinkFormScreenState();
}

class _AffiliateLinkFormScreenState
    extends ConsumerState<AffiliateLinkFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final _originalUrl = TextEditingController();
  final _affiliateUrl = TextEditingController();
  String _marketplace = 'shopee';
  String? _selectedProductId;
  bool _loading = false;
  String? _error;
  String? _info;

  static const _marketplaces = ['shopee', 'tokopedia'];

  String get _marketplaceLabel =>
      _marketplace == 'shopee' ? 'Shopee' : 'Tokopedia';

  String get _helperText => _marketplace == 'shopee'
      ? 'Buat di aplikasi Shopee (Affiliate → Offers → Share to Earn), lalu tempel di sini.'
      : 'Buat di dashboard Tokopedia Affiliate, lalu tempel di sini.';

  @override
  void dispose() {
    _originalUrl.dispose();
    _affiliateUrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    if (_selectedProductId == null) {
      setState(() => _error = 'Pilih produk dulu.');
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
      _info = null;
    });
    try {
      await ref.read(adminRepositoryProvider).addAffiliateLink(
            productId: _selectedProductId!,
            marketplace: _marketplace,
            originalUrl: _originalUrl.text.trim(),
            affiliateUrl: _affiliateUrl.text.trim(),
          );
      setState(() {
        _info = 'Link affiliate $_marketplaceLabel tersimpan.';
        _originalUrl.clear();
        _affiliateUrl.clear();
        _selectedProductId = null;
      });
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final productsAsync =
        ref.watch(adminRepositoryProvider).fetchAllProducts();
    return Scaffold(
      appBar: AppBar(title: const Text('Link Affiliate')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              DropdownButtonFormField<String>(
                initialValue: _marketplace,
                decoration: const InputDecoration(
                  labelText: 'Marketplace',
                  border: OutlineInputBorder(),
                ),
                items: _marketplaces
                    .map((m) => DropdownMenuItem(
                          value: m,
                          child: Text(
                              m == 'shopee' ? 'Shopee' : 'Tokopedia'),
                        ))
                    .toList(),
                onChanged: (v) {
                  if (v == null) return;
                  setState(() {
                    _marketplace = v;
                    _info = null;
                  });
                },
              ),
              const SizedBox(height: 12),
              FutureBuilder<List<Product>>(
                future: productsAsync,
                builder: (context, snap) {
                  if (snap.connectionState == ConnectionState.waiting) {
                    return const LoadingView(message: 'Memuat produk...');
                  }
                  if (snap.hasError) {
                    return ErrorView(message: snap.error.toString());
                  }
                  final products = snap.data ?? [];
                  return DropdownButtonFormField<String>(
                    initialValue: _selectedProductId,
                    decoration: const InputDecoration(
                      labelText: 'Produk katalog',
                      border: OutlineInputBorder(),
                    ),
                    items: products
                        .map((p) => DropdownMenuItem(
                              value: p.id,
                              child: Text(p.name,
                                  overflow: TextOverflow.ellipsis),
                            ))
                        .toList(),
                    onChanged: (v) =>
                        setState(() => _selectedProductId = v),
                    validator: (v) =>
                        v == null ? 'Pilih produk' : null,
                  );
                },
              ),
              const SizedBox(height: 12),
              AppTextField(
                controller: _originalUrl,
                label: 'URL produk asli ($_marketplaceLabel)',
                keyboardType: TextInputType.url,
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? 'Wajib diisi' : null,
              ),
              AppTextField(
                controller: _affiliateUrl,
                label: 'Link affiliate ($_marketplaceLabel)',
                keyboardType: TextInputType.url,
                helperText: _helperText,
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? 'Wajib diisi' : null,
              ),
              if (_error != null) ...[
                Text(_error!,
                    style:
                        TextStyle(color: Theme.of(context).colorScheme.error)),
                const SizedBox(height: 8),
              ],
              if (_info != null) ...[
                Text(_info!),
                const SizedBox(height: 8),
              ],
              AppButton(
                  label: 'Simpan link', loading: _loading, onPressed: _save),
            ],
          ),
        ),
      ),
    );
  }
}
