import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:equatable/equatable.dart';

/// Status values that mirror the price-server / Firestore lifecycle.
/// pending → open → complete | rejected | cancelled
enum OrderStatus { pending, open, complete, rejected, cancelled, unknown }

extension OrderStatusX on OrderStatus {
  String get value => switch (this) {
        OrderStatus.pending   => 'pending',
        OrderStatus.open      => 'open',
        OrderStatus.complete  => 'complete',
        OrderStatus.rejected  => 'rejected',
        OrderStatus.cancelled => 'cancelled',
        OrderStatus.unknown   => 'unknown',
      };

  bool get isActive   => this == OrderStatus.pending || this == OrderStatus.open;
  bool get isTerminal =>
      this == OrderStatus.complete ||
      this == OrderStatus.rejected ||
      this == OrderStatus.cancelled;
}

OrderStatus _parseStatus(String? raw) => switch (raw?.toLowerCase()) {
      'pending'   => OrderStatus.pending,
      'open'      => OrderStatus.open,
      'complete'  => OrderStatus.complete,
      'rejected'  => OrderStatus.rejected,
      'cancelled' => OrderStatus.cancelled,
      _           => OrderStatus.unknown,
    };

class AlgoOrder extends Equatable {
  const AlgoOrder({
    required this.id,
    required this.signalId,
    required this.userId,
    required this.symbol,
    required this.exchange,
    required this.action,
    required this.orderType,
    required this.quantity,
    required this.price,
    this.triggerPrice,
    this.angelOrderId,
    required this.status,
    this.rejectionReason,
    required this.placedAt,
    required this.updatedAt,
    this.paperTrade = false,
  });

  final String id;
  final String signalId;
  final String userId;
  final String symbol;
  final String exchange;

  /// "BUY" or "SELL"
  final String action;

  /// "LIMIT" | "MARKET" | "SL" | "SL-M"
  final String orderType;

  final int quantity;
  final double price;

  /// Only set for SL / SL-M orders.
  final double? triggerPrice;

  /// Populated once Angel One accepts the order.
  final String? angelOrderId;

  final OrderStatus status;
  final String? rejectionReason;

  final DateTime placedAt;
  final DateTime updatedAt;

  /// True when this was a simulated paper trade — no real money moved.
  final bool paperTrade;

  // ── Convenience getters ────────────────────────────────────────────────────

  bool get isBuy      => action.toUpperCase() == 'BUY';
  bool get isSell     => action.toUpperCase() == 'SELL';
  bool get isActive   => status.isActive;
  bool get isTerminal => status.isTerminal;
  bool get isFilled   => status == OrderStatus.complete;

  // ── fromFirestore ──────────────────────────────────────────────────────────

  factory AlgoOrder.fromFirestore(DocumentSnapshot doc) {
    final d = doc.data() as Map<String, dynamic>;
    return AlgoOrder(
      id:              doc.id,
      signalId:        d['signal_id']        as String? ?? '',
      userId:          d['user_id']          as String? ?? '',
      symbol:          d['symbol']           as String? ?? '',
      exchange:        d['exchange']         as String? ?? '',
      action:          d['action']           as String? ?? '',
      orderType:       d['order_type']       as String? ?? '',
      quantity:        (d['quantity']        as num?)?.toInt()    ?? 0,
      price:           (d['price']           as num?)?.toDouble() ?? 0.0,
      triggerPrice:    (d['trigger_price']   as num?)?.toDouble(),
      angelOrderId:    d['angel_order_id']   as String?,
      status:          _parseStatus(d['status'] as String?),
      rejectionReason: d['rejection_reason'] as String?,
      paperTrade:      d['paper_trade']      as bool? ?? false,
      placedAt:        d['placed_at'] is Timestamp
          ? (d['placed_at'] as Timestamp).toDate()
          : DateTime.now(),
      updatedAt:       d['updated_at'] is Timestamp
          ? (d['updated_at'] as Timestamp).toDate()
          : DateTime.now(),
    );
  }

  // ── toFirestore ────────────────────────────────────────────────────────────

  Map<String, dynamic> toFirestore() => {
        'signal_id':        signalId,
        'user_id':          userId,
        'symbol':           symbol,
        'exchange':         exchange,
        'action':           action,
        'order_type':       orderType,
        'quantity':         quantity,
        'price':            price,
        'trigger_price':    triggerPrice,
        'angel_order_id':   angelOrderId,
        'status':           status.value,
        'rejection_reason': rejectionReason,
        'paper_trade':      paperTrade,
        'placed_at':        Timestamp.fromDate(placedAt),
        'updated_at':       Timestamp.fromDate(updatedAt),
      };

  // ── copyWith ───────────────────────────────────────────────────────────────

  AlgoOrder copyWith({
    String?       id,
    String?       signalId,
    String?       userId,
    String?       symbol,
    String?       exchange,
    String?       action,
    String?       orderType,
    int?          quantity,
    double?       price,
    double?       triggerPrice,
    String?       angelOrderId,
    OrderStatus?  status,
    String?       rejectionReason,
    DateTime?     placedAt,
    DateTime?     updatedAt,
    bool?         paperTrade,
  }) =>
      AlgoOrder(
        id:              id              ?? this.id,
        signalId:        signalId        ?? this.signalId,
        userId:          userId          ?? this.userId,
        symbol:          symbol          ?? this.symbol,
        exchange:        exchange        ?? this.exchange,
        action:          action          ?? this.action,
        orderType:       orderType       ?? this.orderType,
        quantity:        quantity        ?? this.quantity,
        price:           price           ?? this.price,
        triggerPrice:    triggerPrice    ?? this.triggerPrice,
        angelOrderId:    angelOrderId    ?? this.angelOrderId,
        status:          status          ?? this.status,
        rejectionReason: rejectionReason ?? this.rejectionReason,
        placedAt:        placedAt        ?? this.placedAt,
        updatedAt:       updatedAt       ?? this.updatedAt,
        paperTrade:      paperTrade      ?? this.paperTrade,
      );

  @override
  List<Object?> get props => [
        id, signalId, userId, symbol, exchange,
        action, orderType, quantity, price, triggerPrice,
        angelOrderId, status, rejectionReason, placedAt, updatedAt,
        paperTrade,
      ];
}
