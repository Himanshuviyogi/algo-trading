import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:shimmer/shimmer.dart';

import '../utils/app_theme.dart';
import 'create_strategy_screen.dart';

// ── Models ────────────────────────────────────────────────────────────────────

class ScreenerMeta {
  final String id;
  final String label;
  final String emoji;
  final String color;
  final int count;
  final String date;
  final String status;

  const ScreenerMeta({
    required this.id,
    required this.label,
    required this.emoji,
    required this.color,
    required this.count,
    required this.date,
    required this.status,
  });

  factory ScreenerMeta.fromDoc(DocumentSnapshot doc) {
    final d = doc.data() as Map<String, dynamic>? ?? {};
    return ScreenerMeta(
      id:     doc.id,
      label:  d['label']  as String? ?? doc.id,
      emoji:  d['emoji']  as String? ?? '📊',
      color:  d['color']  as String? ?? 'blue',
      count:  (d['count'] as num?)?.toInt() ?? 0,
      date:   d['date']   as String? ?? '',
      status: d['status'] as String? ?? 'unavailable',
    );
  }
}

class ScreenerStock {
  final String symbol;
  final String name;
  final double close;
  final double pctChange;
  final double netChange;
  final int volume;
  final double high52;
  final double low52;

  const ScreenerStock({
    required this.symbol,
    required this.name,
    required this.close,
    required this.pctChange,
    required this.netChange,
    required this.volume,
    required this.high52,
    required this.low52,
  });

  factory ScreenerStock.fromMap(Map<String, dynamic> m) => ScreenerStock(
        symbol:    m['symbol']    as String? ?? '',
        name:      m['name']      as String? ?? '',
        close:     (m['close']    as num?)?.toDouble() ?? 0,
        pctChange: (m['pctChange'] as num?)?.toDouble() ?? 0,
        netChange: (m['netChange'] as num?)?.toDouble() ?? 0,
        volume:    (m['volume']   as num?)?.toInt() ?? 0,
        high52:    (m['high52']   as num?)?.toDouble() ?? 0,
        low52:     (m['low52']    as num?)?.toDouble() ?? 0,
      );
}

// ── Color helpers ─────────────────────────────────────────────────────────────

Color _accentColor(String color) {
  switch (color) {
    case 'green':  return const Color(0xFF16A34A);
    case 'red':    return const Color(0xFFDC2626);
    case 'teal':   return const Color(0xFF0D9488);
    case 'amber':  return const Color(0xFFD97706);
    case 'orange': return const Color(0xFFEA580C);
    default:       return AuroraColors.violetLight;
  }
}

// ── Screener list screen ──────────────────────────────────────────────────────

class ScreenersScreen extends StatelessWidget {
  const ScreenersScreen({super.key});

