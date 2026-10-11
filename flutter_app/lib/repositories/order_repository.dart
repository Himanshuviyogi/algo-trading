import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/order.dart';

// ── Abstract interface ────────────────────────────────────────────────────────

abstract class OrderRepository {
  /// Real-time stream of all orders for [userId], newest first.
  /// Emits a new list whenever any order doc changes (status updates,
  /// angel_order_id populated, etc.).
  Stream<List<AlgoOrder>> getUserOrders(String userId);

  /// Real-time stream of the single order placed for a given [signalId].
  /// Emits null when no order exists yet for that signal.
  Stream<AlgoOrder?> getOrderForSignal(String userId, String signalId);

  /// Write a new order document to Firestore.
  /// Called locally after the price-server confirms placement so the
  /// Flutter app has an immediate Firestore record before the server-side
  /// write propagates.
  Future<void> createOrder(AlgoOrder order);
}

// ── Implementation ────────────────────────────────────────────────────────────

class OrderRepositoryImpl implements OrderRepository {
  OrderRepositoryImpl({required FirebaseFirestore firestore})
      : _firestore = firestore;

  final FirebaseFirestore _firestore;

  CollectionReference<Map<String, dynamic>> get _orders =>
      _firestore.collection('orders');

  // ── getUserOrders ──────────────────────────────────────────────────────────

  @override
  Stream<List<AlgoOrder>> getUserOrders(String userId) {
    return _orders
        .where('user_id', isEqualTo: userId)
        .orderBy('placed_at', descending: true)
        .snapshots()
        .map((snap) => snap.docs.map(AlgoOrder.fromFirestore).toList());
  }

  // ── getOrderForSignal ──────────────────────────────────────────────────────

  /// Queries for the most recent order matching both userId and signalId.
  /// In practice at most one order exists per user+signal, but the query
  /// uses limit(1) + orderBy to be safe if duplicates appear during retries.
  @override
  Stream<AlgoOrder?> getOrderForSignal(String userId, String signalId) {
    return _orders
        .where('user_id', isEqualTo: userId)
        .where('signal_id', isEqualTo: signalId)
        .orderBy('placed_at', descending: true)
        .limit(1)
        .snapshots()
        .map((snap) =>
            snap.docs.isEmpty ? null : AlgoOrder.fromFirestore(snap.docs.first));
  }

  // ── createOrder ───────────────────────────────────────────────────────────

  /// Uses the order's [AlgoOrder.id] as the document ID when non-empty
  /// (e.g. the Firestore ID returned by the price server), otherwise lets
  /// Firestore auto-generate one.
  @override
  Future<void> createOrder(AlgoOrder order) {
    final data = order.toFirestore();

    if (order.id.isNotEmpty) {
      return _orders.doc(order.id).set(data);
    }
    return _orders.add(data).then((_) {});
  }
}
