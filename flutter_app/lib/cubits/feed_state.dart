part of 'feed_cubit.dart';

// Sentinel used to distinguish "not provided" from "explicitly null" in copyWith.
const _absent = Object();

class FeedCubitState extends Equatable {
  const FeedCubitState({
    this.isLoading = false,
    this.items = const [],
    this.status = 'live',
    this.category,
    this.categories,
    this.type,
    this.searchQuery,
    this.lastDoc,
    this.hasMore = true,
    this.error,
    this.isSubscribed = false,
  });

  final bool isLoading;
  final List<Recommendation> items;
  final String status;
  final String? category;
  final List<String>? categories; // multi-category (e.g. F&O)
  final String? type;
  final String? searchQuery;
  final DocumentSnapshot? lastDoc;
  final bool hasMore;
  final String? error;
  final bool isSubscribed;

  FeedCubitState copyWith({
    bool? isLoading,
    List<Recommendation>? items,
    String? status,
    Object? category = _absent,
    Object? categories = _absent,
    Object? type = _absent,
    Object? searchQuery = _absent,
    DocumentSnapshot? lastDoc,
    bool? hasMore,
    String? error,
    bool? isSubscribed,
  }) =>
      FeedCubitState(
        isLoading: isLoading ?? this.isLoading,
        items: items ?? this.items,
        status: status ?? this.status,
        category: category == _absent ? this.category : category as String?,
        categories: categories == _absent ? this.categories : categories as List<String>?,
        type: type == _absent ? this.type : type as String?,
        searchQuery: searchQuery == _absent ? this.searchQuery : searchQuery as String?,
        lastDoc: lastDoc ?? this.lastDoc,
        hasMore: hasMore ?? this.hasMore,
        error: error,
        isSubscribed: isSubscribed ?? this.isSubscribed,
      );

  @override
  List<Object?> get props => [
        isLoading, items, status, category, categories, type,
        searchQuery, hasMore, error, isSubscribed,
      ];
}
