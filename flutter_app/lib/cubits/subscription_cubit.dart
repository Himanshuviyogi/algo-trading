import 'dart:async';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../models/models.dart';
import '../repositories/repositories.dart';
import '../services/notification_service.dart';
import '../services/payment_service.dart';
import '../config/payment_config.dart';

part 'subscription_state.dart';

class SubscriptionCubit extends Cubit<SubscriptionState> {
  SubscriptionCubit({
    required SubscriptionRepository subscriptionRepository,
    required PlanRepository planRepository,
    required NotificationService notificationService,
    required String userId,
  })  : _subscriptionRepository = subscriptionRepository,
        _planRepository = planRepository,
        _notificationService = notificationService,
        _userId = userId,
        super(const SubscriptionLoading());

  final SubscriptionRepository _subscriptionRepository;
  final PlanRepository _planRepository;
  final NotificationService _notificationService;
  final String _userId;
  StreamSubscription<List<Subscription>>? _subscription;
  StreamSubscription<List<ActivationRequest>>? _pendingSubscription;

  // Hold latest values from both streams so we can combine them.
  List<Subscription> _latestSubs = [];
  List<ActivationRequest> _latestPending = [];

  /// Guard: only show the expiry toast once per app session.
  bool _expiryAlertShown = false;

  void loadSubscriptions() {
    emit(const SubscriptionLoading());
    _subscription?.cancel();
    _pendingSubscription?.cancel();

    _subscription = _subscriptionRepository.getUserSubscriptions(_userId).listen(
      (subscriptions) async {
        _latestSubs = subscriptions;

        // Check if any active subscription expires within 2 days — show once per session.
        if (!_expiryAlertShown) {
          final expiringSoon = subscriptions.where(
            (s) => s.isEffectivelyActive && s.daysUntilExpiry <= 2,
          );
          if (expiringSoon.isNotEmpty) {
            _expiryAlertShown = true;
            final soonest = expiringSoon.reduce(
              (a, b) => a.daysUntilExpiry < b.daysUntilExpiry ? a : b,
            );
            emit(SubscriptionExpiringSoon(
              daysRemaining: soonest.daysUntilExpiry.clamp(0, 2),
              subscriptions: _latestSubs,
              pendingRequests: _latestPending,
            ));
            // Also emit the normal loaded state so the UI updates correctly.
            emit(SubscriptionLoaded(_latestSubs, pendingRequests: _latestPending));
            await _syncFcmTopics(subscriptions);
            return;
          }
        }

        emit(SubscriptionLoaded(_latestSubs, pendingRequests: _latestPending));
        await _syncFcmTopics(subscriptions);
      },
      onError: (Object error) => emit(SubscriptionError(error.toString())),
    );

    _pendingSubscription = _subscriptionRepository.getPendingRequests(_userId).listen(
      (pending) {
        _latestPending = pending;
        emit(SubscriptionLoaded(_latestSubs, pendingRequests: _latestPending));
      },
      onError: (_) {}, // non-fatal — pending requests failing shouldn't crash the screen
    );
  }

  Future<void> _syncFcmTopics(List<Subscription> subscriptions) async {
    try {
      // Only subscribe to topics for active plans — never unsubscribe.
      // The recom app manages its own topic subscriptions independently on the
      // same Firebase project. Calling unsubscribeFromTopic here would remove
      // the user from recom notifications they still want to receive.
      final plans = await _planRepository.getPlans();
      for (final plan in plans) {
        final hasActiveSub = subscriptions.any(
          (s) => s.planId == plan.id && s.isEffectivelyActive,
        );
        if (hasActiveSub) {
          await _notificationService.subscribeToTopic(plan.fcmTopic);
        }
        // Intentionally no unsubscribeFromTopic call — handled by recom app only.
      }
    } catch (e) {
      print('⚠️ [SubscriptionCubit] Failed to sync FCM topics: $e');
    }
  }

  // ── Manual subscribe (current flow — no payment) ──────────────────────────

