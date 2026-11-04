import '../models/market_quote.dart';
import '../models/market_index.dart';

/// Enum defining all possible error types for market data operations.
enum MarketDataErrorType {
  /// Invalid or missing API key
  authentication,

  /// No network connection available
  network,

  /// API rate limit exceeded
  rateLimit,

  /// Request exceeded timeout duration
  timeout,

  /// Invalid JSON response format
  parsing,

  /// Other API errors (4xx, 5xx)
  apiError,

  /// Unexpected or unknown errors
  unknown,
}

/// Exception thrown when market data operations fail.
class MarketDataException implements Exception {
  final String message;
  final MarketDataErrorType type;

  MarketDataException(this.message, this.type);

  @override
  String toString() => 'MarketDataException: $message';
}

/// Abstract interface for market data operations.
abstract class MarketDataRepository {
  Future<List<MarketIndex>> getMarketIndices();
  Future<MarketQuote> getQuote(String symbol);
  Future<List<MarketQuote>> getMultipleQuotes(List<String> symbols);
  void clearCache();
}

/// No-op implementation — market data is now served by the Railway price
/// server via [LivePriceCubit]. This stub keeps the widget tree intact while
/// the full migration is completed.
class MarketDataRepositoryImpl implements MarketDataRepository {
  @override
  Future<List<MarketIndex>> getMarketIndices() async => [];

  @override
  Future<MarketQuote> getQuote(String symbol) async {
    throw MarketDataException(
      'Market data is served by the live price server',
      MarketDataErrorType.unknown,
    );
  }

  @override
  Future<List<MarketQuote>> getMultipleQuotes(List<String> symbols) async => [];

  @override
  void clearCache() {}
}
