import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/models.dart';

abstract class PlanRepository {
  Future<List<SubscriptionPlan>> getPlans({bool forceRefresh = false});
}

class PlanRepositoryImpl implements PlanRepository {
  PlanRepositoryImpl({required FirebaseFirestore firestore})
      : _firestore = firestore;

  final FirebaseFirestore _firestore;

  // ── In-memory cache ───────────────────────────────────────────────────────
  // Plans change very infrequently (admin edits only), so we fetch once and
  // cache for the app session. This replaces the persistent snapshots() stream
  // which charged a Firestore read on every app open plus on every change.
  //
  // Cache TTL: 10 minutes. After TTL the next call fetches fresh data.
  static const Duration _cacheTtl = Duration(minutes: 10);
  List<SubscriptionPlan>? _cachedPlans;
  DateTime? _cacheTimestamp;

  @override
  Future<List<SubscriptionPlan>> getPlans({bool forceRefresh = false}) async {
    final now = DateTime.now();
    final isFresh = _cachedPlans != null &&
        _cacheTimestamp != null &&
        now.difference(_cacheTimestamp!) < _cacheTtl;

    if (!forceRefresh && isFresh) {
      return _cachedPlans!;
    }

    final snapshot = await _firestore.collection('subscription_plans').get();
    _cachedPlans   = snapshot.docs.map(SubscriptionPlan.fromFirestore).toList();
    _cacheTimestamp = now;
    return _cachedPlans!;
  }

  /// Invalidate the local cache. Call after the admin creates or edits a plan.
  void invalidateCache() {
    _cachedPlans    = null;
    _cacheTimestamp = null;
  }
}
