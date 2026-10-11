import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import '../config/finnhub_config.dart';
import '../models/market_quote.dart';
import '../models/market_index.dart';

/// Enum defining all possible error types for market data operations
enum MarketDataErrorType {
  /// Invalid or missing API key (HTTP 401)
  authentication,
  
  /// No network connection available
  network,
  
  /// API rate limit exceeded (HTTP 429)
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

/// Exception thrown when market data operations fail
class MarketDataException implements Exception {
  /// Descriptive error message
  final String message;
  
  /// Type of error that occurred
  final MarketDataErrorType type;
  
  MarketDataException(this.message, this.type);
  
  @override
  String toString() => 'MarketDataException: $message';
}


/// Abstract interface for market data operations
abstract class MarketDataRepository {
  /// Fetches major market indices (S&P 500, Dow Jones, NASDAQ, Russell 2000)
  Future<List<MarketIndex>> getMarketIndices();
  
  /// Fetches a quote for a single stock symbol
  Future<MarketQuote> getQuote(String symbol);
  
  /// Fetches quotes for multiple stock symbols
  Future<List<MarketQuote>> getMultipleQuotes(List<String> symbols);
  
  /// Clears all cached market data
  void clearCache();
}

/// Internal class to store cached data with timestamp
class _CachedData {
  final dynamic data;
  final DateTime timestamp;
  
  _CachedData(this.data, this.timestamp);
}

/// Implementation of MarketDataRepository with caching support
class MarketDataRepositoryImpl implements MarketDataRepository {
  final http.Client _client;
  final Map<String, _CachedData> _cache = {};
  
  /// Cache duration: 60 seconds
  static const _cacheDuration = Duration(seconds: 60);
  
  /// Request timeout: 10 seconds
  static const _requestTimeout = Duration(seconds: 10);
  
  /// Creates a new MarketDataRepositoryImpl instance
  /// 
  /// Validates the Finnhub configuration on construction.
  /// Optionally accepts an [http.Client] for testing purposes.
  MarketDataRepositoryImpl({http.Client? client}) 
      : _client = client ?? http.Client() {
    FinnhubConfig.validate();
  }

  
  @override
  Future<MarketQuote> getQuote(String symbol) async {
    final cacheKey = 'quote_$symbol';
    
    // Check cache first
    if (_isCacheValid(cacheKey)) {
      print("✅ Cache hit for $symbol");
      return _cache[cacheKey]!.data as MarketQuote;
    }
    
    try {
      // Build Finnhub API URL
      final url = Uri.parse(
        '${FinnhubConfig.baseUrl}/quote?symbol=$symbol&token=${FinnhubConfig.apiKey}'
      );
      
      // print("🌐 Fetching $symbol from ${url.toString().replaceAll(FinnhubConfig.apiKey, '***')}");
      
      // Make HTTP GET request with timeout
      final response = await _client
          .get(url)
          .timeout(_requestTimeout);
      
      // print("📡 Response for $symbol: ${response.statusCode}");
      
      // Handle authentication error
      if (response.statusCode == 401) {
        throw MarketDataException(
          'Invalid API key',
          MarketDataErrorType.authentication,
        );
      }
      
      // Handle rate limit error
      if (response.statusCode == 429) {
        throw MarketDataException(
          'Rate limit exceeded',
          MarketDataErrorType.rateLimit,
        );
      }
      
      // Handle other API errors
      if (response.statusCode != 200) {
        throw MarketDataException(
          'API error: ${response.statusCode}',
          MarketDataErrorType.apiError,
        );
      }
      
      print("📄 Response body for $symbol: ${response.body}");
      
      // Parse JSON response
      final json = jsonDecode(response.body) as Map<String, dynamic>;
      
      // Check if the response contains valid data
      if (json['c'] == null || json['c'] == 0) {
        print("⚠️ Invalid or empty data for $symbol");
        throw MarketDataException(
          'No data available for symbol $symbol',
          MarketDataErrorType.parsing,
        );
      }
      
      final quote = MarketQuote.fromJson(json, symbol);
      
      print("✅ Successfully parsed quote for $symbol: \$${quote.currentPrice}");
      
      // Update cache
      _cache[cacheKey] = _CachedData(quote, DateTime.now());
      return quote;
    } on TimeoutException {
      print("⏱️ Timeout for $symbol");
      throw MarketDataException(
        'Request timeout',
        MarketDataErrorType.timeout,
      );
    } on SocketException catch (e) {
      print("🔌 Network error for $symbol: $e");
      throw MarketDataException(
        'No network connection',
        MarketDataErrorType.network,
      );
    } on FormatException catch (e) {
      print("📋 Parse error for $symbol: $e");
      throw MarketDataException(
        'Invalid response format',
        MarketDataErrorType.parsing,
      );
    } catch (e) {
      if (e is MarketDataException) rethrow;
      print("❌ Unexpected error for $symbol: $e");
      throw MarketDataException(
        'Unexpected error: $e',
        MarketDataErrorType.unknown,
      );
    }
  }

  
  @override
  Future<List<MarketQuote>> getMultipleQuotes(List<String> symbols) async {
    final quotes = <MarketQuote>[];
    
    // Fetch quotes sequentially
    for (final symbol in symbols) {
      try {
        quotes.add(await getQuote(symbol));
      } catch (e) {
        // Continue fetching other symbols even if one fails
        continue;
      }
    }
    
    return quotes;
  }
  
  @override
  Future<List<MarketIndex>> getMarketIndices() async {
    const cacheKey = 'market_indices';
    
    // Check cache first
    if (_isCacheValid(cacheKey)) {
      return _cache[cacheKey]!.data as List<MarketIndex>;
    }
    
    try {
      // Define major market indices with their symbols and names
      final symbols = [
        ('^GSPC', 'S&P 500'),
        ('^DJI', 'Dow Jones'),
        ('^IXIC', 'NASDAQ'),
        ('^RUT', 'Russell 2000'),
      ];
      
      // Fetch quotes for all index symbols
      final quotes = await getMultipleQuotes(
        symbols.map((s) => s.$1).toList()
      );
      
      // Convert quotes to MarketIndex objects
      final indices = <MarketIndex>[];
      for (var i = 0; i < quotes.length; i++) {
        indices.add(MarketIndex.fromQuote(quotes[i], symbols[i].$2));
      }
      
      // Update cache
      _cache[cacheKey] = _CachedData(indices, DateTime.now());
      return indices;
    } catch (e) {
      throw _handleError(e);
    }
  }

  
  @override
  void clearCache() => _cache.clear();
  
  /// Checks if cached data for the given key is still valid
  /// 
  /// Returns true if the cache entry exists and is younger than [_cacheDuration]
  bool _isCacheValid(String key) {
    final cached = _cache[key];
    if (cached == null) return false;
    return DateTime.now().difference(cached.timestamp) < _cacheDuration;
  }
  
  /// Handles errors by wrapping them in MarketDataException if needed
  MarketDataException _handleError(dynamic error) {
    if (error is MarketDataException) return error;
    return MarketDataException('Unexpected error', MarketDataErrorType.unknown);
  }
}
