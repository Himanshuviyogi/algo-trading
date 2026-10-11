import 'dart:async';
import 'dart:ui';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../blocs/auth_bloc.dart';
import '../cubits/live_price_cubit.dart';
import '../services/live_price_service.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Design tokens — shared "trading terminal on paper" system used across the
// dashboard, market, and detail screens. Warm paper base, one flat ink
// surface for emphasis, hairline borders instead of stacked shadows.
// ─────────────────────────────────────────────────────────────────────────────

abstract final class _UT {
  static const bg       = Color(0xFFFAF9F5);
  static const surface  = Color(0xFFFFFFFF);
  static const surface2 = Color(0xFFF1F0EA);
  static const ink      = Color(0xFF14161D);
  static const divider  = Color(0xFFE7E4DA);

  static const primary  = Color(0xFF3548C7);
  static const signal   = Color(0xFFBFFF3D);

  static const profit   = Color(0xFF0E7C6B);
  static const loss     = Color(0xFFD1483F);
  static const warning  = Color(0xFFBF7A16);
  static const info     = Color(0xFF2C6FB0);

  static const t1 = Color(0xFF14161D);
  static const t2 = Color(0xFF5B5D66);
  static const t3 = Color(0xFF9C9DA6);
  static const onInk1 = Color(0xFFF6F6F3);
  static const onInk2 = Color(0xFF9A9CA8);

  static const r10 = 10.0;
  static const r14 = 14.0;
  static const r18 = 18.0;
  static const r24 = 24.0;

  static TextStyle numeral({
    required double size,
    required FontWeight weight,
    required Color color,
    double letterSpacing = -0.3,
  }) {
    return TextStyle(
      fontSize: size,
      fontWeight: weight,
      color: color,
      letterSpacing: letterSpacing,
      fontFeatures: const [FontFeature.tabularFigures()],
      height: 1.0,
    );
  }

  static BoxDecoration card({Color? borderColor}) => BoxDecoration(
    color: surface,
    borderRadius: BorderRadius.circular(r18),
    border: Border.all(color: borderColor ?? divider, width: 1),
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// Status filter
// ─────────────────────────────────────────────────────────────────────────────

enum _StatusFilter { all, live, dropPending, closed }

extension _StatusFilterLabel on _StatusFilter {
  String get label {
    switch (this) {
      case _StatusFilter.all:         return 'All';
      case _StatusFilter.live:        return 'Live';
      case _StatusFilter.dropPending: return 'Drop';
      case _StatusFilter.closed:      return 'Closed';
    }
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// UserStrategiesScreen
// ─────────────────────────────────────────────────────────────────────────────

class UserStrategiesScreen extends StatefulWidget {
  const UserStrategiesScreen({super.key});

  @override
  State<UserStrategiesScreen> createState() => _UserStrategiesScreenState();
}

class _UserStrategiesScreenState extends State<UserStrategiesScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tab;
  _StatusFilter _filter = _StatusFilter.all;

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 2, vsync: this);
    // Connect live prices when the strategies tab is visible
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) context.read<LivePriceCubit>().connect();
    });
  }

  @override
  void dispose() {
    _tab.dispose();
    super.dispose();
  }

  String get _uid {
    final s = context.read<AuthBloc>().state;
    return s is AuthAuthenticated ? s.uid : '';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _UT.bg,
      appBar: AppBar(
        backgroundColor: _UT.bg,
        elevation: 0,
        scrolledUnderElevation: 0,
        titleSpacing: 16,
        title: Row(
          children: [
            Container(
              height: 36,
              width: 36,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(11),
                color: _UT.ink,
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(11),
                child: Image.asset('assets/images/small_logo.png'),
              ),
            ),
            const SizedBox(width: 10),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Strategies',
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 20,
                    color: _UT.t1,
                    letterSpacing: -0.3,
                  ),
                ),
                const Text(
                  'Admin picks & your plays',
                  style: TextStyle(fontSize: 12, color: _UT.t2),
                ),
              ],
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Algo Settings',
            icon: Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: _UT.surface,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: _UT.divider, width: 1),
              ),
              child: const Icon(Icons.tune_rounded, color: _UT.primary, size: 18),
            ),
            onPressed: () => context.push('/algo-config'),
          ),
          const SizedBox(width: 8),
        ],
        bottom: TabBar(
          controller: _tab,
          labelColor: _UT.t1,
          unselectedLabelColor: _UT.t3,
          indicatorColor: _UT.ink,
          indicatorWeight: 2.5,
          labelStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
          unselectedLabelStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
          tabs: const [
            Tab(text: 'Admin strategies'),
            Tab(text: 'My strategies'),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => context.push('/create-strategy'),
        backgroundColor: _UT.ink,
        foregroundColor: _UT.onInk1,
        elevation: 4,
        icon: const Icon(Icons.add_rounded),
        label: const Text('Create strategy',
            style: TextStyle(fontWeight: FontWeight.w700)),
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
      body: TabBarView(
        controller: _tab,
        children: [
          _AdminStrategiesTab(filter: _filter, onFilterChanged: (f) => setState(() => _filter = f)),
          _MyStrategiesTab(uid: _uid, filter: _filter, onFilterChanged: (f) => setState(() => _filter = f)),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Performance summary header — flat ink surface, tabular figures, mirrors
// the dashboard's P&L hero instead of the old violet gradient card.
// ─────────────────────────────────────────────────────────────────────────────

class _PerformanceHeader extends StatelessWidget {
  const _PerformanceHeader({required this.docs});

  final List<QueryDocumentSnapshot> docs;

  @override
  Widget build(BuildContext context) {
    int live = 0, dropPending = 0, closed = 0;
    int profitable = 0;

    for (final doc in docs) {
      final d      = doc.data() as Map<String, dynamic>;
      final status = d['status'] as String? ?? 'live';

      if (status == 'watching') {
        dropPending++;
      } else if (status == 'in_position') {
        live++;
      } else if (status == 'live') {
        live++;
      } else if (status == 'closed' ||
          status == 'target_hit' ||
          status == 'sl_hit' ||
          status == 'hit_target' ||
          status == 'stoploss_hit') {
        closed++;
        final perf = d['performance'] as Map? ?? {};
        final gain = (perf['gain_so_far'] as num?)?.toDouble() ?? 0;
        if (gain > 0) profitable++;
      }
    }

    final winRate = closed > 0 ? (profitable / closed * 100) : null;

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      decoration: BoxDecoration(
        color: _UT.ink,
        borderRadius: BorderRadius.circular(_UT.r18),
      ),
      child: Row(
        children: [
          _HeaderStat(label: 'Live', value: '$live', icon: Icons.bolt_rounded, color: _UT.onInk1),
          _HeaderDivider(),
          _HeaderStat(label: 'Drop pending', value: '$dropPending', icon: Icons.timer_outlined, color: _UT.onInk1),
          _HeaderDivider(),
          _HeaderStat(label: 'Closed', value: '$closed', icon: Icons.check_circle_outline_rounded, color: _UT.onInk1),
          if (winRate != null) ...[
            _HeaderDivider(),
            _HeaderStat(
              label: 'Win rate',
              value: '${winRate.toStringAsFixed(0)}%',
              icon: Icons.emoji_events_outlined,
              color: _UT.signal,
            ),
          ],
        ],
      ),
    );
  }
}

class _HeaderStat extends StatelessWidget {
  const _HeaderStat({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
  });
  final String label;
  final String value;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        children: [
          Icon(icon, size: 15, color: color.withValues(alpha: 0.85)),
          const SizedBox(height: 5),
          Text(value, style: _UT.numeral(size: 17, weight: FontWeight.w800, color: color)),
          const SizedBox(height: 1),
          Text(label,
              style: TextStyle(
                  fontSize: 9.5,
                  fontWeight: FontWeight.w600,
                  color: color == _UT.signal ? _UT.signal.withValues(alpha: 0.75) : _UT.onInk2)),
        ],
      ),
    );
  }
}

