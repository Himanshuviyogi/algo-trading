part of 'feed_bloc.dart';

sealed class FeedState extends Equatable {
  const FeedState();
}

class FeedLoading extends FeedState {
  const FeedLoading();

  @override
  List<Object?> get props => [];
}

class FeedLoaded extends FeedState {
  const FeedLoaded(this.recommendations);

  final List<Recommendation> recommendations;

  @override
  List<Object?> get props => [recommendations];
}

class FeedEmpty extends FeedState {
  const FeedEmpty();

  @override
  List<Object?> get props => [];
}

class FeedError extends FeedState {
  const FeedError(this.message);

  final String message;

  @override
  List<Object?> get props => [message];
}
