import 'dart:async';
import 'dart:isolate';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_mlkit_barcode_scanning/google_mlkit_barcode_scanning.dart';
import 'package:image/image.dart' as img;

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
  const CameraScanView({
    super.key,
    required this.onCode,
    this.aiLiveEnabled = false,
    this.onAiFrame,
  });

  /// Dipanggil tepat sekali setiap kali sebuah kode berhasil dibaca.
  final ValueChanged<String> onCode;

  /// Mode AI Live: bila aktif, frame kamera dikonversi ke JPEG secara
  /// berkala dan dikirim lewat [onAiFrame] untuk diidentifikasi AI.
  final bool aiLiveEnabled;

  /// Menerima JPEG frame kamera (sudah tegak & diperkecil) untuk AI Live.
  final ValueChanged<Uint8List>? onAiFrame;

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

  /// AI Live: frame terakhir dari aliran kamera + timer pengambilan berkala.
  CameraImage? _latestImage;
  Timer? _aiTimer;
  bool _aiConverting = false;

  /// Tanda tangan kecerahan frame (grid 16x16 dari bidang Y) untuk
  /// mendeteksi kamera stabil/terfokus: dua tanda tangan berurutan yang
  /// mirip = gambar diam = autofokus sudah mengunci.
  List<int>? _sigPrev;
  List<int>? _sigLast;
  DateTime _sigAt = DateTime.fromMillisecondsSinceEpoch(0);
  DateTime? _lastAiCaptureAt;

  /// Interval pemeriksaan frame untuk AI Live.
  static const _aiInterval = Duration(seconds: 2);

  /// Jeda minimum antar pengambilan foto AI (hemat kuota).
  static const _aiMinGap = Duration(seconds: 6);

  /// Bila kamera tak kunjung stabil, foto tetap diambil setelah jeda ini.
  static const _aiMaxWait = Duration(seconds: 12);

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
    if (widget.aiLiveEnabled) _startAiTimer();
  }

  @override
  void didUpdateWidget(CameraScanView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.aiLiveEnabled && !oldWidget.aiLiveEnabled) {
      _startAiTimer();
    } else if (!widget.aiLiveEnabled && oldWidget.aiLiveEnabled) {
      _aiTimer?.cancel();
      _aiTimer = null;
    }
  }

  void _startAiTimer() {
    _aiTimer?.cancel();
    _aiTimer = Timer.periodic(_aiInterval, (_) => _captureAiFrame());
  }

  /// Perbarui tanda tangan kecerahan (maks. 2x/detik) untuk deteksi stabil.
  void _updateSignature(CameraImage image) {
    final now = DateTime.now();
    if (now.difference(_sigAt) < const Duration(milliseconds: 500)) return;
    _sigAt = now;
    if (image.planes.isEmpty) return;
    final plane = image.planes[0];
    final bytes = plane.bytes;
    final stride = plane.bytesPerRow;
    const grid = 16;
    final stepY = image.height ~/ grid;
    final stepX = image.width ~/ grid;
    if (stepY < 1 || stepX < 1) return;
    final sig = List<int>.filled(grid * grid, 0);
    for (var gy = 0; gy < grid; gy++) {
      final row = gy * stepY * stride;
      for (var gx = 0; gx < grid; gx++) {
        sig[gy * grid + gx] = bytes[row + gx * stepX];
      }
    }
    _sigPrev = _sigLast;
    _sigLast = sig;
  }

  /// Kamera dianggap stabil/terfokus bila dua tanda tangan berurutan mirip.
  bool get _isStable {
    final a = _sigPrev;
    final b = _sigLast;
    if (a == null || b == null) return false;
    var diff = 0;
    for (var i = 0; i < a.length; i++) {
      diff += (a[i] - b[i]).abs();
    }
    return diff / a.length < 6.0;
  }

  /// Ambil frame terakhir, ubah ke JPEG di isolate, kirim ke [onAiFrame].
  /// Hanya diambil saat kamera stabil (autofokus mengunci) — atau bila
  /// sudah terlalu lama menunggu — dan tidak lebih sering dari [_aiMinGap].
  Future<void> _captureAiFrame() async {
    final image = _latestImage;
    if (image == null ||
        _aiConverting ||
        _codeHandled ||
        _status != _ScanViewStatus.ready ||
        !mounted) {
      return;
    }
    final onAiFrame = widget.onAiFrame;
    if (onAiFrame == null || image.planes.length != 3) return;

    final now = DateTime.now();
    final sinceLast =
        _lastAiCaptureAt == null ? null : now.difference(_lastAiCaptureAt!);
    if (sinceLast != null && sinceLast < _aiMinGap) return;
    final waitedLong = sinceLast == null || sinceLast >= _aiMaxWait;
    if (!_isStable && !waitedLong) return; // tunggu autofokus mengunci
    _lastAiCaptureAt = now;

    _aiConverting = true;
    try {
      final data = _FrameData(
        yBytes: image.planes[0].bytes,
        uBytes: image.planes[1].bytes,
        vBytes: image.planes[2].bytes,
        width: image.width,
        height: image.height,
        yRowStride: image.planes[0].bytesPerRow,
        uvRowStride: image.planes[1].bytesPerRow,
        uvPixelStride: image.planes[1].bytesPerPixel ?? 1,
        rotationDegrees: _lastRotation,
      );
      final jpeg = await Isolate.run(() => _frameToJpeg(data));
      if (jpeg != null && mounted && widget.aiLiveEnabled) {
        onAiFrame(jpeg);
      }
    } catch (_) {
      // Abaikan kegagalan konversi satu frame.
    } finally {
      _aiConverting = false;
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _scanAnim.dispose();
    _confirmTimer?.cancel();
    _focusTimer?.cancel();
    _aiTimer?.cancel();
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
    _latestImage = image; // simpan untuk AI Live (referensi murah)
    if (widget.aiLiveEnabled) _updateSignature(image);
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

/// Data satu frame YUV420 yang bisa dikirim ke isolate.
class _FrameData {
  const _FrameData({
    required this.yBytes,
    required this.uBytes,
    required this.vBytes,
    required this.width,
    required this.height,
    required this.yRowStride,
    required this.uvRowStride,
    required this.uvPixelStride,
    required this.rotationDegrees,
  });

  final Uint8List yBytes;
  final Uint8List uBytes;
  final Uint8List vBytes;
  final int width;
  final int height;
  final int yRowStride;
  final int uvRowStride;
  final int uvPixelStride;
  final int rotationDegrees;
}

/// Konversi frame YUV420 (Android) → JPEG tegak, setengah resolusi agar
/// ringan. Dijalankan di isolate lewat `Isolate.run`.
Uint8List? _frameToJpeg(_FrameData d) {
  const step = 2; // ambil tiap pixel ke-2 (turun resolusi 2x)
  final outW = d.width ~/ step;
  final outH = d.height ~/ step;
  if (outW < 8 || outH < 8) return null;
  var image = img.Image(width: outW, height: outH);
  for (var oy = 0; oy < outH; oy++) {
    final y = oy * step;
    final yRow = y * d.yRowStride;
    final uvRow = (y ~/ 2) * d.uvRowStride;
    for (var ox = 0; ox < outW; ox++) {
      final x = ox * step;
      final yVal = d.yBytes[yRow + x];
      final uvIdx = uvRow + (x ~/ 2) * d.uvPixelStride;
      final uVal = d.uBytes[uvIdx];
      final vVal = d.vBytes[uvIdx];
      var r = (yVal + 1.402 * (vVal - 128)).round();
      var g = (yVal - 0.344136 * (uVal - 128) - 0.714136 * (vVal - 128)).round();
      var b = (yVal + 1.772 * (uVal - 128)).round();
      r = r.clamp(0, 255);
      g = g.clamp(0, 255);
      b = b.clamp(0, 255);
      image.setPixelRgb(ox, oy, r, g, b);
    }
  }
  final rot = d.rotationDegrees % 360;
  if (rot != 0) {
    image = img.copyRotate(image, angle: rot);
  }
  return img.encodeJpg(image, quality: 80);
}