class _HeaderDivider extends StatelessWidget {
  @override
  Widget build(BuildContext context) =>
      Container(width: 1, height: 34, color: Colors.white.withValues(alpha: 0.10));
}

// ─────────────────────────────────────────────────────────────────────────────
// Status filter chips row
// ─────────────────────────────────────────────────────────────────────────────

class _FilterRow extends StatelessWidget {
  const _FilterRow({required this.current, required this.onChanged});

  final _StatusFilter current;
  final ValueChanged<_StatusFilter> onChanged;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 36,
      child: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        scrollDirection: Axis.horizontal,
        children: _StatusFilter.values.map((f) {
          final selected = f == current;
          return GestureDetector(
            onTap: () => onChanged(f),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 160),
              margin: const EdgeInsets.only(right: 8),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
              decoration: BoxDecoration(
                color: selected ? _UT.ink : _UT.surface,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: selected ? _UT.ink : _UT.divider),
              ),
              alignment: Alignment.center,
              child: Text(
                f.label,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: selected ? _UT.onInk1 : _UT.t2,
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Admin strategies tab
// ─────────────────────────────────────────────────────────────────────────────

class _AdminStrategiesTab extends StatelessWidget {
  const _AdminStrategiesTab(
      {required this.filter, required this.onFilterChanged});

  final _StatusFilter filter;
  final ValueChanged<_StatusFilter> onFilterChanged;

  @override
  Widget build(BuildContext context) {
    final query = FirebaseFirestore.instance
        .collection('algo_signals')
        .where('is_published', isEqualTo: true)
        .where('source', isEqualTo: 'admin')
        .where('status', isEqualTo: 'live')
        .orderBy('posted_at', descending: true)
        .limit(30);

    return StreamBuilder<QuerySnapshot>(
      stream: query.snapshots(),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator(color: _UT.primary));
        }
        if (snap.hasError) {
          return const _EmptyState(
            icon: Icons.cloud_off_rounded,
            title: 'Could not load strategies',
            subtitle:
            'A Firestore index may be missing. Check the debug console.',
          );
        }
        final docs = (snap.data?.docs ?? []).cast<QueryDocumentSnapshot>();
        if (docs.isEmpty) {
          return const _EmptyState(
            icon: Icons.business_center_outlined,
            title: 'No admin strategies yet',
            subtitle: 'Published strategies will appear here.',
          );
        }

        // Subscribe live prices for all symbols
        final symbols = docs
            .map((d) {
          final m = d.data() as Map<String, dynamic>;
          return (m['stock'] as Map?)?['symbol'] as String? ?? '';
        })
            .where((s) => s.isNotEmpty)
            .toSet()
            .toList();
        context.read<LivePriceCubit>().subscribe(symbols);

        final filtered = _applyFilter(docs, filter);

        return Column(
          children: [
            const SizedBox(height: 8),
            _FilterRow(current: filter, onChanged: onFilterChanged),
            const SizedBox(height: 8),
            Expanded(
              child: filtered.isEmpty
                  ? const _EmptyState(
                icon: Icons.filter_list_rounded,
                title: 'No strategies match',
                subtitle: 'Try a different filter.',
              )
                  : ListView.separated(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
                itemCount: filtered.length,
                separatorBuilder: (_, __) => const SizedBox(height: 10),
                itemBuilder: (_, i) {
                  final d = filtered[i].data() as Map<String, dynamic>;
                  return _StrategyCard.fromFirestore(
                      d, filtered[i].id,
                      isOwn: false);
                },
              ),
            ),
          ],
        );
      },
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// My strategies tab
// ─────────────────────────────────────────────────────────────────────────────

class _MyStrategiesTab extends StatelessWidget {
  const _MyStrategiesTab(
      {required this.uid,
        required this.filter,
        required this.onFilterChanged});

  final String uid;
  final _StatusFilter filter;
  final ValueChanged<_StatusFilter> onFilterChanged;

  @override
  Widget build(BuildContext context) {
    if (uid.isEmpty) {
      return const _EmptyState(
        icon: Icons.lock_outline_rounded,
        title: 'Not logged in',
        subtitle: 'Sign in to see your strategies.',
      );
    }

    final query = FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .collection('strategies')
        .orderBy('created_at', descending: true);

    return StreamBuilder<QuerySnapshot>(
      stream: query.snapshots(),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator(color: _UT.primary));
        }

        final docs = (snap.data?.docs ?? []).cast<QueryDocumentSnapshot>();

        if (docs.isEmpty) {
          return _EmptyState(
            icon: Icons.edit_note_rounded,
            title: 'No strategies yet',
            subtitle: 'Tap "Create strategy" below to build your first one.',
            cta: 'Create strategy',
            onCta: () => context.push('/create-strategy'),
          );
        }

        // Subscribe live prices
        final symbols = docs
            .map((d) {
          final m = d.data() as Map<String, dynamic>;
          return (m['stock'] as Map?)?['symbol'] as String? ?? '';
        })
            .where((s) => s.isNotEmpty)
            .toSet()
            .toList();
        context.read<LivePriceCubit>().subscribe(symbols);

        final filtered = _applyFilter(docs, filter);

        return Column(
          children: [
            _PerformanceHeader(docs: docs),
            const SizedBox(height: 10),
            // "New Strategy" shortcut — always visible when list has items
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('My Strategies',
                      style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: _UT.t1)),
                  GestureDetector(
                    onTap: () => context.push('/create-strategy'),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                      decoration: BoxDecoration(
                        color: _UT.ink,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.add_rounded, color: Colors.white, size: 16),
                          const SizedBox(width: 4),
                          Text('New Strategy',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                                color: _UT.onInk1,
                              )),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),
            _FilterRow(current: filter, onChanged: onFilterChanged),
            const SizedBox(height: 4),
            Expanded(
              child: filtered.isEmpty
                  ? const _EmptyState(
                icon: Icons.filter_list_rounded,
                title: 'No strategies match',
                subtitle: 'Try a different filter.',
              )
                  : ListView.separated(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
                itemCount: filtered.length,
                separatorBuilder: (_, __) => const SizedBox(height: 10),
                itemBuilder: (_, i) {
                  final d = filtered[i].data() as Map<String, dynamic>;
                  return _StrategyCard.fromFirestore(
                    d, filtered[i].id,
                    isOwn: true,
                    uid: uid,
                  );
                },
              ),
            ),
          ],
        );
      },
    );
  }
}

