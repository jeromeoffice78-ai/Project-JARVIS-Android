import 'dart:async';

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';

import '../../core/network/jarvis_api_service.dart';

enum JarvisVisionState {
  inactive,
  initializing,
  active,
  error,
}

class JarvisVisionService {
  JarvisVisionService({
    required JarvisApiService apiService,
    this.frameInterval = const Duration(milliseconds: 1500),
  }) : _apiService = apiService {
    if (_supportsLocalFaceDetection) {
      _faceDetector = FaceDetector(
        options: FaceDetectorOptions(
          performanceMode: FaceDetectorMode.fast,
          enableLandmarks: false,
          enableContours: false,
          enableClassification: false,
          enableTracking: false,
          minFaceSize: 0.12,
        ),
      );
    }
  }

  final JarvisApiService _apiService;
  final Duration frameInterval;

  final StreamController<JarvisVisionState> _stateController =
      StreamController<JarvisVisionState>.broadcast();

  final StreamController<String?> _errorController =
      StreamController<String?>.broadcast();

  final StreamController<int> _faceCountController =
      StreamController<int>.broadcast();

  FaceDetector? _faceDetector;

  CameraController? _cameraController;
  List<CameraDescription> _cameras = const <CameraDescription>[];
  Timer? _captureTimer;
  bool _captureInProgress = false;
  bool _disposed = false;
  int _cameraIndex = 0;

  JarvisVisionState _state = JarvisVisionState.inactive;

  Stream<JarvisVisionState> get stateStream => _stateController.stream;
  Stream<String?> get errorStream => _errorController.stream;
  Stream<int> get faceCountStream => _faceCountController.stream;

  JarvisVisionState get state => _state;
  CameraController? get cameraController => _cameraController;

  bool get isActive => _state == JarvisVisionState.active;

  Future<void> start() async {
    if (_disposed) {
      throw StateError('JarvisVisionService has been disposed.');
    }

    if (_state == JarvisVisionState.initializing ||
        _state == JarvisVisionState.active) {
      return;
    }

    _setState(JarvisVisionState.initializing);
    _emitError(null);

    try {
      _cameras = await availableCameras();

      if (_cameras.isEmpty) {
        throw StateError('No device camera is available.');
      }

      _cameraIndex = _preferredBackCameraIndex(_cameras);

      await _initializeCamera(_cameras[_cameraIndex]);

      _setState(JarvisVisionState.active);

      await _captureAndUpload();

      _captureTimer = Timer.periodic(
        frameInterval,
        (_) {
          unawaited(_captureAndUpload());
        },
      );
    } on CameraException catch (error) {
      _setState(JarvisVisionState.error);
      _emitError(
        'Camera error ${error.code}: ${error.description ?? 'unknown'}',
      );
    } on Object catch (error) {
      _setState(JarvisVisionState.error);
      _emitError(error.toString());
    }
  }

  Future<void> stop() async {
    _captureTimer?.cancel();
    _captureTimer = null;

    final CameraController? controller = _cameraController;
    _cameraController = null;

    if (controller != null) {
      await controller.dispose();
    }

    try {
      await _apiService.clearVisionFrame();
    } on Object catch (error) {
      debugPrint('Unable to clear backend vision frame: $error');
    }

    if (!_faceCountController.isClosed) {
      _faceCountController.add(0);
    }

    if (!_disposed) {
      _setState(JarvisVisionState.inactive);
    }
  }

  Future<void> switchCamera() async {
    if (_cameras.length < 2 || _state != JarvisVisionState.active) {
      return;
    }

    _captureTimer?.cancel();
    _captureTimer = null;

    _cameraIndex = (_cameraIndex + 1) % _cameras.length;
    await _initializeCamera(_cameras[_cameraIndex]);

    await _captureAndUpload();

    _captureTimer = Timer.periodic(
      frameInterval,
      (_) => unawaited(_captureAndUpload()),
    );
  }

  Future<void> refreshFrameNow() async {
    if (!isActive) {
      return;
    }

    await _captureAndUpload();
  }

  Future<void> _initializeCamera(
    CameraDescription description,
  ) async {
    final CameraController? oldController = _cameraController;
    _cameraController = null;

    if (oldController != null) {
      await oldController.dispose();
    }

    final CameraController controller = CameraController(
      description,
      ResolutionPreset.medium,
      enableAudio: false,
    );

    await controller.initialize();

    _cameraController = controller;
  }

  Future<void> _captureAndUpload() async {
    if (_disposed ||
        _state != JarvisVisionState.active ||
        _captureInProgress) {
      return;
    }

    final CameraController? controller = _cameraController;

    if (controller == null ||
        !controller.value.isInitialized ||
        controller.value.isTakingPicture) {
      return;
    }

    _captureInProgress = true;

    try {
      final XFile frame = await controller.takePicture();
      final List<int> bytes = await frame.readAsBytes();

      if (bytes.isEmpty) {
        return;
      }

      final FaceDetector? detector = _faceDetector;

      if (detector != null) {
        try {
          final InputImage inputImage =
              InputImage.fromFilePath(frame.path);

          final List<Face> faces =
              await detector.processImage(inputImage);

          if (!_faceCountController.isClosed) {
            _faceCountController.add(faces.length);
          }
        } on Object catch (error) {
          debugPrint(
            'Face-presence detection failed: $error',
          );
        }
      }

      await _apiService.uploadVisionFrame(
        bytes: bytes,
        filename: frame.name.toLowerCase().endsWith('.jpg') ||
                frame.name.toLowerCase().endsWith('.jpeg')
            ? frame.name
            : 'jarvis_vision_frame.jpg',
      );

      _emitError(null);
    } on CameraException catch (error) {
      _emitError(
        'Camera capture error ${error.code}: '
        '${error.description ?? 'unknown'}',
      );
    } on Object catch (error) {
      _emitError('Vision upload failed: $error');
    } finally {
      _captureInProgress = false;
    }
  }

  bool get _supportsLocalFaceDetection {
    if (kIsWeb) {
      return false;
    }

    return defaultTargetPlatform == TargetPlatform.android ||
        defaultTargetPlatform == TargetPlatform.iOS;
  }

  static int _preferredBackCameraIndex(
    List<CameraDescription> cameras,
  ) {
    final int index = cameras.indexWhere(
      (CameraDescription camera) =>
          camera.lensDirection == CameraLensDirection.back,
    );

    return index >= 0 ? index : 0;
  }

  void _setState(JarvisVisionState state) {
    if (_disposed || _stateController.isClosed || state == _state) {
      return;
    }

    _state = state;
    _stateController.add(state);
  }

  void _emitError(String? message) {
    if (!_disposed && !_errorController.isClosed) {
      _errorController.add(message);
    }
  }

  Future<void> dispose() async {
    if (_disposed) {
      return;
    }

    await stop();

    await _faceDetector?.close();
    _faceDetector = null;

    _disposed = true;

    await Future.wait<void>(<Future<void>>[
      _stateController.close(),
      _errorController.close(),
      _faceCountController.close(),
    ]);
  }
}
