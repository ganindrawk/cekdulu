/// Model produk dari tabel public.products.
class Product {
  const Product({
    required this.id,
    required this.name,
    this.description,
    this.imageUrl,
    required this.marketplace,
    this.marketplaceUrl,
    this.barcode,
    this.price,
    this.rating,
    required this.reviewCount,
  });

  final String id;
  final String name;
  final String? description;
  final String? imageUrl;
  final String marketplace; // 'shopee' | 'tokopedia'
  final String? marketplaceUrl;
  final String? barcode; // EAN/UPC/GTIN untuk pencocokan scan
  final double? price;
  final double? rating; // 0..5
  final int reviewCount;

  factory Product.fromMap(Map<String, dynamic> m) => Product(
        id: m['id'] as String,
        name: m['name'] as String,
        description: m['description'] as String?,
        imageUrl: m['image_url'] as String?,
        marketplace: m['marketplace'] as String,
        marketplaceUrl: m['marketplace_url'] as String?,
        barcode: m['barcode'] as String?,
        price: (m['price'] as num?)?.toDouble(),
        rating: (m['rating'] as num?)?.toDouble(),
        reviewCount: (m['review_count'] as int?) ?? 0,
      );

  Map<String, dynamic> toMap() => {
        'name': name,
        'description': description,
        'image_url': imageUrl,
        'marketplace': marketplace,
        'marketplace_url': marketplaceUrl,
        'barcode': barcode,
        'price': price,
        'rating': rating,
        'review_count': reviewCount,
      };

  String get marketplaceLabel =>
      marketplace == 'shopee' ? 'Shopee' : 'Tokopedia';
}

/// Model link affiliate dari tabel public.affiliate_links.
class AffiliateLink {
  const AffiliateLink({
    required this.id,
    required this.productId,
    required this.marketplace,
    required this.originalUrl,
    required this.affiliateUrl,
    required this.status,
  });

  final String id;
  final String productId;
  final String marketplace;
  final String originalUrl;
  final String affiliateUrl;
  final String status;

  factory AffiliateLink.fromMap(Map<String, dynamic> m) => AffiliateLink(
        id: m['id'] as String,
        productId: m['product_id'] as String,
        marketplace: m['marketplace'] as String,
        originalUrl: m['original_url'] as String,
        affiliateUrl: m['affiliate_url'] as String,
        status: m['status'] as String,
      );
}
