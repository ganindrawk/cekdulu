import 'dart:async';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_mlkit_barcode_scanning/google_mlkit_barcode_scanning.dart';

import 'package:cekdulu/src/features/scan/presentation/scan_overlay.dart';

/// Tampilan scan barcode/QR.
///
/// Memakai plugin `camera` resmi dengan implementasi Camera2 di Android
/// (dipaksa lewat `AndroidCamera.registerWith()` di `main()`, bukan CameraX)
/// + ML Kit untuk deteksi barcode dari aliran frame kamera.
///
/// Pengganti mobile_scanner: CameraX gagal inisialisasi di sebagian HP
/// (mis. Redmi Note 8 Pro) walau izin kamera sudah diberikan.
///
/// Umpan balik visual yang diberikan ke pengguna:
/// - preview selalu di tengah area (bukan menempel ke atas),
/// - garis pindai beranimasi + status "Mencari barcode…" selagi aktif,
/// - status "Barcode terbaca, memproses…" saat kode dikunci,
/// - ketuk layar untuk fokus manual (cincin fokus sesaat).
class CameraScanView extends StatefulWidget {
  const CameraScanView({super.key, required this.onCode});

  /// Dipanggil tepat sekali setiap kali sebuah kode berhasil dibaca.
  final ValueChanged<String> onCode;

  @override
  State<CameraScanView> createState() => _CameraScanViewState();
}

enum _ScanViewStatus { initializing, ready, error }

