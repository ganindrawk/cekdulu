-- =============================================================================
-- CekDulu Migration 004: kolom barcode untuk pencocokan scan produk fisik
-- -----------------------------------------------------------------------------
-- Idempotent: aman dijalankan ulang.
--
-- Latar: findByScannedCode() di aplikasi mencocokkan hasil scan sebagai
-- substring marketplace_url. Barcode fisik (EAN-13/UPC) tidak pernah muncul
-- di URL marketplace, jadi kolom barcode (cocok persis) ditambahkan.
-- Urutan pencocokan di aplikasi: 1) barcode persis, 2) fallback URL (QR).
-- =============================================================================

ALTER TABLE public.products
  ADD COLUMN IF NOT EXISTS barcode TEXT;

CREATE INDEX IF NOT EXISTS idx_products_barcode
  ON public.products (barcode)
  WHERE barcode IS NOT NULL;

COMMENT ON COLUMN public.products.barcode IS
  'EAN/UPC/GTIN barcode produk fisik; dicocokkan persis saat scan.';
