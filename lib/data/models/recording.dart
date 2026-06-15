import 'package:cloud_firestore/cloud_firestore.dart';

class TranscriptSegment {
  final double start;
  final double end;
  final String text;

  TranscriptSegment({
    required this.start,
    required this.end,
    required this.text,
  });

  Map<String, dynamic> toMap() => {
        'start': start,
        'end': end,
        'text': text,
      };

  factory TranscriptSegment.fromMap(Map<String, dynamic> map) {
    return TranscriptSegment(
      start: (map['start'] ?? 0).toDouble(),
      end: (map['end'] ?? 0).toDouble(),
      text: map['text'] ?? '',
    );
  }
}

class Recording {
  final String id;
  final String userId;
  final String localPath;
  final int durationMs;
  final int fileSizeBytes;
  final DateTime createdAt;
  final String name;
  final String category;
  final String? transcript;
  final List<TranscriptSegment>? transcriptSegments;
  final DateTime? transcribedAt;
  final String? language;
  final int? fillerWordCount;
  final Map<String, int>? fillerWordBreakdown;
  final int? totalWords;
  final int? uniqueWords;
  final double? lexicalDiversity;
  final List<Map<String, dynamic>>? topWords;
  final List<Map<String, dynamic>>? overusedWords;
  final int? silenceCount;
  final double? totalSilenceSeconds;
  final double? longestSilenceSeconds;
  final double? averageSilenceSeconds;
  final List<Map<String, dynamic>>? silenceEvents;
  final double? averageConfidencePercentage;
  final int? lookingAwayCount;

  // NEW: posture / stability (computed live from ML Kit Pose Detection)
  final double? averagePostureStability; // 0-100, higher = steadier posture
  final int? postureShiftCount;          // how many frames the user was shifting/unstable

  // NEW (step 2): cloud-analysis lifecycle
  final String? status;      // 'processing' | 'ready' | 'failed'
  final String? storagePath; // path of the uploaded video in Firebase Storage

  Recording({
    required this.id,
    required this.userId,
    required this.localPath,
    required this.durationMs,
    required this.fileSizeBytes,
    required this.createdAt,
    this.name = '',
    this.category = '',
    this.transcript,
    this.transcriptSegments,
    this.transcribedAt,
    this.language,
    this.fillerWordCount,
    this.fillerWordBreakdown,
    this.totalWords,
    this.uniqueWords,
    this.lexicalDiversity,
    this.topWords,
    this.overusedWords,
    this.silenceCount,
    this.totalSilenceSeconds,
    this.longestSilenceSeconds,
    this.averageSilenceSeconds,
    this.silenceEvents,
    this.averageConfidencePercentage,
    this.lookingAwayCount,
    this.averagePostureStability,
    this.postureShiftCount,
    this.status,
    this.storagePath,
  });

  bool get hasTranscript => transcript != null && transcript!.isNotEmpty;

  // Returns a copy with the given analysis fields replaced and everything
  // else (name, category, body-language metrics, ...) preserved.
  Recording copyWith({
    String? transcript,
    List<TranscriptSegment>? transcriptSegments,
    DateTime? transcribedAt,
    String? language,
    int? fillerWordCount,
    Map<String, int>? fillerWordBreakdown,
    int? totalWords,
    int? uniqueWords,
    double? lexicalDiversity,
    List<Map<String, dynamic>>? topWords,
    List<Map<String, dynamic>>? overusedWords,
    int? silenceCount,
    double? totalSilenceSeconds,
    double? longestSilenceSeconds,
    double? averageSilenceSeconds,
    List<Map<String, dynamic>>? silenceEvents,
    String? status,
    String? storagePath,
  }) {
    return Recording(
      id: id,
      userId: userId,
      localPath: localPath,
      durationMs: durationMs,
      fileSizeBytes: fileSizeBytes,
      createdAt: createdAt,
      name: name,
      category: category,
      transcript: transcript ?? this.transcript,
      transcriptSegments: transcriptSegments ?? this.transcriptSegments,
      transcribedAt: transcribedAt ?? this.transcribedAt,
      language: language ?? this.language,
      fillerWordCount: fillerWordCount ?? this.fillerWordCount,
      fillerWordBreakdown: fillerWordBreakdown ?? this.fillerWordBreakdown,
      totalWords: totalWords ?? this.totalWords,
      uniqueWords: uniqueWords ?? this.uniqueWords,
      lexicalDiversity: lexicalDiversity ?? this.lexicalDiversity,
      topWords: topWords ?? this.topWords,
      overusedWords: overusedWords ?? this.overusedWords,
      silenceCount: silenceCount ?? this.silenceCount,
      totalSilenceSeconds: totalSilenceSeconds ?? this.totalSilenceSeconds,
      longestSilenceSeconds:
          longestSilenceSeconds ?? this.longestSilenceSeconds,
      averageSilenceSeconds:
          averageSilenceSeconds ?? this.averageSilenceSeconds,
      silenceEvents: silenceEvents ?? this.silenceEvents,
      averageConfidencePercentage: averageConfidencePercentage,
      lookingAwayCount: lookingAwayCount,
      averagePostureStability: averagePostureStability,
      postureShiftCount: postureShiftCount,
      status: status ?? this.status,
      storagePath: storagePath ?? this.storagePath,
    );
  }

