import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:camera_android/camera_android.dart';
import 'package:cekdulu/src/app.dart';
import 'package:cekdulu/src/core/config/supabase_config.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Paksa implementasi kamera Camera2 (camera_android), bukan CameraX
  // (camera_android_camerax): CameraX gagal inisialisasi di sebagian HP
  // (mis. Redmi Note 8 Pro) walau izin sudah diberikan.
  AndroidCamera.registerWith();
  await SupabaseConfig.initialize();
  runApp(const ProviderScope(child: CekDuluApp()));
}
