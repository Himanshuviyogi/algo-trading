import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/models.dart';

abstract class RecommendationRepository {
  /// Paginated fetch for the feed.
  Future<List<Recommendation>> getFeed({
    required List<String> planIds,
    required String status,       // 'live' | 'closed'
    String? category,             // single category filter
    List<String>? categories,     // multi-category filter (e.g. F&O = ['futures','options'])
    String? type,                 // null = all
    String? searchQuery,
    DocumentSnapshot? lastDoc,
    int pageSize = 20,
  });

  /// Closed calls are visible to everyone (no plan filter).
  Future<List<Recommendation>> getClosedCalls({
    String? category,
    List<String>? categories,
    String? type,
    String? searchQuery,
    DocumentSnapshot? lastDoc,
    int pageSize = 20,
  });

  Future<Recommendation> getById(String id);
  Future<DocumentSnapshot> getDocSnapshot(String id);
  
  /// Stream real-time updates for a specific recommendation
  Stream<Recommendation> streamById(String id);

  /// Stream real-time updates for all live recommendations (for feed)
  Stream<List<Recommendation>> streamLiveFeed({
    required List<String> planIds,
    String? category,
    List<String>? categories, // multi-category (e.g. F&O = ['futures','options'])
    String? type,
  });
}

class RecommendationRepositoryImpl implements RecommendationRepository {
  RecommendationRepositoryImpl({required FirebaseFirestore firestore})
      : _firestore = firestore;

  final FirebaseFirestore _firestore;

  @override
  Future<List<Recommendation>> getFeed({
    required List<String> planIds,
    required String status,
    String? category,
    List<String>? categories,
    String? type,
    String? searchQuery,
    DocumentSnapshot? lastDoc,
    int pageSize = 20,
  }) async {
    // Closed calls are public — delegate to getClosedCalls.
    if (status == 'closed') {
      return getClosedCalls(
        category: category,
        categories: categories,
        type: type,
        searchQuery: searchQuery,
        lastDoc: lastDoc,
        pageSize: pageSize,
      );
    }

    // Always fetch live calls — plan filter applied only when subscribed.
    Query query = _firestore
        .collection('algo_signals')
        .where('is_published', isEqualTo: true)
        .where('status', isEqualTo: 'live');

    if (planIds.isNotEmpty) {
      final ids = planIds.take(30).toList();
      query = query.where('plan_ids', arrayContainsAny: ids);
    }

    // Multi-category (e.g. F&O = futures + options) uses whereIn.
    // Single category uses isEqualTo (avoids a composite index requirement).
    if (categories != null && categories.length > 1) {
      query = query.where('category', whereIn: categories);
    } else if (category != null) {
      query = query.where('category', isEqualTo: category);
    }

    if (type != null) query = query.where('type', isEqualTo: type);

    query = query.orderBy('posted_at', descending: true).limit(pageSize);
    if (lastDoc != null) query = query.startAfterDocument(lastDoc);

    final snap = await query.get();
    final results = snap.docs.map(Recommendation.fromFirestore).toList();

    if (searchQuery != null && searchQuery.isNotEmpty) {
      final q = searchQuery.toLowerCase();
      return results
          .where((r) =>
              r.stock.name.toLowerCase().contains(q) ||
              r.stock.symbol.toLowerCase().contains(q))
          .toList();
    }

    return results;
  }

  @override
  Future<List<Recommendation>> getClosedCalls({
    String? category,
    List<String>? categories,
    String? type,
    String? searchQuery,
    DocumentSnapshot? lastDoc,
    int pageSize = 20,
  }) async {
    Query query = _firestore
        .collection('algo_signals')
        .where('is_published', isEqualTo: true)
        .where('status', whereIn: ['hit_target', 'stoploss_hit', 'closed']);

    if (categories != null && categories.length > 1) {
      query = query.where('category', whereIn: categories);
    } else if (category != null) {
      query = query.where('category', isEqualTo: category);
    }

    if (type != null) query = query.where('type', isEqualTo: type);

    query = query.orderBy('trade.exit_date', descending: true).limit(pageSize);
    if (lastDoc != null) query = query.startAfterDocument(lastDoc);

    final snap = await query.get();
    var results = snap.docs.map(Recommendation.fromFirestore).toList();

    if (searchQuery != null && searchQuery.isNotEmpty) {
      final q = searchQuery.toLowerCase();
      results = results
          .where((r) =>
              r.stock.name.toLowerCase().contains(q) ||
              r.stock.symbol.toLowerCase().contains(q))
          .toList();
    }

    return results;
  }

  @override
  Future<Recommendation> getById(String id) async {
    final doc = await _firestore.collection('algo_signals').doc(id).get();
    return Recommendation.fromFirestore(doc);
  }

  @override
  Future<DocumentSnapshot> getDocSnapshot(String id) =>
      _firestore.collection('algo_signals').doc(id).get();

  @override
  Stream<Recommendation> streamById(String id) {
    return _firestore
        .collection('algo_signals')
        .doc(id)
        .snapshots()
        .map((doc) => Recommendation.fromFirestore(doc));
  }

  /// Stream real-time updates for all live recommendations matching the given plan IDs.
  /// Used by the feed to update target/stoploss/status without a full refresh.
  @override
  Stream<List<Recommendation>> streamLiveFeed({
    required List<String> planIds,
    String? category,
    List<String>? categories, // multi-category (e.g. F&O = ['futures','options'])
    String? type,
  }) {
    Query query = _firestore
        .collection('algo_signals')
        .where('is_published', isEqualTo: true)
        .where('status', isEqualTo: 'live');

    if (planIds.isNotEmpty) {
      final ids = planIds.take(30).toList();
      query = query.where('plan_ids', arrayContainsAny: ids);
    }

    // Mirror the same category logic used in getFeed so the stream
    // only returns items matching the active filter.
    if (categories != null && categories.length > 1) {
      query = query.where('category', whereIn: categories);
    } else if (category != null) {
      query = query.where('category', isEqualTo: category);
    }

    if (type != null) query = query.where('type', isEqualTo: type);

    query = query.orderBy('posted_at', descending: true).limit(50);

    return query.snapshots().map(
          (snap) => snap.docs.map(Recommendation.fromFirestore).toList(),
        );
  }
}
