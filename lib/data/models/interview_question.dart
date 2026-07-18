import 'package:cloud_firestore/cloud_firestore.dart';

// A user-authored interview question, tagged to one or more practice
// categories (e.g. "Behavioral", "Leadership"). The AI coach asks these one
// at a time during a recording whose category matches.
class InterviewQuestion {
  final String id;
  final String text;
  final List<String> categories;
  final DateTime createdAt;

  InterviewQuestion({
    required this.id,
    required this.text,
    required this.categories,
    required this.createdAt,
  });

  Map<String, dynamic> toFirestore() => {
        'text': text,
        'categories': categories,
        'createdAt': Timestamp.fromDate(createdAt),
      };

  factory InterviewQuestion.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;

    // Prefer the current 'categories' list; fall back to the older
    // single-'category' string (questions saved before multi-category
    // support existed) so nothing already saved gets orphaned.
    List<String> categories;
    final rawCategories = data['categories'];
    if (rawCategories is List) {
      categories = rawCategories.map((e) => e.toString()).toList();
    } else {
      final legacy = (data['category'] as String?)?.trim();
      categories = (legacy != null && legacy.isNotEmpty) ? [legacy] : [];
    }

    return InterviewQuestion(
      id: doc.id,
      text: data['text'] ?? '',
      categories: categories,
      createdAt: (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
    );
  }
}
