part of 'signal_detail_cubit.dart';

sealed class RecommendationDetailState extends Equatable {
  const RecommendationDetailState();
}

class RecommendationDetailLoading extends RecommendationDetailState {
  const RecommendationDetailLoading();

  @override
  List<Object?> get props => [];
}

class RecommendationDetailLoaded extends RecommendationDetailState {
  const RecommendationDetailLoaded(this.recommendation);

  final Recommendation recommendation;

  @override
  List<Object?> get props => [recommendation];
}

class RecommendationDetailAccessDenied extends RecommendationDetailState {
  const RecommendationDetailAccessDenied();

  @override
  List<Object?> get props => [];
}

class RecommendationDetailError extends RecommendationDetailState {
  const RecommendationDetailError(this.message);

  final String message;

  @override
  List<Object?> get props => [message];
}
