import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/interview_question.dart';

class QuestionRepository {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  CollectionReference<Map<String, dynamic>> _userQuestions(String userId) =>
      _firestore.collection('users').doc(userId).collection('questions');

  Stream<List<InterviewQuestion>> watchQuestions(String userId) {
    return _userQuestions(userId)
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map((snap) => snap.docs
            .map((doc) => InterviewQuestion.fromFirestore(doc))
            .toList());
  }

  Future<String> addQuestion({
    required String userId,
    required String text,
    required List<String> categories,
  }) async {
    final docRef = await _userQuestions(userId).add({
      'text': text,
      'categories': categories,
      'createdAt': FieldValue.serverTimestamp(),
    });
    return docRef.id;
  }

  Future<void> updateQuestion({
    required String userId,
    required String questionId,
    required String text,
    required List<String> categories,
  }) {
    return _userQuestions(userId)
        .doc(questionId)
        .update({'text': text, 'categories': categories});
  }

  Future<void> deleteQuestion(String userId, String questionId) {
    return _userQuestions(userId).doc(questionId).delete();
  }
}
