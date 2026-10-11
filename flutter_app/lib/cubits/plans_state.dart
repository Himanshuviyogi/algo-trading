part of 'plans_cubit.dart';

sealed class PlansState extends Equatable {
  const PlansState();
}

class PlansLoading extends PlansState {
  const PlansLoading();

  @override
  List<Object?> get props => [];
}

class PlansLoaded extends PlansState {
  const PlansLoaded(this.plans);

  final List<SubscriptionPlan> plans;

  @override
  List<Object?> get props => [plans];
}

class PlansError extends PlansState {
  const PlansError(this.message);

  final String message;

  @override
  List<Object?> get props => [message];
}