// Apply status filter to docs list
List<QueryDocumentSnapshot> _applyFilter(
    List<QueryDocumentSnapshot> docs, _StatusFilter filter) {
  if (filter == _StatusFilter.all) return docs;
  return docs.where((doc) {
    final d      = doc.data() as Map<String, dynamic>;
    final status = d['status'] as String? ?? 'live';
    switch (filter) {
      case _StatusFilter.live:
        return status == 'live' || status == 'in_position';
      case _StatusFilter.dropPending:
        return status == 'watching';
      case _StatusFilter.closed:
        return status == 'closed' ||
            status == 'target_hit' ||
            status == 'sl_hit' ||
            status == 'hit_target' ||    // legacy
            status == 'stoploss_hit';    // legacy
      case _StatusFilter.all:
        return true;
    }
  }).toList();
}

// ─────────────────────────────────────────────────────────────────────────────
// Strategy card — enhanced with live P&L, price progress bar, status chip
// ─────────────────────────────────────────────────────────────────────────────

class _StrategyCard extends StatelessWidget {
  const _StrategyCard({
    required this.docId,
    required this.label,
    required this.symbol,
    required this.category,
    required this.type,
    required this.action,
    required this.entry,
    required this.target,
    required this.sl,
    required this.duration,
    required this.badge,
    required this.status,
    required this.isOwn,
    required this.dropEnabled,
    required this.isPublished,
    required this.confidence,
    required this.tags,
    required this.quantity,
    this.uid,
    this.description = '',
    // New fields
    this.target2 = 0,
    this.orderType = 'LIMIT',
    this.execMode = 'immediate',
    this.trailingSL = false,
    this.trailingSLMode = 'points',
    this.trailingSLValue = 0,
    this.autoExecute = false,
    this.sizeMode = 'qty',
    this.bracketOrder = false,
    this.rawData = const {},
    this.paperTrade = false,
    // Product type / validity / valid-till
    this.productType = 'CNC',
    this.validity    = 'DAY',
    this.validTill,
  });

