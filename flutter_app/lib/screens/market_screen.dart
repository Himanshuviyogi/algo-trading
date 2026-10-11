import 'dart:async';
import 'dart:convert';
import 'dart:ui';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shimmer/shimmer.dart';

import '../screens/stock_chart_screen.dart';

// ─────────────────────────────────────────────────────────────────────────────
//  Design tokens — matches the dashboard's "trading terminal on paper" system.
//  Warm paper base, one flat ink surface for emphasis, a single signal accent.
// ─────────────────────────────────────────────────────────────────────────────

abstract final class _MT {
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

  static const t1 = Color(0xFF14161D);
  static const t2 = Color(0xFF5B5D66);
  static const t3 = Color(0xFF9C9DA6);

  static const r10 = 10.0;
  static const r14 = 14.0;
  static const r18 = 18.0;

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
}

// ── NSE Mover model ──────────────────────────────────────────────────────────

class NseMover {
  final String symbol;
  final String companyName;
  final double ltp;
  final double percentChange;
  final double netChange;
  final int? volume;

  const NseMover({
    required this.symbol,
    required this.companyName,
    required this.ltp,
    required this.percentChange,
    required this.netChange,
    this.volume,
  });

  // NSE live-analysis-variations fields: ltp, net_price, perChange, trade_quantity
  factory NseMover.fromNse(Map<String, dynamic> j) => NseMover(
    symbol:        j['symbol']?.toString() ?? '',
    companyName:   (j['meta'] as Map?)?['companyName'] as String?
        ?? j['symbol']?.toString() ?? '',
    ltp:           (j['ltp']           as num?)?.toDouble() ?? 0,
    percentChange: (j['perChange']     as num?)?.toDouble() ?? 0,
    netChange:     (j['net_price']     as num?)?.toDouble()
        ?? (j['change']     as num?)?.toDouble() ?? 0,
    volume:        (j['trade_quantity'] as num?)?.toInt()
        ?? (j['totalTradedVolume'] as num?)?.toInt(),
  );

  // Firestore EOD fallback fields
  factory NseMover.fromFirestore(Map<String, dynamic> j) => NseMover(
    symbol:        j['symbol']      as String? ?? '',
    companyName:   j['companyName'] as String? ?? j['symbol'] as String? ?? '',
    ltp:           (j['ltp']           as num?)?.toDouble()
        ?? (j['close']      as num?)?.toDouble() ?? 0,
    percentChange: (j['percentChange'] as num?)?.toDouble() ?? 0,
    netChange:     (j['netChange']     as num?)?.toDouble() ?? 0,
    volume:        (j['volume']        as num?)?.toInt(),
  );
}

// ── Data source tag ───────────────────────────────────────────────────────────

enum _DataSource { live, eod, none }

// ── NSE session manager ───────────────────────────────────────────────────────

String?   _nseCookies;
DateTime? _nseSessionExpiry;
const     _kNseSessionTtl = Duration(minutes: 20);
const     _kNseUserAgent  =
    'Mozilla/5.0 (Linux; Android 13; Pixel 7) AppleWebKit/537.36 '
    '(KHTML, like Gecko) Chrome/124.0 Mobile Safari/537.36';

Future<String> _getNseSession() async {
  if (_nseCookies != null &&
      _nseSessionExpiry != null &&
      DateTime.now().isBefore(_nseSessionExpiry!)) {
    return _nseCookies!;
  }
  final res = await http.get(
    Uri.parse('https://www.nseindia.com'),
    headers: {
      'User-Agent':      _kNseUserAgent,
      'Accept':          'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
      'Accept-Language': 'en-US,en;q=0.5',
    },
  ).timeout(const Duration(seconds: 12));

  final rawCookies = res.headers['set-cookie'] ?? '';
  final cookies = rawCookies
      .split(RegExp(r',(?=[^;])'))
      .map((c) => c.split(';').first.trim())
      .where((c) => c.isNotEmpty)
      .join('; ');
  _nseCookies       = cookies;
  _nseSessionExpiry = DateTime.now().add(_kNseSessionTtl);
  return cookies;
}

