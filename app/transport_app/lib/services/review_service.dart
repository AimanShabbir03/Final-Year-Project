import 'package:cloud_firestore/cloud_firestore.dart';

class ReviewService {
  ReviewService._();

  static final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  static Future<void> submitReview({
    required String parentId,
    required String driverId,
    required int rating,
    required String comment,
    required String sentiment,
  }) async {
    final normalizedComment = comment.trim();
    final clampedRating = rating.clamp(1, 5);

    final reviewRef = _firestore.collection('reviews').doc();
    print('FINAL SENTIMENT BEFORE FIRESTORE: $sentiment');
    await reviewRef.set({
      'reviewId': reviewRef.id,
      'parentId': parentId,
      'driverId': driverId,
      'rating': clampedRating,
      'comment': normalizedComment,
      'sentiment': sentiment,
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  static Future<void> createReview({
    required String parentId,
    required String driverId,
    required int rating,
    required String comment,
    required String sentiment,
  }) {
    return submitReview(
      parentId: parentId,
      driverId: driverId,
      rating: rating,
      comment: comment,
      sentiment: sentiment,
    );
  }

  static Stream<QuerySnapshot<Map<String, dynamic>>> watchParentReviews(
    String parentId,
  ) {
    return _firestore
        .collection('reviews')
        .where('parentId', isEqualTo: parentId)
        .snapshots();
  }
}
