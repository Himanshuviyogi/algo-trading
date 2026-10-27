import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:razorpay_flutter/razorpay_flutter.dart';
import '../config/payment_config.dart';

/// Result returned after a payment attempt.
class PaymentResult {
  const PaymentResult._({
    required this.success,
    this.paymentId,
    this.orderId,
    this.signature,
    this.error,
  });

  final bool success;
  final String? paymentId;
  final String? orderId;
  final String? signature;
  final String? error;

  factory PaymentResult.success({
    required String paymentId,
    required String orderId,
    required String signature,
  }) =>
      PaymentResult._(
        success: true,
        paymentId: paymentId,
        orderId: orderId,
        signature: signature,
      );

  factory PaymentResult.failure(String error) =>
      PaymentResult._(success: false, error: error);
}

/// Manages Razorpay SDK lifecycle and payment config loading.
///
/// Usage:
/// ```dart
/// final service = PaymentService();
/// await service.init();
/// final result = await service.startPayment(
///   planId: 'gold',
///   planName: 'Gold Plan',
///   amountRupees: 999,
/// );
/// if (result.success) { ... }
/// service.dispose();
/// ```
class PaymentService {
  PaymentService();

  Razorpay? _razorpay;
  PaymentConfig _config = PaymentConfig.defaults;
  Completer<PaymentResult>? _completer;

  PaymentConfig get config => _config;

  /// Load payment config from Firestore and initialise Razorpay SDK.
  Future<void> init() async {
    await _loadConfig();
    _initSdk();
  }

  Future<void> _loadConfig() async {
    try {
      final snap = await FirebaseFirestore.instance
          .collection('app_config')
          .doc('payment')
          .get();
      if (snap.exists && snap.data() != null) {
        _config = PaymentConfig.fromMap(snap.data()!);
      }
    } catch (e) {
      debugPrint('[PaymentService] Config load failed: $e');
    }
  }

  void _initSdk() {
    _razorpay?.clear();
    _razorpay = Razorpay();
    _razorpay!.on(Razorpay.EVENT_PAYMENT_SUCCESS, _onSuccess);
    _razorpay!.on(Razorpay.EVENT_PAYMENT_ERROR,   _onError);
    _razorpay!.on(Razorpay.EVENT_EXTERNAL_WALLET, _onExternalWallet);
  }

  /// Open the Razorpay payment sheet.
  ///
  /// [orderId] must be a Razorpay order ID created server-side
  /// via the `createRazorpayOrder` Firebase Function.
  Future<PaymentResult> openCheckout({
    required String orderId,
    required String planName,
    required int amountPaise,
  }) {
    _completer = Completer<PaymentResult>();

    // Guard against the placeholder key reaching production
    if (!_config.hasValidRazorpayKey) {
      _completer!.complete(PaymentResult.failure(
        'Razorpay key not configured. Please contact support.',
      ));
      return _completer!.future;
    }

    final user = FirebaseAuth.instance.currentUser;

    final options = {
      'key':         _config.razorpayKeyId,
      'order_id':    orderId,
      'amount':      amountPaise,
      'name':        _config.businessName,
      'description': planName,
      'prefill': {
        'contact': user?.phoneNumber ?? '',
        'email':   user?.email       ?? '',
      },
      'theme': {
        'color': '#4C46E5',
      },
    };

    try {
      _razorpay!.open(options);
    } catch (e) {
      _completer!.complete(PaymentResult.failure(e.toString()));
    }

    return _completer!.future;
  }

  void _onSuccess(PaymentSuccessResponse response) {
    debugPrint('[PaymentService] ✅ Payment success: ${response.paymentId}');
    _completer?.complete(PaymentResult.success(
      paymentId: response.paymentId ?? '',
      orderId:   response.orderId   ?? '',
      signature: response.signature ?? '',
    ));
    _completer = null;
  }

  void _onError(PaymentFailureResponse response) {
    debugPrint('[PaymentService] ❌ Payment error: ${response.message}');
    _completer?.complete(PaymentResult.failure(
      response.message ?? 'Payment failed',
    ));
    _completer = null;
  }

  void _onExternalWallet(ExternalWalletResponse response) {
    debugPrint('[PaymentService] 👛 External wallet: ${response.walletName}');
    _completer?.complete(PaymentResult.failure(
      'External wallet selected: ${response.walletName}',
    ));
    _completer = null;
  }

  void dispose() {
    _razorpay?.clear();
    _razorpay = null;
  }
}
