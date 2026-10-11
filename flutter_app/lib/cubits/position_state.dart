part of 'position_cubit.dart';

sealed class PositionState extends Equatable {
  const PositionState();
}

/// Waiting for the first Firestore snapshot to arrive.
class PositionLoading extends PositionState {
  const PositionLoading();

  @override
  List<Object?> get props => [];
}

/// Positions are loaded and live P&L is up-to-date.
///
/// [positions] contains the open positions with [AlgoPosition.currentPrice],
/// [AlgoPosition.pnl], and [AlgoPosition.pnlPercent] updated in-memory from
/// the latest price ticks — no Firestore round-trips required.
///
/// [totalPnl] and [totalPnlPercent] are the portfolio-level aggregates,
/// computed as the sum across all open positions.
class PositionLoaded extends PositionState {
  const PositionLoaded({
    required this.positions,
    required this.totalPnl,
    required this.totalPnlPercent,
  });

  final List<AlgoPosition> positions;

  /// Sum of unrealised P&L across all open positions (₹).
  final double totalPnl;

  /// Portfolio-level P&L as a percentage of total cost basis.
  /// 0.0 when there are no open positions.
  final double totalPnlPercent;

  bool get isEmpty     => positions.isEmpty;
  bool get isProfit    => totalPnl >= 0;

  @override
  List<Object?> get props => [positions, totalPnl, totalPnlPercent];
}

/// The Firestore stream or a manual refresh failed.
class PositionError extends PositionState {
  const PositionError(this.message);

  final String message;

  @override
  List<Object?> get props => [message];
}