class _CameraScanViewState extends State<CameraScanView>
    with WidgetsBindingObserver, SingleTickerProviderStateMixin {
  CameraController? _controller;
  CameraDescription? _cameraDescription;
  late final BarcodeScanner _barcodeScanner = BarcodeScanner();
  _ScanViewStatus _status = _ScanViewStatus.initializing;
  String? _errorMessage;
  bool _processingFrame = false;
  bool _codeHandled = false;
  bool _streaming = false;

  /// Box barcode yang sedang terlihat (koordinat gambar asli).
  List<Rect> _boxes = const [];
  Size? _lastImageSize;
  int _lastRotation = 0;

  /// Kode yang sedang "dikunci" (tunggu sebentar sebelum dinavigasi
  /// agar kotak hijaunya sempat terlihat).
  String? _confirmingCode;
  Timer? _confirmTimer;

  /// Animasi garis pindai (berulang selama status "mencari").
  late final AnimationController _scanAnim = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 2),
  )..repeat();

  final _previewKey = GlobalKey();

  /// Titik fokus manual terakhir (koordinat relatif 0..1 dalam preview),
  /// ditampilkan sebagai cincin sesaat.
  Offset? _focusPoint;
  Timer? _focusTimer;

  static const _orientations = <DeviceOrientation, int>{
    DeviceOrientation.portraitUp: 0,
    DeviceOrientation.landscapeLeft: 90,
    DeviceOrientation.portraitDown: 180,
    DeviceOrientation.landscapeRight: 270,
  };

  /// Jeda antara barcode terkunci dan navigasi ke hasil.
  static const _confirmDelay = Duration(milliseconds: 700);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initCamera();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _scanAnim.dispose();
    _confirmTimer?.cancel();
    _focusTimer?.cancel();
    _disposeCamera();
    _barcodeScanner.close();
    super.dispose();
  }

  Future<void> _disposeCamera() async {
    final controller = _controller;
    _controller = null;
    _streaming = false;
    try {
      await controller?.stopImageStream();
    } catch (_) {
      // Abaikan.
    }
    try {
      await controller?.dispose();
    } catch (_) {
      // Abaikan.
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (_controller == null) return;
    if (state == AppLifecycleState.inactive) {
      _stopStream();
    } else if (state == AppLifecycleState.resumed) {
      if (_status == _ScanViewStatus.ready && !_codeHandled) {
        _startStream();
      }
    }
  }

  /// Inisialisasi penuh dari nol (dipakai saat pertama kali dan saat retry).
  Future<void> _initCamera() async {
    await _disposeCamera();
    if (!mounted) return;
    setState(() {
      _status = _ScanViewStatus.initializing;
      _errorMessage = null;
      _codeHandled = false;
      _confirmingCode = null;
      _focusPoint = null;
      _boxes = const [];
    });
    try {
      final cameras = await availableCameras();
      if (cameras.isEmpty) {
        throw CameraException(
            'NoCamera', 'Tidak ada kamera yang ditemukan di perangkat ini.');
      }
      _cameraDescription = cameras.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.back,
        orElse: () => cameras.first,
      );
      final controller = CameraController(
        _cameraDescription!,
        ResolutionPreset.medium,
        enableAudio: false,
        imageFormatGroup: ImageFormatGroup.yuv420,
      );
      _controller = controller;
      await controller.initialize();
      if (!mounted) return;
      await _startStream();
      if (!mounted) return;
      setState(() => _status = _ScanViewStatus.ready);
    } on CameraException catch (e) {
      if (!mounted) return;
      setState(() {
        _status = _ScanViewStatus.error;
        _errorMessage = e.description?.isNotEmpty == true
            ? '${e.code}: ${e.description}'
            : e.code;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _status = _ScanViewStatus.error;
        _errorMessage = e.toString();
      });
    }
  }

  Future<void> _startStream() async {
    final controller = _controller;
    if (controller == null || _streaming || _codeHandled || !mounted) return;
    try {
      await controller.startImageStream(_onImage);
      _streaming = true;
    } catch (_) {
      _streaming = false;
    }
  }

  Future<void> _stopStream() async {
    final controller = _controller;
    if (controller == null || !_streaming) return;
    _streaming = false;
    try {
      await controller.stopImageStream();
    } catch (_) {
      // Abaikan.
    }
  }

  Future<void> _onImage(CameraImage image) async {
    if (_processingFrame || _codeHandled || !mounted) return;
    _processingFrame = true;
    try {
      final imgSize = Size(image.width.toDouble(), image.height.toDouble());
      final inputImage = _toInputImage(image);
      if (inputImage == null) return;
      final barcodes = await _barcodeScanner.processImage(inputImage);
      if (!mounted || _codeHandled) return;

      final boxes = <Rect>[];
      String? code;
      for (final b in barcodes) {
        boxes.add(b.boundingBox);
        code ??= b.rawValue;
      }
      if (code != null && code.isNotEmpty) {
        final isNew = _confirmingCode == null;
        _confirmingCode ??= code;
        setState(() {
          _boxes = boxes;
          _lastImageSize = imgSize;
        });
        if (isNew) _startConfirmTimer(code);
      } else if (_confirmingCode == null && _boxes.isNotEmpty) {
        setState(() => _boxes = const []);
      }
    } catch (_) {
      // Abaikan kegagalan satu frame; frame berikutnya dicoba lagi.
    } finally {
      _processingFrame = false;
    }
  }

  void _startConfirmTimer(String code) {
    _confirmTimer?.cancel();
    _confirmTimer = Timer(_confirmDelay, () {
      if (!mounted || _codeHandled) return;
      _codeHandled = true;
      _confirmTimer = null;
      _confirmingCode = null;
      _stopStream();
      // Getar singkat: tanda barcode berhasil terbaca.
      HapticFeedback.mediumImpact();
      widget.onCode(code);
    });
  }

  /// Ketuk layar: fokuskan kamera ke titik yang diketuk.
  void _onTapToFocus(TapDownDetails details) {
    final controller = _controller;
    final box =
        _previewKey.currentContext?.findRenderObject() as RenderBox?;
    if (controller == null || box == null || !box.hasSize) return;
    final local = box.globalToLocal(details.globalPosition);
    final rel = Offset(
      (local.dx / box.size.width).clamp(0.0, 1.0),
      (local.dy / box.size.height).clamp(0.0, 1.0),
    );
    unawaited(controller.setFocusPoint(rel).catchError((_) {}));
    setState(() => _focusPoint = rel);
    _focusTimer?.cancel();
    _focusTimer = Timer(const Duration(seconds: 1), () {
      if (mounted) setState(() => _focusPoint = null);
    });
  }

  InputImage? _toInputImage(CameraImage image) {
    final camera = _cameraDescription;
    final controller = _controller;
    if (camera == null || controller == null) return null;

    final rotationCompensation =
        _orientations[controller.value.deviceOrientation];
    if (rotationCompensation == null) return null;

    final sensorOrientation = camera.sensorOrientation;
    final compensated = camera.lensDirection == CameraLensDirection.front
        ? (sensorOrientation + rotationCompensation) % 360
        : (sensorOrientation - rotationCompensation + 360) % 360;
    _lastRotation = compensated;

    final rotation = InputImageRotationValue.fromRawValue(compensated);
    final format = InputImageFormatValue.fromRawValue(image.format.raw);
    if (rotation == null || format == null) return null;
    if (image.planes.length != 3) return null;

    final allBytes = WriteBuffer();
    for (final plane in image.planes) {
      allBytes.putUint8List(plane.bytes);
    }
    final bytes = allBytes.done().buffer.asUint8List();

    return InputImage.fromBytes(
      bytes: bytes,
      metadata: InputImageMetadata(
        size: Size(image.width.toDouble(), image.height.toDouble()),
        rotation: rotation,
        format: format,
        bytesPerRow: image.planes[0].bytesPerRow,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    switch (_status) {
      case _ScanViewStatus.initializing:
        return Container(
          color: Colors.black,
          alignment: Alignment.center,
          child: const Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(),
              SizedBox(height: 12),
              Text(
                'Menyiapkan kamera...',
                style: TextStyle(color: Colors.white70),
              ),
            ],
          ),
        );
      case _ScanViewStatus.error:
        return Container(
          color: Colors.black,
          alignment: Alignment.center,
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.videocam_off_outlined,
                  color: Colors.white70,
                  size: 48,
                ),
                const SizedBox(height: 12),
                const Text(
                  'Kamera tidak dapat diakses.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.white),
                ),
                if (_errorMessage != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    _errorMessage!,
                    textAlign: TextAlign.center,
                    style:
                        const TextStyle(color: Colors.white54, fontSize: 12),
                  ),
                ],
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: _initCamera,
                  child: const Text('Muat ulang kamera'),
                ),
              ],
            ),
          ),
        );
      case _ScanViewStatus.ready:
        final controller = _controller;
        if (controller == null || !controller.value.isInitialized) {
          return const ColoredBox(color: Colors.black);
        }
        final scanning = _confirmingCode == null;
        return Stack(
          fit: StackFit.expand,
          children: [
            const ColoredBox(color: Colors.black),
            // Preview selalu di tengah area, bukan menempel ke atas.
            Center(
              child: GestureDetector(
                onTapDown: _onTapToFocus,
                child: CameraPreview(
                  key: _previewKey,
                  controller,
                  child: AnimatedBuilder(
                    animation: _scanAnim,
                    builder: (context, _) => CustomPaint(
                      painter: ScanOverlayPainter(
                        boxes: _boxes,
                        imageSize: _lastImageSize ?? Size.zero,
                        rotationDegrees: _lastRotation,
                        locked: _confirmingCode != null,
                        scanT: scanning ? _scanAnim.value : null,
                        focusPoint: _focusPoint,
                      ),
                    ),
                  ),
                ),
              ),
            ),
            // Status di atas: umpan balik bahwa kamera sedang bekerja.
            Positioned(
              top: 12,
              left: 0,
              right: 0,
              child: Center(
                child: AnimatedBuilder(
                  animation: _scanAnim,
                  builder: (context, _) => Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 8),
                    decoration: BoxDecoration(
                      color: Colors.black54,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (scanning)
                          Opacity(
                            opacity:
                                0.4 + 0.6 * (0.5 + 0.5 * _scanAnim.value),
                            child: const Icon(
                              Icons.fiber_manual_record,
                              size: 12,
                              color: Colors.greenAccent,
                            ),
                          )
                        else
                          const SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.greenAccent,
                            ),
                          ),
                        const SizedBox(width: 8),
                        Text(
                          scanning
                              ? 'Mencari barcode…'
                              : 'Barcode terbaca, memproses…',
                          style: const TextStyle(
                              color: Colors.white, fontSize: 13),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        );
    }
  }
}
