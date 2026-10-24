# CekDulu

Aplikasi Flutter untuk memindai (scan) barcode/QR produk lewat HP, mencocokkannya
ke katalog, lalu menampilkan produk beserta **link affiliate Shopee/Tokopedia
milik pemilik aplikasi** — diurutkan berdasarkan rating/ulasan terbaik.

- **Package:** `com.kan.cekdulu`
- **Tech stack:** Flutter + Supabase (PostgreSQL, Auth, Row Level Security)

## Struktur

```
cekdulu/
├── app/                        # Project Flutter
│   └── lib/
│       ├── main.dart
│       └── src/
│           ├── app.dart                  # GoRouter + redirect auth/role
│           ├── core/
│           │   ├── config/supabase_config.dart  # init via --dart-define
│           │   ├── theme/app_theme.dart
│           │   └── widgets/common_widgets.dart
│           └── features/
│               ├── auth/       # login, register, verifikasi email
│               ├── scan/       # scan barcode/QR (mobile_scanner) + hasil
│               ├── catalog/    # daftar produk (ulasan terbaik), detail + link affiliate
│               └── admin/      # dashboard, CRUD katalog, kredensial affiliate,
│                               # form link Tokopedia, kelola pengguna
└── supabase/
    ├── migrations/   # skema + RLS policies
    └── seed/         # panduan seed akun test (dev/staging saja)
```

## Cara menjalankan

Flutter SDK sudah terinstall di `~/workspace/flutter-sdk`.

```sh
export PATH="$HOME/workspace/flutter-sdk/bin:$PATH"
cd ~/workspace/gobest/app

# Mode demo (tanpa backend):
flutter run

# Dengan backend Supabase:
flutter run \
  --dart-define=SUPABASE_URL=https://xyzcompany.supabase.co \
  --dart-define=SUPABASE_ANON_KEY=isi_publishable_key_di_sini
```

Perintah berguna lain:

```sh
flutter analyze   # cek lints (harus bersih)
flutter test      # unit test
```

> **Keamanan:** jangan pernah hardcode URL/key Supabase atau kredensial
> affiliate di source code. Kredensial affiliate Shopee disimpan terenkripsi
> di server (Edge Function secrets) dan kolom `secret` bersifat write-only.

## Status saat ini (scaffold awal)

Sudah selesai:

- [x] Struktur project feature-first + navigasi GoRouter (redirect berdasarkan
      status login & peran admin/pengguna)
- [x] Auth: registrasi email, login, layar verifikasi email
- [x] Scan barcode/QR + pencocokan ke katalog + label "Ulasan terbaik"
- [x] Katalog produk terurut rating/review + detail + tombol buka link affiliate
- [x] Panel admin: dashboard, CRUD katalog, form kredensial Shopee,
      form tempel link Tokopedia, kelola peran pengguna
- [x] `flutter analyze` bersih, `flutter test` lolos

Belum / butuh tindak lanjut:

- [ ] Hubungkan ke project Supabase asli (migrasi di `supabase/` belum dijalankan
      ke project production)
- [ ] Trigger pembuatan row `profiles` saat user registrasi (mis. via Database
      Webhook / trigger di Supabase)
- [ ] Edge Function `save-affiliate-secret` untuk Secret Shopee (write-only)
- [ ] Edge Function generate link affiliate Shopee otomatis via Shopee Open Platform API
- [ ] Job refresh berkala harga/rating/stok produk
- [ ] Build release (butuh Android SDK / Xcode) & submit ke Play Store / App Store
- [ ] Cek merek "CekDulu" ke DJKI sebelum rilis publik
