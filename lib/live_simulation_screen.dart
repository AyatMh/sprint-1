import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:camera/camera.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:google_mlkit_pose_detection/google_mlkit_pose_detection.dart';
import 'package:provider/provider.dart';

import 'data/models/interview_question.dart';
import 'features/recording/providers/recording_provider.dart';
import 'features/auth/providers/auth_provider.dart';
import 'features/recording/screens/session_complete_screen.dart';
import 'core/theme/app_theme.dart';

class LiveSimulationScreen extends StatefulWidget {
  final String initialCategory;

  // Questions from the user's question bank for this category, if any. When
  // non-empty, the AI coach shows them one at a time during the recording.
  final List<InterviewQuestion> questions;

  const LiveSimulationScreen({
    super.key,
    required this.initialCategory,
    this.questions = const [],
  });

  @override
  State<LiveSimulationScreen> createState() => _LiveSimulationScreenState();
}

class _LiveSimulationScreenState extends State<LiveSimulationScreen> {
  Timer? _timer;
  int _startSeconds = 600;
  bool _isSaving = false;

  // True while a take is actually being recorded; leaving the screen in
  // this state asks for confirmation and discards the footage.
  bool _sessionActive = false;

  // ===== Detectors =====
  late FaceDetector _faceDetector;
  late PoseDetector _poseDetector;
  bool _isProcessingImage = false;
  int _frameCount = 0;

  // Pose detection is heavier than face detection, so we only run it on
  // every Nth processed frame to keep the live preview smooth.
  static const int _kPoseFrameInterval = 2;

  // ===== Session details (captured before recording starts) =====
  String _recordingName = '';
  late String _recordingCategory;

  // ===== AI coach: asks the user's saved questions one at a time =====
  int _questionIndex = 0;
  bool get _hasQuestions => widget.questions.isNotEmpty;

  void _nextQuestion() {
    if (_questionIndex < widget.questions.length - 1) {
      setState(() => _questionIndex++);
    }
  }

  // ===== Live face metrics (smoothed values are what the UI shows) =====
  double _confidencePercentage = 0.0;
  String _eyeContactStatus = "Active";
  int _lookingAwayCount = 0; // debounced events, not per-frame
  double _smoothedConfidence = 0.0;
  bool _hasSmoothedConfidence = false;

  // ===== Live posture metrics =====
  String _postureStatus = "Stable";
  int _postureShiftCount = 0; // debounced events, not per-frame
  double _smoothedPosture = 100.0;
  bool _hasSmoothedPosture = false;

  // ===== Time-weighted accumulators (remove frame-rate bias) =====
  // Average = sum(value * dt) / sum(dt), so faster frame delivery doesn't
  // over-weight a stretch of the session.
  final Stopwatch _clock = Stopwatch();
  int _lastConfMs = 0;
  double _confSum = 0, _confWeight = 0;
  int _lastPostMs = 0;
  double _postSum = 0, _postWeight = 0;

  // ===== Look-away / posture-shift debounce (count sustained events) =====
  bool _awayActive = false; // currently in a not-looking stretch
  int _awayStartMs = 0;
  bool _awayCounted = false;
  bool _shiftActive = false;
  int _shiftStartMs = 0;
  bool _shiftCounted = false;
  static const int _kSustainMs = 600; // hold this long before it counts
  static const double _kEmaAlpha = 0.2;
  static const int _kMaxDtMs = 500; // clamp gaps so stalls don't skew averages

  // ===== Calibration (neutral baseline before scoring starts) =====
  // Seconds the user gets to settle and look at the camera before scoring.
  static const int _kCalibSeconds = 6;
  bool _calibrating = false;
  int _calibCountdown = _kCalibSeconds;
  Timer? _calibTimer;
  int _calibFaceSamples = 0;
  double _calibYawSum = 0, _calibPitchSum = 0;
  int _calibPoseSamples = 0;
  double _calibMidXSum = 0, _calibMidYSum = 0, _calibWidthSum = 0, _calibTiltSum = 0;
  // Baselines: head pose neutral defaults to 0; posture baselines stay null
  // until calibrated (falls back to absolute scoring if the user wasn't seen).
  double _baselineYaw = 0, _baselinePitch = 0;
  double? _baselineMidX, _baselineMidY, _baselineWidth, _baselineTilt;

