import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../cubits/subscription_cubit.dart';
import '../models/recommendation.dart';
import '../models/subscription.dart';
import '../repositories/signal_repository.dart';

part 'signal_detail_state.dart';

class RecommendationDetailCubit extends Cubit<RecommendationDetailState> {
  RecommendationDetailCubit({
    required RecommendationRepository recommendationRepository,
    required SubscriptionCubit subscriptionCubit,
  })  : _recommendationRepository = recommendationRepository,
        _subscriptionCubit = subscriptionCubit,
        super(const RecommendationDetailLoading());

  final RecommendationRepository _recommendationRepository;
  final SubscriptionCubit _subscriptionCubit;
  StreamSubscription? _recommendationSubscription;
  StreamSubscription? _subscriptionWatchSub;

  Future<void> load(String id) async {
    emit(const RecommendationDetailLoading());
    await _recommendationSubscription?.cancel();
    await _subscriptionWatchSub?.cancel();

    final subState = _subscriptionCubit.state;

    if (subState is SubscriptionLoaded) {
      // Subscriptions ready — load immediately
      await _loadWithSubscriptions(id, subState.subscriptions);
    } else {
      // Subscriptions still loading — wait for them then load
      _subscriptionWatchSub = _subscriptionCubit.stream.listen((state) async {
        if (state is SubscriptionLoaded) {
          await _subscriptionWatchSub?.cancel();
          _subscriptionWatchSub = null;
          if (!isClosed) {
            await _loadWithSubscriptions(id, state.subscriptions);
          }
        }
      });
    }
  }

  Future<void> _loadWithSubscriptions(
    String id,
    List<Subscription> subscriptions,
  ) async {
    try {
      final recommendation = await _recommendationRepository.getById(id);

      final hasAccess = subscriptions.any(
        (s) => s.isEffectivelyActive && recommendation.planIds.contains(s.planId),
      );

      if (!hasAccess) {
        emit(const RecommendationDetailAccessDenied());
        return;
      }

      emit(RecommendationDetailLoaded(recommendation));
      _startRealtimeListener(id);
    } catch (e) {
      emit(RecommendationDetailError(e.toString()));
    }
  }

  void _startRealtimeListener(String id) {
    _recommendationSubscription = _recommendationRepository
        .streamById(id)
        .listen(
          (recommendation) {
            // Only emit if we're currently in a loaded state
            if (state is RecommendationDetailLoaded) {
              emit(RecommendationDetailLoaded(recommendation));
            }
          },
          onError: (error) {
            // Don't emit error if we're already showing data
            if (state is! RecommendationDetailLoaded) {
              emit(RecommendationDetailError(error.toString()));
            }
          },
        );
  }

  @override
  Future<void> close() {
    _recommendationSubscription?.cancel();
    _subscriptionWatchSub?.cancel();
    return super.close();
  }
}
