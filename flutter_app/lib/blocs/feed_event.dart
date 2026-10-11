part of 'feed_bloc.dart';

sealed class FeedEvent extends Equatable {
  const FeedEvent();
}

class FeedStarted extends FeedEvent {
  const FeedStarted();

  @override
  List<Object?> get props => [];
}

class FeedSubscriptionsUpdated extends FeedEvent {
  const FeedSubscriptionsUpdated(this.activePlanIds);

  final List<String> activePlanIds;

  @override
  List<Object?> get props => [activePlanIds];
}