Future<List<NseMover>> _fetchNseMoversFromNse(String index) async {
  final cookies = await _getNseSession();
  final res = await http.get(
    Uri.parse('https://www.nseindia.com/api/live-analysis-variations?index=$index'),
    headers: {
      'User-Agent':      _kNseUserAgent,
      'Accept':          'application/json, text/plain, */*',
      'Accept-Language': 'en-US,en;q=0.5',
      'Referer':         'https://www.nseindia.com/market-data/live-equity-market',
      'Cookie':          cookies,
    },
  ).timeout(const Duration(seconds: 12));

  if (res.statusCode != 200) throw Exception('NSE returned ${res.statusCode}');

  final body = jsonDecode(res.body) as Map<String, dynamic>;
  List<dynamic> raw = [];

  // Response: { "NIFTY50": {"data": [...]}, "NIFTY500": {"data": [...]}, ... }
  for (final key in ['NIFTY500', 'NIFTY200', 'NIFTY100', 'NIFTY50', 'NIFTY']) {
    final section = body[key];
    if (section is Map && section['data'] is List) {
      raw = section['data'] as List<dynamic>;
      if (raw.isNotEmpty) break;
    }
  }

  // Fallback to first section with data
  if (raw.isEmpty) {
    for (final val in body.values) {
      if (val is Map && val['data'] is List && (val['data'] as List).isNotEmpty) {
        raw = val['data'] as List<dynamic>;
        break;
      }
    }
  }

  if (raw.isEmpty) throw Exception('NSE returned empty data');

  return raw
      .whereType<Map<String, dynamic>>()
      .map(NseMover.fromNse)
      .where((m) => m.symbol.isNotEmpty)
      .take(20)
      .toList();
}

// ── Market hours ──────────────────────────────────────────────────────────────

bool _isMarketOpen() {
  final now = DateTime.now().toUtc().add(const Duration(hours: 5, minutes: 30));
  if (now.weekday == DateTime.saturday || now.weekday == DateTime.sunday) return false;
  final mins = now.hour * 60 + now.minute;
  return mins >= (9 * 60 + 15) && mins < (15 * 60 + 30);
}

