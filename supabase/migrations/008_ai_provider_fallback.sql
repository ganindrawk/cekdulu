-- =============================================================================
-- CekDulu Migration 008: rantai fallback (combo) provider AI
-- -----------------------------------------------------------------------------
-- Tujuan: pengenalan gambar tidak berhenti di satu provider. Bila provider
-- pertama kuotanya habis (429) atau layanannya tidak tersedia (503),
-- identify-product-image otomatis mencoba provider berikutnya sesuai urutan
-- priority (1 = utama, 2 = cadangan pertama, dst).
--
-- File ini MENCAKUP migrasi 007 (base_url + is_active + CHECK provider),
-- jadi cukup jalankan file ini saja — aman bila 007 sudah pernah dijalankan
-- (semua perintah IF NOT EXISTS / DROP IF EXISTS).
--
-- CARA MENJALANKAN (URUTAN PENTING):
--   1) Jalankan file ini di Supabase Dashboard -> SQL Editor -> Run.
--   2) BARU deploy ulang Edge Function save-ai-secret, identify-product-image,
--      dan save-ai-order (BARU).
--   3) Buka aplikasi -> AI Pengenalan Gambar -> atur urutan fallback bila
--      sudah ada lebih dari satu provider tersimpan.
-- =============================================================================

-- 1) CHECK provider (dari 007): gemini | openai | groq | openrouter | custom.
ALTER TABLE public.ai_credentials
  DROP CONSTRAINT IF EXISTS ai_credentials_provider_check;
ALTER TABLE public.ai_credentials
  ADD CONSTRAINT ai_credentials_provider_check
  CHECK (provider IN ('gemini', 'openai', 'groq', 'openrouter', 'custom'));

-- 2) Kolom dari 007 (bila belum ada).
ALTER TABLE public.ai_credentials
  ADD COLUMN IF NOT EXISTS base_url TEXT NOT NULL DEFAULT '';
ALTER TABLE public.ai_credentials
  ADD COLUMN IF NOT EXISTS is_active BOOLEAN NOT NULL DEFAULT false;

COMMENT ON COLUMN public.ai_credentials.base_url IS
  'Base URL API untuk provider OpenAI-compatible (mis. https://api.openai.com/v1). Kosong untuk Gemini.';
COMMENT ON COLUMN public.ai_credentials.is_active IS
  'true = provider utama (priority terkecil). Diatur otomatis oleh save-ai-secret / save-ai-order.';

-- 3) Kolom BARU 008: urutan fallback.
ALTER TABLE public.ai_credentials
  ADD COLUMN IF NOT EXISTS priority INTEGER NOT NULL DEFAULT 100;

COMMENT ON COLUMN public.ai_credentials.priority IS
  'Urutan coba provider: 1 = utama, 2 = cadangan pertama, dst. Diatur lewat save-ai-order.';

-- Backfill priority: provider yang tadinya aktif jadi 1, sisanya urut
-- berdasarkan waktu dibuat. Hanya mengisi baris yang masih bernilai default.
WITH ranked AS (
  SELECT id,
         ROW_NUMBER() OVER (
           ORDER BY CASE WHEN is_active THEN 0 ELSE 1 END, created_at
         ) AS rn
  FROM public.ai_credentials
)
UPDATE public.ai_credentials c
SET priority = r.rn
FROM ranked r
WHERE c.id = r.id AND c.priority = 100;

-- Bila belum ada baris aktif sama sekali (fresh install), tidak ada yang
-- diubah; priority diisi penuh oleh save-ai-secret saat pertama menyimpan.

-- 4) Perbarui safe view: ikut menampilkan priority
--    (bukan rahasia; api_key tetap dibuang).
DROP VIEW IF EXISTS public.ai_credentials_safe;
CREATE VIEW public.ai_credentials_safe
WITH (security_invoker = true) AS
SELECT
  id,
  provider,
  model,
  base_url,
  is_active,
  priority,
  (credentials - 'api_key') AS credentials,
  created_at,
  updated_at
FROM public.ai_credentials;

COMMENT ON VIEW public.ai_credentials_safe IS
  'Admin-safe view of ai_credentials with the api_key stripped (now also exposes base_url, is_active and priority).';
