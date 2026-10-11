import 'dart:async';

import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../models/order.dart';
import '../models/recommendation.dart';
import '../repositories/order_repository.dart';
import '../services/order_service.dart';

part 'order_state.dart';

/// Cubit that manages the lifecycle of a single order action (place / cancel).
///
/// This is intentionally scoped to **one action at a time** — the UI should
/// provide one OrderCubit per signal card or order detail sheet, not a global
/// singleton. Real-time order list updates come from a Firestore stream in
/// [OrderRepository], not from this cubit.
///
/// Usage:
/// ```dart
/// BlocProvider(
///   create: (_) => OrderCubit(
///     orderRepository: context.read<OrderRepository>(),
///     orderService: OrderService.instance,
///     userId: currentUser.uid,
///   ),
///   child: SignalCard(signal: signal),
/// )
/// ```
class OrderCubit extends Cubit<OrderState> {
  OrderCubit({
    required OrderRepository orderRepository,
    required OrderService orderService,
    required String userId,
  })  : _orderRepository = orderRepository,
        _orderService = orderService,
        _userId = userId,
        super(const OrderInitial());

  final OrderRepository _orderRepository;
  final OrderService _orderService;
  final String _userId;

  // ── placeOrder ─────────────────────────────────────────────────────────────

  /// Place an order for [signal] at the given [quantity].
  ///
  /// Derives symbol, exchange, action, orderType and price from the signal so
  /// the call site only needs to supply the user-controlled quantity.
  ///
  /// State transitions:
  ///   OrderInitial → OrderPlacing → OrderPlaced(order)
  ///                              → OrderFailed(message)
  Future<void> placeOrder({
    required Recommendation signal,
    required int quantity,
  }) async {
    if (state is OrderPlacing) return; // guard against double-tap
    emit(const OrderPlacing());

    try {
      final result = await _orderService.placeOrder(
        userId:    _userId,
        signalId:  signal.id,
        symbol:    signal.stock.symbol,
        exchange:  'NSE',                         // equities default to NSE
        action:    signal.trade.action.toUpperCase(),
        orderType: 'LIMIT',
        quantity:  quantity,
        price:     signal.trade.entryPrice,
      );

      // Build a local AlgoOrder to pass to OrderPlaced so the UI can show
      // immediate confirmation without waiting for the Firestore stream.
      final now = DateTime.now();
      final order = AlgoOrder(
        id:           result.firestoreOrderId,
        signalId:     signal.id,
        userId:       _userId,
        symbol:       signal.stock.symbol,
        exchange:     'NSE',
        action:       signal.trade.action.toUpperCase(),
        orderType:    'LIMIT',
        quantity:     quantity,
        price:        signal.trade.entryPrice,
        angelOrderId: result.angelOrderId,
        status:       OrderStatus.pending,
        placedAt:     now,
        updatedAt:    now,
      );

      // Write to Firestore so the order book screen sees it immediately,
      // even before the price-server write propagates through the stream.
      await _orderRepository.createOrder(order);

      emit(OrderPlaced(order));
    } on OrderBlockedException catch (e) {
      // Risk check blocked the order — show the specific reason (e.g.
      // "Daily loss limit ₹5000 breached") so the user understands why.
      emit(OrderFailed(e.reason));
    } on OrderAuthException catch (e) {
      emit(OrderFailed(e.message));
    } on OrderServerException catch (e) {
      emit(OrderFailed(e.message));
    } catch (e) {
      emit(OrderFailed(e.toString()));
    }
  }

  // ── cancelOrder ────────────────────────────────────────────────────────────

  /// Cancel an open order by its Angel One order ID.
  ///
  /// State transitions:
  ///   * → OrderPlacing → OrderInitial  (on success — UI pops the sheet)
  ///                    → OrderFailed   (on error)
  Future<void> cancelOrder(String angelOrderId) async {
    if (state is OrderPlacing) return;
    emit(const OrderPlacing());

    try {
      await _orderService.cancelOrder(
        angelOrderId: angelOrderId,
        userId:       _userId,
      );
      // Return to initial so the UI knows the action completed cleanly.
      // The order list will update via the Firestore stream.
      emit(const OrderInitial());
    } on OrderAuthException catch (e) {
      emit(OrderFailed(e.message));
    } on OrderServerException catch (e) {
      emit(OrderFailed(e.message));
    } catch (e) {
      emit(OrderFailed(e.toString()));
    }
  }

  // ── reset ──────────────────────────────────────────────────────────────────

  /// Reset to [OrderInitial] — call this to clear a previous result before
  /// re-showing the order form (e.g. after dismissing a failure snackbar).
  void reset() => emit(const OrderInitial());
}