  final String docId;
  final String label;
  final String symbol;
  final String category;
  final String type;
  final String action;
  final double entry;
  final double target;
  final double sl;
  final String duration;
  final String badge;
  final String status;
  final bool isOwn;
  final bool dropEnabled;
  final bool isPublished;
  final String confidence;
  final List<String> tags;
  final int quantity;
  final String? uid;
  final String description;
  // New fields
  final double target2;
  final String orderType;
  final String execMode;
  final bool trailingSL;
  final String trailingSLMode;
  final double trailingSLValue;
  final bool autoExecute;
  final String sizeMode;
  final bool bracketOrder;
  final Map<String, dynamic> rawData; // full doc for edit pre-fill
  final bool paperTrade;
  // Product type / validity / valid-till
  final String productType;
  final String validity;
  final DateTime? validTill;

  factory _StrategyCard.fromFirestore(
      Map<String, dynamic> d, String docId,
      {required bool isOwn, String? uid}) {
    final stock    = d['stock']    as Map? ?? {};
    final trade    = d['trade']    as Map? ?? {};
    final analysis = d['analysis'] as Map? ?? {};
    final meta     = d['meta']     as Map? ?? {};
    return _StrategyCard(
      docId:       docId,
      label:       stock['name']    as String? ?? d['title'] as String? ?? '—',
      symbol:      stock['symbol']  as String? ?? '',
      category:    d['category']    as String? ?? 'stocks',
      type:        d['type']        as String? ?? '',
      action:      trade['action']  as String? ?? 'BUY',
      entry:       (trade['entry_price']   as num?)?.toDouble() ?? 0,
      target:      (analysis['target']     as num?)?.toDouble() ?? 0,
      target2:     (analysis['target2']    as num?)?.toDouble() ?? 0,
      sl:          (analysis['stoploss']   as num?)?.toDouble() ?? 0,
      duration:    analysis['duration']    as String? ?? '',
      badge:       meta['badge']    as String? ?? d['badge'] as String? ?? '',
      status:      d['status']      as String? ?? 'live',
      isOwn:       isOwn,
      dropEnabled: d['drop_enabled']  as bool?   ?? false,
      isPublished: d['is_published']  as bool?   ?? true,
      confidence:  d['confidence']    as String? ?? '',
      tags:        List<String>.from(d['tags'] as List? ?? []),
      quantity:    (d['quantity']     as num?)?.toInt() ?? 1,
      uid:         uid,
      description: d['body'] as String? ?? d['notes'] as String? ?? '',
      // New fields
      orderType:       (trade['order_type']      as String? ?? 'LIMIT').toUpperCase(),
      execMode:        d['execution_mode']        as String? ?? 'immediate',
      trailingSL:      d['trailing_sl_enabled']   as bool?   ?? false,
      trailingSLMode:  d['trailing_sl_mode']       as String? ?? 'points',
      trailingSLValue: (d['trailing_sl_value']    as num?)?.toDouble() ?? 0,
      autoExecute:     d['auto_execute']           as bool?   ?? false,
      sizeMode:        d['position_size_mode']     as String? ?? 'qty',
      bracketOrder:    d['bracket_order']          as bool?   ?? false,
      rawData:         d,
      paperTrade:      d['paper_trade']             as bool?   ?? false,
      // Product type / validity / valid-till
      productType: (d['product_type'] as String? ?? 'CNC').toUpperCase(),
      validity:    (d['validity']     as String? ?? 'DAY').toUpperCase(),
      validTill: () {
        final v = d['valid_till'];
        if (v is Timestamp) return v.toDate();
        if (v is String) return DateTime.tryParse(v);
        return null;
      }(),
    );
  }

