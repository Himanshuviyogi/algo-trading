import 'dart:async';
import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../services/live_price_service.dart';

// ── State ─────────────────────────────────────────────────────────────────────

class LivePriceState extends Equatable {
  /// symbol → latest PriceTick
  final Map<String, PriceTick> prices;
  final bool isConnected;
  final bool isMarketClosed;

  const LivePriceState({
    this.prices = const {},
    this.isConnected = false,
    this.isMarketClosed = false,
  });

  LivePriceState copyWith({
    Map<String, PriceTick>? prices,
    bool? isConnected,
    bool? isMarketClosed,
  }) =>
      LivePriceState(
        prices:         prices         ?? this.prices,
        isConnected:    isConnected    ?? this.isConnected,
        isMarketClosed: isMarketClosed ?? this.isMarketClosed,
      );

  /// Convenience: get LTP for a symbol, or null if not yet received.
  double? ltp(String symbol) => prices[symbol]?.ltp;

  @override
  List<Object?> get props => [prices, isConnected, isMarketClosed];
}

// ── Cubit ─────────────────────────────────────────────────────────────────────

/// Cubit that wraps [LivePriceService] and exposes price updates as BLoC state.
///
/// Usage in a widget:
/// ```dart
/// // Subscribe when entering a screen
/// context.read<LivePriceCubit>().subscribe(['RELIANCE', 'TCS']);
///
/// // Read price in BlocBuilder
/// BlocBuilder<LivePriceCubit, LivePriceState>(
///   builder: (context, state) {
///     final ltp = state.ltp('RELIANCE') ?? fallbackPrice;
///     return Text('₹${ltp.toStringAsFixed(2)}');
///   },
/// )
/// ```
class LivePriceCubit extends Cubit<LivePriceState> {
  final LivePriceService _service;
  StreamSubscription<PriceTick>? _sub;
  StreamSubscription<bool>? _marketSub;

  LivePriceCubit({LivePriceService? service})
      : _service = service ?? LivePriceService.instance,
        super(const LivePriceState());

  /// Connect to the price server and start listening.
  Future<void> connect() async {
    // Cancel any existing subscriptions before creating new ones
    await _sub?.cancel();
    await _marketSub?.cancel();
    _sub = null;
    _marketSub = null;

    // Set up stream listeners BEFORE connecting so we don't miss
    // the onConnect snapshot/cached price emissions
    _sub = _service.priceStream.listen((tick) {
      if (isClosed) return;
      final updated = Map<String, PriceTick>.from(state.prices);
      updated[tick.symbol] = tick;
      emit(state.copyWith(
        prices:         updated,
        isConnected:    _service.isConnected,
        isMarketClosed: _service.isMarketClosed,
      ));
    });

    _marketSub = _service.marketStatusStream.listen((closed) {
      if (isClosed) return;
      emit(state.copyWith(isMarketClosed: closed));
    });

    // Now connect — onConnect will fire and emit cached prices into the stream
    await _service.connect();

    emit(state.copyWith(
      isConnected:    _service.isConnected,
      isMarketClosed: _service.isMarketClosed,
    ));
  }

  /// Subscribe to live prices for the given symbols.
  void subscribe(List<String> symbols) {
    _service.subscribe(symbols);
  }

  /// Unsubscribe from live prices for the given symbols.
  void unsubscribe(List<String> symbols) {
    _service.unsubscribe(symbols);
  }

  /// Disconnect the socket (on logout). Does not close the cubit.
  void disconnect() {
    _sub?.cancel();
    _marketSub?.cancel();
    _sub = null;
    _marketSub = null;
    _service.fullDisconnect();
    emit(state.copyWith(isConnected: false));
  }

  /// Get the latest price tick for a symbol (from cache, no stream needed).
  PriceTick? getPrice(String symbol) => _service.getPrice(symbol);

  @override
  Future<void> close() {
    _sub?.cancel();
    _marketSub?.cancel();
    return super.close();
  }
}
