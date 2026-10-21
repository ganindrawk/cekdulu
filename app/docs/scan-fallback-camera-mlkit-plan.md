# Rencana fallback scan: `camera` + `google_mlkit_barcode_scanning`

**Status:** RENCANA SIAP — JANGAN EKSEKUSI sebelum Kan melaporkan hasil tes restart HP.
**Dibuat:** 2026-10-16 ~11:45 WIB oleh Kai (riset proaktif, stage-1).
**Pemicu eksekusi:** Kan sudah restart Redmi Note 8 Pro + tes aplikasi Kamera bawaan,
lalu melaporkan scan CekDulu MASIH error (kode genericError) sementara kamera bawaan normal.

## Diagnosis yang mendasari

- Error `genericError` dari layar self-diagnosing = `ProcessCameraProvider.getInstance().get()`
  mengembalikan null di native layer mobile_scanner 5.2.3 (CameraX 1.3.3 gagal inisialisasi).
  Izin kamera SUDAH lolos — ini bukan masalah izin.
- `mobile_scanner` 5.x di Android berjalan di atas **CameraX**. Plugin resmi **`camera`**
  memakai **Camera2 API langsung** (tanpa CameraX), jadi kegagalan init CameraX tidak
  ikut terbawa. Ini jalur escape hatch yang umum dipakai untuk HP yang rewel dengan CameraX.
- Model barcode ML Kit yang dipakai `google_mlkit_barcode_scanning` adalah model **bundled**
  (`com.google.mlkit:barcode-scanning:17.3.0`) — jalan 100% on-device, **tidak butuh
  Google Play Services**, tidak ada download model saat runtime.

## Versi yang sudah diverifikasi (2026-10-16, via pub.dev API)

| Package | Versi pin | Syarat SDK | Cocok Flutter 3.47.7 / Dart 3.13.5 |
|---|---|---|---|
| `camera` | `^0.12.1` | `sdk: ^3.12.0`, `flutter: >=3.44.0` | ✅ |
| `google_mlkit_barcode_scanning` | `^0.16.1` | `sdk: ^3.12.0`, `flutter: >=3.44.0` | ✅ (pub.dev menganalisis versi ini dengan Flutter 3.47.7 / Dart 3.13.5 tepat — 150 pub points) |

`minSdk` aplikasi = `flutter.minSdkVersion` (default 21) — memenuhi syarat ML Kit & camera plugin.
`AndroidManifest.xml` sudah mendeklarasikan `CAMERA` ✅. `Info.plist` sudah punya
`NSCameraUsageDescription` ✅. Tidak ada izin baru yang dibutuhkan.

## Perubahan pubspec.yaml (`app/pubspec.yaml`)

```yaml
dependencies:
  # HAPUS: mobile_scanner: ^5.2.3  (digantikan total; ikut membuang transitive CameraX)
  camera: ^0.12.1
  google_mlkit_barcode_scanning: ^0.16.1
```

Keputusan sadar: hapus `mobile_scanner` sekalian (bukan dua-duanya dipasang) — mengurangi
ukuran APK dan menghindari konflik dependensi CameraX vs Camera2.

## Perubahan `lib/src/features/scan/presentation/scan_screen.dart`

Hanya mesin kameranya yang diganti. Yang **dipakai ulang tanpa perubahan**:
`_onCodeDetected` (findByScannedCode + logScan + navigasi hasil), input kode manual,
tampilan hasil `ScanResultScreen`, placeholder "Menyiapkan kamera...", pola error + tombol retry.

Struktur baru `_ScanScreenState`:

1. **State:** `CameraController? _cam; BarcodeScanner _mlkit; bool _processing=false,
   bool _camReady=false; String? _camError;` (tetap `WidgetsBindingObserver`).
2. **init:** `availableCameras()` → pilih `lensDirection == back` (fallback: pertama).
   `CameraController(cam, ResolutionPreset.medium, enableAudio: false,
   imageFormatGroup: ImageFormatGroup.yuv420)` → `initialize()` →
   `startImageStream(_onFrame)`. Tangkap exception init → tampilkan di UI error
   (kode + tombol "Muat ulang kamera" memanggil ulang init dari nol).