  static Color _catColor(String cat) {
    switch (cat) {
      case 'options':   return const Color(0xFF6D4FD1);
      case 'futures':   return _UT.info;
      case 'commodity': return _UT.warning;
      case 'forex':     return _UT.profit;
      default:          return _UT.primary;
    }
  }

  Color get _statusColor {
    if (dropEnabled && !isPublished && status == 'watching') return _UT.warning;
    switch (status) {
      case 'active':      return _UT.warning;   // draft — not yet deployed
      case 'watching':    return _UT.warning;
      case 'in_position': return _UT.info;
      case 'target_hit':  return _UT.profit;
      case 'sl_hit':      return _UT.loss;
      case 'closed':      return _UT.t3;
      default:            return _UT.primary;
    }
  }

  String get _statusLabel {
    switch (status) {
      case 'active':      return '📋 Draft';
      case 'watching':    return 'Watching';
      case 'in_position': return 'In position';
      case 'target_hit':  return 'Target hit';
      case 'sl_hit':      return 'SL hit';
      case 'closed':      return 'Closed';
      default:            return 'Live';
    }
  }

  Future<void> _delete(BuildContext context) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: _UT.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Delete strategy?',
            style: TextStyle(fontWeight: FontWeight.w800, color: _UT.t1)),
        content: Text('This will permanently remove "$label".',
            style: const TextStyle(color: _UT.t2)),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Cancel', style: TextStyle(color: _UT.t2))),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Delete', style: TextStyle(color: _UT.loss)),
          ),
        ],
      ),
    );
    if (confirm != true || uid == null) return;
    await FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .collection('strategies')
        .doc(docId)
        .delete();
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('"$label" deleted'),
          backgroundColor: _UT.loss,
          behavior: SnackBarBehavior.floating,
          margin: const EdgeInsets.all(16),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      );
    }
  }

  Future<void> _deploy(BuildContext context) async {
    if (uid == null || docId.isEmpty) return;
    try {
      await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .collection('strategies')
          .doc(docId)
          .update({
        'status':          'watching',
        'auto_execute':    true,
        'deployed_at':     FieldValue.serverTimestamp(),
        'meta.updated_at': FieldValue.serverTimestamp(),
      });
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: const Row(children: [
            Icon(Icons.rocket_launch_rounded, color: Colors.white, size: 18),
            SizedBox(width: 10),
            Text('Strategy deployed! Engine is now watching.'),
          ]),
          backgroundColor: _UT.profit,
          behavior: SnackBarBehavior.floating,
          margin: const EdgeInsets.all(16),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ));
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Deploy failed: $e'),
          backgroundColor: _UT.loss,
          behavior: SnackBarBehavior.floating,
          margin: const EdgeInsets.all(16),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ));
      }
    }
  }


  @override
  Widget build(BuildContext context) {
    final catColor = _catColor(category);
    final isClosed = status == 'closed' ||
        status == 'target_hit' ||
        status == 'sl_hit' ||
        status == 'hit_target' ||    // legacy
        status == 'stoploss_hit';    // legacy
    final isWatching   = status == 'watching';
    final isInPosition = status == 'in_position';

    return BlocBuilder<LivePriceCubit, LivePriceState>(
      buildWhen: (prev, curr) =>
      prev.prices[symbol]?.ltp != curr.prices[symbol]?.ltp,
      builder: (context, priceState) {
        final ltp = priceState.prices[symbol]?.ltp ??
            (isClosed
                ? entry
                : LivePriceService.instance.getPrice(symbol)?.ltp ?? entry);

        // Live P&L
        final isBuy = action.toUpperCase() == 'BUY';
        final gainPct = entry > 0
            ? (isBuy
            ? ((ltp - entry) / entry) * 100
            : ((entry - ltp) / entry) * 100)
            : 0.0;
        final gainRs = entry > 0 ? (gainPct / 100) * entry * quantity : 0.0;
        final isProfit = gainPct >= 0;

        // Price progress bar: position of ltp between sl and target
        final rangeSize =
        (target > 0 && sl > 0) ? (target - sl) : 0.0;
        final progress = (rangeSize > 0 && entry > 0)
            ? ((ltp - sl) / rangeSize).clamp(0.0, 1.0)
            : null;

        return GestureDetector(
          onTap: () => context.push(
            '/strategy-detail',
            extra: {
              'docId': docId,
              'uid': uid ?? '',
              'isOwn': isOwn,
              'data': {
                'label': label,
                'symbol': symbol,
                'category': category,
                'type': type,
                'action': action,
                'entry': entry,
                'target': target,
                'target2': target2,
                'sl': sl,
                'duration': duration,
                'badge': badge,
                'status': status,
                'dropEnabled': dropEnabled,
                'isPublished': isPublished,
                'confidence': confidence,
                'tags': tags,
                'quantity': quantity,
                'description': description,
                // New fields
                'orderType': orderType,
                'execMode': execMode,
                'trailingSL': trailingSL,
                'trailingSLMode': trailingSLMode,
                'trailingSLValue': trailingSLValue,
                'autoExecute': autoExecute,
                'sizeMode': sizeMode,
                'bracketOrder': bracketOrder,
                'paper_trade':  paperTrade,
                // Full raw doc for edit pre-fill
                'stock': rawData['stock'],
                'trade': rawData['trade'],
                'analysis': rawData['analysis'],
                'notes': rawData['notes'],
                'body': rawData['body'],
                'entry_condition_type': rawData['entry_condition_type'],
                'entry_condition_price': rawData['entry_condition_price'],
                'trailing_sl_enabled': trailingSL,
                'trailing_sl_mode': trailingSLMode,
                'trailing_sl_value': trailingSLValue,
                'auto_execute': autoExecute,
                'execution_mode': execMode,
                'position_size_mode': sizeMode,
                'lot_size': rawData['lot_size'],
                'capital_pct': rawData['capital_pct'],
                'fixed_rs': rawData['fixed_rs'],
                'bracket_order': bracketOrder,
                // Product type / validity / valid-till
                'productType': productType,
                'validity':    validity,
                'validTill':   validTill,
                'product_type': productType,
              },
            },
          ),
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: _UT.card(),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ── Top row: pills + delete ──────────────────────────
                Row(
                  children: [
                    _Pill(text: category.toUpperCase(), color: catColor),
                    const SizedBox(width: 6),
                    _Pill(
                      text: action,
                      color: action == 'BUY' ? _UT.profit : _UT.loss,
                    ),
                    const SizedBox(width: 6),
                    // Status chip — animated pulse for live states
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: _statusColor.withValues(alpha: 0.10),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        if (status == 'watching' || status == 'in_position') ...[
                          _LivePulseDot(
                            color: _statusColor,
                            size: status == 'in_position' ? 7.0 : 6.0,
                          ),
                          const SizedBox(width: 5),
                        ],
                        Text(
                          _statusLabel,
                          style: TextStyle(
                              fontSize: 9.5,
                              fontWeight: FontWeight.w800,
                              color: _statusColor),
                        ),
                      ]),
                    ),
                    // Paper trade badge
                    if (paperTrade) ...[
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFFFBEB),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: const Color(0xFFFDE68A)),
                        ),
                        child: const Text(
                          '🧪 PAPER',
                          style: TextStyle(
                              fontSize: 9.5,
                              fontWeight: FontWeight.w800,
                              color: Color(0xFFD97706)),
                        ),
                      ),
                    ],
                    const Spacer(),
                    // Confidence badge
                    if (confidence.isNotEmpty) ...[
                      _ConfidenceBadge(level: confidence),
                      const SizedBox(width: 6),
                    ],
                    if (isOwn && uid != null) ...[
                      GestureDetector(
                        onTap: () => _delete(context),
                        child: Container(
                          padding: const EdgeInsets.all(6),
                          decoration: BoxDecoration(
                            color: _UT.loss.withValues(alpha: 0.08),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Icon(Icons.delete_outline_rounded, size: 16, color: _UT.loss),
                        ),
                      ),
                    ],
                  ],
                ),

                const SizedBox(height: 12),

                // ── Title + live price row ───────────────────────────
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            label,
                            style: const TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 15,
                              color: _UT.t1,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            symbol,
                            style: const TextStyle(
                              fontWeight: FontWeight.w600,
                              fontSize: 12,
                              color: _UT.primary,
                            ),
                          ),
                        ],
                      ),
                    ),
                    // Live P&L column (right side)
                    if (!isClosed && !isWatching && symbol.isNotEmpty && entry > 0) ...[
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(
                            '₹${ltp.toStringAsFixed(2)}',
                            style: _UT.numeral(size: 15, weight: FontWeight.w800, color: _UT.t1),
                          ),
                          const SizedBox(height: 3),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                            decoration: BoxDecoration(
                              color: (isProfit ? _UT.profit : _UT.loss).withValues(alpha: 0.10),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              '${isProfit ? '+' : ''}${gainPct.toStringAsFixed(2)}%  ${isProfit ? '+' : ''}₹${gainRs.abs().toStringAsFixed(0)}',
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w700,
                                color: isProfit ? _UT.profit : _UT.loss,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),

                // ── Price progress bar ───────────────────────────────
                if (progress != null) ...[
                  const SizedBox(height: 12),
                  _PriceProgressBar(
                    progress: progress,
                    sl: sl,
                    entry: entry,
                    target: target,
                    ltp: ltp,
                    isBuy: isBuy,
                  ),
                ],

                const SizedBox(height: 12),

                // ── Metrics row ──────────────────────────────────────
                Row(
                  children: [
                    _Metric(label: 'Entry', value: entry > 0 ? '₹${_fmt(entry)}' : '—'),
                    _vDivider(),
                    _Metric(
                        label: 'Target',
                        value: target > 0 ? '₹${_fmt(target)}' : '—',
                        valueColor: _UT.profit),
                    _vDivider(),
                    _Metric(
                        label: 'SL',
                        value: sl > 0 ? '₹${_fmt(sl)}' : '—',
                        valueColor: _UT.loss),
                    _vDivider(),
                    _Metric(
                      label: 'R:R',
                      value: _rrLabel(),
                      valueColor: _rrValue() != null && _rrValue()! >= 2
                          ? _UT.profit
                          : _UT.warning,
                    ),
                  ],
                ),

                // ── Tags ─────────────────────────────────────────────
                if (tags.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 6,
                    runSpacing: 4,
                    children: tags
                        .take(4)
                        .map((t) => Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: _UT.primary.withValues(alpha: 0.06),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        '#$t',
                        style: const TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                          color: _UT.primary,
                        ),
                      ),
                    ))
                        .toList(),
                  ),
                ],

                // ── Draft deploy button ─────────────────────────────
                if (status == 'active' && isOwn && uid != null) ...[
                  const SizedBox(height: 12),
                  GestureDetector(
                    onTap: () => _deploy(context),
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(vertical: 11),
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [Color(0xFF0E7C6B), Color(0xFF16A34A)],
                          begin: Alignment.centerLeft,
                          end: Alignment.centerRight,
                        ),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                        Icon(Icons.rocket_launch_rounded, color: Colors.white, size: 16),
                        SizedBox(width: 8),
                        Text('Deploy Now', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: Colors.white)),
                        SizedBox(width: 8),
                        Text('· start watching market', style: TextStyle(fontSize: 11, color: Colors.white70)),
                      ]),
                    ),
                  ),
                ],

                // ── Footer row ───────────────────────────────────────
                if (duration.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Icon(Icons.schedule_rounded, size: 13, color: _UT.t3),
                      const SizedBox(width: 4),
                      Text(duration, style: const TextStyle(fontSize: 12, color: _UT.t3)),
                      if (quantity > 1) ...[
                        const SizedBox(width: 10),
                        Icon(Icons.layers_rounded, size: 13, color: _UT.t3),
                        const SizedBox(width: 4),
                        Text('Qty $quantity', style: const TextStyle(fontSize: 12, color: _UT.t3)),
                      ],
                      const Spacer(),
                      Icon(Icons.chevron_right_rounded, size: 16, color: _UT.t3),
                    ],
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }

  double? _rrValue() {
    if (entry <= 0 || target <= 0 || sl <= 0) return null;
    final upside = (target - entry).abs();
    final downside = (entry - sl).abs();
    if (downside == 0) return null;
    return upside / downside;
  }

  String _rrLabel() {
    final v = _rrValue();
    return v != null ? '${v.toStringAsFixed(1)}x' : '—';
  }

  Widget _vDivider() => Container(
    width: 1,
    height: 28,
    margin: const EdgeInsets.symmetric(horizontal: 10),
    color: _UT.divider,
  );

  static String _fmt(double v) {
    if (v >= 1000) {
      return v.toStringAsFixed(0).replaceAllMapped(
        RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'),
            (m) => '${m[1]},',
      );
    }
    return v.toStringAsFixed(2);
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Price progress bar — SL ←───●───→ Target, dot = current ltp
// ─────────────────────────────────────────────────────────────────────────────

class _PriceProgressBar extends StatelessWidget {
  const _PriceProgressBar({
    required this.progress,
    required this.sl,
    required this.entry,
    required this.target,
    required this.ltp,
    required this.isBuy,
  });

  final double progress;
  final double sl;
  final double entry;
  final double target;
  final double ltp;
  final bool isBuy;

  @override
  Widget build(BuildContext context) {
    final isProfit = isBuy ? ltp > entry : ltp < entry;
    final moveColor = isProfit ? _UT.profit : _UT.loss;

    return Column(
      children: [
        LayoutBuilder(builder: (context, constraints) {
          final width = constraints.maxWidth;
          final dotX = (progress * width).clamp(6.0, width - 6.0);

          // Entry marker position
          final rangeSize = target - sl;
          final entryProgress =
          rangeSize > 0 ? ((entry - sl) / rangeSize).clamp(0.0, 1.0) : 0.5;
          final entryX = (entryProgress * width).clamp(0.0, width);

          return SizedBox(
            height: 20,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                // Track background
                Positioned(
                  top: 7,
                  left: 0,
                  right: 0,
                  child: Container(
                    height: 6,
                    decoration: BoxDecoration(
                      color: _UT.surface2,
                      borderRadius: BorderRadius.circular(3),
                    ),
                  ),
                ),
                // Filled portion (SL → current)
                Positioned(
                  top: 7,
                  left: 0,
                  width: dotX,
                  child: Container(
                    height: 6,
                    decoration: BoxDecoration(
                      color: moveColor.withValues(alpha: 0.5),
                      borderRadius: BorderRadius.circular(3),
                    ),
                  ),
                ),
                // Entry marker line
                Positioned(
                  top: 5,
                  left: entryX - 1,
                  child: Container(width: 2, height: 10, color: _UT.t3),
                ),
                // Current price dot
                Positioned(
                  top: 4,
                  left: dotX - 6,
                  child: Container(
                    width: 12,
                    height: 12,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: moveColor,
                      border: Border.all(color: _UT.surface, width: 2),
                    ),
                  ),
                ),
              ],
            ),
          );
        }),
        const SizedBox(height: 4),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('SL ₹${_fmt(sl)}',
                style: TextStyle(
                    fontSize: 9,
                    fontWeight: FontWeight.w600,
                    color: _UT.loss.withValues(alpha: 0.75))),
            Text('₹${_fmt(ltp)}',
                style: _UT.numeral(size: 10, weight: FontWeight.w800, color: _UT.t1)),
            Text('T ₹${_fmt(target)}',
                style: TextStyle(
                    fontSize: 9,
                    fontWeight: FontWeight.w600,
                    color: _UT.profit.withValues(alpha: 0.75))),
          ],
        ),
      ],
    );
  }

  static String _fmt(double v) =>
      v >= 1000 ? v.toStringAsFixed(0) : v.toStringAsFixed(2);
}

