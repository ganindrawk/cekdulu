-- =============================================================================
-- CekDulu Migration 007: provider AI dinamis untuk pengenalan gambar
-- -----------------------------------------------------------------------------
-- Tujuan: setting AI Pengenalan Gambar tidak lagi Gemini-only. Admin bisa
-- memilih provider: gemini | openai | groq | openrouter | custom.
-- Provider non-Gemini memakai format OpenAI-compatible (chat completions).
--
-- CARA MENJALANKAN (URUTAN PENTING):
--   1) Jalankan file ini di Supabase Dashboard -> SQL Editor -> Run.
--   2) BARU deploy ulang Edge Function save-ai-secret dan
--      identify-product-image (versi baru membaca kolom is_active).
--      Deploy sebelum migrasi = identify mengembalikan ai_not_configured.
--   3) Buka aplikasi -> AI Pengenalan Gambar -> pilih provider, tempel
--      API key provider tersebut, isi model, simpan.
--
-- Aman diulang (semua perintah IF NOT EXISTS / OR REPLACE).
-- =============================================================================

-- 1) Longgarkan CHECK provider (dulu hanya 'gemini').
ALTER TABLE public.ai_credentials
  DROP CONSTRAINT IF EXISTS ai_credentials_provider_check;
ALTER TABLE public.ai_credentials
  ADD CONSTRAINT ai_credentials_provider_check
  CHECK (provider IN ('gemini', 'openai', 'groq', 'openrouter', 'custom'));

-- 2) Endpoint dasar untuk provider OpenAI-compatible ('' untuk Gemini).
ALTER TABLE public.ai_credentials
  ADD COLUMN IF NOT EXISTS base_url TEXT NOT NULL DEFAULT '';

COMMENT ON COLUMN public.ai_credentials.base_url IS
  'Base URL API untuk provider OpenAI-compatible (mis. https://api.openai.com/v1). Kosong untuk Gemini.';

-- 3) Penanda provider yang sedang aktif (satu-satunya yang dipakai identify).
ALTER TABLE public.ai_credentials
  ADD COLUMN IF NOT EXISTS is_active BOOLEAN NOT NULL DEFAULT false;

COMMENT ON COLUMN public.ai_credentials.is_active IS
  'true = provider aktif untuk pengenalan gambar. Diatur otomatis oleh save-ai-secret.';

-- Baris Gemini yang sudah ada tetap aktif (tidak mengubah perilaku lama).
UPDATE public.ai_credentials
SET is_active = true
WHERE provider = 'gemini';

-- 4) Perbarui safe view: ikut menampilkan base_url + is_active
--    (keduanya bukan rahasia; api_key tetap dibuang).
DROP VIEW IF EXISTS public.ai_credentials_safe;
CREATE VIEW public.ai_credentials_safe
WITH (security_invoker = true) AS
SELECT
  id,
  provider,
  model,
  base_url,
  is_active,
  (credentials - 'api_key') AS credentials,
  created_at,
  updated_at
FROM public.ai_credentials;

COMMENT ON VIEW public.ai_credentials_safe IS
  'Admin-safe view of ai_credentials with the api_key stripped (now also exposes base_url and is_active).';
