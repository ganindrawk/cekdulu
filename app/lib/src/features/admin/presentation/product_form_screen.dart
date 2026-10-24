import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:cekdulu/src/core/widgets/common_widgets.dart';
import 'package:cekdulu/src/features/admin/data/admin_repository.dart';
import 'package:cekdulu/src/features/admin/presentation/admin_form_widgets.dart';
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

  void _comingSoon(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isEdit = widget.productId != null;
    return Scaffold(
      backgroundColor: ShopeePalette.cream,
      body: Column(
        children: [
          AdminFormHeader(
            title: 'Kelola Katalog',
            subtitle: isEdit ? 'Ubah Produk' : 'Tambah Produk',
            onBack: () => context.go('/admin'),
            trailing: const Icon(Icons.store_outlined,
                size: 30, color: Colors.white),
            decorations: const [
              Positioned(
                right: 88,
                top: 56,
                child: Icon(Icons.shopping_cart_outlined,
                    size: 48, color: Colors.white24),
              ),
              Positioned(
                right: 8,
                top: 30,
                child: Icon(Icons.shopping_bag_outlined,
                    size: 84, color: Colors.white24),
              ),
            ],
          ),
          Expanded(
            child: _loadingProduct
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
                              icon: Icons.inventory_2_outlined,
                              label: 'Nama produk',
                              required: true,
                              child: TextFormField(
                                controller: _name,
                                decoration: adminInputDecoration(
                                    hintText: 'Masukkan nama produk'),
                                validator: (v) =>
                                    (v == null || v.trim().isEmpty)
                                        ? 'Nama wajib diisi'
                                        : null,
                              ),
                            ),
                            const SizedBox(height: 20),
                            AdminFieldRow(
                              icon: Icons.store_outlined,
                              label: 'Marketplace',
                              required: true,
                              child: DropdownButtonFormField<String>(
                                initialValue: _marketplace,
                                decoration: adminInputDecoration(),
                                items: const [
                                  DropdownMenuItem(
                                      value: 'shopee',
                                      child: Text('Shopee')),
                                  DropdownMenuItem(
                                      value: 'tokopedia',
                                      child: Text('Tokopedia')),
                                ],
                                onChanged: (v) => setState(
                                    () => _marketplace = v ?? 'shopee'),
                              ),
                            ),
                            const SizedBox(height: 20),
                            AdminFieldRow(
                              icon: Icons.link,
                              label: 'URL produk marketplace',
                              required: true,
                              child: TextFormField(
                                controller: _marketplaceUrl,
                                keyboardType: TextInputType.url,
                                decoration: adminInputDecoration(
                                    hintText:
                                        'Tempel link produk dari Shopee / Tokopedia / dll'),
                              ),
                            ),
                            const SizedBox(height: 20),
                            AdminFieldRow(
                              icon: Icons.barcode_reader,
                              label: 'Barcode / EAN (opsional)',
                              helper:
                                  'Kode barcode fisik produk (mis. 8991234567890). Dipakai untuk pencocokan hasil scan kamera.',
                              highlight: true,
                              trailing: AdminInputAction(
                                icon: Icons.camera_alt_outlined,
                                label: '',
                                onTap: () => _comingSoon(
                                    'Pindai barcode dari form belum tersedia — ketik kodenya manual ya.'),
                              ),
                              child: TextFormField(
                                controller: _barcode,
                                keyboardType: TextInputType.number,
                                decoration: adminInputDecoration(),
                              ),
                            ),
                            const SizedBox(height: 20),
                            AdminFieldRow(
                              icon: Icons.local_offer_outlined,
                              label: 'Harga (Rp)',
                              required: true,
                              child: TextFormField(
                                controller: _price,
                                keyboardType: TextInputType.number,
                                decoration: adminInputDecoration(
                                    hintText: 'Masukkan harga produk'),
                              ),
                            ),
                            const SizedBox(height: 20),
                            AdminFieldRow(
                              icon: Icons.star_outline,
                              label: 'Rating (0-5)',
                              required: true,
                              child: TextFormField(
                                controller: _rating,
                                keyboardType:
                                    const TextInputType.numberWithOptions(
                                        decimal: true),
                                decoration: adminInputDecoration(
                                    hintText: 'Masukkan rating produk'),
                              ),
                            ),
                            const SizedBox(height: 20),
                            AdminFieldRow(
                              icon: Icons.archive_outlined,
                              label: 'Jumlah ulasan',
                              required: true,
                              child: TextFormField(
                                controller: _reviewCount,
                                keyboardType: TextInputType.number,
                                decoration: adminInputDecoration(
                                    hintText: 'Masukkan jumlah ulasan'),
                              ),
                            ),
                            const SizedBox(height: 20),
                            AdminFieldRow(
                              icon: Icons.image_outlined,
                              label: 'URL gambar',
                              required: true,
                              trailing: AdminInputAction(
                                icon: Icons.image_outlined,
                                label: 'Pilih Gambar',
                                onTap: () => _comingSoon(
                                    'Pilih gambar dari galeri belum tersedia — tempel link gambar produk ya.'),
                              ),
                              child: TextFormField(
                                controller: _imageUrl,
                                keyboardType: TextInputType.url,
                                decoration: adminInputDecoration(
                                    hintText: 'Tempel link gambar produk'),
                              ),
                            ),
                            const SizedBox(height: 20),
                            AdminFieldRow(
                              icon: Icons.description_outlined,
                              label: 'Deskripsi',
                              required: true,
                              child: TextFormField(
                                controller: _description,
                                maxLines: 4,
                                decoration: adminInputDecoration(
                                    hintText: 'Masukkan deskripsi produk'),
                              ),
                            ),
                            if (_error != null) ...[
                              const SizedBox(height: 16),
                              Text(_error!,
                                  style: const TextStyle(color: Colors.red)),
                            ],
                            const SizedBox(height: 24),
                            AdminGradientButton(
                              label:
                                  isEdit ? 'Simpan Perubahan' : 'Simpan Produk',
                              icon: Icons.save_outlined,
                              loading: _loading,
                              onPressed: _save,
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
