import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:equatable/equatable.dart';

/// Represents a manual subscription activation request submitted by a user.
/// Status lifecycle: pending → approved | rejected
class ActivationRequest extends Equatable {
  const ActivationRequest({
    required this.id,
    required this.userId,
    required this.planId,
    required this.planName,
    required this.durationMonths,
    required this.amount,
    required this.paymentMethod,
    required this.status,
    required this.userName,
    required this.userPhone,
    required this.createdAt,
    this.note,
    this.updatedAt,
    this.rejectionReason,
  });

  final String id;
  final String userId;
  final String planId;
  final String planName;
  final int durationMonths;
  final int amount; // in rupees
  final String paymentMethod; // 'request' | 'qr_bank'
  final String status; // 'pending' | 'approved' | 'rejected'
  final String userName;
  final String userPhone;
  final DateTime createdAt;
  final String? note;
  final DateTime? updatedAt;
  final String? rejectionReason;

  bool get isPending  => status == 'pending';
  bool get isApproved => status == 'approved';
  bool get isRejected => status == 'rejected';

  String get durationLabel {
    switch (durationMonths) {
      case 6:  return '6 Months';
      case 12: return '1 Year';
      default: return '1 Month';
    }
  }

  factory ActivationRequest.fromFirestore(DocumentSnapshot doc) {
    final d = doc.data() as Map<String, dynamic>;
    return ActivationRequest(
      id:               doc.id,
      userId:           d['user_id']        as String? ?? '',
      planId:           d['plan_id']         as String? ?? '',
      planName:         d['plan_name']       as String? ?? '',
      durationMonths:   (d['duration_months'] as num?)?.toInt() ?? 1,
      amount:           (d['amount']          as num?)?.toInt() ?? 0,
      paymentMethod:    d['payment_method']  as String? ?? 'request',
      status:           d['status']          as String? ?? 'pending',
      userName:         d['user_name']       as String? ?? '',
      userPhone:        d['user_phone']      as String? ?? '',
      note:             d['note']            as String?,
      rejectionReason:  d['rejection_reason'] as String?,
      createdAt: d['created_at'] is Timestamp
          ? (d['created_at'] as Timestamp).toDate()
          : DateTime.now(),
      updatedAt: d['updated_at'] is Timestamp
          ? (d['updated_at'] as Timestamp).toDate()
          : null,
    );
  }

  Map<String, dynamic> toFirestore() => {
        'user_id':         userId,
        'plan_id':         planId,
        'plan_name':       planName,
        'duration_months': durationMonths,
        'amount':          amount,
        'payment_method':  paymentMethod,
        'status':          status,
        'user_name':       userName,
        'user_phone':      userPhone,
        if (note != null) 'note': note,
        'created_at':      Timestamp.fromDate(createdAt),
        'updated_at':      Timestamp.now(),
      };

  @override
  List<Object?> get props => [
        id, userId, planId, durationMonths, amount,
        paymentMethod, status, createdAt,
      ];
}