// ─────────────────────────────────────────────────────────────────────────────
// MARKET BREADTH — commented out, re-enable when needed
// ─────────────────────────────────────────────────────────────────────────────
//
// class BreadthData {
//   final int advancing;
//   final int declining;
//   final int unchanged;
//   BreadthData(this.advancing, this.declining, this.unchanged);
//   int get total => advancing + declining + unchanged;
// }
//
// const _kBreadthIndices = {
//   'NIFTY 50':  'NIFTY%2050',
//   'NIFTY 100': 'NIFTY%20100',
//   'NIFTY 500': 'NIFTY%20500',
// };
//
// Future<BreadthData?> _fetchBreadthForIndex(String indexParam) async {
//   try {
//     final cookies = await _getNseSession();
//     final res = await http.get(
//       Uri.parse('https://www.nseindia.com/api/equity-stockIndices?index=$indexParam'),
//       headers: {
//         'User-Agent':      _kNseUserAgent,
//         'Accept':          'application/json, text/plain, */*',
//         'Accept-Language': 'en-US,en;q=0.5',
//         'Referer':         'https://www.nseindia.com/market-data/live-equity-market',
//         'Cookie':          cookies,
//       },
//     ).timeout(const Duration(seconds: 12));
//     if (res.statusCode != 200) return null;
//     final body = jsonDecode(res.body) as Map<String, dynamic>;
//     final data = (body['data'] as List?)
//         ?.whereType<Map<String, dynamic>>()
//         .where((s) => s['symbol'] != null)
//         .toList() ?? [];
//     if (data.isEmpty) return null;
//     int adv = 0, dec = 0, unch = 0;
//     for (final s in data) {
//       final pct = (s['pChange'] as num?)?.toDouble() ?? 0;
//       if (pct > 0)      adv++;
//       else if (pct < 0) dec++;
//       else               unch++;
//     }
//     return BreadthData(adv, dec, unch);
//   } catch (_) {
//     return null;
//   }
// }
//
// ── MarketBreadthCard widget — add back to Tab 0 Column when re-enabling ──────
//
// class MarketBreadthCard extends StatefulWidget {
//   final Map<String, BreadthData> breadth;
//   const MarketBreadthCard({super.key, required this.breadth});
//   @override
//   State<MarketBreadthCard> createState() => _MarketBreadthCardState();
// }
//
// class _MarketBreadthCardState extends State<MarketBreadthCard> {
//   static const _kIndices = [
//     ('NIFTY 500', 'NIFTY 500'),
//     ('NIFTY 100', 'NIFTY 100'),
//     ('NIFTY 50',  'NIFTY 50'),
//   ];
//   String _selected = 'NIFTY 500';
//
//   @override
//   void didUpdateWidget(MarketBreadthCard old) {
//     super.didUpdateWidget(old);
//     if (!widget.breadth.containsKey(_selected)) {
//       for (final (key, _) in _kIndices) {
//         if (widget.breadth.containsKey(key)) { _selected = key; break; }
//       }
//     }
//   }
//
//   @override
//   Widget build(BuildContext context) {
//     final hasData = widget.breadth.isNotEmpty;
//     return Container(
//       margin: const EdgeInsets.only(bottom: 12),
//       padding: const EdgeInsets.all(16),
//       decoration: BoxDecoration(
//         color: Colors.white, borderRadius: BorderRadius.circular(16),
//         border: Border.all(color: Colors.grey.withOpacity(0.08)),
//         boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 8, offset: const Offset(0,3))],
//       ),
//       child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
//         Row(children: [
//           const Text('Stocks up or down in', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Color(0xFF111827))),
//           const SizedBox(width: 8),
//           GestureDetector(
//             onTap: hasData ? () => _showIndexPicker(context) : null,
//             child: Container(
//               padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
//               decoration: BoxDecoration(
//                 color: AuroraColors.violetLight.withOpacity(0.08),
//                 borderRadius: BorderRadius.circular(8),
//                 border: Border.all(color: AuroraColors.violetLight.withOpacity(0.2)),
//               ),
//               child: Row(mainAxisSize: MainAxisSize.min, children: [
//                 Text(_kIndices.firstWhere((e) => e.$1 == _selected, orElse: () => _kIndices.first).$2,
//                   style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AuroraColors.violetLight)),
//                 const SizedBox(width: 4),
//                 const Icon(Icons.keyboard_arrow_down_rounded, size: 14, color: AuroraColors.violetLight),
//               ]),
//             ),
//           ),
//         ]),
//         const SizedBox(height: 14),
//         if (!hasData) _buildSkeleton() else _buildBar(widget.breadth[_selected]),
//       ]),
//     );
//   }
//
//   void _showIndexPicker(BuildContext context) {
//     final available = _kIndices.where((e) => widget.breadth.containsKey(e.$1)).toList();
//     if (available.length <= 1) return;
//     showModalBottomSheet<void>(context: context, backgroundColor: Colors.white,
//       shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
//       builder: (_) => Column(mainAxisSize: MainAxisSize.min, children: [
//         const SizedBox(height: 12),
//         Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(2))),
//         const SizedBox(height: 8),
//         const Padding(padding: EdgeInsets.all(16), child: Text('Select Index', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700))),
//         ...available.map((e) => ListTile(title: Text(e.$2),
//           trailing: _selected == e.$1 ? const Icon(Icons.check_rounded, color: AuroraColors.violetLight) : null,
//           onTap: () { setState(() => _selected = e.$1); Navigator.pop(context); })),
//         const SizedBox(height: 16),
//       ]),
//     );
//   }
//
//   Widget _buildBar(BreadthData? data) {
//     if (data == null || data.total == 0) return _buildSkeleton();
//     final advPct = data.advancing / data.total;
//     final decPct = data.declining / data.total;
//     final unchPct = data.unchanged / data.total;
//     return Column(children: [
//       LayoutBuilder(builder: (_, constraints) {
//         final w = constraints.maxWidth;
//         return ClipRRect(borderRadius: BorderRadius.circular(8), child: SizedBox(height: 20, child: Row(children: [
//           TweenAnimationBuilder<double>(duration: const Duration(milliseconds: 600), curve: Curves.easeOutCubic, tween: Tween(begin: 0, end: advPct),
//             builder: (_, v, __) => Container(width: w * v, color: const Color(0xFF16A34A))),
//           if (data.unchanged > 0) TweenAnimationBuilder<double>(duration: const Duration(milliseconds: 600), curve: Curves.easeOutCubic, tween: Tween(begin: 0, end: unchPct),
//             builder: (_, v, __) => Container(width: w * v, color: Colors.grey.shade300)),
//           TweenAnimationBuilder<double>(duration: const Duration(milliseconds: 600), curve: Curves.easeOutCubic, tween: Tween(begin: 0, end: decPct),
//             builder: (_, v, __) => Container(width: w * v, color: const Color(0xFFDC2626))),
//         ])));
//       }),
//       const SizedBox(height: 10),
//       Row(children: [
//         _chip(Icons.arrow_upward_rounded, const Color(0xFF16A34A), '${data.advancing} Up'),
//         const Spacer(),
//         if (data.unchanged > 0) ...[_chip(Icons.remove_rounded, Colors.grey.shade500, '${data.unchanged} Flat'), const Spacer()],
//         _chip(Icons.arrow_downward_rounded, const Color(0xFFDC2626), '${data.declining} Down'),
//       ]),
//     ]);
//   }
//
//   Widget _chip(IconData icon, Color color, String label) => Row(mainAxisSize: MainAxisSize.min, children: [
//     Icon(icon, size: 13, color: color), const SizedBox(width: 3),
//     Text(label, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: color)),
//   ]);
//
//   Widget _buildSkeleton() => Column(children: [
//     Container(height: 20, decoration: BoxDecoration(color: Colors.grey.shade200, borderRadius: BorderRadius.circular(8))),
//     const SizedBox(height: 10),
//     Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: List.generate(3,
//       (_) => Container(width: 60, height: 14, decoration: BoxDecoration(color: Colors.grey.shade200, borderRadius: BorderRadius.circular(4))))),
//   ]);
// }
//
// ── To re-enable breadth in _fetchMovers, replace the try block with: ─────────
//   final results = await Future.wait([
//     _fetchNseMoversFromNse('gainers'),
//     _fetchNseMoversFromNse('loosers'),
//     _fetchBreadthForIndex(_kBreadthIndices['NIFTY 500']!),
//     _fetchBreadthForIndex(_kBreadthIndices['NIFTY 100']!),
//     _fetchBreadthForIndex(_kBreadthIndices['NIFTY 50']!),
//   ]);
//   final newBreadth = <String, BreadthData>{};
//   if (results[2] != null) newBreadth['NIFTY 500'] = results[2] as BreadthData;
//   if (results[3] != null) newBreadth['NIFTY 100'] = results[3] as BreadthData;
//   if (results[4] != null) newBreadth['NIFTY 50']  = results[4] as BreadthData;
//   setState(() { ...; _breadth = newBreadth; });
//
// ── Also add to state: Map<String, BreadthData> _breadth = {};
// ── And in Tab 0 Column, add: MarketBreadthCard(breadth: _breadth),
// ─────────────────────────────────────────────────────────────────────────────

