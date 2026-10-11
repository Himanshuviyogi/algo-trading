import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:equatable/equatable.dart';

class Subscription extends Equatable {
  const Subscription({
    required this.id,
    required this.userId,
    required this.planId,
    required this.startDate,
    required this.expiryDate,
    required this.isActive,
  });

  final String id;
  final String userId;
  final String planId;
  final DateTime startDate;
  final DateTime expiryDate;
  final bool isActive;

  bool get isExpired => DateTime.now().isAfter(expiryDate);
  bool get isEffectivelyActive => isActive && !isExpired;

  /// Days remaining until expiry (0 means expires today, negative means already expired).
  int get daysUntilExpiry =>
      expiryDate.difference(DateTime.now()).inDays;

  /// True when the subscription is active and expires within 5 days.
  bool get isExpiringSoon => isEffectivelyActive && daysUntilExpiry <= 5;

  factory Subscription.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return Subscription(
      id: doc.id,
      // In the new structure the doc ID is the planId itself.
      userId: data['user_id'] as String? ?? '',
      planId: data['plan_id'] as String? ?? doc.id,
      startDate: (data['start_date'] as Timestamp).toDate(),
      expiryDate: (data['expiry_date'] as Timestamp).toDate(),
      isActive: data['is_active'] as bool? ?? true,
    );
  }

  Map<String, dynamic> toFirestore() => {
        'user_id': userId,
        'plan_id': planId,
        'start_date': Timestamp.fromDate(startDate),
        'expiry_date': Timestamp.fromDate(expiryDate),
        'is_active': isActive,
      };

  @override
  List<Object?> get props => [id, userId, planId, startDate, expiryDate, isActive];
}