  // Tuning constants for the posture heuristic (deviation from the user's own
  // calibrated neutral, normalized by shoulder width).
  static const double _kTiltMax = 0.35; // tilt deviation that scores 0
  static const double _kDriftMax = 0.22; // sustained lean/slouch that scores 0
  // Head-angle tolerance (degrees) around the calibrated neutral for "looking".
  static const double _kYawTolerance = 13;
  static const double _kPitchTolerance = 13;

  @override
  void initState() {
    super.initState();

    _recordingCategory = widget.initialCategory;

    _faceDetector = FaceDetector(
      options: FaceDetectorOptions(
        enableClassification: true,
        enableTracking: true,
        performanceMode: FaceDetectorMode.accurate,
        minFaceSize: 0.15,
      ),
    );

    _poseDetector = PoseDetector(
      options: PoseDetectorOptions(
        mode: PoseDetectionMode.stream,
        model: PoseDetectionModel.base,
      ),
    );

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final name = await _showSessionDetailsSheet();
      if (!mounted) return;
      if (name == null) {
        Navigator.of(context).maybePop();
        return;
      }
      _recordingName = name;

      final recordingProv = context.read<RecordingProvider>();
      await recordingProv.initialize();
      if (!mounted) return;

      if (recordingProv.state == RecordingState.ready) {
        // Stream frames to the detectors *during* recording (concurrent
        // capture). A separate startImageStream call throws because the
        // plugin forbids streaming while recording — which previously left
        // the live confidence/eye-contact/posture analysis doing nothing.
        await recordingProv.startRecording(onImage: _processCameraImage);
        _sessionActive = true;

        // Tell the user what's about to happen before the countdown runs, so
        // they know to sit straight and look at the camera for calibration.
        await _showGetReadyDialog();
        if (!mounted) return;

        // Spend the first few seconds learning the user's neutral pose so
        // posture and eye-contact are measured relative to *them*, not fixed
        // thresholds. The countdown timer starts once calibration finishes.
        _startCalibration();
      }
    });
  }

  // ===== Calibration =====

  // Heads-up shown before the calibration countdown. Explains that the next
  // few seconds tune the analysis to the user, so they know to hold still.
  Future<void> _showGetReadyDialog() {
    return showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.wine,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
        ),
        icon: const Icon(Icons.center_focus_strong_rounded,
            color: Colors.white, size: 48),
        title: const Text(
          'Get ready',
          textAlign: TextAlign.center,
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        content: const Text(
          'Before we begin, we\'ll take a few seconds to calibrate.\n\n'
          'Sit straight, face the camera, and hold still while the countdown '
          'runs so we can tune the analysis to you.',
          textAlign: TextAlign.center,
          style: TextStyle(color: Colors.white70, height: 1.4),
        ),
        actionsAlignment: MainAxisAlignment.center,
        actions: [
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Colors.white,
              foregroundColor: AppColors.wine,
            ),
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text("I'm ready"),
          ),
        ],
      ),
    );
  }

  void _startCalibration() {
    setState(() {
      _calibrating = true;
      _calibCountdown = _kCalibSeconds;
    });
    _calibTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) {
        t.cancel();
        return;
      }
      if (_calibCountdown <= 1) {
        t.cancel();
        _finishCalibration();
      } else {
        setState(() => _calibCountdown--);
      }
    });
  }

  void _finishCalibration() {
    if (_calibFaceSamples > 0) {
      _baselineYaw = _calibYawSum / _calibFaceSamples;
      _baselinePitch = _calibPitchSum / _calibFaceSamples;
    }
    if (_calibPoseSamples > 0) {
      _baselineMidX = _calibMidXSum / _calibPoseSamples;
      _baselineMidY = _calibMidYSum / _calibPoseSamples;
      _baselineWidth = _calibWidthSum / _calibPoseSamples;
      _baselineTilt = _calibTiltSum / _calibPoseSamples;
    }

    // Start the scoring clock fresh so time-weighted averages begin now.
    _clock
      ..reset()
      ..start();
    _lastConfMs = 0;
    _lastPostMs = 0;

    if (!mounted) return;
    setState(() => _calibrating = false);
    _startTimer();

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          'Recording started. Please note that analysis currently supports English only.',
        ),
        duration: Duration(seconds: 4),
      ),
    );
  }

  // Asks the user to name this session before the camera starts recording.
  // The category was already chosen on the previous screen. Returns null if
  // the user backs out. Presented as a modern bottom sheet that resizes with
  // the keyboard and the device screen.
  Future<String?> _showSessionDetailsSheet() {
    final nameController = TextEditingController();

    return showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      isDismissible: false,
      enableDrag: false,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        final size = MediaQuery.sizeOf(sheetContext);
        final bottomInset = MediaQuery.viewInsetsOf(sheetContext).bottom;

        return StatefulBuilder(
          builder: (context, setLocalState) {
            final canStart = nameController.text.trim().isNotEmpty;
            return Padding(
              padding: EdgeInsets.only(bottom: bottomInset),
              child: Container(
                width: double.infinity,
                constraints: BoxConstraints(maxHeight: size.height * 0.8),
                decoration: const BoxDecoration(
                  color: AppColors.cardBg,
                  borderRadius:
                      BorderRadius.vertical(top: Radius.circular(28)),
                ),
                child: SafeArea(
                  top: false,
                  child: SingleChildScrollView(
                    padding: EdgeInsets.symmetric(
                      horizontal: (size.width * 0.06).clamp(16.0, 32.0),
                      vertical: 16,
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Center(
                          child: Container(
                            width: 40,
                            height: 4,
                            margin: const EdgeInsets.only(bottom: 20),
                            decoration: BoxDecoration(
                              color: AppColors.paleMauve,
                              borderRadius: BorderRadius.circular(2),
                            ),
                          ),
                        ),
                        const Text(
                          'Name Your Session',
                          style: TextStyle(
                            color: AppColors.wine,
                            fontSize: 20,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 6),
                        const Text(
                          'Give this practice session a name before you start recording.',
                          style: TextStyle(
                            color: AppColors.midMauve,
                            fontSize: 13.5,
                            height: 1.4,
                          ),
                        ),
                        const SizedBox(height: 20),
                        TextField(
                          controller: nameController,
                          autofocus: true,
                          textCapitalization: TextCapitalization.sentences,
                          decoration: const InputDecoration(
                            labelText: 'Recording name',
                            hintText: 'e.g. Behavioral Mock #1',
                            prefixIcon: Icon(Icons.edit_outlined),
                          ),
                          onChanged: (_) => setLocalState(() {}),
                          onSubmitted: (_) {
                            if (canStart) {
                              Navigator.of(sheetContext)
                                  .pop(nameController.text.trim());
                            }
                          },
                        ),
                        const SizedBox(height: 14),
                        Row(
                          children: [
                            const Icon(Icons.folder_rounded,
                                size: 18, color: AppColors.deepMauve),
                            const SizedBox(width: 8),
                            const Text(
                              'Category:',
                              style: TextStyle(
                                color: AppColors.midMauve,
                                fontSize: 13.5,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Flexible(
                              child: Chip(label: Text(_recordingCategory)),
                            ),
                          ],
                        ),
                        const SizedBox(height: 20),
                        Row(
                          children: [
                            Expanded(
                              child: OutlinedButton(
                                onPressed: () =>
                                    Navigator.of(sheetContext).pop(),
                                child: const Text('Cancel'),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              flex: 2,
                              child: FilledButton.icon(
                                onPressed: canStart
                                    ? () => Navigator.of(sheetContext)
                                        .pop(nameController.text.trim())
                                    : null,
                                icon: const Icon(
                                    Icons.fiber_manual_record_rounded,
                                    size: 18),
                                label: const Text('Start Recording'),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _processCameraImage(CameraImage image) async {
    // Stop doing detection work the moment the session is ending.
    if (_isProcessingImage || _isSaving) return;
    _isProcessingImage = true;
    _frameCount++;

    try {
      // The camera is configured (in RecordingService) to emit NV21 on
      // Android and BGRA8888 on iOS — both single-plane formats ML Kit can
      // consume directly. Concatenating the plane bytes yields the buffer.
      final WriteBuffer allBytes = WriteBuffer();
      for (final Plane plane in image.planes) {
        allBytes.putUint8List(plane.bytes);
      }
      final bytes = allBytes.done().buffer.asUint8List();

      final Size imageSize =
          Size(image.width.toDouble(), image.height.toDouble());
      final InputImageRotation imageRotation = _currentRotation();
      final InputImageFormat inputImageFormat = Platform.isAndroid
          ? InputImageFormat.nv21
          : InputImageFormat.bgra8888;

      final inputImageMetadata = InputImageMetadata(
        size: imageSize,
        rotation: imageRotation,
        format: inputImageFormat,
        bytesPerRow:
            image.planes.isNotEmpty ? image.planes[0].bytesPerRow : image.width,
      );

      final inputImage =
          InputImage.fromBytes(bytes: bytes, metadata: inputImageMetadata);

      await _detectFace(inputImage);

      if (_frameCount % _kPoseFrameInterval == 0) {
        await _detectPose(inputImage);
      }
    } catch (e) {
      debugPrint("Error processing camera frame: $e");
    } finally {
      _isProcessingImage = false;
    }
  }

  static const Map<DeviceOrientation, int> _orientationDegrees = {
    DeviceOrientation.portraitUp: 0,
    DeviceOrientation.landscapeLeft: 90,
    DeviceOrientation.portraitDown: 180,
    DeviceOrientation.landscapeRight: 270,
  };

  // Rotation ML Kit needs to interpret camera frames upright, derived from
  // the camera sensor orientation and the current device orientation
  // (Google's recommended computation) instead of a hardcoded value.
  InputImageRotation _currentRotation() {
    final controller = context.read<RecordingProvider>().service.controller;
    if (controller == null) return InputImageRotation.rotation270deg;

    final camera = controller.description;
    final sensorOrientation = camera.sensorOrientation;
    if (Platform.isIOS) {
      return InputImageRotationValue.fromRawValue(sensorOrientation) ??
          InputImageRotation.rotation0deg;
    }

    final deviceRotation =
        _orientationDegrees[controller.value.deviceOrientation] ?? 0;
    final int compensation;
    if (camera.lensDirection == CameraLensDirection.front) {
      compensation = (sensorOrientation + deviceRotation) % 360;
    } else {
      compensation = (sensorOrientation - deviceRotation + 360) % 360;
    }
    return InputImageRotationValue.fromRawValue(compensation) ??
        InputImageRotation.rotation270deg;
  }

  Future<void> _detectFace(InputImage inputImage) async {
    final List<Face> faces = await _faceDetector.processImage(inputImage);

    // No face → treat as not looking (for the debounced counter) and bail.
    if (faces.isEmpty) {
      if (!_calibrating) _updateLookAway(false);
      if (mounted) {
        setState(() => _eyeContactStatus = "Not Detected");
      }
      return;
    }

    final Face face = faces.first;
    final double yaw = face.headEulerAngleY ?? 0.0;
    final double pitch = face.headEulerAngleX ?? 0.0;
    final double? smileP = face.smilingProbability;
    final double? leftP = face.leftEyeOpenProbability;
    final double? rightP = face.rightEyeOpenProbability;

    // During calibration we only learn the neutral head pose.
    if (_calibrating) {
      _calibYawSum += yaw;
      _calibPitchSum += pitch;
      _calibFaceSamples++;
      return;
    }

    // Eye-contact: head pose within tolerance of the calibrated neutral, and
    // (when known) eyes open. Null eye probabilities are treated as unknown
    // rather than forcing them open.
    final bool headOk = (yaw - _baselineYaw).abs() < _kYawTolerance &&
        (pitch - _baselinePitch).abs() < _kPitchTolerance;
    // Null eye probabilities are treated as unknown (don't force them open).
    final bool eyesOpen = (leftP == null || rightP == null)
        ? true
        : (leftP > 0.5 && rightP > 0.5);
    final bool lookingNow = headOk && eyesOpen;

    _updateLookAway(lookingNow);

    // Confidence is only meaningful when the classifier produced values;
    // skip the frame otherwise so "unknown" never inflates the average.
    if (smileP != null && leftP != null && rightP != null) {
      final double eyeOpenness = (leftP + rightP) / 2;
      final double raw = (smileP * 0.5 + eyeOpenness * 0.5) * 100;

      _smoothedConfidence = _hasSmoothedConfidence
          ? _smoothedConfidence + _kEmaAlpha * (raw - _smoothedConfidence)
          : raw;
      _hasSmoothedConfidence = true;

      // Time-weight the raw value for the saved average.
      final int now = _clock.elapsedMilliseconds;
      final int dt = (now - _lastConfMs).clamp(0, _kMaxDtMs);
      if (_lastConfMs > 0) {
        _confSum += raw * dt;
        _confWeight += dt;
      }
      _lastConfMs = now;
    }

    if (mounted) {
      setState(() {
        _confidencePercentage = _smoothedConfidence;
        _eyeContactStatus = lookingNow ? "Active" : "Looking Away";
      });
    }
  }

  // Counts one look-away event once the not-looking state has been held for
  // _kSustainMs, so blinks/quick glances don't inflate the count and the
  // tally is independent of frame rate.
  void _updateLookAway(bool lookingNow) {
    final int now = _clock.elapsedMilliseconds;
    if (!lookingNow) {
      if (!_awayActive) {
        _awayActive = true;
        _awayStartMs = now;
        _awayCounted = false;
      } else if (!_awayCounted && now - _awayStartMs >= _kSustainMs) {
        _lookingAwayCount++;
        _awayCounted = true;
      }
    } else {
      _awayActive = false;
      _awayCounted = false;
    }
  }

  Future<void> _detectPose(InputImage inputImage) async {
    final List<Pose> poses = await _poseDetector.processImage(inputImage);
    if (poses.isEmpty) return;

    final pose = poses.first;
    final ls = pose.landmarks[PoseLandmarkType.leftShoulder];
    final rs = pose.landmarks[PoseLandmarkType.rightShoulder];

    if (ls == null || rs == null || ls.likelihood < 0.5 || rs.likelihood < 0.5) {
      return;
    }

    final double shoulderWidth = (ls.x - rs.x).abs();
    if (shoulderWidth < 1) return;

    final double tilt = (ls.y - rs.y).abs() / shoulderWidth;
    final double midX = (ls.x + rs.x) / 2;
    final double midY = (ls.y + rs.y) / 2;

    // During calibration we only learn the neutral seated posture.
    if (_calibrating) {
      _calibMidXSum += midX;
      _calibMidYSum += midY;
      _calibWidthSum += shoulderWidth;
      _calibTiltSum += tilt;
      _calibPoseSamples++;
      return;
    }

    // Tilt scored as deviation from the user's calibrated neutral tilt.
    final double baseTilt = _baselineTilt ?? 0.0;
    final double tiltDev = (tilt - baseTilt).abs();
    final double tiltScore = (1 - (tiltDev / _kTiltMax)).clamp(0.0, 1.0);

    // Drift: how far the shoulders have moved from the calibrated neutral
    // position (catches a sustained lean/slouch, not just rapid sway).
    double driftScore = 1.0;
    if (_baselineMidX != null &&
        _baselineMidY != null &&
        _baselineWidth != null &&
        _baselineWidth! > 0) {
      final double dx = midX - _baselineMidX!;
      final double dy = midY - _baselineMidY!;
      final double drift = sqrt(dx * dx + dy * dy) / _baselineWidth!;
      driftScore = (1 - (drift / _kDriftMax)).clamp(0.0, 1.0);
    }

    final double raw = (tiltScore * 0.5 + driftScore * 0.5) * 100;

    _smoothedPosture = _hasSmoothedPosture
        ? _smoothedPosture + _kEmaAlpha * (raw - _smoothedPosture)
        : raw;
    _hasSmoothedPosture = true;

    // Time-weight the raw value for the saved average.
    final int now = _clock.elapsedMilliseconds;
    final int dt = (now - _lastPostMs).clamp(0, _kMaxDtMs);
    if (_lastPostMs > 0) {
      _postSum += raw * dt;
      _postWeight += dt;
    }
    _lastPostMs = now;

    // Status + debounced shift counter off the smoothed value.
    final double s = _smoothedPosture;
    final String status =
        s >= 70 ? "Stable" : (s >= 45 ? "Shifting" : "Unstable");
    _updatePostureShift(s < 70);

    if (mounted) {
      setState(() => _postureStatus = status);
    }
  }

  // Counts one posture-shift event once the user has been out of "stable" for
  // _kSustainMs — frame-rate independent, ignores momentary wobbles.
  void _updatePostureShift(bool shiftedNow) {
    final int now = _clock.elapsedMilliseconds;
    if (shiftedNow) {
      if (!_shiftActive) {
        _shiftActive = true;
        _shiftStartMs = now;
        _shiftCounted = false;
      } else if (!_shiftCounted && now - _shiftStartMs >= _kSustainMs) {
        _postureShiftCount++;
        _shiftCounted = true;
      }
    } else {
      _shiftActive = false;
      _shiftCounted = false;
    }
  }

  void _startTimer() {
    if (_timer != null) _timer!.cancel();
    if (!mounted) return;

    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_startSeconds == 0) {
        _finishSession();
      } else {
        if (mounted) {
          setState(() {
            _startSeconds--;
          });
        }
      }
    });
  }

  // Ends the session: shows a "we'll notify you" message, leaves the screen
  // immediately, and saves the recording + live metrics in the background.
  // The heavy cloud analysis + push notification are wired in later steps.
  void _finishSession() async {
    if (_isSaving) return;
    setState(() => _isSaving = true);
    _sessionActive = false;
    _timer?.cancel();

    final double averageConfidence =
        _confWeight > 0 ? _confSum / _confWeight : 0.0;
    final double averagePosture =
        _postWeight > 0 ? _postSum / _postWeight : 0.0;

    // Stop the camera work and save the video WHILE the RecordingProvider is
    // still in scope (it is provided only around this screen). We then hand
    // the saved file path + user id to the confirmation screen, which finishes
    // the Firestore write + upload without needing the provider.
    final recordingProv = context.read<RecordingProvider>();
    final userId = context.read<AuthProvider>().user?.uid;

    try {
      await recordingProv.service.controller?.stopImageStream();
    } catch (_) {}

    String? localFilePath;
    String? recordingId;
    if (userId != null) {
      final saved = await recordingProv.stopAndSave(
        userId,
        name: _recordingName,
        category: _recordingCategory,
      );
      localFilePath = saved?.file.path;
      recordingId = saved?.recordingId;
    }

    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) => SessionCompleteScreen(
          userId: userId,
          recordingId: recordingId,
          localFilePath: localFilePath,
          averageConfidence: averageConfidence,
          averagePosture: averagePosture,
          lookingAwayCount: _lookingAwayCount,
          postureShiftCount: _postureShiftCount,
        ),
      ),
    );
  }

  // Asks before abandoning an in-progress take; on confirm, stops the
  // camera work, deletes the footage and leaves the screen.
  Future<void> _confirmDiscard() async {
    if (_isSaving) return;
    final discard = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Discard this session?'),
        content: const Text(
          'Recording will stop and this take will not be saved.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Keep practicing'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFFFF453A),
            ),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Discard'),
          ),
        ],
      ),
    );
    if (discard != true || !mounted) return;

    _timer?.cancel();
    _sessionActive = false;
    final prov = context.read<RecordingProvider>();
    try {
      await prov.service.controller?.stopImageStream();
    } catch (_) {}
    await prov.discard();
    if (mounted) Navigator.of(context).pop();
  }

  void _handleBack() {
    if (_sessionActive) {
      _confirmDiscard();
    } else {
      Navigator.of(context).maybePop();
    }
  }

  String _formatTime(int totalSeconds) {
    int minutes = totalSeconds ~/ 60;
    int seconds = totalSeconds % 60;
    return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }

  String _shortEye(String status) {
    if (status == "Active") return "Active";
    if (status == "Looking Away") return "Away";
    return "No Face";
  }

  @override
  void dispose() {
    _timer?.cancel();
    _calibTimer?.cancel();
    _clock.stop();
    _faceDetector.close();
    _poseDetector.close();
    super.dispose();
  }

  // Camera preview shown at its natural field of view — no crop/zoom, so it
  // may letterbox (black bars) if the camera's aspect ratio doesn't exactly
  // match the screen, rather than stretching/cropping to fill it.
  Widget _fullScreenCamera(CameraController controller) {
    final camera = controller.description;

    // The stock CameraPreview rotates using `recordingOrientation`, which on
    // some devices is reported wrong once recording actually starts (the
    // saved video's own rotation metadata is set correctly regardless — only
    // the *live* preview widget was affected). The app is locked to portrait
    // (see main.dart), so the device's own rotation contribution is always
    // zero here — only the camera's fixed sensor orientation needs
    // compensating, using the same degrees-based formula already proven for
    // ML Kit's rotation in _currentRotation() above.
    final quarterTurns = (camera.sensorOrientation ~/ 90) % 4;
    final rawAspect = controller.value.aspectRatio;
    final displayAspect = quarterTurns.isOdd ? (1 / rawAspect) : rawAspect;

    Widget preview = RotatedBox(
      quarterTurns: quarterTurns,
      child: controller.buildPreview(),
    );

    // Mirror the front camera horizontally so it reads like a mirror (the
    // natural "selfie" view) instead of appearing flipped/reversed.
    if (camera.lensDirection == CameraLensDirection.front) {
      preview = Transform.flip(flipX: true, child: preview);
    }

    return ColoredBox(
      color: Colors.black,
      child: Center(
        child: AspectRatio(aspectRatio: displayAspect, child: preview),
      ),
    );
  }

  // A floating circular live-metric indicator with a label underneath.
  Widget _circleMetric({
    required String label,
    required Widget center,
    required Color ringColor,
    required double progress,
  }) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: 82,
          height: 82,
          child: Stack(
            alignment: Alignment.center,
            children: [
              Container(
                width: 82,
                height: 82,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  color: AppColors.cardBg,
                  boxShadow: [
                    BoxShadow(
                        color: Colors.black38,
                        blurRadius: 10,
                        offset: Offset(0, 4)),
                  ],
                ),
              ),
              SizedBox(
                width: 82,
                height: 82,
                child: CircularProgressIndicator(
                  value: progress,
                  strokeWidth: 6,
                  backgroundColor: AppColors.paleMauve,
                  valueColor: AlwaysStoppedAnimation<Color>(ringColor),
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(10),
                child: center,
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        Text(
          label,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 13,
            fontWeight: FontWeight.w600,
            shadows: [Shadow(color: Colors.black54, blurRadius: 4)],
          ),
        ),
      ],
    );
  }

  // Floating card showing the current AI-coach question, with a button to
  // advance to the next one. Hidden entirely once the last question is
  // reached (the user keeps answering it until they end the session).
  Widget _questionCard() {
    final questions = widget.questions;
    final isLast = _questionIndex >= questions.length - 1;
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 12, 14),
      decoration: BoxDecoration(
        color: AppColors.wine.withValues(alpha: 0.92),
        borderRadius: BorderRadius.circular(20),
        boxShadow: const [
          BoxShadow(color: Colors.black38, blurRadius: 12, offset: Offset(0, 4)),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.only(top: 2),
            child: Icon(Icons.auto_awesome_rounded,
                color: AppColors.ice, size: 20),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Question ${_questionIndex + 1} of ${questions.length}',
                  style: const TextStyle(
                    color: AppColors.ice,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.3,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  questions[_questionIndex].text,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    height: 1.3,
                  ),
                ),
              ],
            ),
          ),
          if (!isLast)
            IconButton(
              onPressed: _nextQuestion,
              tooltip: 'Next question',
              icon: const Icon(Icons.arrow_forward_rounded,
                  color: Colors.white),
            ),
        ],
      ),
    );
  }

  Widget _circleIconButton(IconData icon, VoidCallback onTap) {
    return Material(
      color: AppColors.cardBg.withValues(alpha: 0.9),
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Icon(icon, color: AppColors.wine),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final recordingProv = context.watch<RecordingProvider>();
    final controller = recordingProv.service.controller;

    final Color eyeColor =
        _eyeContactStatus == "Active" ? AppColors.deepMauve : AppColors.gold;
    final Color postureColor =
        _postureStatus == "Stable" ? AppColors.deepMauve : AppColors.gold;

    return PopScope(
      // Intercept the system back gesture while a take is in progress so
      // the user confirms before the footage is thrown away.
      canPop: !_sessionActive,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _confirmDiscard();
      },
      child: Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // ===== Full-screen camera =====
          Positioned.fill(
            child: (controller != null && controller.value.isInitialized)
                ? _fullScreenCamera(controller)
                : Container(
                    color: AppColors.wine,
                    child: const Center(
                      child: CircularProgressIndicator(color: Colors.white),
                    ),
                  ),
          ),

          // ===== Top bar: back button + timer pill =====
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              child: Row(
                children: [
                  _circleIconButton(Icons.arrow_back, _handleBack),
                  const Spacer(),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 20, vertical: 8),
                    decoration: BoxDecoration(
                      color: AppColors.cardBg.withValues(alpha: 0.92),
                      borderRadius: BorderRadius.circular(30),
                      boxShadow: const [
                        BoxShadow(color: Colors.black26, blurRadius: 8),
                      ],
                    ),
                    child: Text(
                      _formatTime(_startSeconds),
                      style: const TextStyle(
                        color: AppColors.wine,
                        fontSize: 26,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  const Spacer(),
                  const SizedBox(width: 44), // balances the back button
                ],
              ),
            ),
          ),

          // ===== AI coach: current question, shown once recording begins =====
          if (_hasQuestions && _sessionActive && !_calibrating)
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: SafeArea(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 70, 16, 0),
                  child: _questionCard(),
                ),
              ),
            ),

          // ===== Bottom: circular live metrics + finish button =====
          Align(
            alignment: Alignment.bottomCenter,
            child: SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 20),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        _circleMetric(
                          label: 'Confidence',
                          ringColor: AppColors.deepMauve,
                          progress:
                              (_confidencePercentage / 100).clamp(0.0, 1.0),
                          center: Text(
                            '${_confidencePercentage.toStringAsFixed(0)}%',
                            style: const TextStyle(
                              color: AppColors.deepMauve,
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        _circleMetric(
                          label: 'Eye Contact',
                          ringColor: eyeColor,
                          progress: 1.0,
                          center: Text(
                            _shortEye(_eyeContactStatus),
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: eyeColor,
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        _circleMetric(
                          label: 'Posture',
                          ringColor: postureColor,
                          progress: 1.0,
                          center: Text(
                            _postureStatus,
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: postureColor,
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 22),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: _isSaving ? null : _finishSession,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.deepMauve,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: const Text(
                          'FINISH SESSION',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),

          // ===== Calibration overlay =====
          if (_calibrating)
            Positioned.fill(
              child: Container(
                color: Colors.black.withValues(alpha: 0.7),
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.center_focus_strong_rounded,
                          color: Colors.white, size: 56),
                      const SizedBox(height: 20),
                      const Text(
                        'Calibrating…',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 10),
                      const Padding(
                        padding: EdgeInsets.symmetric(horizontal: 48),
                        child: Text(
                          'Sit straight and look at the camera so we can tune the analysis to you.',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: Colors.white70,
                            fontSize: 15,
                            height: 1.4,
                          ),
                        ),
                      ),
                      const SizedBox(height: 24),
                      Text(
                        '$_calibCountdown',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 48,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
      ),
    );
  }
}