// ── Screen ───────────────────────────────────────────────────────────────────

class MarketScreen extends StatefulWidget {
  const MarketScreen({super.key});

  @override
  State<MarketScreen> createState() => _MarketScreenState();
}

class _MarketScreenState extends State<MarketScreen>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  late final TabController _tabController;

  List<NseMover> _gainers       = [];
  List<NseMover> _losers        = [];
  bool           _moversLoading = false;
  _DataSource    _dataSource    = _DataSource.none;
  DateTime?      _lastUpdated;
  String?        _moversError;

  Timer? _pollTimer;
  bool   _pollingActive = false;
  static const _kPollInterval = Duration(seconds: 60);

  bool get _isOnMoverTab => true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _tabController = TabController(length: 2, vsync: this);
    _tabController.addListener(_onTabChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _startPolling();
    });
  }

  void _onTabChanged() {
    if (!_tabController.indexIsChanging) return;
    _startPolling();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      if (_isOnMoverTab) _startPolling();
    } else if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive) {
      _stopPolling();
    }
  }

  void _startPolling() {
    if (_pollingActive) return;
    _pollingActive = true;
    _fetchMovers();
    _pollTimer = Timer.periodic(_kPollInterval, (_) {
      if (!_isMarketOpen()) { _stopPolling(); return; }
      _fetchMovers();
    });
  }

  void _stopPolling() {
    _pollTimer?.cancel();
    _pollTimer     = null;
    _pollingActive = false;
  }

  Future<void> _fetchMovers() async {
    if (_moversLoading) return;
    if (mounted) setState(() { _moversLoading = true; _moversError = null; });

    // ── NSE live ──────────────────────────────────────────────────────────────
    try {
      final results = await Future.wait([
        _fetchNseMoversFromNse('gainers'),
        _fetchNseMoversFromNse('loosers'),
      ]);
      if (mounted) {
        setState(() {
          _gainers       = results[0];
          _losers        = results[1];
          _dataSource    = _DataSource.live;
          _lastUpdated   = DateTime.now();
          _moversLoading = false;
        });
      }
      return;
    } catch (e) {
      _nseCookies       = null;
      _nseSessionExpiry = null;
      debugPrint('[NSE] Live fetch failed: $e');
    }

    // ── Firestore EOD fallback ────────────────────────────────────────────────
    try {
      final fs   = FirebaseFirestore.instance;
      final docs = await Future.wait([
        fs.collection('market_data').doc('gainers').get(),
        fs.collection('market_data').doc('losers').get(),
      ]);
      List<NseMover> parse(DocumentSnapshot doc) {
        if (!doc.exists) return [];
        final d = doc.data() as Map<String, dynamic>? ?? {};
        if (d['status'] != 'ok') return [];
        return ((d['stocks'] as List?) ?? [])
            .cast<Map<String, dynamic>>()
            .map(NseMover.fromFirestore)
            .toList();
      }
      if (mounted) {
        setState(() {
          _gainers       = parse(docs[0]);
          _losers        = parse(docs[1]);
          _dataSource    = _DataSource.eod;
          _lastUpdated   = DateTime.now();
          _moversLoading = false;
        });
      }
      return;
    } catch (e) {
      debugPrint('[NSE] Firestore fallback failed: $e');
    }

    if (mounted) {
      setState(() { _moversError = 'Data temporarily unavailable'; _moversLoading = false; });
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _stopPolling();
    _tabController.removeListener(_onTabChanged);
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _MT.bg,
      appBar: _buildAppBar(),
      body: TabBarView(
        controller: _tabController,
        children: [
          // ── Tab 0: NSE Top Gainers ───────────────────────────────────────────
          _NseMoverList(
            movers:      _gainers,
            loading:     _moversLoading,
            error:       _moversError,
            isGainer:    true,
            dataSource:  _dataSource,
            lastUpdated: _lastUpdated,
            onRefresh: () { _startPolling(); return _fetchMovers(); },
          ),

          // ── Tab 1: NSE Top Losers ────────────────────────────────────────────
          _NseMoverList(
            movers:      _losers,
            loading:     _moversLoading,
            error:       _moversError,
            isGainer:    false,
            dataSource:  _dataSource,
            lastUpdated: _lastUpdated,
            onRefresh: () { _startPolling(); return _fetchMovers(); },
          ),
        ],
      ),
    );
  }

  PreferredSizeWidget _buildAppBar() {
    return AppBar(
      backgroundColor: _MT.bg,
      elevation: 0,
      scrolledUnderElevation: 0,
      titleSpacing: 16,
      title: Row(
        children: [
          Container(
            height: 36, width: 36,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(11),
              color: _MT.ink,
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(11),
              child: Image.asset('assets/images/small_logo.png', fit: BoxFit.cover),
            ),
          ),
          const SizedBox(width: 10),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Market',
                  style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18, color: _MT.t1, letterSpacing: -0.3)),
              Row(children: [
                _LiveDot(),
                const SizedBox(width: 5),
                Text('NSE · auto refresh',
                    style: TextStyle(fontSize: 11.5, color: _MT.t2, fontWeight: FontWeight.w500)),
              ]),
            ],
          ),
        ],
      ),
      bottom: PreferredSize(
        preferredSize: const Size.fromHeight(60),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
          child: Container(
            height: 44,
            decoration: BoxDecoration(
              color: _MT.surface,
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: _MT.divider, width: 1),
            ),
            child: TabBar(
              controller: _tabController,
              dividerColor: Colors.transparent,
              indicatorSize: TabBarIndicatorSize.tab,
              splashFactory: NoSplash.splashFactory,
              overlayColor: WidgetStateProperty.all(Colors.transparent),
              indicatorPadding: const EdgeInsets.all(4),
              indicator: BoxDecoration(
                borderRadius: BorderRadius.circular(20),
                color: _MT.ink,
              ),
              labelColor: Colors.white,
              unselectedLabelColor: _MT.t2,
              labelStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
              unselectedLabelStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
              tabs: const [
                Tab(text: 'Top gainers'),
                Tab(text: 'Top losers'),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _LiveDot extends StatefulWidget {
  @override
  State<_LiveDot> createState() => _LiveDotState();
}

class _LiveDotState extends State<_LiveDot> with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 900))
      ..repeat(reverse: true);
  }

  @override
  void dispose() { _ctrl.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: Tween<double>(begin: 0.4, end: 1.0).animate(
        CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut),
      ),
      child: Container(
        height: 6, width: 6,
        decoration: const BoxDecoration(color: _MT.profit, shape: BoxShape.circle),
      ),
    );
  }
}

