import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/models.dart';

abstract class SubscriptionRepository {
  Future<void> subscribe(String userId, String planId, DateTime expiry);
  Future<void> cancel(String userId, String planId);
  Stream<List<Subscription>> getUserSubscriptions(String userId);
  Stream<List<ActivationRequest>> getPendingRequests(String userId);
}

class SubscriptionRepositoryImpl implements SubscriptionRepository {
  SubscriptionRepositoryImpl({required FirebaseFirestore firestore})
      : _firestore = firestore;

  final FirebaseFirestore _firestore;

  // Doc ID = userId_planId — guarantees one doc per user+plan, overwrites on re-subscribe.
  String _docId(String userId, String planId) => '${userId}_$planId';

  @override
  Future<void> subscribe(String userId, String planId, DateTime expiry) {
    return _firestore.collection('subscriptions').doc(_docId(userId, planId)).set({
      'user_id': userId,
      'plan_id': planId,
      'start_date': Timestamp.fromDate(DateTime.now()),
      'expiry_date': Timestamp.fromDate(expiry),
      'is_active': true,
    });
  }

  @override
  Future<void> cancel(String userId, String planId) {
    return _firestore
        .collection('subscriptions')
        .doc(_docId(userId, planId))
        .update({'is_active': false});
  }

  @override
  Stream<List<Subscription>> getUserSubscriptions(String userId) {
    return _firestore
        .collection('subscriptions')
        .where('user_id', isEqualTo: userId)
        .snapshots()
        .map((snap) => snap.docs.map(Subscription.fromFirestore).toList());
  }

  @override
  Stream<List<ActivationRequest>> getPendingRequests(String userId) {
    return _firestore
        .collection('activation_requests')
        .where('user_id', isEqualTo: userId)
        .where('status', isEqualTo: 'pending')
        .snapshots()
        .map((snap) =>
            snap.docs.map(ActivationRequest.fromFirestore).toList());
  }
}
