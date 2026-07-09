import 'dart:io';
import 'package:camera/camera.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';

// Image-stream format the live ML Kit detectors can consume directly:
// NV21 on Android, BGRA8888 on iOS. (The previous yuv420 group produced
// YUV_420_888 frames that ML Kit rejects with "ImageFormat is not supported".)
ImageFormatGroup get mlKitImageFormatGroup =>
    Platform.isAndroid ? ImageFormatGroup.nv21 : ImageFormatGroup.bgra8888;

class RecordingService {
  CameraController? _controller;
  List<CameraDescription>? _cameras;

  CameraController? get controller => _controller;
  bool get isRecording => _controller?.value.isRecordingVideo ?? false;
  bool get isInitialized => _controller?.value.isInitialized ?? false;

  Future<bool> requestPermissions() async {
    final camera = await Permission.camera.request();
    final mic = await Permission.microphone.request();
    return camera.isGranted && mic.isGranted;
  }

  Future<bool> arePermissionsGranted() async {
    final camera = await Permission.camera.status;
    final mic = await Permission.microphone.status;
    return camera.isGranted && mic.isGranted;
  }

  Future<void> initialize({bool useFrontCamera = true}) async {
    _cameras = await availableCameras();
    if (_cameras == null || _cameras!.isEmpty) {
      throw Exception('No cameras available on this device');
    }

    final camera = _cameras!.firstWhere(
      (c) => useFrontCamera
          ? c.lensDirection == CameraLensDirection.front
          : c.lensDirection == CameraLensDirection.back,
      orElse: () => _cameras!.first,
    );

    _controller = CameraController(
      camera,
      ResolutionPreset.high,
      enableAudio: true,
      imageFormatGroup: mlKitImageFormatGroup,
    );

    await _controller!.initialize();

    // Lock the sensor to portrait so the preview (and recorded video) stay
    // upright instead of appearing rotated sideways/landscape. Wrapped in a
    // try/catch since not every platform supports orientation locking.
    try {
      await _controller!.lockCaptureOrientation(DeviceOrientation.portraitUp);
    } catch (_) {
      // Best-effort — ignore on platforms that don't support it.
    }
  }

  // Starts video recording. If [onImage] is given, camera frames are streamed
  // to it *during* recording via the plugin's concurrent capture API. (Calling
  // startImageStream separately throws because the plugin forbids streaming
  // while a recording is active — that was silently disabling live analysis.)
  Future<void> startRecording({void Function(CameraImage image)? onImage}) async {
    if (_controller == null || !_controller!.value.isInitialized) {
      throw Exception('Camera not initialized');
    }
    if (_controller!.value.isRecordingVideo) return;
    await _controller!.startVideoRecording(onAvailable: onImage);
  }

  Future<File> stopRecording() async {
    if (_controller == null || !_controller!.value.isRecordingVideo) {
      throw Exception('Not currently recording');
    }
    final xfile = await _controller!.stopVideoRecording();

    // Move from temp to app documents directory with a timestamped name
    final docsDir = await getApplicationDocumentsDirectory();
    final recordingsDir = Directory('${docsDir.path}/recordings');
    if (!await recordingsDir.exists()) {
      await recordingsDir.create(recursive: true);
    }
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final newPath = '${recordingsDir.path}/recording_$timestamp.mp4';
    final newFile = await File(xfile.path).copy(newPath);
    await File(xfile.path).delete().catchError((_) => File(xfile.path));

    return newFile;
  }

  // Stops a recording in progress and deletes the temp footage. Used when
  // the user abandons a session instead of finishing it.
  Future<void> discardRecording() async {
    if (_controller == null || !_controller!.value.isRecordingVideo) return;
    final xfile = await _controller!.stopVideoRecording();
    await File(xfile.path).delete().catchError((_) => File(xfile.path));
  }

  Future<void> dispose() async {
    await _controller?.dispose();
    _controller = null;
  }
}