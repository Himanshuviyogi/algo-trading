import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:equatable/equatable.dart';

/// Position status: open while trade is live, closed once exited.
enum PositionStatus { open, closed, unknown }

extension PositionStatusX on PositionStatus {
  String get value => switch (this) {
        PositionStatus.open    => 'open',
        PositionStatus.closed  => 'closed',
        PositionStatus.unknown => 'unknown',
      };

  bool get isOpen   => this == PositionStatus.open;
  bool get isClosed => this == PositionStatus.closed;
}

PositionStatus _parseStatus(String? raw) => switch (raw?.toLowerCase()) {
      'open'   => PositionStatus.open,
      'closed' => PositionStatus.closed,
      _        => PositionStatus.unknown,
    };

class AlgoPosition extends Equatable {
  const AlgoPosition({
    required this.id,
    required this.userId,
    required this.signalId,
    required this.orderId,
    required this.symbol,
    required this.exchange,
    required this.action,
    required this.quantity,
    required this.avgPrice,
    required this.currentPrice,
    required this.pnl,
    required this.pnlPercent,
    required this.status,
    required this.openedAt,
    this.closedAt,
  });

  final String id;
  final String userId;
  final String signalId;
  final String orderId;
  final String symbol;
  final String exchange;

  /// "BUY" or "SELL" — direction of the original entry order.
  final String action;

  final int quantity;

  /// Average fill price of the entry order.
  final double avgPrice;

  /// Last known LTP — updated in-memory by LivePriceCubit, not persisted.
  final double currentPrice;

  /// Realised P&L when closed; unrealised when open.
  final double pnl;
  final double pnlPercent;

  final PositionStatus status;
  final DateTime openedAt;

  /// Populated when status transitions to closed.
  final DateTime? closedAt;

  // ── Convenience getters ────────────────────────────────────────────────────

  bool get isOpen   => status.isOpen;
  bool get isClosed => status.isClosed;
  bool get isProfit => pnl >= 0;
  bool get isLoss   => pnl < 0;

  // ── fromFirestore ──────────────────────────────────────────────────────────

  factory AlgoPosition.fromFirestore(DocumentSnapshot doc) {
    final d = doc.data() as Map<String, dynamic>;
    return AlgoPosition(
      id:           doc.id,
      userId:       d['user_id']       as String? ?? '',
      signalId:     d['signal_id']     as String? ?? '',
      orderId:      d['order_id']      as String? ?? '',
      symbol:       d['symbol']        as String? ?? '',
      exchange:     d['exchange']      as String? ?? '',
      action:       d['action']        as String? ?? '',
      quantity:     (d['quantity']     as num?)?.toInt()    ?? 0,
      avgPrice:     (d['avg_price']    as num?)?.toDouble() ?? 0.0,
      currentPrice: (d['current_price'] as num?)?.toDouble() ?? 0.0,
      pnl:          (d['pnl']          as num?)?.toDouble() ?? 0.0,
      pnlPercent:   (d['pnl_percent']  as num?)?.toDouble() ?? 0.0,
      status:       _parseStatus(d['status'] as String?),
      openedAt:     d['opened_at'] is Timestamp
          ? (d['opened_at'] as Timestamp).toDate()
          : DateTime.now(),
      closedAt:     d['closed_at'] is Timestamp
          ? (d['closed_at'] as Timestamp).toDate()
          : null,
    );
  }

  // ── toFirestore ────────────────────────────────────────────────────────────

  Map<String, dynamic> toFirestore() => {
        'user_id':       userId,
        'signal_id':     signalId,
        'order_id':      orderId,
        'symbol':        symbol,
        'exchange':      exchange,
        'action':        action,
        'quantity':      quantity,
        'avg_price':     avgPrice,
        'current_price': currentPrice,
        'pnl':           pnl,
        'pnl_percent':   pnlPercent,
        'status':        status.value,
        'opened_at':     Timestamp.fromDate(openedAt),
        'closed_at':     closedAt != null ? Timestamp.fromDate(closedAt!) : null,
      };

  // ── copyWith ───────────────────────────────────────────────────────────────
  // Primary use-case: updating currentPrice / pnl from LivePriceCubit
  // without touching Firestore.

  AlgoPosition copyWith({
    String?         id,
    String?         userId,
    String?         signalId,
    String?         orderId,
    String?         symbol,
    String?         exchange,
    String?         action,
    int?            quantity,
    double?         avgPrice,
    double?         currentPrice,
    double?         pnl,
    double?         pnlPercent,
    PositionStatus? status,
    DateTime?       openedAt,
    DateTime?       closedAt,
  }) =>
      AlgoPosition(
        id:           id           ?? this.id,
        userId:       userId       ?? this.userId,
        signalId:     signalId     ?? this.signalId,
        orderId:      orderId      ?? this.orderId,
        symbol:       symbol       ?? this.symbol,
        exchange:     exchange     ?? this.exchange,
        action:       action       ?? this.action,
        quantity:     quantity     ?? this.quantity,
        avgPrice:     avgPrice     ?? this.avgPrice,
        currentPrice: currentPrice ?? this.currentPrice,
        pnl:          pnl          ?? this.pnl,
        pnlPercent:   pnlPercent   ?? this.pnlPercent,
        status:       status       ?? this.status,
        openedAt:     openedAt     ?? this.openedAt,
        closedAt:     closedAt     ?? this.closedAt,
      );

  @override
  List<Object?> get props => [
        id, userId, signalId, orderId, symbol, exchange,
        action, quantity, avgPrice, currentPrice,
        pnl, pnlPercent, status, openedAt, closedAt,
      ];
}
