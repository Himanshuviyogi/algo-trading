import 'dart:async';

import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../cubits/cubits.dart';
import '../models/models.dart';
import '../repositories/repositories.dart';

part 'feed_event.dart';
part 'feed_state.dart';

class FeedBloc extends Bloc<FeedEvent, FeedState> {
  FeedBloc({
    required RecommendationRepository recommendationRepository,
    required SubscriptionCubit subscriptionCubit,
  })  : _recommendationRepository = recommendationRepository,
        _subscriptionCubit = subscriptionCubit,
        super(const FeedLoading()) {
    on<FeedStarted>(_onFeedStarted);
    on<FeedSubscriptionsUpdated>(_onFeedSubscriptionsUpdated);
  }

  final RecommendationRepository _recommendationRepository;
  final SubscriptionCubit _subscriptionCubit;

  StreamSubscription<SubscriptionState>? _subscriptionCubitSub;

  Future<void> _onFeedStarted(
    FeedStarted event,
    Emitter<FeedState> emit,
  ) async {
    await _subscriptionCubitSub?.cancel();
    _subscriptionCubitSub = _subscriptionCubit.stream.listen(
      (subscriptionState) {
        if (subscriptionState is SubscriptionLoaded) {
          final activePlanIds = subscriptionState.subscriptions
              .where((s) => s.isEffectivelyActive)
              .map((s) => s.planId)
              .toList();
          add(FeedSubscriptionsUpdated(activePlanIds));
        }
      },
    );

    // Also handle the current state if already loaded
    final currentState = _subscriptionCubit.state;
    if (currentState is SubscriptionLoaded) {
      final activePlanIds = currentState.subscriptions
          .where((s) => s.isEffectivelyActive)
          .map((s) => s.planId)
          .toList();
      add(FeedSubscriptionsUpdated(activePlanIds));
    }
  }

  Future<void> _onFeedSubscriptionsUpdated(
    FeedSubscriptionsUpdated event,
    Emitter<FeedState> emit,
  ) async {
    // await _feedStreamSub?.cancel();
    // _feedStreamSub = null;

    if (event.activePlanIds.isEmpty) {
      emit(const FeedEmpty());
      return;
    }

    emit(const FeedLoading());

    try {
      final results = await _recommendationRepository.getFeed(
        planIds: event.activePlanIds,
        status: 'live',
      );
      emit(FeedLoaded(results));
    } catch (e) {
      emit(FeedError(e.toString()));
    }
  }

  @override
  Future<void> close() async {
    await _subscriptionCubitSub?.cancel();
    return super.close();
  }
}
