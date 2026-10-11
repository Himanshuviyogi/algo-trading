/// Represents real-time quote data for a stock from Finnhub API
class MarketQuote {
  /// Stock ticker symbol (e.g., "AAPL")
  final String symbol;
  
  /// Current trading price
  final double currentPrice;
  
  /// Price change from previous close
  final double change;
  
  /// Percentage change from previous close
  final double percentChange;
  
  /// Day's high price
  final double high;
  
  /// Day's low price
  final double low;
  
  /// Opening price
  final double open;
  
  /// Previous day's closing price
  final double previousClose;
  
  /// When the quote was fetched
  final DateTime timestamp;
  
  const MarketQuote({
    required this.symbol,
    required this.currentPrice,
    required this.change,
    required this.percentChange,
    required this.high,
    required this.low,
    required this.open,
    required this.previousClose,
    required this.timestamp,
  });
  
  /// Returns true if the price movement is positive (change >= 0)
  bool get isPositive => change >= 0;
  
  /// Creates a MarketQuote from Finnhub API JSON response
  /// 
  /// Finnhub API response format:
  /// {
  ///   "c": 169.59,  // current price
  ///   "d": 2.46,    // change (not used, we calculate it)
  ///   "dp": 1.47,   // percent change (not used, we calculate it)
  ///   "h": 170.33,  // high
  ///   "l": 167.5,   // low
  ///   "o": 167.88,  // open
  ///   "pc": 167.13, // previous close
  ///   "t": 1704999600 // timestamp (not used)
  /// }
  factory MarketQuote.fromJson(Map<String, dynamic> json, String symbol) {
    final current = (json['c'] as num).toDouble();
    final previousClose = (json['pc'] as num).toDouble();
    final change = current - previousClose;
    final percentChange = (change / previousClose) * 100;
    
    return MarketQuote(
      symbol: symbol,
      currentPrice: current,
      change: change,
      percentChange: percentChange,
      high: (json['h'] as num).toDouble(),
      low: (json['l'] as num).toDouble(),
      open: (json['o'] as num).toDouble(),
      previousClose: previousClose,
      timestamp: DateTime.now(),
    );
  }
  
  /// Serializes the MarketQuote to JSON format
  Map<String, dynamic> toJson() => {
    'symbol': symbol,
    'c': currentPrice,
    'h': high,
    'l': low,
    'o': open,
    'pc': previousClose,
  };
  
  /// Creates a MarketQuote from cached JSON data
  /// 
  /// Used when loading data from SharedPreferences cache
  factory MarketQuote.fromCachedJson(Map<String, dynamic> json) {
    final symbol = json['symbol'] as String;
    final current = (json['c'] as num).toDouble();
    final previousClose = (json['pc'] as num).toDouble();
    final change = current - previousClose;
    final percentChange = (change / previousClose) * 100;
    
    return MarketQuote(
      symbol: symbol,
      currentPrice: current,
      change: change,
      percentChange: percentChange,
      high: (json['h'] as num).toDouble(),
      low: (json['l'] as num).toDouble(),
      open: (json['o'] as num).toDouble(),
      previousClose: previousClose,
      timestamp: DateTime.now(),
    );
  }
}