// ── NSE movers list ───────────────────────────────────────────────────────────

class _NseMoverList extends StatelessWidget {
  final List<NseMover>          movers;
  final bool                    loading;
  final String?                 error;
  final bool                    isGainer;
  final _DataSource             dataSource;
  final DateTime?               lastUpdated;
  final Future<void> Function() onRefresh;

  const _NseMoverList({
    required this.movers,
    required this.loading,
    required this.error,
    required this.isGainer,
    required this.dataSource,
    required this.lastUpdated,
    required this.onRefresh,
  });

  @override
  Widget build(BuildContext context) {
    // Shimmer while first load
    if (loading && movers.isEmpty) {
      return ListView.builder(
        padding: EdgeInsets.fromLTRB(16, 16, 16, MediaQuery.of(context).padding.bottom + 80),
        itemCount: 15,
        itemBuilder: (_, __) => Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Shimmer.fromColors(
            baseColor: _MT.surface2, highlightColor: const Color(0xFFFAFAF7),
            child: Container(
              height: 68,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(_MT.r14),
              ),
            ),
          ),
        ),
      );
    }

    if (error != null && movers.isEmpty) {
      return RefreshIndicator(
        color: _MT.primary,
        onRefresh: onRefresh,
        child: ListView(padding: const EdgeInsets.all(32), children: [
          Icon(Icons.cloud_off_rounded, size: 44, color: _MT.t3),
          const SizedBox(height: 16),
          Text('Data temporarily unavailable\nPull down to retry',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, color: _MT.t2)),
        ]),
      );
    }

    if (movers.isEmpty) {
      return RefreshIndicator(
        color: _MT.primary,
        onRefresh: onRefresh,
        child: ListView(padding: const EdgeInsets.all(32), children: [
          Icon(Icons.bar_chart_rounded, size: 44, color: _MT.t3),
          const SizedBox(height: 16),
          Text(isGainer ? 'No gainers data yet\nUpdates after market opens'
              : 'No losers data yet\nUpdates after market opens',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 14, color: _MT.t2)),
        ]),
      );
    }

    final accentColor = isGainer ? _MT.profit : _MT.loss;

    return RefreshIndicator(
      color: _MT.primary,
      onRefresh: onRefresh,
      child: ListView.builder(
        padding: EdgeInsets.fromLTRB(16, 12, 16, MediaQuery.of(context).padding.bottom + 80),
        itemCount: movers.length + 1,
        itemBuilder: (_, i) {
          if (i == 0) return _buildHeader(accentColor);
          final m     = movers[i - 1];
          final isUp  = m.percentChange >= 0;
          final color = isUp ? _MT.profit : _MT.loss;
          final sign  = isUp ? '+' : '';

          return Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: GestureDetector(
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => StockChartScreen(symbol: 'NSE:${m.symbol}'),
                ),
              ),
              child: Container(
                padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
                decoration: BoxDecoration(
                  color: _MT.surface,
                  borderRadius: BorderRadius.circular(_MT.r14),
                  border: Border.all(color: _MT.divider, width: 1),
                ),
                child: Row(
                  children: [
                    // ── Rank badge ────────────────────────────────────
                    Container(
                      width: 30, height: 30,
                      decoration: BoxDecoration(
                        color: accentColor.withValues(alpha: 0.10),
                        borderRadius: BorderRadius.circular(9),
                      ),
                      alignment: Alignment.center,
                      child: Text(
                        '$i',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                          color: accentColor,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),

                    // ── Symbol + company + volume ─────────────────────
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            m.symbol,
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w800,
                              color: _MT.t1,
                              letterSpacing: -0.2,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            m.companyName,
                            style: const TextStyle(
                              fontSize: 11,
                              color: _MT.t3,
                              fontWeight: FontWeight.w500,
                            ),
                            overflow: TextOverflow.ellipsis,
                            maxLines: 1,
                          ),
                          if (m.volume != null && m.volume! > 0) ...[
                            const SizedBox(height: 3),
                            Row(
                              children: [
                                Icon(Icons.bar_chart_rounded, size: 10, color: _MT.t3),
                                const SizedBox(width: 2),
                                Text(
                                  'Vol ${_fmtVol(m.volume!)}',
                                  style: const TextStyle(
                                    fontSize: 10,
                                    color: _MT.t3,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ],
                      ),
                    ),

                    // ── Price + change ────────────────────────────────
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          '₹${m.ltp.toStringAsFixed(2)}',
                          style: _MT.numeral(size: 15, weight: FontWeight.w800, color: _MT.t1),
                        ),
                        const SizedBox(height: 5),
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              isUp ? Icons.arrow_upward_rounded : Icons.arrow_downward_rounded,
                              size: 11,
                              color: color,
                            ),
                            const SizedBox(width: 2),
                            Text(
                              '$sign${m.percentChange.toStringAsFixed(2)}%',
                              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: color),
                            ),
                          ],
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '$sign${m.netChange.toStringAsFixed(2)}',
                          style: TextStyle(
                            fontSize: 10,
                            color: color.withValues(alpha: 0.75),
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(width: 6),
                    Icon(Icons.chevron_right_rounded, size: 18, color: _MT.t3),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildHeader(Color accentColor) {
    final isLive = dataSource == _DataSource.live;
    final isEod  = dataSource == _DataSource.eod;
    final sourceLabel = isLive ? 'Live' : isEod ? 'EOD · prev close' : 'NSE';
    final sourceColor = isLive ? _MT.profit : isEod ? _MT.warning : _MT.t3;
    final updatedStr = lastUpdated != null
        ? '${lastUpdated!.hour.toString().padLeft(2,'0')}:${lastUpdated!.minute.toString().padLeft(2,'0')}'
        : '';

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(children: [
        Icon(
          isGainer ? Icons.trending_up_rounded : Icons.trending_down_rounded,
          size: 14,
          color: accentColor,
        ),
        const SizedBox(width: 6),
        Text(
          isGainer ? 'Top ${movers.length} NSE gainers' : 'Top ${movers.length} NSE losers',
          style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: _MT.t1),
        ),
        const Spacer(),
        Row(children: [
          if (isLive)
            Padding(
              padding: const EdgeInsets.only(right: 5),
              child: Container(
                height: 6, width: 6,
                decoration: const BoxDecoration(color: _MT.profit, shape: BoxShape.circle),
              ),
            ),
          Text(sourceLabel, style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700, color: sourceColor)),
        ]),
        if (updatedStr.isNotEmpty) ...[
          const SizedBox(width: 6),
          Text(updatedStr, style: const TextStyle(fontSize: 10.5, color: _MT.t3)),
        ],
      ]),
    );
  }

  String _fmtVol(int v) {
    if (v >= 10000000) return '${(v / 10000000).toStringAsFixed(1)}Cr';
    if (v >= 100000)   return '${(v / 100000).toStringAsFixed(1)}L';
    if (v >= 1000)     return '${(v / 1000).toStringAsFixed(1)}K';
    return '$v';
  }
}

// ── Screeners tab (removed — Screeners is now a standalone screen) ────────────