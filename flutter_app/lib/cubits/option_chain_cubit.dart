import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../models/option_chain.dart';
import '../repositories/option_chain_repository.dart';

// ── State ─────────────────────────────────────────────────────────────────────

sealed class OptionChainState extends Equatable {
  const OptionChainState();
}

class OptionChainInitial extends OptionChainState {
  const OptionChainInitial();
  @override
  List<Object?> get props => [];
}

class OptionChainLoading extends OptionChainState {
  /// When refreshing we keep the old data visible — only null on first load.
  final OptionChainData? previousData;
  const OptionChainLoading({this.previousData});
  @override
  List<Object?> get props => [previousData];
}

class OptionChainLoaded extends OptionChainState {
  final OptionChainData data;
  /// The expiry the user has currently selected in the UI (may differ from
  /// data.expiry if user just changed the dropdown but fetch hasn't returned yet).
  final String? selectedExpiry;
  const OptionChainLoaded({required this.data, this.selectedExpiry});
  @override
  List<Object?> get props => [data, selectedExpiry];
}

class OptionChainError extends OptionChainState {
  final String message;
  final OptionChainErrorType errorType;
  /// Keep old data so the screen can show a retry overlay rather than a blank page.
  final OptionChainData? previousData;
  const OptionChainError({
    required this.message,
    required this.errorType,
    this.previousData,
  });
  @override
  List<Object?> get props => [message, errorType, previousData];
}

// ── Cubit ─────────────────────────────────────────────────────────────────────

class OptionChainCubit extends Cubit<OptionChainState> {
  OptionChainCubit({required OptionChainRepository repository})
      : _repository = repository,
        super(const OptionChainInitial());

  final OptionChainRepository _repository;

  // ── In-memory cache — 2 minutes per symbol+expiry ─────────────────────────
  // Keyed by "<SYMBOL>__<expiry|latest>".
  // Avoids re-fetching when user pops and reopens the same screen within 2min.

  static const _cacheTtl = Duration(minutes: 2);
  final Map<String, _CacheEntry> _cache = {};

  String _cacheKey(String symbol, String? expiry) =>
      '${symbol.toUpperCase()}__${expiry ?? 'latest'}';

  OptionChainData? _getCached(String symbol, String? expiry) {
    final entry = _cache[_cacheKey(symbol, expiry)];
    if (entry == null) return null;
    if (DateTime.now().difference(entry.fetchedAt) > _cacheTtl) {
      _cache.remove(_cacheKey(symbol, expiry));
      return null;
    }
    return entry.data;
  }

  void _putCache(String symbol, String? expiry, OptionChainData data) {
    _cache[_cacheKey(symbol, expiry)] = _CacheEntry(data, DateTime.now());
  }

  // ── Public API ─────────────────────────────────────────────────────────────

  /// Load option chain for [symbol] / [expiry].
  /// Serves from the 2-min cubit cache first; falls back to network.
  Future<void> load(String symbol, {String? expiry}) async {
    if (isClosed) return;

    final cached = _getCached(symbol, expiry);
    if (cached != null) {
      emit(OptionChainLoaded(data: cached, selectedExpiry: expiry));
      return;
    }

    // Keep old data visible while loading
    final oldData = _previousData();
    emit(OptionChainLoading(previousData: oldData));

    await _fetch(symbol, expiry: expiry);
  }

  /// Force-refresh — bypasses cubit cache (server still has its own 60s cache).
  Future<void> refresh(String symbol, {String? expiry}) async {
    if (isClosed) return;

    _cache.remove(_cacheKey(symbol, expiry));

    final oldData = _previousData();
    if (oldData != null) {
      emit(OptionChainLoading(previousData: oldData));
    } else {
      emit(const OptionChainLoading());
    }

    await _fetch(symbol, expiry: expiry);
  }

  /// Called when user picks a different expiry from the dropdown.
  Future<void> changeExpiry(String symbol, String expiry) async {
    if (isClosed) return;
    await load(symbol, expiry: expiry);
  }

  // ── Internal ───────────────────────────────────────────────────────────────

  Future<void> _fetch(String symbol, {String? expiry}) async {
    try {
      final data = await _repository.fetchChain(symbol, expiry: expiry);
      if (isClosed) return;
      _putCache(symbol, expiry, data);
      emit(OptionChainLoaded(data: data, selectedExpiry: expiry ?? data.expiry));
    } on OptionChainException catch (e) {
      if (isClosed) return;
      emit(OptionChainError(
        message: e.message,
        errorType: e.type,
        previousData: _previousData(),
      ));
    } catch (e) {
      if (isClosed) return;
      emit(OptionChainError(
        message: e.toString(),
        errorType: OptionChainErrorType.unknown,
        previousData: _previousData(),
      ));
    }
  }

  OptionChainData? _previousData() => switch (state) {
        OptionChainLoaded(:final data) => data,
        OptionChainLoading(:final previousData) => previousData,
        OptionChainError(:final previousData) => previousData,
        _ => null,
      };
}

// ── Cache entry helper ────────────────────────────────────────────────────────

class _CacheEntry {
  final OptionChainData data;
  final DateTime fetchedAt;
  const _CacheEntry(this.data, this.fetchedAt);
}
