part of 'market_data_cubit.dart';

// ─── States ───────────────────────────────────────────────────────────────────

/// Before any load has been attempted.
class MarketDataInitial extends MarketDataState {
  const MarketDataInitial();
  @override
  List<Object?> get props => [];
}

/// Fetching data for the first time (no cached data available).
class MarketDataLoading extends MarketDataState {
  const MarketDataLoading();
  @override
  List<Object?> get props => [];
}

/// Watchlist quotes are available (may still be refreshing in the background).
class MarketDataLoaded extends MarketDataState {
  /// All quotes for the active watchlist, in watchlist order.
  final List<MarketQuote> quotes;

  /// When this snapshot was fetched.
  final DateTime loadedAt;

  /// True while a background refresh is in progress.
  final bool isRefreshing;

  const MarketDataLoaded({
    required this.quotes,
    required this.loadedAt,
    this.isRefreshing = false,
  });

  /// Quotes sorted by % change descending (gainers first).
  List<MarketQuote> get gainers => [...quotes]
    ..sort((a, b) => b.percentChange.compareTo(a.percentChange));

  /// Quotes sorted by % change ascending (losers first).
  List<MarketQuote> get losers => [...quotes]
    ..sort((a, b) => a.percentChange.compareTo(b.percentChange));

  MarketDataLoaded copyWith({
    List<MarketQuote>? quotes,
    DateTime? loadedAt,
    bool? isRefreshing,
  }) =>
      MarketDataLoaded(
        quotes: quotes ?? this.quotes,
        loadedAt: loadedAt ?? this.loadedAt,
        isRefreshing: isRefreshing ?? this.isRefreshing,
      );

  @override
  List<Object?> get props => [quotes, loadedAt, isRefreshing];
}

/// Fetch failed (no cached data to fall back on).
class MarketDataError extends MarketDataState {
  final String message;
  final MarketDataErrorType errorType;

  const MarketDataError({
    required this.message,
    required this.errorType,
  });

  String get userFriendlyMessage {
    switch (errorType) {
      case MarketDataErrorType.authentication:
        return 'Authentication failed. Please check API configuration.';
      case MarketDataErrorType.network:
        return 'No internet connection. Please check your network.';
      case MarketDataErrorType.rateLimit:
        return 'Too many requests. Please try again in a moment.';
      case MarketDataErrorType.timeout:
        return 'Request timed out. Please try again.';
      case MarketDataErrorType.parsing:
        return 'Unable to process market data. Please try again.';
      case MarketDataErrorType.apiError:
        return 'Market data service unavailable. Please try again later.';
      case MarketDataErrorType.unknown:
        return 'An unexpected error occurred. Please try again.';
    }
  }

  @override
  List<Object?> get props => [message, errorType];
}

// ─── Base ─────────────────────────────────────────────────────────────────────

sealed class MarketDataState extends Equatable {
  const MarketDataState();
}

// ─── Legacy aliases (kept so nothing outside the cubit breaks) ────────────────
// These are type aliases — existing code that checks `state is MarketDataPartiallyLoaded`
// will still compile; just treat it the same as MarketDataLoaded.
typedef MarketDataPartiallyLoaded = MarketDataLoaded;