  static const _kScreenerOrder = [
    '52w_high_breakout',
    'near_52w_high',
    'strong_gainers',
    'upper_circuit',
    'lower_circuit',
    'strong_losers',
    '52w_low',
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AuroraColors.background,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        scrolledUnderElevation: 0,
        titleSpacing: 16,
        title: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Screeners',
                style: TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 18,
                    color: Color(0xFF111827))),
            Text('NSE EOD · Updated daily after market close',
                style: TextStyle(fontSize: 11, color: Color(0xFF9CA3AF))),
          ],
        ),
      ),
      body: FutureBuilder<List<DocumentSnapshot>>(
        future: _fetchAll(),
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return _buildShimmer();
          }
          if (snap.hasError || !snap.hasData) {
            return _buildError(context);
          }

          // Sort by defined order
          final docs = snap.data!;
          final docsMap = {for (final d in docs) d.id: d};
          final ordered = _kScreenerOrder
              .map((id) => docsMap[id])
              .where((d) => d != null)
              .cast<DocumentSnapshot>()
              .toList();

          // Append any extras not in the order list
          for (final d in docs) {
            if (!_kScreenerOrder.contains(d.id)) ordered.add(d);
          }

          return RefreshIndicator(
            onRefresh: () async {
              (context as Element).markNeedsBuild();
            },
            child: ListView.builder(
              padding: EdgeInsets.fromLTRB(16, 16, 16, MediaQuery.of(context).padding.bottom + 80),
              itemCount: ordered.length,
              itemBuilder: (ctx, i) {
                final meta = ScreenerMeta.fromDoc(ordered[i]);
                return Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: ScreenerCard(
                    meta: meta,
                    onTap: () => Navigator.push(
                      ctx,
                      MaterialPageRoute(
                        builder: (_) => ScreenerDetailScreen(screenerId: meta.id, meta: meta),
                      ),
                    ),
                  ),
                );
              },
            ),
          );
        },
      ),
    );
  }

  Future<List<DocumentSnapshot>> _fetchAll() async {
    final snap = await FirebaseFirestore.instance.collection('screeners').get();
    return snap.docs;
  }

  Widget _buildShimmer() {
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
      itemCount: 7,
      itemBuilder: (_, __) => Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Shimmer.fromColors(
          baseColor: Colors.grey.shade300,
          highlightColor: Colors.grey.shade100,
          child: Container(
            height: 88,
            decoration: BoxDecoration(
                color: Colors.white, borderRadius: BorderRadius.circular(16)),
          ),
        ),
      ),
    );
  }

  Widget _buildError(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.cloud_off_rounded, size: 48, color: Color(0xFFCBD5E1)),
          const SizedBox(height: 12),
          const Text('Could not load screeners',
              style: TextStyle(fontSize: 14, color: Color(0xFF6B7280))),
          const SizedBox(height: 8),
          TextButton(
            onPressed: () => (context as Element).markNeedsBuild(),
            child: const Text('Retry'),
          ),
        ],
      ),
    );
  }
}

// ── Screener card ─────────────────────────────────────────────────────────────

class ScreenerCard extends StatelessWidget {
  final ScreenerMeta meta;
  final VoidCallback onTap;
  const ScreenerCard({super.key, required this.meta, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final accent   = _accentColor(meta.color);
    final isOk     = meta.status == 'ok';
    final subtitle = isOk
        ? '${meta.count} stocks · ${meta.date}'
        : 'Unavailable — runs after market close';

    return GestureDetector(
      onTap: isOk ? onTap : null,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.grey.withOpacity(0.08)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.03),
              blurRadius: 8,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Row(
          children: [
            // Emoji badge
            Container(
              width: 46,
              height: 46,
              decoration: BoxDecoration(
                color: accent.withOpacity(0.1),
                borderRadius: BorderRadius.circular(14),
              ),
              alignment: Alignment.center,
              child: Text(meta.emoji, style: const TextStyle(fontSize: 22)),
            ),
            const SizedBox(width: 14),
            // Label + subtitle
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(meta.label,
                      style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF111827))),
                  const SizedBox(height: 3),
                  Text(subtitle,
                      style: TextStyle(
                          fontSize: 11,
                          color: isOk ? Colors.grey.shade500 : Colors.orange.shade600)),
                ],
              ),
            ),
            if (isOk) ...[
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: accent.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  '${meta.count}',
                  style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                      color: accent),
                ),
              ),
              const SizedBox(width: 6),
              Icon(Icons.chevron_right_rounded, color: Colors.grey.shade400, size: 20),
            ],
          ],
        ),
      ),
    );
  }
}

// ── Screener detail screen ────────────────────────────────────────────────────

class ScreenerDetailScreen extends StatefulWidget {
  final String screenerId;
  final ScreenerMeta meta;
  const ScreenerDetailScreen({
    super.key,
    required this.screenerId,
    required this.meta,
  });

  @override
  State<ScreenerDetailScreen> createState() => _ScreenerDetailScreenState();
}

class _ScreenerDetailScreenState extends State<ScreenerDetailScreen> {
  List<ScreenerStock> _stocks   = [];
  List<ScreenerStock> _filtered = [];
  bool     _loading    = true;
  String   _search     = '';
  DateTime? _updatedAt;
  StreamSubscription<DocumentSnapshot>? _sub;

  @override
  void initState() {
    super.initState();
    _subscribe();
  }

