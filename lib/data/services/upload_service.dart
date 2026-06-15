import 'dart:io';
import 'package:firebase_storage/firebase_storage.dart';

class UploadService {
  final FirebaseStorage _storage = FirebaseStorage.instance;

  /// Uploads the recording file to Firebase Storage under
  /// `recordings/{userId}/{recordingId}.mp4` and returns the storage path.
  ///
  /// The Cloud Function (step 3) is triggered by this upload, extracts the
  /// audio, runs Whisper + the analyzers, and writes the results back.
  Future<String> uploadRecording({
    required String userId,
    required String recordingId,
    required File file,
  }) async {
    final path = 'recordings/$userId/$recordingId.mp4';
    final ref = _storage.ref(path);
    await ref.putFile(
      file,
      SettableMetadata(contentType: 'video/mp4'),
    );
    return path;
  }
}