  Future<void> subscribe(String planId, DateTime expiry) async {
    try {
      await _subscriptionRepository.subscribe(_userId, planId, expiry);
      // Small delay so the Firestore write propagates before the stream re-fires
      await Future.delayed(const Duration(milliseconds: 500));
      final plans = await _planRepository.getPlans();
      final plan = plans.firstWhere((p) => p.id == planId);
      await _notificationService.subscribeToTopic(plan.fcmTopic);
    } catch (e) {
      emit(SubscriptionError(e.toString()));
    }
  }

  // ── Activation request flow (manual payment) ─────────────────────────────
  // User submits a request; admin approves from the dashboard.

  Future<void> submitActivationRequest({
    required String planId,
    required String planName,
    required int durationMonths,
    required int amount,
    required String paymentMethod, // 'request' | 'qr_bank'
    required String userName,
    required String userPhone,
    String type = 'subscription', // 'subscription' | 'ai_boost'
    String? note,
  }) async {
    try {
      final fn = FirebaseFunctions.instance
          .httpsCallable('submitActivationRequest');
      await fn.call({
        'type':            type,
        'planId':          planId,
        'planName':        planName,
        'durationMonths':  durationMonths,
        'amount':          amount,
        'paymentMethod':   paymentMethod,
        'userName':        userName,
        'userPhone':       userPhone,
        if (note != null && note.isNotEmpty) 'note': note,
      });
    } catch (e) {
      rethrow;
    }
  }

  // ── Razorpay flow ─────────────────────────────────────────────────────────
  // Returns a PaymentResult so the UI can show the Razorpay sheet and handle
  // success/failure. The cubit handles the server-side verification step.

  /// Step 1: Create a Razorpay order server-side.
  /// Returns the order details needed to open the payment sheet.
  Future<Map<String, dynamic>> createRazorpayOrder({
    required String planId,
    required int durationMonths,
  }) async {
    final fn = FirebaseFunctions.instance.httpsCallable('createRazorpayOrder');
    final result = await fn.call({
      'planId':          planId,
      'durationMonths':  durationMonths,
    });
    return Map<String, dynamic>.from(result.data as Map);
  }

  /// Step 2: After Razorpay payment success, verify server-side and activate.
  Future<void> verifyAndActivate({
    required String razorpayOrderId,
    required String razorpayPaymentId,
    required String razorpaySignature,
    required String planId,
    required int durationMonths,
  }) async {
    try {
      final fn = FirebaseFunctions.instance.httpsCallable('verifyRazorpayPayment');
      final result = await fn.call({
        'razorpayOrderId':   razorpayOrderId,
        'razorpayPaymentId': razorpayPaymentId,
        'razorpaySignature': razorpaySignature,
        'planId':            planId,
        'durationMonths':    durationMonths,
      });

      final data = Map<String, dynamic>.from(result.data as Map);
      if (data['success'] == true) {
        // Wait 2s for Firestore write to propagate before reloading subscriptions.
        // Without this delay the stream may fire before the doc is readable.
        await Future.delayed(const Duration(seconds: 2));
        loadSubscriptions(); // triggers stream → SubscriptionLoaded → feed reloads
        final plans = await _planRepository.getPlans();
        final plan = plans.firstWhere((p) => p.id == planId);
        await _notificationService.subscribeToTopic(plan.fcmTopic);
      } else {
        emit(SubscriptionError('Payment verification failed'));
      }
    } catch (e) {
      emit(SubscriptionError(e.toString()));
    }
  }

  Future<void> cancel(String planId) async {
    try {
      await _subscriptionRepository.cancel(_userId, planId);
      // Do not unsubscribeFromTopic here — the recom app controls its own
      // topic subscriptions. The device will stop receiving algo signals for
      // this plan once the subscription is marked inactive in Firestore.
    } catch (e) {
      emit(SubscriptionError(e.toString()));
    }
  }

  @override
  Future<void> close() {
    _subscription?.cancel();
    _pendingSubscription?.cancel();
    return super.close();
  }
}
