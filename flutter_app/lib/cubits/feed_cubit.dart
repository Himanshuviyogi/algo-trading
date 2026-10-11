import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../models/recommendation.dart';
import '../repositories/signal_repository.dart';

part 'feed_state.dart';

class FeedCubit extends Cubit<FeedCubitState> {
  FeedCubit({required RecommendationRepository recommendationRepository})
      : _repo = recommendationRepository,
        super(const FeedCubitState());

  final RecommendationRepository _repo;
  StreamSubscription<List<Recommendation>>? _liveStreamSub;

  static const _pageSize = 20;

  Future<void> load({
    required List<String> activePlanIds,
    required String status,
    String? category,
    List<String>? categories, // multi-category filter (e.g. F&O = ['futures','options'])
    String? type,
    String? searchQuery,
    bool refresh = false,
  }) async {
    if (state.isLoading && !refresh) return;

    // Normalise: if categories has exactly one value, use category instead
    final effectiveCategory = categories != null && categories.length == 1
        ? categories.first
        : category;
    final effectiveCategories = categories != null && categories.length > 1
        ? categories
        : null;

    final isSubscribed = activePlanIds.isNotEmpty;
    final newStatus = status;
    final filtersChanged = refresh ||
        newStatus != state.status ||
        effectiveCategory != state.category ||
        !_listEquals(effectiveCategories, state.categories) ||
        type != state.type ||
        searchQuery != state.searchQuery;

    final lastDoc = filtersChanged ? null : state.lastDoc;
    final existingItems = filtersChanged ? <Recommendation>[] : state.items;

    emit(state.copyWith(
      isLoading: true,
      status: newStatus,
      category: effectiveCategory,
      categories: effectiveCategories,
      type: type,
      searchQuery: searchQuery,
      items: existingItems,
      lastDoc: lastDoc,
      hasMore: true,
      error: null,
      isSubscribed: isSubscribed,
    ));

    try {
      final results = await _repo.getFeed(
        planIds: activePlanIds,
        status: newStatus,
        category: effectiveCategory,
        categories: effectiveCategories,
        type: type,
        searchQuery: searchQuery,
        lastDoc: lastDoc,
        pageSize: _pageSize,
      );

      final allItems = [...existingItems, ...results];
      final newLastDoc = results.isNotEmpty
          ? await _getLastDoc(results.last.id)
          : lastDoc;

      emit(state.copyWith(
        isLoading: false,
        items: allItems,
        lastDoc: newLastDoc,
        hasMore: results.length == _pageSize,
        error: null,
        isSubscribed: isSubscribed,
      ));

      // Start real-time listener for live feed so target/stoploss/status
      // updates from admin panel reflect immediately without a refresh.
      if (newStatus == 'live' && activePlanIds.isNotEmpty && filtersChanged) {
        _startLiveStream(
          planIds: activePlanIds,
          category: effectiveCategory,
          categories: effectiveCategories,
          type: type,
        );
      }
    } catch (e) {
      emit(state.copyWith(isLoading: false, error: e.toString()));
    }
  }

  void _startLiveStream({
    required List<String> planIds,
    String? category,
    List<String>? categories,
    String? type,
  }) {
    _liveStreamSub?.cancel();
    _liveStreamSub = _repo
        .streamLiveFeed(
          planIds: planIds,
          category: category,
          categories: categories,
          type: type,
        )
        .listen((updatedItems) {
      if (isClosed) return;
      if (state.items.isEmpty) return;

      // Merge: update existing items in place, preserving order and pagination
      final currentIds = state.items.map((r) => r.id).toSet();
      final updatedMap = {for (final r in updatedItems) r.id: r};

      final merged = state.items.map((r) {
        return updatedMap[r.id] ?? r;
      }).toList();

      // Add any new items that appeared (e.g. newly published)
      for (final r in updatedItems) {
        if (!currentIds.contains(r.id)) merged.insert(0, r);
      }

      emit(state.copyWith(items: merged));
    });
  }

  Future<void> loadMore({required List<String> activePlanIds}) async {
    if (!state.hasMore || state.isLoading) return;
    await load(
      activePlanIds: activePlanIds,
      status: state.status,
      category: state.category,
      categories: state.categories,
      type: state.type,
      searchQuery: state.searchQuery,
    );
  }

  Future<DocumentSnapshot?> _getLastDoc(String id) async {
    try {
      return await _repo.getDocSnapshot(id);
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> close() {
    _liveStreamSub?.cancel();
    return super.close();
  }
}

// Shallow equality check for nullable string lists.
bool _listEquals(List<String>? a, List<String>? b) {
  if (a == null && b == null) return true;
  if (a == null || b == null) return false;
  if (a.length != b.length) return false;
  for (int i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}
