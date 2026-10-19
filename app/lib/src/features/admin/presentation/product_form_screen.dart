import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:cekdulu/src/core/widgets/common_widgets.dart';
import 'package:cekdulu/src/features/admin/data/admin_repository.dart';
import 'package:cekdulu/src/features/catalog/data/product.dart';
import 'package:cekdulu/src/features/catalog/data/product_repository.dart';

/// Form tambah/ubah produk katalog (admin).
class ProductFormScreen extends ConsumerStatefulWidget {
  const ProductFormScreen({super.key, this.productId});

  final String? productId;

  @override
  ConsumerState<ProductFormScreen> createState() => _ProductFormScreenState();
}

class _ProductFormScreenState extends ConsumerState<ProductFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _description = TextEditingController();
  final _imageUrl = TextEditingController();
  final _marketplaceUrl = TextEditingController();
  final _barcode = TextEditingController();
  final _price = TextEditingController();
  final _rating = TextEditingController();
  final _reviewCount = TextEditingController();
  String _marketplace = 'shopee';
  bool _loading = false;
  bool _loadingProduct = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    if (widget.productId != null) _loadProduct();
  }

  @override
  void dispose() {
    _name.dispose();
    _description.dispose();
    _imageUrl.dispose();
    _marketplaceUrl.dispose();
    _barcode.dispose();
    _price.dispose();
    _rating.dispose();
    _reviewCount.dispose();
    super.dispose();
  }

  Future<void> _loadProduct() async {
    setState(() => _loadingProduct = true);
    try {
      final p = await ref
          .read(productRepositoryProvider)
          .fetchById(widget.productId!);
      if (p != null && mounted) {
        _name.text = p.name;
        _description.text = p.description ?? '';
        _imageUrl.text = p.imageUrl ?? '';
        _marketplaceUrl.text = p.marketplaceUrl ?? '';
        _barcode.text = p.barcode ?? '';
        _price.text = p.price?.toStringAsFixed(0) ?? '';
        _rating.text = p.rating?.toString() ?? '';
        _reviewCount.text = p.reviewCount.toString();
        _marketplace = p.marketplace;
      }
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loadingProduct = false);
    }
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final product = Product(
        id: '',
        name: _name.text.trim(),
        description:
            _description.text.trim().isEmpty ? null : _description.text.trim(),
        imageUrl:
            _imageUrl.text.trim().isEmpty ? null : _imageUrl.text.trim(),
        marketplace: _marketplace,
        marketplaceUrl: _marketplaceUrl.text.trim().isEmpty
            ? null
            : _marketplaceUrl.text.trim(),
        barcode: _barcode.text.trim().isEmpty ? null : _barcode.text.trim(),
        price: double.tryParse(_price.text.trim()),
        rating: double.tryParse(_rating.text.trim()),
        reviewCount: int.tryParse(_reviewCount.text.trim()) ?? 0,
      );
      await ref
          .read(adminRepositoryProvider)
          .upsertProduct(product, id: widget.productId);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Produk tersimpan')),
        );
        context.go('/admin');
      }
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isEdit = widget.productId != null;
    return Scaffold(
      appBar: AppBar(title: Text(isEdit ? 'Ubah Produk' : 'Tambah Produk')),
      body: _loadingProduct
          ? const LoadingView()
          : SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    AppTextField(
                      controller: _name,
                      label: 'Nama produk',
                      validator: (v) => (v == null || v.trim().isEmpty)
                          ? 'Nama wajib diisi'
                          : null,
                    ),
                    DropdownButtonFormField<String>(
                      initialValue: _marketplace,
                      decoration: const InputDecoration(
                        labelText: 'Marketplace',
                        border: OutlineInputBorder(),
                      ),
                      items: const [
                        DropdownMenuItem(
                            value: 'shopee', child: Text('Shopee')),
                        DropdownMenuItem(
                            value: 'tokopedia', child: Text('Tokopedia')),
                      ],
                      onChanged: (v) =>
                          setState(() => _marketplace = v ?? 'shopee'),
                    ),
                    const SizedBox(height: 12),
                    AppTextField(
                      controller: _marketplaceUrl,
                      label: 'URL produk marketplace',
                      keyboardType: TextInputType.url,
                    ),
                    AppTextField(
                      controller: _barcode,
                      label: 'Barcode / EAN (opsional)',
                      helperText:
                          'Kode barcode fisik produk (mis. 8991234567890). Dipakai untuk pencocokan hasil scan kamera.',
                    ),
                    AppTextField(
                      controller: _price,
                      label: 'Harga (Rp)',
                      keyboardType: TextInputType.number,
                    ),
                    AppTextField(
                      controller: _rating,
                      label: 'Rating (0-5)',
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
                    ),
                    AppTextField(
                      controller: _reviewCount,
                      label: 'Jumlah ulasan',
                      keyboardType: TextInputType.number,
                    ),
                    AppTextField(
                      controller: _imageUrl,
                      label: 'URL gambar',
                      keyboardType: TextInputType.url,
                    ),
                    AppTextField(
                      controller: _description,
                      label: 'Deskripsi',
                      maxLines: 3,
                    ),
                    if (_error != null) ...[
                      Text(_error!,
                          style: TextStyle(
                              color: Theme.of(context).colorScheme.error)),
                      const SizedBox(height: 8),
                    ],
                    AppButton(
                      label: isEdit ? 'Simpan perubahan' : 'Tambah produk',
                      loading: _loading,
                      onPressed: _save,
                    ),
                  ],
                ),
              ),
            ),
    );
  }
}
