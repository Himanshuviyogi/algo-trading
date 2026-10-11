import 'market_quote.dart';

/// Represents a market index (e.g., S&P 500, NASDAQ, Dow Jones)
class MarketIndex {
  /// Human-readable index name (e.g., "S&P 500")
  final String name;
  
  /// Index ticker symbol (e.g., "^GSPC")
  final String symbol;
  
  /// Current index value
  final double currentValue;
  
  /// Change from previous close
  final double change;
  
  /// Percentage change from previous close
  final double percentChange;
  
  /// When the index data was fetched
  final DateTime timestamp;
  
  const MarketIndex({
    required this.name,
    required this.symbol,
    required this.currentValue,
    required this.change,
    required this.percentChange,
    required this.timestamp,
  });
  
  /// Returns true if the index movement is positive (change >= 0)
  bool get isPositive => change >= 0;
  
  /// Creates a MarketIndex from a MarketQuote
  /// 
  /// This is used to convert quote data for index symbols into MarketIndex objects
  factory MarketIndex.fromQuote(MarketQuote quote, String name) {
    return MarketIndex(
      name: name,
      symbol: quote.symbol,
      currentValue: quote.currentPrice,
      change: quote.change,
      percentChange: quote.percentChange,
      timestamp: quote.timestamp,
    );
  }
  
  /// Creates a MarketIndex from JSON
  factory MarketIndex.fromJson(Map<String, dynamic> json) {
    return MarketIndex(
      name: json['name'] as String,
      symbol: json['symbol'] as String,
      currentValue: (json['currentValue'] as num).toDouble(),
      change: (json['change'] as num).toDouble(),
      percentChange: (json['percentChange'] as num).toDouble(),
      timestamp: DateTime.now(),
    );
  }
  
  /// Serializes the MarketIndex to JSON format
  Map<String, dynamic> toJson() => {
    'name': name,
    'symbol': symbol,
    'currentValue': currentValue,
    'change': change,
    'percentChange': percentChange,
  };
}
