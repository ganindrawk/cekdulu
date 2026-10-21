# CekDulu — Supabase Database

Skema PostgreSQL untuk aplikasi CekDulu (Flutter + Supabase): katalog produk,
link affiliate Shopee/Tokopedia, riwayat scan, dan RBAC admin/pengguna.

## Struktur

```
supabase/
├── migrations/
│   ├── 001_initial_schema.sql   # tabel, index, trigger (idempotent)
│   ├── 002_rls_policies.sql     # RLS + policies + view aman (idempotent)
│   └── 003_profile_trigger.sql  # re-assert trigger handle_new_user (idempotent)
├── functions/
│   ├── _shared/                 # crypto.ts, supa.ts (helpers Deno)
│   ├── save-affiliate-secret/   # simpan secret terenkripsi (admin)
│   ├── generate-affiliate-link/ # generate link affiliate Shopee (admin)
│   └── refresh-catalog/         # refresh katalog via cron
├── seed/
│   ├── seed.sql                 # seed akun test (local/staging SAJA)
│   └── seed_test_accounts.md    # panduan lengkap seeding
└── README.md
```

## Urutan eksekusi migrasi

Jalankan **berurutan**: `001`, lalu `002`, lalu `003`. Semuanya idempotent
sehingga aman dijalankan ulang.

### Opsi A — Supabase Dashboard (paling mudah)

1. Buka project Supabase → **SQL Editor**.
2. Paste isi `migrations/001_initial_schema.sql` → **Run**.
3. Paste isi `migrations/002_rls_policies.sql` → **Run**.
4. Paste isi `migrations/003_profile_trigger.sql` → **Run**.

### Opsi B — Supabase CLI

```bash
supabase db push --db-url "$DATABASE_URL"
# atau salin file ke supabase/migrations/ lalu: supabase db push
```

### Opsi C — psql langsung

```bash
psql "$DATABASE_URL" -f migrations/001_initial_schema.sql
psql "$DATABASE_URL" -f migrations/002_rls_policies.sql
```

## Ringkasan skema

| Tabel | Fungsi |
| ----- | ------ |
| `profiles` | Profil 1:1 dengan `auth.users`; kolom `role` (`admin`/`user`) |
| `products` | Katalog produk Shopee/Tokopedia; diurutkan rating & jumlah review |
| `affiliate_links` | Link affiliate per produk & marketplace (Shopee otomatis via API, Tokopedia manual oleh admin) |
| `affiliate_credentials` | Kredensial API marketplace (satu baris per marketplace); secret bersifat write-only |
| `scan_history` | Log scan per pengguna (`product_id` NULL = tidak cocok katalog) |

Aturan akses (RLS):

- `products`, `affiliate_links`: semua user terautentikasi bisa **baca**; **tulis** hanya admin.
- `affiliate_credentials`: hanya admin. UI admin **wajib** baca lewat view
  `affiliate_credentials_safe` (kolom `secret` dibuang); secret hanya dipakai
  server-side oleh Edge Functions via `service_role`.
- `scan_history`: user hanya akses miliknya sendiri; admin akses semua.
- `profiles`: user baca/ubah miliknya sendiri (ganti role diblokir trigger
  kecuali oleh admin); admin akses penuh.

Fungsi helper: `is_admin()` (cek role dari JWT), trigger `handle_new_user()`
(buat profil otomatis saat signup), `handle_updated_at()`.

## Seeding akun test

Baca **`seed/seed_test_accounts.md`** untuk panduan lengkap. Ringkasnya:

1. Buat auth user via Auth Admin API (`service_role` key) — password dari
   env var `SEED_ADMIN_PASSWORD` / `SEED_USER_PASSWORD`.
2. Jalankan `PGOPTIONS="-c app.env=local" psql "$DATABASE_URL" -f seed/seed.sql`.
3. Verifikasi login di aplikasi.

Dilarang keras menjalankan seed di production — script gagal tertutup
(fail-closed) bila `app.env` bukan `local`/`staging`.

## Catatan keamanan

- Tidak ada kredensial default/hardcoded di mana pun.
- `service_role` key melewati semua RLS — simpan sebagai secret, jangan
  pernah kirim ke aplikasi Flutter.
