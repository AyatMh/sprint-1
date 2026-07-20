import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/recording.dart';

class RecordingRepository {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  CollectionReference<Map<String, dynamic>> _userRecordings(String userId) =>
      _firestore.collection('users').doc(userId).collection('recordings');

  Future<String> saveMetadata({
    required String userId,
    required String localPath,
    required int durationMs,
    required int fileSizeBytes,
    required String name,
    required String category,
    bool usedAiCoach = false,
    List<Map<String, dynamic>>? aiCoachQuestions,
    double speechStartSeconds = 0.0,
  }) async {
    final docRef = await _userRecordings(userId).add({
      'userId': userId,
      'localPath': localPath,
      'durationMs': durationMs,
      'fileSizeBytes': fileSizeBytes,
      'name': name,
      'category': category,
      'usedAiCoach': usedAiCoach,
      'aiCoachQuestions': ?aiCoachQuestions,
      'speechStartSeconds': speechStartSeconds,
      'createdAt': FieldValue.serverTimestamp(),
    });
    return docRef.id;
  }

  Stream<List<Recording>> watchRecordings(String userId) {
    return _userRecordings(userId)
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map((snap) =>
            snap.docs.map((doc) => Recording.fromFirestore(doc)).toList());
  }

  Future<void> deleteRecording(String userId, String recordingId) {
    return _userRecordings(userId).doc(recordingId).delete();
  }

  // Deletes every recording document for a user. Used when the user deletes
  // their account so no orphaned data is left behind in Firestore.
  Future<void> deleteAllRecordings(String userId) async {
    final snap = await _userRecordings(userId).get();
    for (final doc in snap.docs) {
      await doc.reference.delete();
    }
  }

  // Renames a single recording.
  Future<void> renameRecording(
    String userId,
    String recordingId,
    String name,
  ) {
    return _userRecordings(userId).doc(recordingId).update({'name': name});
  }

  // Sets the category for a set of recordings in one batch. Used both to move
  // a single recording and to rename a whole category (every recording in it).
  Future<void> setCategoryForRecordings(
    String userId,
    List<String> recordingIds,
    String category,
  ) async {
    final batch = _firestore.batch();
    for (final id in recordingIds) {
      batch.update(_userRecordings(userId).doc(id), {'category': category});
    }
    await batch.commit();
  }

  Future<void> updateAnalysis({
    required String userId,
    required String recordingId,
    required String transcript,
    required List<TranscriptSegment> segments,
    required String language,
    required int fillerWordCount,
    required Map<String, int> fillerWordBreakdown,
    required int totalWords,
    required int uniqueWords,
    required double lexicalDiversity,
    required List<Map<String, dynamic>> topWords,
    required List<Map<String, dynamic>> overusedWords,
    required int silenceCount,
    required double totalSilenceSeconds,
    required double longestSilenceSeconds,
    required double averageSilenceSeconds,
    required List<Map<String, dynamic>> silenceEvents,
    double? averageConfidencePercentage,
    int? lookingAwayCount,
    double? averagePostureStability,
    int? postureShiftCount,
  }) async {
    await _userRecordings(userId).doc(recordingId).update({
      'transcript': transcript,
      'transcriptSegments': segments.map((s) => s.toMap()).toList(),
      'transcribedAt': FieldValue.serverTimestamp(),
      'language': language,
      'fillerWordCount': fillerWordCount,
      'fillerWordBreakdown': fillerWordBreakdown,
      'totalWords': totalWords,
      'uniqueWords': uniqueWords,
      'lexicalDiversity': lexicalDiversity,
      'topWords': topWords,
      'overusedWords': overusedWords,
      'silenceCount': silenceCount,
      'totalSilenceSeconds': totalSilenceSeconds,
      'longestSilenceSeconds': longestSilenceSeconds,
      'averageSilenceSeconds': averageSilenceSeconds,
      'silenceEvents': silenceEvents,
      'averageConfidencePercentage': ?averageConfidencePercentage,
      'lookingAwayCount': ?lookingAwayCount,
      'averagePostureStability': ?averagePostureStability,
      'postureShiftCount': ?postureShiftCount,
    });
  }

  // Stores the AI coaching tips generated from a recording's analysis.
  Future<void> updateAiTips({
    required String userId,
    required String recordingId,
    required Map<String, dynamic> tips,
  }) async {
    await _userRecordings(userId).doc(recordingId).update({
      'aiTips': tips,
      'aiTipsAt': FieldValue.serverTimestamp(),
    });
  }

  // Marks a recording as being analyzed in the cloud. Called after the video
  // is uploaded to Storage; the Cloud Function will later set status 'ready'.
  Future<void> markProcessing({
    required String userId,
    required String recordingId,
    String? storagePath,
  }) async {
    await _userRecordings(userId).doc(recordingId).update({
      'status': 'processing',
      'storagePath': ?storagePath,
    });
  }

  Future<void> markFailed({
    required String userId,
    required String recordingId,
  }) async {
    await _userRecordings(userId).doc(recordingId).update({'status': 'failed'});
  }
}