// ─────────────────────────────────────────────────────────────────────────────
// Confidence badge
// ─────────────────────────────────────────────────────────────────────────────

class _ConfidenceBadge extends StatelessWidget {
  const _ConfidenceBadge({required this.level});
  final String level;

  @override
  Widget build(BuildContext context) {
    Color color;
    switch (level.toLowerCase()) {
      case 'high':
        color = _UT.profit;
        break;
      case 'medium':
        color = _UT.warning;
        break;
      default:
        color = _UT.t3;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        '${level[0].toUpperCase()}${level.substring(1)}',
        style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.w800, color: color),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Reusable pill
// ─────────────────────────────────────────────────────────────────────────────

class _Pill extends StatelessWidget {
  const _Pill({required this.text, required this.color});
  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(text,
          style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: color)),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Metric widget
// ─────────────────────────────────────────────────────────────────────────────

class _Metric extends StatelessWidget {
  const _Metric({
    required this.label,
    required this.value,
    this.valueColor = _UT.t1,
  });

  final String label;
  final String value;
  final Color valueColor;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        children: [
          Text(label, style: const TextStyle(fontSize: 10, color: _UT.t3)),
          const SizedBox(height: 3),
          Text(value, style: _UT.numeral(size: 13, weight: FontWeight.w700, color: valueColor)),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Empty state
// ─────────────────────────────────────────────────────────────────────────────

class _EmptyState extends StatelessWidget {
  const _EmptyState({
    required this.icon,
    required this.title,
    required this.subtitle,
    this.cta,
    this.onCta,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final String? cta;
  final VoidCallback? onCta;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 68,
              height: 68,
              decoration: const BoxDecoration(
                color: _UT.surface2,
                shape: BoxShape.circle,
              ),
              child: Icon(icon, size: 32, color: _UT.t3),
            ),
            const SizedBox(height: 20),
            Text(title,
                style: const TextStyle(
                    fontSize: 17, fontWeight: FontWeight.w700, color: _UT.t1)),
            const SizedBox(height: 8),
            Text(subtitle,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 13, color: _UT.t2)),
            if (cta != null && onCta != null) ...[
              const SizedBox(height: 24),
              ElevatedButton.icon(
                onPressed: onCta,
                icon: const Icon(Icons.add_rounded, size: 18),
                label: Text(cta!),
                style: ElevatedButton.styleFrom(
                  backgroundColor: _UT.ink,
                  foregroundColor: _UT.onInk1,
                  elevation: 0,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                  textStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Animated live-pulse dot — shown on strategy cards when status is
// 'watching' (engine armed) or 'in_position' (trade active).
// A concentric ripple expands outward and fades, like a radar ping.
// ─────────────────────────────────────────────────────────────────────────────
class _LivePulseDot extends StatefulWidget {
  const _LivePulseDot({required this.color, this.size = 10.0});
  final Color color;
  final double size;
  @override
  State<_LivePulseDot> createState() => _LivePulseDotState();
}

class _LivePulseDotState extends State<_LivePulseDot>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _scaleAnim;
  late Animation<double> _opacityAnim;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1600),
    )..repeat();
    _scaleAnim = Tween<double>(begin: 0.6, end: 2.2).animate(
      CurvedAnimation(parent: _ctrl, curve: Curves.easeOut),
    );
    _opacityAnim = Tween<double>(begin: 0.8, end: 0.0).animate(
      CurvedAnimation(parent: _ctrl, curve: Curves.easeOut),
    );
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.size;
    return SizedBox(
      width: s * 2.4,
      height: s * 2.4,
      child: Stack(alignment: Alignment.center, children: [
        // Ripple ring
        AnimatedBuilder(
          animation: _ctrl,
          builder: (_, __) => Transform.scale(
            scale: _scaleAnim.value,
            child: Opacity(
              opacity: _opacityAnim.value,
              child: Container(
                width: s,
                height: s,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: widget.color.withValues(alpha: 0.4),
                ),
              ),
            ),
          ),
        ),
        // Solid core dot
        Container(
          width: s * 0.7,
          height: s * 0.7,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: widget.color,
          ),
        ),
      ]),
    );
  }
}