  void _subscribe() {
    _sub = FirebaseFirestore.instance
        .collection('screeners')
        .doc(widget.screenerId)
        .snapshots()
        .listen((doc) {
      if (!mounted) return;
      final raw    = (doc.data()?['stocks'] as List?) ?? [];
      final stocks = raw
          .cast<Map<String, dynamic>>()
          .map(ScreenerStock.fromMap)
          .toList();

      // Try to read the server-side updated_at timestamp
      DateTime? updatedAt;
      final ts = doc.data()?['updated_at'];
      if (ts is Timestamp) updatedAt = ts.toDate();

      setState(() {
        _stocks    = stocks;
        _filtered  = _search.isEmpty ? stocks : _applySearch(stocks, _search);
        _updatedAt = updatedAt;
        _loading   = false;
      });
    }, onError: (_) {
      if (mounted) setState(() => _loading = false);
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  // Manual pull-to-refresh: just forces a re-read (stream already auto-updates,
  // but users expect pull-to-refresh to do something visible).
  Future<void> _onRefresh() async {
    setState(() => _loading = true);
    final doc = await FirebaseFirestore.instance
        .collection('screeners')
        .doc(widget.screenerId)
        .get();
    if (!mounted) return;
    final raw    = (doc.data()?['stocks'] as List?) ?? [];
    final stocks = raw.cast<Map<String, dynamic>>().map(ScreenerStock.fromMap).toList();
    DateTime? updatedAt;
    final ts = doc.data()?['updated_at'];
    if (ts is Timestamp) updatedAt = ts.toDate();
    setState(() {
      _stocks    = stocks;
      _filtered  = _search.isEmpty ? stocks : _applySearch(stocks, _search);
      _updatedAt = updatedAt;
      _loading   = false;
    });
  }

  List<ScreenerStock> _applySearch(List<ScreenerStock> stocks, String q) =>
      stocks.where((s) =>
          s.symbol.toUpperCase().contains(q.toUpperCase()) ||
          s.name.toUpperCase().contains(q.toUpperCase())).toList();

  void _onSearch(String q) {
    setState(() {
      _search   = q;
      _filtered = _applySearch(_stocks, q);
    });
  }

  String _fmtUpdated() {
    if (_updatedAt == null) return widget.meta.date;
    final now  = DateTime.now();
    final diff = now.difference(_updatedAt!);
    if (diff.inMinutes < 1)  return 'Updated just now';
    if (diff.inMinutes < 60) return 'Updated ${diff.inMinutes}m ago';
    if (diff.inHours   < 24) return 'Updated ${diff.inHours}h ago';
    return 'Updated ${_updatedAt!.day}/${_updatedAt!.month}';
  }

  @override
  Widget build(BuildContext context) {
    final accent = _accentColor(widget.meta.color);

    return Scaffold(
      backgroundColor: AuroraColors.background,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        scrolledUnderElevation: 0,
        titleSpacing: 0,
        title: Row(
          children: [
            Text(widget.meta.emoji, style: const TextStyle(fontSize: 20)),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                widget.meta.label,
                style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 16,
                    color: Color(0xFF111827)),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
      body: _loading
          ? _buildShimmer()
          : Column(
              children: [
                // Search bar
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                  child: Container(
                    height: 42,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.grey.withOpacity(0.15)),
                    ),
                    child: TextField(
                      onChanged: _onSearch,
                      style: const TextStyle(fontSize: 13),
                      decoration: InputDecoration(
                        hintText: 'Search symbol or company…',
                        hintStyle: TextStyle(fontSize: 13, color: Colors.grey.shade400),
                        prefixIcon: Icon(Icons.search, size: 18, color: Colors.grey.shade400),
                        border: InputBorder.none,
                        contentPadding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                    ),
                  ),
                ),
                // Count label
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                  child: Row(
                    children: [
                      Text(
                        _search.isEmpty
                            ? '${_stocks.length} stocks'
                            : '${_filtered.length} of ${_stocks.length} results',
                        style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
                      ),
                      const Spacer(),
                      Text(
                        _fmtUpdated(),
                        style: TextStyle(fontSize: 11, color: Colors.grey.shade400),
                      ),
                      const SizedBox(width: 4),
                      Icon(Icons.autorenew_rounded, size: 12, color: Colors.grey.shade400),
                    ],
                  ),
                ),
                // Stock list
                Expanded(
                  child: RefreshIndicator(
                    onRefresh: _onRefresh,
                    child: _filtered.isEmpty
                        ? Center(
                            child: Text('No stocks found',
                                style: TextStyle(color: Colors.grey.shade500)),
                          )
                        : ListView.builder(
                            padding: EdgeInsets.fromLTRB(16, 0, 16, MediaQuery.of(context).padding.bottom + 80),
                            itemCount: _filtered.length,
                            itemBuilder: (_, i) =>
                                _StockRow(stock: _filtered[i], accent: accent, rank: i + 1),
                          ),
                  ),
                ),
              ],
            ),
    );
  }

  Widget _buildShimmer() {
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
      itemCount: 10,
      itemBuilder: (_, __) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Shimmer.fromColors(
          baseColor: Colors.grey.shade300,
          highlightColor: Colors.grey.shade100,
          child: Container(
            height: 64,
            decoration: BoxDecoration(
                color: Colors.white, borderRadius: BorderRadius.circular(14)),
          ),
        ),
      ),
    );
  }
}

