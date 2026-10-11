/// Which market dataset to use.
/// Switch to [MarketMode.india] once you upgrade to a Finnhub paid plan
/// that supports NSE/BSE symbols.
enum MarketMode { us, india }

/// A single watchlist entry — the API symbol plus a human-readable display name.
class WatchlistEntry {
  /// Symbol sent to the Finnhub API (e.g. "AAPL" or "NSE:RELIANCE")
  final String apiSymbol;

  /// Short label shown in the strip and market cards (e.g. "Apple" or "Reliance")
  final String displayName;

  const WatchlistEntry(this.apiSymbol, this.displayName);
}

/// Configuration for Finnhub API integration.
class FinnhubConfig {
  // ── API credentials ──────────────────────────────────────────────────────

  /// Finnhub API key.  Replace with your key from https://finnhub.io
  static const String apiKey = 'd7flf69r01qpjqql8o30d7flf69r01qpjqql8o3g';

  /// Base URL for Finnhub REST endpoints.
  static const String baseUrl = 'https://finnhub.io/api/v1';

  // ── Market mode ──────────────────────────────────────────────────────────

  // TODO(future): Replace AnimatedMarketStrip (home dashboard) with live
  // Indian stock prices from the Railway price server (Socket.IO) instead
  // of Finnhub US data. Steps:
  //   1. Switch AnimatedMarketStrip to use LivePriceCubit instead of MarketDataCubit
  //   2. Subscribe to NIFTY, BANKNIFTY, RELIANCE, TCS, INFY etc. from the price server
  //   3. Remove Finnhub dependency from the strip entirely
  //   4. Update FinnhubConfig watchlist to Indian symbols or remove it

  /// Active market mode.
  ///
  /// • [MarketMode.us]    — free-tier Finnhub, US symbols (default)
  /// • [MarketMode.india] — paid-tier Finnhub, NSE/BSE symbols
  ///
  /// To switch to Indian stocks:
  ///   1. Upgrade your Finnhub plan.
  ///   2. Change this line to `MarketMode.india`.
  ///   3. Hot-restart the app — no other changes needed.
  static const MarketMode mode = MarketMode.us;

  // ── Curated watchlists ───────────────────────────────────────────────────

  /// 12 well-known US symbols for the free Finnhub tier.
  static const List<WatchlistEntry> _usWatchlist = [
    // Index ETFs
    WatchlistEntry('SPY',  'S&P 500'),
    WatchlistEntry('QQQ',  'NASDAQ'),
    WatchlistEntry('DIA',  'Dow Jones'),
    WatchlistEntry('IWM',  'Russell 2K'),
    // Blue-chip tech
    WatchlistEntry('AAPL', 'Apple'),
    WatchlistEntry('MSFT', 'Microsoft'),
    WatchlistEntry('GOOGL','Alphabet'),
    WatchlistEntry('AMZN', 'Amazon'),
    // High-interest
    WatchlistEntry('TSLA', 'Tesla'),
    WatchlistEntry('NVDA', 'NVIDIA'),
    WatchlistEntry('META', 'Meta'),
    WatchlistEntry('NFLX', 'Netflix'),
  ];

  /// 12 well-known Indian symbols for the Finnhub paid tier (NSE/BSE prefix).
  static const List<WatchlistEntry> _indiaWatchlist = [
    // Large-cap NSE
    WatchlistEntry('NSE:RELIANCE',   'Reliance'),
    WatchlistEntry('NSE:TCS',        'TCS'),
    WatchlistEntry('NSE:HDFCBANK',   'HDFC Bank'),
    WatchlistEntry('NSE:INFY',       'Infosys'),
    WatchlistEntry('NSE:ICICIBANK',  'ICICI Bank'),
    WatchlistEntry('NSE:SBIN',       'SBI'),
    WatchlistEntry('NSE:BAJFINANCE', 'Bajaj Finance'),
    WatchlistEntry('NSE:WIPRO',      'Wipro'),
    WatchlistEntry('NSE:TATAMOTORS', 'Tata Motors'),
    WatchlistEntry('NSE:AXISBANK',   'Axis Bank'),
    // Indices via ETFs / BSE
    WatchlistEntry('BSE:SENSEX',     'Sensex'),
    WatchlistEntry('NSE:NIFTY50',    'Nifty 50'),
  ];

  /// Returns the active watchlist based on [mode].
  static List<WatchlistEntry> get watchlist =>
      mode == MarketMode.india ? _indiaWatchlist : _usWatchlist;

  /// Convenience: just the API symbols from the active watchlist.
  static List<String> get watchlistSymbols =>
      watchlist.map((e) => e.apiSymbol).toList();

  /// Look up the display name for an API symbol.
  /// Falls back to the raw symbol if not found.
  static String displayName(String apiSymbol) {
    return watchlist
        .firstWhere(
          (e) => e.apiSymbol == apiSymbol,
          orElse: () => WatchlistEntry(apiSymbol, apiSymbol),
        )
        .displayName;
  }

  // ── Validation ───────────────────────────────────────────────────────────

  static void validate() {
    if (apiKey.isEmpty || apiKey == 'YOUR_FINNHUB_API_KEY') {
      throw ConfigurationException(
        'Finnhub API key not configured. '
        'Set a valid key in lib/config/finnhub_config.dart',
      );
    }
  }
}

/// Thrown when Finnhub configuration is invalid.
class ConfigurationException implements Exception {
  final String message;
  ConfigurationException(this.message);

  @override
  String toString() => 'ConfigurationException: $message';
}