3. **_onFrame(CameraImage img):** `if (_processing || _handling) return;`
   `_processing = true;` lalu:
   - Gabung `img.planes[].bytes` jadi satu `Uint8List`.
   - `InputImageMetadata(size: Size(img.width, img.height), rotation: <rotasi>,
     format: InputImageFormatValue.fromRawValue(img.format.raw) ?? nv21,
     bytesPerRow: img.planes[0].bytesPerRow)`.
   - `InputImage.fromBytes(bytes: ..., metadata: ...)` →
     `await _mlkit.processImage(...)` → `barcodes.firstOrNull?.rawValue` →
     panggil `_onCodeDetected(code)` (ia yang menghentikan stream & menavigasi).
   - `finally { _processing = false; }` + try/catch agar satu frame gagal tidak mematikan stream.
4. **Rotasi** (pola kanonis contoh ML Kit):
   - iOS: `InputImageRotationValue.fromRawValue(sensorOrientation)`.
   - Android: kompensasi orientasi device —
     `(sensorOrientation - orientationDegrees(deviceOrientation) + 360) % 360`,
     dengan peta portraitUp→0, landscapeLeft→90, portraitDown→180, landscapeRight→270.
   - Untuk MVP portrait-only, `sensorOrientation` (umumnya 90° → rotation90deg) saja sudah cukup;
     verifikasi di HP Kan.
5. **Format barcode:** `BarcodeScanner(formats: [BarcodeFormat.ean13, BarcodeFormat.qrCode,
   BarcodeFormat.upca, BarcodeFormat.code128])` — EAN-13 untuk barcode fisik produk,
   QR untuk URL. (`BarcodeFormat.all` juga boleh; daftar eksplisit sedikit lebih hemat.)
6. **Lifecycle:** `didChangeAppLifecycleState` — pause → `stopImageStream()`;
   resumed → start ulang bila `_camReady && !_handling`. `dispose()` →
   `stopImageStream()`, `_cam.dispose()`, `_mlkit.close()`.
7. **UI preview:** `CameraPreview(_cam!)` menggantikan widget `MobileScanner`;
   bungkus dengan `AspectRatio` dari `_cam.value.aspectRatio` agar tidak gepeng.
   Pertahankan overlay teks "Arahkan kamera ke barcode / QR produk".

## Build, uji, rilis (pola yang sama seperti build sebelumnya)

1. `export PATH="$HOME/workspace/flutter-sdk/bin:$PATH"` lalu
   `flutter pub get && flutter analyze` (harus bersih) `&& flutter test`.
2. `flutter build apk --release --dart-define=SUPABASE_URL=https://mfppajuxqugxncpgkxun.supabase.co --dart-define=SUPABASE_ANON_KEY=<anon key>`
   (anon key = `sb_publishable_...` client-safe yang sudah dipakai build sebelumnya —
   ambil dari build script/catatan sebelumnya, JANGAN tulis ulang dari memori bila ragu;
   cek `TOOLS.md`/riwayat build).
3. Verifikasi: `aapt dump badging` → package `com.kan.cekdulu`, permission CAMERA ada.
4. Upload via file-hosting, kirim link ke Kan (berlaku ~2 hari, install menimpa versi lama).
5. Minta Kan: buka Scan → laporkan preview hidup / error apa; scan satu barcode produk
   (katalog masih kosong → hasil "Tidak ada produk yang cocok" = SUKSES untuk mesin scan).

## Catatan jujur / risiko

- APK akan membesar (model ML Kit bundled ikut ter-embed; perkiraan +10–20 MB dari 68 MB).
- Ini tetap memakai HAL kamera fisik yang sama — bila aplikasi Kamera bawaan pun gagal
  setelah restart, masalahnya hardware/HAL dan **tidak ada** jalur software yang bisa
  memperbaikinya. Fallback terakhir produk: input kode manual (sudah ada di layar).
- `IndexedStack` tab: stream hanya dikelola via app-lifecycle (paritas dengan perilaku
  saat ini); pindah tab tidak mematikan stream — catat sebagai batasan untuk diverifikasi.
- `ResolutionPreset.medium` dipilih untuk kecepatan deteksi; naikkan ke `high` hanya bila
  barcode kecil sulit terbaca dan HP Kan masih mulus.