// ── Stock row ─────────────────────────────────────────────────────────────────

class _StockRow extends StatelessWidget {
  final ScreenerStock stock;
  final Color accent;
  final int rank;
  const _StockRow({required this.stock, required this.accent, required this.rank});

  String _fmtVol(int v) {
    if (v >= 10000000) return '${(v / 10000000).toStringAsFixed(1)}Cr';
    if (v >= 100000)   return '${(v / 100000).toStringAsFixed(1)}L';
    if (v >= 1000)     return '${(v / 1000).toStringAsFixed(1)}K';
    return '$v';
  }

  @override
  Widget build(BuildContext context) {
    final isUp  = stock.pctChange >= 0;
    final color = isUp ? const Color(0xFF16A34A) : const Color(0xFFDC2626);
    final sign  = isUp ? '+' : '';

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.grey.withOpacity(0.07)),
          boxShadow: [
            BoxShadow(
                color: Colors.black.withOpacity(0.025),
                blurRadius: 6,
                offset: const Offset(0, 2)),
          ],
        ),
        child: Row(
          children: [
            // Rank
            Container(
              width: 26,
              height: 26,
              decoration: BoxDecoration(
                color: accent.withOpacity(0.08),
                borderRadius: BorderRadius.circular(7),
              ),
              alignment: Alignment.center,
              child: Text('$rank',
                  style: TextStyle(
                      fontSize: 10, fontWeight: FontWeight.w800, color: accent)),
            ),
            const SizedBox(width: 10),
            // Symbol + name
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(stock.symbol,
                      style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w800,
                          color: Color(0xFF111827))),
                  Text(stock.name,
                      style: TextStyle(fontSize: 10, color: Colors.grey.shade500),
                      overflow: TextOverflow.ellipsis,
                      maxLines: 1),
                  if (stock.volume > 0)
                    Text('Vol: ${_fmtVol(stock.volume)}',
                        style: TextStyle(fontSize: 9, color: Colors.grey.shade400)),
                ],
              ),
            ),
            // Price + change
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text('₹${stock.close.toStringAsFixed(2)}',
                    style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                        color: Color(0xFF111827))),
                const SizedBox(height: 2),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: color.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(5),
                  ),
                  child: Text(
                    '$sign${stock.pctChange.toStringAsFixed(2)}%',
                    style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: color),
                  ),
                ),
                Text('$sign${stock.netChange.toStringAsFixed(2)}',
                    style: TextStyle(fontSize: 10, color: Colors.grey.shade500)),
              ],
            ),
            // ── Quick-add strategy button ────────────────────────────────
            const SizedBox(width: 10),
            GestureDetector(
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => CreateStrategyScreen(
                    prefillSymbol: stock.symbol,
                    prefillName:   stock.name,
                    prefillPrice:  stock.close,
                  ),
                ),
              ),
              child: Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: AuroraColors.violet.withOpacity(0.08),
                  borderRadius: BorderRadius.circular(9),
                  border: Border.all(
                      color: AuroraColors.violet.withOpacity(0.2)),
                ),
                child: const Icon(Icons.add_rounded,
                    size: 18, color: AuroraColors.violet),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
