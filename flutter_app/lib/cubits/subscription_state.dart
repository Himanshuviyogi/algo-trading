part of 'subscription_cubit.dart';

sealed class SubscriptionState extends Equatable {
  const SubscriptionState();
}

class SubscriptionLoading extends SubscriptionState {
  const SubscriptionLoading();

  @override
  List<Object?> get props => [];
}

class SubscriptionLoaded extends SubscriptionState {
  const SubscriptionLoaded(this.subscriptions, {this.pendingRequests = const []});

  final List<Subscription> subscriptions;
  final List<ActivationRequest> pendingRequests;

  @override
  List<Object?> get props => [subscriptions, pendingRequests];
}

class SubscriptionError extends SubscriptionState {
  const SubscriptionError(this.message);

  final String message;

  @override
  List<Object?> get props => [message];
}

/// Emitted once per session when at least one active subscription expires
/// within 2 days. The UI should show a toast + play the expiry sound.
class SubscriptionExpiringSoon extends SubscriptionState {
  const SubscriptionExpiringSoon({
    required this.daysRemaining,
    required this.subscriptions,
    this.pendingRequests = const [],
  });

  /// Days until the soonest-expiring active subscription (0 = today).
  final int daysRemaining;
  final List<Subscription> subscriptions;
  final List<ActivationRequest> pendingRequests;

  @override
  List<Object?> get props => [daysRemaining, subscriptions, pendingRequests];
}
