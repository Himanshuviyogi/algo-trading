/// Payment configuration loaded from Firestore `app_config/payment`.
///
/// Admin panel toggles `payment_mode` between 'manual' and 'razorpay'.
/// The app reads this once on the plans screen and routes accordingly.
///
/// Razorpay Key ID is safe to embed in the app (it's public).
/// Key Secret NEVER goes in the app — it lives in Firebase Functions env.
class PaymentConfig {
  const PaymentConfig({
    required this.mode,
    required this.razorpayKeyId,
    required this.businessName,
    required this.businessDescription,
  });

  /// 'manual' = direct Firestore write (current flow, no payment)
  /// 'razorpay' = Razorpay payment sheet → server-side verification
  final String mode;

  /// Razorpay Key ID (test: rzp_test_xxx, live: rzp_live_xxx)
  final String razorpayKeyId;

  /// Shown in the Razorpay payment sheet
  final String businessName;
  final String businessDescription;

  bool get isRazorpay => mode == 'razorpay';
  bool get isManual   => mode == 'manual';

  factory PaymentConfig.fromMap(Map<String, dynamic> m) => PaymentConfig(
        mode:                m['payment_mode']        as String? ?? 'manual',
        razorpayKeyId:       m['razorpay_key_id']     as String? ?? _testKeyId,
        businessName:        m['business_name']        as String? ?? 'Stockara',
        businessDescription: m['business_description'] as String? ?? 'Premium Trading Signals',
      );

  /// Fallback test key — replace with your actual test key ID
  static const String _testKeyId = 'rzp_test_YOUR_KEY_ID';

  /// Default config used while Firestore is loading
  static const PaymentConfig defaults = PaymentConfig(
    mode:                'manual',
    razorpayKeyId:       _testKeyId,
    businessName:        'Stockara',
    businessDescription: 'Premium Trading Signals',
  );
}
