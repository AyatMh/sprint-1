import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../auth/providers/auth_provider.dart';
import '../providers/recording_provider.dart';

class RecordingScreen extends StatefulWidget {
  const RecordingScreen({super.key});

  @override
  State<RecordingScreen> createState() => _RecordingScreenState();
}

class _RecordingScreenState extends State<RecordingScreen> {
  late final RecordingProvider _provider;

  @override
  void initState() {
    super.initState();
    _provider = RecordingProvider();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _provider.initialize();
    });
  }

  @override
  void dispose() {
    _provider.dispose();
    super.dispose();
  }

  String _formatDuration(Duration d) {
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  Future<void> _toggleRecording() async {
    final state = _provider.state;
    if (state == RecordingState.ready) {
      await _provider.startRecording();
    } else if (state == RecordingState.recording) {
      final userId = context.read<AuthProvider>().user?.uid;
      if (userId == null) return;
      final saved =
          await _provider.stopAndSave(userId, name: '', category: '');
      if (!mounted) return;
      if (saved != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Saved: ${saved.file.path.split('/').last}'),
            duration: const Duration(seconds: 3),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider<RecordingProvider>.value(
      value: _provider,
      child: Consumer<RecordingProvider>(
        builder: (context, prov, _) {
          return Scaffold(
            backgroundColor: Colors.black,
            appBar: AppBar(
              backgroundColor: Colors.black,
              foregroundColor: Colors.white,
              title: const Text('Record Practice'),
              iconTheme: const IconThemeData(color: Colors.white),
            ),
            body: _buildBody(prov),
          );
        },
      ),
    );
  }

  Widget _buildBody(RecordingProvider prov) {
    switch (prov.state) {
      case RecordingState.idle:
      case RecordingState.initializing:
        return const Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              CircularProgressIndicator(color: Colors.white),
              SizedBox(height: 16),
              Text('Starting camera...', style: TextStyle(color: Colors.white)),
            ],
          ),
        );
      case RecordingState.error:
        return Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.error_outline, color: Colors.red, size: 64),
                const SizedBox(height: 16),
                Text(
                  prov.errorMessage ?? 'Unknown error',
                  style: const TextStyle(color: Colors.white),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 24),
                FilledButton(
                  onPressed: () => prov.initialize(),
                  child: const Text('Try again'),
                ),
              ],
            ),
          ),
        );
      case RecordingState.ready:
      case RecordingState.recording:
      case RecordingState.saving:
        return _buildCameraView(prov);
    }
  }

  Widget _buildCameraView(RecordingProvider prov) {
    final controller = prov.service.controller;
    if (controller == null || !controller.value.isInitialized) {
      return const Center(child: CircularProgressIndicator(color: Colors.white));
    }

    final isRecording = prov.state == RecordingState.recording;
    final isSaving = prov.state == RecordingState.saving;

    return Stack(
      children: [
        Positioned.fill(child: CameraPreview(controller)),
        if (isRecording)
          Positioned(
            top: 16,
            left: 0,
            right: 0,
            child: Center(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.red.withValues(alpha: 0.85),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.fiber_manual_record,
                        color: Colors.white, size: 14),
                    const SizedBox(width: 6),
                    Text(
                      _formatDuration(prov.elapsed),
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        Positioned(
          bottom: 32,
          left: 0,
          right: 0,
          child: Center(
            child: GestureDetector(
              onTap: isSaving ? null : _toggleRecording,
              child: Container(
                width: 80,
                height: 80,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: isRecording ? Colors.red : Colors.white,
                  border: Border.all(color: Colors.white, width: 4),
                ),
                child: Center(
                  child: isSaving
                      ? const CircularProgressIndicator(color: Colors.black)
                      : Icon(
                          isRecording ? Icons.stop : Icons.fiber_manual_record,
                          color: isRecording ? Colors.white : Colors.red,
                          size: 40,
                        ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}