  Map<String, dynamic> toFirestore() => {
        'userId': userId,
        'localPath': localPath,
        'durationMs': durationMs,
        'fileSizeBytes': fileSizeBytes,
        'createdAt': Timestamp.fromDate(createdAt),
        'name': name,
        'category': category,
        if (transcript != null) 'transcript': transcript,
        if (transcriptSegments != null)
          'transcriptSegments':
              transcriptSegments!.map((s) => s.toMap()).toList(),
        if (transcribedAt != null)
          'transcribedAt': Timestamp.fromDate(transcribedAt!),
        if (language != null) 'language': language,
        if (fillerWordCount != null) 'fillerWordCount': fillerWordCount,
        if (fillerWordBreakdown != null)
          'fillerWordBreakdown': fillerWordBreakdown,
        if (totalWords != null) 'totalWords': totalWords,
        if (uniqueWords != null) 'uniqueWords': uniqueWords,
        if (lexicalDiversity != null) 'lexicalDiversity': lexicalDiversity,
        if (topWords != null) 'topWords': topWords,
        if (overusedWords != null) 'overusedWords': overusedWords,
        if (silenceCount != null) 'silenceCount': silenceCount,
        if (totalSilenceSeconds != null)
          'totalSilenceSeconds': totalSilenceSeconds,
        if (longestSilenceSeconds != null)
          'longestSilenceSeconds': longestSilenceSeconds,
        if (averageSilenceSeconds != null)
          'averageSilenceSeconds': averageSilenceSeconds,
        if (silenceEvents != null) 'silenceEvents': silenceEvents,
        if (averageConfidencePercentage != null)
          'averageConfidencePercentage': averageConfidencePercentage,
        if (lookingAwayCount != null) 'lookingAwayCount': lookingAwayCount,
        if (averagePostureStability != null)
          'averagePostureStability': averagePostureStability,
        if (postureShiftCount != null) 'postureShiftCount': postureShiftCount,
        if (status != null) 'status': status,
        if (storagePath != null) 'storagePath': storagePath,
      };

  factory Recording.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    final segmentsRaw = data['transcriptSegments'] as List?;
    return Recording(
      id: doc.id,
      userId: data['userId'] ?? '',
      localPath: data['localPath'] ?? '',
      durationMs: data['durationMs'] ?? 0,
      fileSizeBytes: data['fileSizeBytes'] ?? 0,
      createdAt: (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      name: data['name'] ?? '',
      category: data['category'] ?? '',
      transcript: data['transcript'],
      transcriptSegments: segmentsRaw
          ?.map((m) => TranscriptSegment.fromMap(Map<String, dynamic>.from(m)))
          .toList(),
      transcribedAt: (data['transcribedAt'] as Timestamp?)?.toDate(),
      language: data['language'],
      fillerWordCount: data['fillerWordCount'],
      fillerWordBreakdown: data['fillerWordBreakdown'] != null
          ? Map<String, int>.from(data['fillerWordBreakdown'])
          : null,
      totalWords: data['totalWords'],
      uniqueWords: data['uniqueWords'],
      lexicalDiversity: (data['lexicalDiversity'] as num?)?.toDouble(),
      topWords: (data['topWords'] as List?)
          ?.map((e) => Map<String, dynamic>.from(e))
          .toList(),
      overusedWords: (data['overusedWords'] as List?)
          ?.map((e) => Map<String, dynamic>.from(e))
          .toList(),
      silenceCount: data['silenceCount'],
      totalSilenceSeconds: (data['totalSilenceSeconds'] as num?)?.toDouble(),
      longestSilenceSeconds:
          (data['longestSilenceSeconds'] as num?)?.toDouble(),
      averageSilenceSeconds:
          (data['averageSilenceSeconds'] as num?)?.toDouble(),
      silenceEvents: (data['silenceEvents'] as List?)
          ?.map((e) => Map<String, dynamic>.from(e))
          .toList(),
      averageConfidencePercentage:
          (data['averageConfidencePercentage'] as num?)?.toDouble(),
      lookingAwayCount: data['lookingAwayCount'] as int?,
      averagePostureStability:
          (data['averagePostureStability'] as num?)?.toDouble(),
      postureShiftCount: data['postureShiftCount'] as int?,
      status: data['status'] as String?,
      storagePath: data['storagePath'] as String?,
    );
  }
}