import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/user_profile.dart';

abstract class UserRepository {
  Future<void> createUserProfile(String uid, String phoneNumber);
  Future<UserProfile?> getUserProfile(String uid);
  Future<void> updateProfile(String uid, {required String name, required String email});
  Future<void> markOnboardingSkipped(String uid);
  Future<void> updateFcmToken(String uid, String token);
  Future<void> clearFcmToken(String uid);
}

class UserRepositoryImpl implements UserRepository {
  UserRepositoryImpl({required FirebaseFirestore firestore})
      : _firestore = firestore;

  final FirebaseFirestore _firestore;

  @override
  Future<void> createUserProfile(String uid, String phoneNumber) {
    return _firestore.collection('users').doc(uid).set({
      'uid': uid,
      'phone_number': phoneNumber,
      'created_at': Timestamp.fromDate(DateTime.now()),
    }, SetOptions(merge: true));
  }

  @override
  Future<UserProfile?> getUserProfile(String uid) async {
    final doc = await _firestore.collection('users').doc(uid).get();
    if (!doc.exists) return null;
    return UserProfile.fromFirestore(doc);
  }

  @override
  Future<void> updateProfile(String uid, {required String name, required String email}) {
    return _firestore.collection('users').doc(uid).set({
      'name': name,
      'email': email,
    }, SetOptions(merge: true));
  }

  @override
  Future<void> markOnboardingSkipped(String uid) {
    return _firestore.collection('users').doc(uid).set({
      'onboarding_skipped': false,
    }, SetOptions(merge: true));
  }

  @override
  Future<void> updateFcmToken(String uid, String token) {
    // Uses a separate field name from the recom app (`fcm_token`) so both apps
    // can coexist on the same Firebase project without overwriting each other's
    // push notification tokens.
    return _firestore.collection('users').doc(uid).set({
      'algo_fcm_token': token,
    }, SetOptions(merge: true));
  }

  @override
  Future<void> clearFcmToken(String uid) {
    return _firestore.collection('users').doc(uid).set({
      'algo_fcm_token': null,
    }, SetOptions(merge: true));
  }
}
