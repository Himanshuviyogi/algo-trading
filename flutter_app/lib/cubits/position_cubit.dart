import 'dart:async';

import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../models/position.dart';
import '../repositories/position_repository.dart';
import 'live_price_cubit.dart';

part 'position_state.dart';

/// Cubit that maintains a live view of the user's open positions.
///
/// It merges two data sources without polling:
///   1. **Firestore stream** ([PositionRepository.getOpenPositions]) — provides
///      the base position data (avgPrice, quantity, symbol) and fires whenever
///      a position is opened or closed.
///   2. **Price stream** ([LivePriceCubit]) — provides live LTP ticks so that
///      unrealised P&L updates on every price change without a Firestore read.
///
/// The merge strategy:
///   - When Firestore fires → rebuild _positions list, recompute P&L using the
///     latest prices already held in [LivePriceCubit.state].
///   - When a price tick fires for a symbol we hold → update only the affected
///     position in-memory using [AlgoPosition.copyWith], then recompute totals.
///     No Firestore read, no new stream event.
///
/// Usage:
/// ```dart
/// BlocProvider(
///   create: (context) => PositionCubit(
///     positionRepository: context.read<PositionRepository>(),
///     livePriceCubit: context.read<LivePriceCubit>(),
///     userId: currentUser.uid,
///   )..loadPositions(),
/// )
/// ```
class PositionCubit extends Cubit<PositionState> {
  PositionCubit({
    required PositionRepository positionRepository,
    required LivePriceCubit livePriceCubit,
    required String userId,
  })  : _positionRepository = positionRepository,
        _livePriceCubit = livePriceCubit,
        _userId = userId,
        super(const PositionLoading());

  final PositionRepository _positionRepository;
  final LivePriceCubit _livePriceCubit;
  final String _userId;

  // In-memory position list — updated by both streams.
  List<AlgoPosition> _positions = [];

  StreamSubscription<List<AlgoPosition>>? _positionSub;
  StreamSubscription<LivePriceState>?     _priceSub;

  // ── loadPositions ──────────────────────────────────────────────────────────

  /// Start listening to Firestore and price ticks.
  /// Safe to call multiple times — cancels existing subscriptions first.
  void loadPositions() {
    emit(const PositionLoading());
    _positionSub?.cancel();
    _priceSub?.cancel();

    // ── Stream 1: Firestore open positions ───────────────────────────────────
    _positionSub = _positionRepository
        .getOpenPositions(_userId)
        .listen(
          (firestorePositions) {
            if (isClosed) return;

            // Rehydrate each position with the current live price we already
            // hold in LivePriceCubit, so P&L is immediately correct when the
            // list first arrives — no waiting for the next price tick.
            final prices = _livePriceCubit.state.prices;
            _positions = firestorePositions.map((p) {
              final ltp = prices[p.symbol]?.ltp;
              return ltp != null ? _withLivePrice(p, ltp) : p;
            }).toList();

            // Subscribe to live prices for any symbols not yet tracked.
            final symbols = _positions.map((p) => p.symbol).toSet().toList();
            _livePriceCubit.subscribe(symbols);

            _emitLoaded();
          },
          onError: (Object error) {
            if (isClosed) return;
            emit(PositionError(error.toString()));
          },
        );

    // ── Stream 2: Live price ticks ────────────────────────────────────────────
    // Listen to the full LivePriceState stream. On each tick, check if any of
    // our held symbols changed and update only those positions in-memory.
    // This avoids a full rebuild for every tick when we hold many positions.
    _priceSub = _livePriceCubit.stream.listen(
      (priceState) {
        if (isClosed) return;
        if (_positions.isEmpty) return;

        bool anyUpdated = false;
        final updated = _positions.map((p) {
          final ltp = priceState.prices[p.symbol]?.ltp;
          if (ltp == null || ltp == p.currentPrice) return p;
          anyUpdated = true;
          return _withLivePrice(p, ltp);
        }).toList();

        if (!anyUpdated) return; // nothing changed — skip the emit

        _positions = updated;
        _emitLoaded();
      },
    );
  }

  // ── _withLivePrice ─────────────────────────────────────────────────────────

  /// Returns a new [AlgoPosition] with [currentPrice], [pnl], and [pnlPercent]
  /// recomputed from [ltp]. Does not touch Firestore.
  ///
  /// P&L formula:
  ///   BUY  position: pnl = (ltp − avgPrice) × quantity
  ///   SELL position: pnl = (avgPrice − ltp) × quantity   (short)
  AlgoPosition _withLivePrice(AlgoPosition position, double ltp) {
    final isBuy = position.action.toUpperCase() == 'BUY';
    final pnl = isBuy
        ? (ltp - position.avgPrice) * position.quantity
        : (position.avgPrice - ltp) * position.quantity;

    final costBasis = position.avgPrice * position.quantity;
    final pnlPercent = costBasis > 0 ? (pnl / costBasis) * 100 : 0.0;

    return position.copyWith(
      currentPrice: ltp,
      pnl:          pnl,
      pnlPercent:   pnlPercent,
    );
  }

  // ── _emitLoaded ────────────────────────────────────────────────────────────

  void _emitLoaded() {
    final totalPnl = _positions.fold(0.0, (sum, p) => sum + p.pnl);

    // totalPnlPercent = total P&L / total cost basis
    final totalCostBasis = _positions.fold(
      0.0,
      (sum, p) => sum + (p.avgPrice * p.quantity),
    );
    final totalPnlPercent =
        totalCostBasis > 0 ? (totalPnl / totalCostBasis) * 100 : 0.0;

    emit(PositionLoaded(
      positions:       List.unmodifiable(_positions),
      totalPnl:        totalPnl,
      totalPnlPercent: totalPnlPercent,
    ));
  }

  // ── close ──────────────────────────────────────────────────────────────────

  @override
  Future<void> close() {
    _positionSub?.cancel();
    _priceSub?.cancel();
    return super.close();
  }
}
