import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:equatable/equatable.dart';

class PlanPricing extends Equatable {
  const PlanPricing({
    required this.oneMonth,
    required this.sixMonth,
    required this.oneYear,
  });

  /// Price in paise/cents (integer, e.g. 1499 = ₹14.99).
  final int oneMonth;
  final int sixMonth;
  final int oneYear;

  factory PlanPricing.fromMap(Map<String, dynamic> map) => PlanPricing(
        oneMonth: (map['1_month'] as num).toInt(),
        sixMonth: (map['6_month'] as num).toInt(),
        oneYear: (map['1_year'] as num).toInt(),
      );

  Map<String, dynamic> toMap() => {
        '1_month': oneMonth,
        '6_month': sixMonth,
        '1_year': oneYear,
      };

  @override
  List<Object?> get props => [oneMonth, sixMonth, oneYear];
}

class SubscriptionPlan extends Equatable {
  const SubscriptionPlan({
    required this.id,
    required this.name,
    required this.category,
    required this.fcmTopic,
    required this.pricing,
    required this.features,
    required this.isActive,
    required this.createdAt,
  });

  final String id;
  final String name;
  final String category;
  final String fcmTopic;
  final PlanPricing pricing;
  final List<String> features;
  final bool isActive;
  final DateTime createdAt;

  /// Convenience: price in rupees for the 1-month tier.
  double get monthlyPrice => pricing.oneMonth / 100;

  factory SubscriptionPlan.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return SubscriptionPlan(
      id: doc.id,
      name: data['name'] as String,
      category: data['category'] as String? ?? '',
      fcmTopic: data['fcm_topic'] as String,
      pricing: PlanPricing.fromMap(
          (data['pricing'] as Map<String, dynamic>?) ?? {}),
      features: List<String>.from(data['features'] as List? ?? []),
      isActive: data['is_active'] as bool? ?? true,
      createdAt: data['created_at'] is Timestamp
          ? (data['created_at'] as Timestamp).toDate()
          : DateTime.now(),
    );
  }

  Map<String, dynamic> toFirestore() => {
        'name': name,
        'category': category,
        'fcm_topic': fcmTopic,
        'pricing': pricing.toMap(),
        'features': features,
        'is_active': isActive,
        'created_at': Timestamp.fromDate(createdAt),
      };

  @override
  List<Object?> get props =>
      [id, name, category, fcmTopic, pricing, features, isActive, createdAt];
}
