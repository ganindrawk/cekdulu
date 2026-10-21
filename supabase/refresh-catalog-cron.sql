-- CekDulu: jadwalkan refresh-catalog tiap jam via pg_cron + pg_net.
-- ------------------------------------------------------------------
-- CARA PAKAI (sekali saja, SETELAH katalog produk terisi):
--   1. Di dashboard Supabase project CekDulu, buka Database → Extensions,
--      aktifkan `pg_cron` dan `pg_net` (kalau belum aktif).
--   2. Buka SQL Editor, ganti <CRON_SECRET> di bawah dengan nilai
--      CRON_SECRET milikmu (lihat via `supabase secrets list` di laptop,
--      atau dari vault bila sudah disimpan di sana). JANGAN paste secret
--      ini ke chat.
--   3. Jalankan seluruh script ini sekali. Verifikasi dengan:
--        select jobname, schedule, active from cron.job;
--
-- CATATAN:
--   - Tanpa kredensial Shopee API (pendaftaran Open Platform Kan diblokir),
--     fungsi ini me-refresh 0 produk Shopee (skipped_no_credentials) dan
--     hanya melaporkan produk Tokopedia yang basi — tetap berguna sebagai
--     pengingat manual mingguan.
--   - Untuk berhenti: select cron.unschedule('refresh-catalog-hourly');

select cron.schedule(
  'refresh-catalog-hourly',
  '0 * * * *',
  $$
  select net.http_post(
    url := 'https://mfppajuxqugxncpgkxun.supabase.co/functions/v1/refresh-catalog',
    headers := jsonb_build_object(
      'x-cron-secret', '<CRON_SECRET>',
      'Content-Type', 'application/json'
    ),
    body := '{}'::jsonb
  );
  $$
);
