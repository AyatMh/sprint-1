import 'dart:async';
import 'dart:io';
import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import '../../../data/repositories/recording_repository.dart';
import '../../../data/services/recording_service.dart';

enum RecordingState { idle, initializing, ready, recording, saving, error }

// Result of a finished take: the saved file plus the Firestore document ID
// created for it, so later writes (live metrics, upload) target the exact
// recording instead of guessing "the latest one".
class SavedRecording {
  final File file;
  final String recordingId;

  SavedRecording({required this.file, required this.recordingId});
}

class RecordingProvider extends ChangeNotifier {
  final RecordingService _service = RecordingService();
  final RecordingRepository _repo = RecordingRepository();

  RecordingService get service => _service;

  RecordingState _state = RecordingState.idle;
  RecordingState get state => _state;

  String? _errorMessage;
  String? get errorMessage => _errorMessage;

  DateTime? _recordStartTime;
  Duration _elapsed = Duration.zero;
  Duration get elapsed => _elapsed;
  Timer? _ticker;

  Future<void> initialize() async {
    _setState(RecordingState.initializing);
    try {
      final granted = await _service.requestPermissions();
      if (!granted) {
        _errorMessage = 'Camera and microphone permissions are required.';
        _setState(RecordingState.error);
        return;
      }
      await _service.initialize(useFrontCamera: true);
      _setState(RecordingState.ready);
    } catch (e) {
      _errorMessage = 'Failed to start camera: $e';
      _setState(RecordingState.error);
    }
  }

  Future<void> startRecording({void Function(CameraImage image)? onImage}) async {
    if (_state != RecordingState.ready) return;
    try {
      await _service.startRecording(onImage: onImage);
      _recordStartTime = DateTime.now();
      _elapsed = Duration.zero;
      _ticker = Timer.periodic(const Duration(milliseconds: 200), (_) {
        if (_recordStartTime != null) {
          _elapsed = DateTime.now().difference(_recordStartTime!);
          notifyListeners();
        }
      });
      _setState(RecordingState.recording);
    } catch (e) {
      _errorMessage = 'Failed to start recording: $e';
      _setState(RecordingState.error);
    }
  }

  Future<SavedRecording?> stopAndSave(
    String userId, {
    required String name,
    required String category,
    bool usedAiCoach = false,
    List<Map<String, dynamic>>? aiCoachQuestions,
    double speechStartSeconds = 0.0,
  }) async {
    if (_state != RecordingState.recording) return null;
    _ticker?.cancel();
    _setState(RecordingState.saving);

    try {
      final file = await _service.stopRecording();
      final stat = await file.stat();
      final recordingId = await _repo.saveMetadata(
        userId: userId,
        localPath: file.path,
        durationMs: _elapsed.inMilliseconds,
        fileSizeBytes: stat.size,
        name: name,
        category: category,
        usedAiCoach: usedAiCoach,
        aiCoachQuestions: aiCoachQuestions,
        speechStartSeconds: speechStartSeconds,
      );
      _recordStartTime = null;
      _setState(RecordingState.ready);
      return SavedRecording(file: file, recordingId: recordingId);
    } catch (e) {
      _errorMessage = 'Failed to save recording: $e';
      _setState(RecordingState.error);
      return null;
    }
  }

  // Stops an in-progress take and throws the footage away (user backed out).
  Future<void> discard() async {
    _ticker?.cancel();
    _recordStartTime = null;
    try {
      await _service.discardRecording();
    } catch (_) {}
    _setState(RecordingState.ready);
  }

  void _setState(RecordingState s) {
    _state = s;
    notifyListeners();
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _service.dispose();
    super.dispose();
  }
}