- Secret kredensial affiliate (`secret` di JSONB) bersifat write-only: ditulis
  sekali via Edge Function secrets, tidak pernah dibaca kembali lewat API.

## Edge Functions

Fungsi server-side (Deno) di `functions/`. Kode tidak menyimpan kredensial
apa pun — semua secret dibaca dari environment function.

| Function | Akses | Tugas |
| -------- | ----- | ----- |
| `save-affiliate-secret` | Admin (JWT) | Simpan kredensial Shopee terenkripsi AES-GCM; `secret` write-only |
| `generate-affiliate-link` | Admin (JWT) | Generate link affiliate Shopee via Open Platform API, upsert ke `affiliate_links` |
| `refresh-catalog` | Admin JWT atau `x-cron-secret` | Refresh harga/rating/stok produk Shopee; laporkan produk Tokopedia yang basi |

Shared helpers di `functions/_shared/`: `crypto.ts` (enkripsi AES-GCM),
`supa.ts` (service client + `requireAdmin`).

### Deploy

```bash
cd ~/workspace/gobest/supabase
supabase functions deploy save-affiliate-secret
supabase functions deploy generate-affiliate-link
supabase functions deploy refresh-catalog
# atau sekaligus:
supabase functions deploy
```

Jalankan lokal untuk tes (butuh Docker):

```bash
supabase functions serve save-affiliate-secret --env-file ./functions/.env.local
```

### Secrets yang wajib di-set

Set via dashboard (**Project Settings → Edge Functions → Secrets**) atau CLI:

```bash
supabase secrets set AFFILIATE_ENCRYPTION_KEY="$(openssl rand -base64 32)"
supabase secrets set CRON_SECRET="$(openssl rand -hex 32)"
# SUPABASE_URL dan SUPABASE_SERVICE_ROLE_KEY tersedia otomatis di Functions.
```

| Secret | Wajib | Kegunaan |
| ------ | ----- | -------- |
| `AFFILIATE_ENCRYPTION_KEY` | Ya | Kunci AES-256-GCM (base64 dari 32 byte acak) untuk enkripsi `secret` |
| `CRON_SECRET` | Untuk cron | Token bersama agar scheduler bisa memanggil `refresh-catalog` tanpa JWT user |
| `SHOPEE_API_BASE` | Opsional | Override base URL Shopee API (default `https://open-api.shopee.com`) |
| `REFRESH_STALE_DAYS` | Opsional | Batas usia data Tokopedia sebelum dilaporkan basi (default 7) |
| `REFRESH_BATCH_LIMIT` | Opsional | Jumlah produk per run refresh (default 200) |

**PENTING:** `SHOPEE_API_BASE` dan path endpoint di dalam kode (`SHOPEE_GENERATE_LINK_PATH`,
`SHOPEE_ITEM_INFO_PATH`) masih bertanda TODO — validasi endpoint resmi di
https://open.shopee.com sebelum production, karena dokumentasi publik
bervariasi. Setelah tervalidasi, cukup ubah konstanta + parsing responsnya.

### Menjadwalkan refresh-catalog

**Opsi A — pg_cron + pg_net (di dalam Supabase):**

```sql
-- Simpan CRON_SECRET di vault, lalu:
select cron.schedule(
  'refresh-catalog-hourly',
  '0 * * * *',
  $$
  select net.http_post(
    url := 'https://<project-ref>.supabase.co/functions/v1/refresh-catalog',
    headers := jsonb_build_object(
      'x-cron-secret', '<CRON_SECRET>',
      'Content-Type', 'application/json'
    ),
    body := '{}'::jsonb
  );
  $$
);
```

**Opsi B — scheduler eksternal (GitHub Actions / cron VPS):**

```bash
curl -X POST https://<project-ref>.supabase.co/functions/v1/refresh-catalog \
  -H "x-cron-secret: $CRON_SECRET" \
  -H "Content-Type: application/json" \
  -d '{}'
```

Ganti `<project-ref>` dengan ref project Supabase-mu. Jangan pernah
menaruh `CRON_SECRET` di repository — simpan di secret manager scheduler.
