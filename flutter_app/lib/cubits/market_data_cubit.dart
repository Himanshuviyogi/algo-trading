import 'dart:convert';

import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../config/finnhub_config.dart';
import '../models/market_quote.dart';
import '../repositories/market_data_repository.dart';

// MarketIndex is no longer used internally but kept exported so existing
// screens that import it don't break.
import '../models/market_index.dart';
export '../models/market_index.dart';

part 'market_data_state.dart';

class MarketDataCubit extends Cubit<MarketDataState> {
  final MarketDataRepository _repository;
  SharedPreferences? _prefs;

  static const _cacheKey = 'watchlist_quotes';
  static const _cacheTimeKey = 'watchlist_quotes_ts';
  static const _cacheTtl = Duration(minutes: 5);

  MarketDataCubit({required MarketDataRepository repository})
      : _repository = repository,
        super(const MarketDataInitial()) {
    _initPrefs();
  }

  Future<void> _initPrefs() async {
    _prefs = await SharedPreferences.getInstance();
  }

  // ── Public API ─────────────────────────────────────────────────────────────

  /// Load (or refresh) the active watchlist.
  /// Shows cached data immediately while fetching fresh quotes in the background.
  Future<void> loadMarketData() async {
    if (state is MarketDataLoading) return;
    if (isClosed) return;

    // Try to serve cached data first so the UI isn't blank.
    final cached = await _loadCache();
    if (cached != null) {
      if (!isClosed) {
        emit(MarketDataLoaded(
          quotes: cached,
          loadedAt: _cacheTime() ?? DateTime.now(),
          isRefreshing: true,
        ));
      }
    } else {
      if (!isClosed) emit(const MarketDataLoading());
    }

    await _fetchWatchlist();
  }

  /// Force-refresh: clears the in-memory cache then reloads.
  Future<void> refresh() async {
    _repository.clearCache();
    if (state is MarketDataLoaded) {
      // Keep showing current data while refreshing.
      emit((state as MarketDataLoaded).copyWith(isRefreshing: true));
    }
    await _fetchWatchlist();
  }

  /// Fetch a single quote (used by the chart screen).
  Future<MarketQuote?> getQuote(String symbol) async {
    try {
      return await _repository.getQuote(symbol);
    } catch (e) {
      return null;
    }
  }

  // ── Internal ───────────────────────────────────────────────────────────────

  Future<void> _fetchWatchlist() async {
    try {
      final symbols = FinnhubConfig.watchlistSymbols;
      final quotes = await _repository.getMultipleQuotes(symbols);

      if (isClosed) return;

      await _saveCache(quotes);

      emit(MarketDataLoaded(
        quotes: quotes,
        loadedAt: DateTime.now(),
        isRefreshing: false,
      ));
    } catch (e) {
      if (isClosed) return;

      // If we already have data, keep it and just stop the refresh spinner.
      if (state is MarketDataLoaded) {
        emit((state as MarketDataLoaded).copyWith(isRefreshing: false));
        return;
      }

      final errorType = e is MarketDataException
          ? e.type
          : MarketDataErrorType.unknown;

      emit(MarketDataError(
        message: e.toString(),
        errorType: errorType,
      ));
    }
  }

  // ── Cache helpers ──────────────────────────────────────────────────────────

  Future<List<MarketQuote>?> _loadCache() async {
    if (_prefs == null) return null;
    try {
      final ts = _prefs!.getInt(_cacheTimeKey);
      if (ts == null) return null;
      final age = DateTime.now().millisecondsSinceEpoch - ts;
      if (age > _cacheTtl.inMilliseconds) return null;

      final raw = _prefs!.getString(_cacheKey);
      if (raw == null) return null;

      return (jsonDecode(raw) as List)
          .map((e) => MarketQuote.fromCachedJson(e as Map<String, dynamic>))
          .toList();
    } catch (_) {
      return null;
    }
  }

  Future<void> _saveCache(List<MarketQuote> quotes) async {
    if (_prefs == null) return;
    try {
      await _prefs!.setString(
        _cacheKey,
        jsonEncode(quotes.map((q) => q.toJson()).toList()),
      );
      await _prefs!.setInt(
        _cacheTimeKey,
        DateTime.now().millisecondsSinceEpoch,
      );
    } catch (_) {}
  }

  DateTime? _cacheTime() {
    final ts = _prefs?.getInt(_cacheTimeKey);
    if (ts == null) return null;
    return DateTime.fromMillisecondsSinceEpoch(ts);
  }
}
