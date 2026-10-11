import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:equatable/equatable.dart';

class UserProfile extends Equatable {
  const UserProfile({
    required this.uid,
    required this.phoneNumber,
    this.name,
    this.email,
    this.fcmToken,
    this.onboardingSkipped = false,
    required this.createdAt,
  });

  final String uid;
  final String phoneNumber;
  final String? name;
  final String? email;
  final String? fcmToken;
  final bool onboardingSkipped;
  final DateTime createdAt;

  /// Profile is complete if the user has set a name.
  /// Email is optional — we don't want to re-prompt on every login
  /// just because email wasn't filled in.
  bool get isProfileComplete =>
      name != null && name!.trim().isNotEmpty;

  /// True if the user has either subscribed to a plan OR explicitly skipped
  /// the onboarding plans screen. Used by the router to avoid showing it again.
  bool get shouldSkipPlanOnboarding => onboardingSkipped;

  factory UserProfile.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return UserProfile(
      uid: data['uid'] as String,
      phoneNumber: data['phone_number'] as String,
      name: data['name'] as String?,
      email: data['email'] as String?,
      fcmToken: data['fcm_token'] as String?,
      onboardingSkipped: data['onboarding_skipped'] as bool? ?? false,
      createdAt: (data['created_at'] as Timestamp).toDate(),
    );
  }

  Map<String, dynamic> toFirestore() => {
        'uid': uid,
        'phone_number': phoneNumber,
        'name': name,
        'email': email,
        'fcm_token': fcmToken,
        'onboarding_skipped': onboardingSkipped,
        'created_at': Timestamp.fromDate(createdAt),
      };

  @override
  List<Object?> get props => [uid, phoneNumber, name, email, fcmToken, onboardingSkipped, createdAt];
}
