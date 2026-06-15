import 'dart:io';
import 'package:flutter/material.dart';

import '../../../data/repositories/recording_repository.dart';
import '../../../data/services/upload_service.dart';
import '../../../core/theme/app_theme.dart';

class SessionCompleteScreen extends StatefulWidget {
  final String? userId;
  final String? recordingId;
  final String? localFilePath;
  final double averageConfidence;
  final double averagePosture;
  final int lookingAwayCount;
  final int postureShiftCount;

  const SessionCompleteScreen({
    super.key,
    required this.userId,
    required this.recordingId,
    required this.localFilePath,
    required this.averageConfidence,
    required this.averagePosture,
    required this.lookingAwayCount,
    required this.postureShiftCount,
  });

  @override
  State<SessionCompleteScreen> createState() => _SessionCompleteScreenState();
}

class _SessionCompleteScreenState extends State<SessionCompleteScreen> {
  @override
  void initState() {
    super.initState();
    // Finish saving in the background once this screen is shown. The recording
    // was already stopped + saved on the previous screen; here we attach the
    // live metrics and upload the video for cloud analysis.
    WidgetsBinding.instance.addPostFrameCallback((_) => _saveInBackground());
  }

  Future<void> _saveInBackground() async {
    final userId = widget.userId;
    final recordingId = widget.recordingId;
    final localFilePath = widget.localFilePath;
    if (userId == null || recordingId == null || localFilePath == null) {
      return;
    }

    try {
      final repo = RecordingRepository();

      // Live body-language metrics, written to the exact document created
      // when the take was saved. Speech analysis (transcript, filler words,
      // WPM, vocabulary, silences) is filled later by the cloud from Whisper.
      await repo.updateAnalysis(
        userId: userId,
        recordingId: recordingId,
        transcript: '',
        segments: [],
        language: 'en',
        fillerWordCount: 0,
        fillerWordBreakdown: {},
        totalWords: 0,
        uniqueWords: 0,
        lexicalDiversity: 0,
        topWords: [],
        overusedWords: [],
        silenceCount: 0,
        totalSilenceSeconds: 0,
        longestSilenceSeconds: 0,
        averageSilenceSeconds: 0,
        silenceEvents: [],
        averageConfidencePercentage: widget.averageConfidence,
        lookingAwayCount: widget.lookingAwayCount,
        averagePostureStability: widget.averagePosture,
        postureShiftCount: widget.postureShiftCount,
      );

      // Step 2: mark "processing" and upload the video to Firebase Storage.
      // (Requires Blaze + Storage enabled. Until then this upload fails safely
      // and the recording is marked 'failed', but the metrics above are kept.)
      await repo.markProcessing(userId: userId, recordingId: recordingId);
      try {
        final uploadService = UploadService();
        final storagePath = await uploadService.uploadRecording(
          userId: userId,
          recordingId: recordingId,
          file: File(localFilePath),
        );
        await repo.markProcessing(
          userId: userId,
          recordingId: recordingId,
          storagePath: storagePath,
        );
      } catch (e) {
        debugPrint("Upload failed: $e");
        await repo.markFailed(userId: userId, recordingId: recordingId);
      }
    } catch (e) {
      debugPrint("Error saving session: $e");
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.pageBg,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Container(
                width: 104,
                height: 104,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  color: AppColors.paleMauve,
                ),
                child: const Icon(
                  Icons.check_circle_rounded,
                  size: 52,
                  color: AppColors.deepMauve,
                ),
              ),
              const SizedBox(height: 30),
              const Text(
                'Session Complete!',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 26,
                  fontWeight: FontWeight.bold,
                  color: AppColors.wine,
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                "Your recording has been saved.\nOpen the Recordings tab to view your full report.",
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 16,
                  height: 1.5,
                  color: AppColors.midMauve,
                ),
              ),
              const SizedBox(height: 40),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () {
                    Navigator.of(context).popUntil((route) => route.isFirst);
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.deepMauve,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: const Text(
                    'Back to Home',
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
    );
  }
}