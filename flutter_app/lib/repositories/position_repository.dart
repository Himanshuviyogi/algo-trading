import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/position.dart';

// ── Abstract interface ────────────────────────────────────────────────────────

abstract class PositionRepository {
  /// Real-time stream of all open positions for [userId].
  /// Emits a new list whenever any position doc changes (P&L sync,
  /// status transitions, etc.).
  Stream<List<AlgoPosition>> getOpenPositions(String userId);

  /// One-shot fetch of closed positions for [userId], ordered by close time
  /// descending. Use [limit] to paginate — default is 20.
  Future<List<AlgoPosition>> getClosedPositions(
    String userId, {
    int limit = 20,
    DocumentSnapshot? lastDoc,
  });
}

// ── Implementation ────────────────────────────────────────────────────────────

class PositionRepositoryImpl implements PositionRepository {
  PositionRepositoryImpl({required FirebaseFirestore firestore})
      : _firestore = firestore;

  final FirebaseFirestore _firestore;

  CollectionReference<Map<String, dynamic>> get _positions =>
      _firestore.collection('positions');

  // ── getOpenPositions ───────────────────────────────────────────────────────

  @override
  Stream<List<AlgoPosition>> getOpenPositions(String userId) {
    return _positions
        .where('user_id', isEqualTo: userId)
        .where('status', isEqualTo: 'open')
        .orderBy('opened_at', descending: true)
        .snapshots()
        .map((snap) => snap.docs.map(AlgoPosition.fromFirestore).toList());
  }

  // ── getClosedPositions ─────────────────────────────────────────────────────

  /// Ordered by [closed_at] descending so the most recently closed positions
  /// appear first. Supports cursor-based pagination via [lastDoc].
  @override
  Future<List<AlgoPosition>> getClosedPositions(
    String userId, {
    int limit = 20,
    DocumentSnapshot? lastDoc,
  }) async {
    Query<Map<String, dynamic>> query = _positions
        .where('user_id', isEqualTo: userId)
        .where('status', isEqualTo: 'closed')
        .orderBy('closed_at', descending: true)
        .limit(limit);

    if (lastDoc != null) {
      query = query.startAfterDocument(lastDoc);
    }

    final snap = await query.get();
    return snap.docs.map(AlgoPosition.fromFirestore).toList();
  }
}
