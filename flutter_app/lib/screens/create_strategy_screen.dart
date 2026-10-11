import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import '../blocs/auth_bloc.dart';
import '../services/live_price_service.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Design tokens
// ─────────────────────────────────────────────────────────────────────────────
abstract final class _K {
  static const bg         = Color(0xFFF4F6FB);
  static const surface    = Color(0xFFFFFFFF);
  static const surfaceAlt = Color(0xFFF0F3FA);
  static const divider    = Color(0xFFE4E8F2);
  static const primary    = Color(0xFF2563EB);
  static const primaryBg  = Color(0xFFEEF3FE);
  static const profit     = Color(0xFF16A34A);
  static const profitBg   = Color(0xFFDCFCE7);
  static const loss       = Color(0xFFDC2626);
  static const lossBg     = Color(0xFFFEE2E2);
  static const warning    = Color(0xFFD97706);
  static const t1         = Color(0xFF0F172A);
  static const t2         = Color(0xFF475569);
  static const t3         = Color(0xFF94A3B8);
  static const t4         = Color(0xFFCBD5E1);

  static List<BoxShadow> get shadow => [
    BoxShadow(color: const Color(0xFF1E3A8A).withValues(alpha: 0.06), blurRadius: 12, offset: const Offset(0, 3)),
  ];

  static BoxDecoration card({Color? border}) => BoxDecoration(
    color: surface, borderRadius: BorderRadius.circular(16),
    border: Border.all(color: border ?? divider), boxShadow: shadow,
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// Strategy type enum — drives which flow/steps are shown
// ─────────────────────────────────────────────────────────────────────────────
enum _StratType { options, stocks }

// (Step labels removed — single-scroll layout, no step wizard)

// ─────────────────────────────────────────────────────────────────────────────
// Stock instrument model — returned by /search-instruments or Firestore
// ─────────────────────────────────────────────────────────────────────────────
class _StockInstrument {
  final String symbol;
  final String name;
  final String exchange;

  const _StockInstrument({
    required this.symbol,
    required this.name,
    required this.exchange,
  });

  /// From price-server /search-instruments response item
  factory _StockInstrument.fromServerJson(Map<String, dynamic> j) =>
      _StockInstrument(
        // Strip -EQ suffix for display (e.g. "RELIANCE-EQ" → "RELIANCE")
        symbol:   (j['symbol']   as String? ?? '').toUpperCase().replaceAll('-EQ', ''),
        name:     j['name']     as String? ?? '',
        exchange: j['exchange'] as String? ?? 'NSE',
      );

  /// From Firestore instrument_tokens/{symbol} document
  factory _StockInstrument.fromFirestore(Map<String, dynamic> d) =>
      _StockInstrument(
        symbol:   (d['symbol']   as String? ?? '').toUpperCase(),
        name:     d['name']     as String? ?? d['symbol'] as String? ?? '',
        exchange: d['exchange'] as String? ?? 'NSE',
      );
}

// ─────────────────────────────────────────────────────────────────────────────
// Async instrument search — price server primary, Firestore fallback
// ─────────────────────────────────────────────────────────────────────────────

/// Calls GET /search-instruments?q=<query>&exchange=NSE
/// Falls back to Firestore instrument_tokens on any error.
Future<List<_StockInstrument>> _searchStockInstruments(String query) async {
  if (query.trim().length < 1) return _fetchFirestoreInstruments(query);

  try {
    final uri = Uri.parse('$_kServerUrl/search-instruments').replace(
      queryParameters: {
        'q':        query.trim(),
        'exchange': 'NSE',
        // Note: NSE cash equities have empty instrumentType in Angel One ScripMaster
        // so we do NOT pass type=EQ — we filter client-side instead
        'limit':    '30',
      },
    );
    final res = await http.get(uri).timeout(const Duration(seconds: 8));
    if (res.statusCode == 200) {
      final body    = jsonDecode(res.body) as Map<String, dynamic>;
      final results = (body['results'] as List<dynamic>? ?? [])
          .cast<Map<String, dynamic>>()
          .map(_StockInstrument.fromServerJson)
          .where((i) =>
              i.symbol.isNotEmpty &&
              // Keep only NSE cash equities: empty or 'EQ' instrumentType
              // Filter out futures (FUTSTK) and options (OPTSTK)
              !i.symbol.contains('FUT') &&
              !i.symbol.contains('CE') &&
              !i.symbol.contains('PE'))
          .toList();
      if (results.isNotEmpty) return results;
    }
  } catch (_) {
    // fall through to Firestore
  }
  return _fetchFirestoreInstruments(query);
}

/// Reads Firestore instrument_tokens collection, filters by query.
/// Used as the fallback when the price server is unreachable.
Future<List<_StockInstrument>> _fetchFirestoreInstruments(String query) async {
  try {
    final snap = await FirebaseFirestore.instance
        .collection('instrument_tokens')
        .where('enabled', isEqualTo: true)
        .limit(300)
        .get();
    final q = query.trim().toUpperCase();
    return snap.docs
        .map((d) => _StockInstrument.fromFirestore(d.data()))
        .where((i) =>
            i.exchange == 'NSE' &&
            (q.isEmpty || i.symbol.contains(q) || i.name.toUpperCase().contains(q)))
        .toList()
      ..sort((a, b) => a.symbol.compareTo(b.symbol));
  } catch (_) {
    return [];
  }
}

const _kIndexes = ['NIFTY', 'BANKNIFTY', 'FINNIFTY', 'MIDCPNIFTY', 'SENSEX'];

// ─────────────────────────────────────────────────────────────────────────────
// Lot sizes per index underlying
// ─────────────────────────────────────────────────────────────────────────────
const _kLotSizes = {
  'NIFTY':       50.0,
  'BANKNIFTY':   15.0,
  'FINNIFTY':    40.0,
  'MIDCPNIFTY':  75.0,
  'SENSEX':      10.0,
};

// ─────────────────────────────────────────────────────────────────────────────
// Models
// ─────────────────────────────────────────────────────────────────────────────

class _Condition {
  // ── LHS ──────────────────────────────────────────────────────────────────
  String lhsType;     // 'Indicator' | 'Price'
  String indicator;   // indicator name when lhsType == 'Indicator'
  String lhsPrice;    // 'Close' | 'Open' | 'High' | 'Low' | 'LTP' | 'Volume'  when lhsType == 'Price'
  String paramA;      // 1st indicator param (period)
  String paramB;      // 2nd indicator param (e.g. Bollinger Std Dev / EMA slow period)
  String paramC;      // 3rd indicator param (MACD signal line)
  String candleSrc;   // 'Current Candle' | 'Previous Candle' | '2 Candles Ago'
  String timeframe;   // '' = same as strategy | '1min' | '3min' | '5min' | '15min' | '1hr' | '1D'
  // ── Operator ─────────────────────────────────────────────────────────────
  String op;
  // ── RHS ──────────────────────────────────────────────────────────────────
  bool   rhsIsInd;    // true = compare against another indicator
  String valueA;      // numeric constant when rhsIsInd == false
  String valueB;      // RHS indicator name when rhsIsInd == true
  String paramC2;     // RHS indicator period when rhsIsInd == true
  // ── Logic gate to next row ────────────────────────────────────────────────
  String logic;       // 'AND' | 'OR'

  _Condition({
    this.lhsType   = 'Indicator',
    this.indicator = 'EMA',
    this.lhsPrice  = 'Close',
    this.paramA    = '20',
    this.paramB    = '',
    this.paramC    = '',
    this.candleSrc = 'Current Candle',
    this.timeframe = '',
    this.op        = '>',
    this.rhsIsInd  = false,
    this.valueA    = '',
    this.valueB    = '',
    this.paramC2   = '',
    this.logic     = 'AND',
  });

  Map<String, dynamic> toMap() => {
    'lhs_type':          lhsType,
    'indicator':         indicator,
    'lhs_price':         lhsPrice,
    'param_a':           paramA,
    'param_b':           paramB,
    'param_c':           paramC,
    'candle_src':        candleSrc,
    'timeframe':         timeframe,
    'operator':          op,
    'rhs_is_indicator':  rhsIsInd,
    'value_a':           valueA,
    'value_b':           valueB,
    'rhs_period':        paramC2,
    'logic':             logic,
  };
}

class _Leg {
  String side;
  String optType;
  int    qty;
  String strikeMode;
  int    strikeN;
  double delta;
  bool   useSetupExpiry;
  String expiry;

  _Leg({
    this.side           = 'Buy',
    this.optType        = 'Call',
    this.qty            = 1,
    this.strikeMode     = 'ATM+N',
    this.strikeN        = 0,
    this.delta          = 0.30,
    this.useSetupExpiry = true,
    this.expiry         = 'Current Week',
  });

  String get strikeLabel {
    if (strikeMode == 'Delta') return 'Δ${delta.toStringAsFixed(2)}';
    if (strikeN == 0)          return 'ATM';
    return strikeN > 0 ? 'ATM+$strikeN' : 'ATM$strikeN';
  }

  Map<String, dynamic> toMap() => {
    'side': side, 'option_type': optType, 'quantity': qty,
    'strike_mode': strikeMode, 'strike_n': strikeN, 'delta': delta,
    'use_setup_expiry': useSetupExpiry, 'expiry': expiry,
  };
}

// ─────────────────────────────────────────────────────────────────────────────
// Strategy presets (Options only)
// ─────────────────────────────────────────────────────────────────────────────
class _Preset {
  final String name, description, icon, style;
  final List<_Leg> legs;
  final List<_Condition> entryConds;
  const _Preset({required this.name, required this.description, required this.icon, required this.style, required this.legs, required this.entryConds});
}

List<_Preset> _buildPresets() => [
  _Preset(
    name: 'Bull Call Spread', icon: '📈', style: 'Spread',
    description: 'Buy lower-strike call, sell higher-strike call. Capped profit & risk.',
    legs: [_Leg(side: 'Buy', optType: 'Call', strikeN: 0), _Leg(side: 'Sell', optType: 'Call', strikeN: 2)],
    entryConds: [_Condition(indicator: 'RSI', op: '>', valueA: '50', paramA: '14')],
  ),
  _Preset(
    name: 'Bear Put Spread', icon: '📉', style: 'Spread',
    description: 'Buy higher-strike put, sell lower-strike put. Bearish with capped risk.',
    legs: [_Leg(side: 'Buy', optType: 'Put', strikeN: 0), _Leg(side: 'Sell', optType: 'Put', strikeN: -2)],
    entryConds: [_Condition(indicator: 'RSI', op: '<', valueA: '45', paramA: '14')],
  ),
  _Preset(
    name: 'Straddle', icon: '⚖️', style: 'Buying',
    description: 'Buy ATM call + ATM put. Profits from large moves in either direction.',
    legs: [_Leg(side: 'Buy', optType: 'Call', strikeN: 0), _Leg(side: 'Buy', optType: 'Put', strikeN: 0)],
    // Enter when IV is elevated (>40) — buying a straddle works best when
    // a large directional move is expected (event/breakout). Avoid paying up
    // for vol that has already expanded (IV > 70 is usually too expensive).
    entryConds: [
      _Condition(indicator: 'IV / IV Rank', op: '>', valueA: '40', paramA: ''),
      _Condition(indicator: 'IV / IV Rank', op: '<', valueA: '70', paramA: '', logic: 'AND'),
    ],
  ),
  _Preset(
    name: 'Strangle', icon: '🔀', style: 'Buying',
    description: 'Buy OTM call + OTM put. Cheaper than straddle, needs bigger move.',
    legs: [_Leg(side: 'Buy', optType: 'Call', strikeN: 2), _Leg(side: 'Buy', optType: 'Put', strikeN: -2)],
    // Same rationale as straddle but slightly looser IV band because OTM
    // premiums are cheaper and can still be profitable with moderate vol expansion.
    entryConds: [
      _Condition(indicator: 'IV / IV Rank', op: '>', valueA: '35', paramA: ''),
      _Condition(indicator: 'IV / IV Rank', op: '<', valueA: '65', paramA: '', logic: 'AND'),
    ],
  ),
  _Preset(
    name: 'Iron Condor', icon: '🦅', style: 'Selling',
    description: 'Sell OTM strangle, buy further OTM wings. Profits in sideways market.',
    legs: [
      _Leg(side: 'Buy',  optType: 'Put',  strikeN: -4),
      _Leg(side: 'Sell', optType: 'Put',  strikeN: -2),
      _Leg(side: 'Sell', optType: 'Call', strikeN:  2),
      _Leg(side: 'Buy',  optType: 'Call', strikeN:  4),
    ],
    entryConds: [_Condition(indicator: 'IV / IV Rank', op: '>', valueA: '50', paramA: '')],
  ),
  _Preset(
    name: 'Covered Call', icon: '🛡️', style: 'Hedged',
    description: 'Long underlying futures + short OTM call. Income generation on a bullish view.',
    legs: [
      // Leg 1: long the underlying (represented as a deep ITM call proxy)
      _Leg(side: 'Buy',  optType: 'Call', strikeN: -6),   // deep ITM call ≈ long futures
      // Leg 2: short OTM call to collect premium
      _Leg(side: 'Sell', optType: 'Call', strikeN:  2),
    ],
    // Enter only in a confirmed uptrend: price above both 20 & 50 EMAs
    entryConds: [
      _Condition(indicator: 'EMA', op: '>', valueA: '', paramA: '20', paramB: '50'),
      _Condition(indicator: 'RSI', op: '<', valueA: '65', paramA: '14', logic: 'AND'),
    ],
  ),
];

// ─────────────────────────────────────────────────────────────────────────────
// Backtest
// ─────────────────────────────────────────────────────────────────────────────
const String _kServerUrl = String.fromEnvironment(
  'PRICE_SERVER_URL', defaultValue: 'http://31.172.87.141:3002',
);

class _BacktestResult {
  final double totalPnl, maxDrawdown, winRate;
  final int totalTrades, winTrades;
  final List<double> equityCurve;
  final String? interval, fromDate, toDate;
  final int? candleCount;
  final String source;

  const _BacktestResult({
    required this.totalPnl, required this.totalTrades, required this.winTrades,
    required this.maxDrawdown, required this.winRate, required this.equityCurve,
    this.interval, this.candleCount, this.fromDate, this.toDate, this.source = 'angel_one',
  });

  factory _BacktestResult.fromJson(Map<String, dynamic> j) {
    final rawCurve = j['equityCurve'] as List<dynamic>? ?? [];
    final curve    = rawCurve.map((v) => (v as num).toDouble()).toList();
    return _BacktestResult(
      totalPnl:    (j['totalPnl']    as num?)?.toDouble() ?? 0,
      totalTrades: (j['totalTrades'] as num?)?.toInt()    ?? 0,
      winTrades:   (j['winTrades']   as num?)?.toInt()    ?? 0,
      maxDrawdown: (j['maxDrawdown'] as num?)?.toDouble() ?? 0,
      winRate:     (j['winRate']     as num?)?.toDouble() ?? 0,
      equityCurve: curve.isEmpty ? [0, 0] : curve,
      interval:    j['interval']    as String?,
      candleCount: (j['candleCount'] as num?)?.toInt(),
      fromDate:    j['fromDate']    as String?,
      toDate:      j['toDate']      as String?,
      source:      j['source']      as String? ?? 'angel_one',
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Payoff diagram helpers
// ─────────────────────────────────────────────────────────────────────────────
class _PayoffPoint { final double spot, pnl; const _PayoffPoint({required this.spot, required this.pnl}); }

List<_PayoffPoint> _computePayoff({required List<_Leg> legs, required double spotPrice, required double lotSize}) {
  const steps = 40;
  final low  = spotPrice * 0.90;
  final high = spotPrice * 1.10;
  final inc  = (high - low) / steps;
  final pts  = <_PayoffPoint>[];
  for (int i = 0; i <= steps; i++) {
    final s = low + i * inc;
    double pnl = 0;
    for (final leg in legs) {
      final strikeOffset = leg.strikeMode == 'Delta'
          ? (leg.delta * 200).roundToDouble()
          : leg.strikeN * 50.0;
      final strike    = spotPrice + strikeOffset;
      double intrinsic = leg.optType == 'Call' ? math.max(0, s - strike) : math.max(0, strike - s);
      final premium   = spotPrice * 0.02;
      final legPnl    = leg.side == 'Buy'
          ? (intrinsic - premium) * leg.qty * lotSize
          : (premium - intrinsic) * leg.qty * lotSize;
      pnl += legPnl;
    }
    pts.add(_PayoffPoint(spot: s, pnl: pnl));
  }
  return pts;
}

// ─────────────────────────────────────────────────────────────────────────────
// Greeks estimation
// ─────────────────────────────────────────────────────────────────────────────
class _Greeks {
  final double delta, theta, iv;
  const _Greeks({required this.delta, required this.theta, required this.iv});

  static _Greeks estimate(_Leg leg, String underlying) {
    double baseDelta = leg.strikeMode == 'Delta' ? leg.delta : _deltaFromN(leg.strikeN, leg.optType);
    if (leg.optType == 'Put') baseDelta = -baseDelta;
    final baseIv    = underlying == 'BANKNIFTY' ? 14.5 : 12.0;
    final baseTheta = -(baseDelta.abs() * 2.0 + 0.5);
    return _Greeks(delta: baseDelta, theta: baseTheta, iv: baseIv);
  }

  static double _deltaFromN(int n, String type) => (0.50 - n.abs() * 0.05).clamp(0.05, 0.50);
}

// ─────────────────────────────────────────────────────────────────────────────
// CreateStrategyScreen
// ─────────────────────────────────────────────────────────────────────────────
class CreateStrategyScreen extends StatefulWidget {
  const CreateStrategyScreen({
    super.key,
    this.prefillSymbol, this.prefillName, this.prefillPrice,
    this.editDocId, this.editUid, this.prefillData,
  });
  final String? prefillSymbol, prefillName;
  final double? prefillPrice;
  final String? editDocId, editUid;
  final Map<String, dynamic>? prefillData;

  @override
  State<CreateStrategyScreen> createState() => _CSS();
}

class _CSS extends State<CreateStrategyScreen> {
  // Single-scroll — no PageController / step index needed
  final _scrollCtrl = ScrollController();
  bool _saving = false;
  bool get _editing => widget.editDocId != null;

  // Section expand/collapse state
  bool _secSetup      = true;
  bool _secConditions = true;
  bool _secLegs       = true;
  bool _secRisk       = true;
  bool _secBacktest   = false;

  // ── Strategy type (Options vs Stocks) ──────────────────────────────────────
  _StratType _stratType = _StratType.options;

  // ── Step 1 — Setup ─────────────────────────────────────────────────────────
  final _nameCtrl = TextEditingController(text: 'My Options Strategy');

  // Options-specific
  String _market      = 'NSE F&O';  // no Forex
  String _underlying  = 'NIFTY';    // index for options
  String _expiry      = 'Current Week';
  String _style       = 'Buying';
  String _tf          = '3m';

  // Stocks-specific
  String _stockMarket   = 'NSE Equity';
  String _stockSymbol   = '';       // set when user picks from live search
  String _stockName     = '';       // full company name from instrument data
  String _stockProduct  = 'Intraday';  // Intraday | Delivery
  String _stockTf       = '5m';
  String _stockStyle    = 'Long';

  // ── Step 2 — Conditions ────────────────────────────────────────────────────
  String _condTab = 'Entry';
  final List<_Condition> _entryConds = [
    _Condition(indicator: 'EMA',            op: '>',  valueA: '',   paramA: '20', paramB: '50'),
    _Condition(indicator: 'RSI',            op: '>',  valueA: '60', paramA: '14'),
    _Condition(indicator: 'Option Premium', op: '>',  valueA: '100'),
  ];
  final List<_Condition> _exitConds   = [];
  final List<_Condition> _filterConds = [];
  bool _advExp = true;
  final Set<String> _advSel = {
    'Open Interest (OI)', 'Put Call Ratio (PCR)', 'IV / IV Rank', 'Option Chain Data Filter',
  };
  List<_Condition> get _conds {
    if (_condTab == 'Exit')    return _exitConds;
    if (_condTab == 'Filters') return _filterConds;
    return _entryConds;
  }

  // ── Step 3 — Options Legs / Stock Position ─────────────────────────────────
  String _legsTab   = 'Strategy Legs';
  final List<_Leg> _legs = [
    _Leg(side: 'Buy',  optType: 'Call', strikeN: 0),
    _Leg(side: 'Sell', optType: 'Call', strikeN: 2),
  ];
  String _orderType   = 'Market Order';
  String _posSizing   = 'Fixed Lots';   // options: Fixed Lots | % of Capital
  String _stockSizing = 'Fixed Shares'; // stocks:  Fixed Shares | % of Capital
  final _capitalCtrl  = TextEditingController();
  final _lotsCtrl     = TextEditingController(text: '1');
  final _sharesCtrl   = TextEditingController(text: '10');
  final _pctCapCtrl   = TextEditingController(text: '5');

  // ── Step 1 Options extra ───────────────────────────────────────────────────
  String _optUnderlying = 'Cash';  // Cash | Futures

  // ── Entry Trigger — what the engine actually evaluates every minute ─────────
  // 'above'     → place order when LTP >= _entryTriggerPrice
  // 'below'     → place order when LTP <= _entryTriggerPrice
  // 'at_market' → place order immediately at market price
  String _entryTriggerType  = 'above';
  final _entryTriggerPriceCtrl = TextEditingController();

  // ── Step 4 — Risk & Exit ───────────────────────────────────────────────────
  final _slCtrl           = TextEditingController();
  final _tgtCtrl          = TextEditingController();
  final _maxLossCtrl      = TextEditingController();
  final _lockedProfitCtrl = TextEditingController(); // locked profit ₹ threshold
  final _lockAtCtrl       = TextEditingController(); // lock-at ₹ level
  String _timeExit        = 'Square off at 3:15 PM';
  bool   _trailSl         = false;
  bool   _paperTrade      = false;

  // ── Trading schedule (uTrade: start time / end time / trading days) ────────
  String _startTime   = '09:20 AM';
  String _endTime     = '03:00 PM';
  final Set<String> _tradingDays = {'Mon', 'Tue', 'Wed', 'Thu', 'Fri'};

  // ── Re-entry / Re-order ────────────────────────────────────────────────────
  bool   _reEntry          = false;
  String _reEntryMode      = 'Time-based';   // Time-based | Signal-based
  String _reEntryWait      = '30';            // minutes to wait before re-entry

  // ── Backtest ───────────────────────────────────────────────────────────────
  _BacktestResult? _btResult;
  bool             _btRunning    = false;
  String           _btRange      = '3 Months'; // backtest date range

  // (single-scroll — no step list needed)

  @override
  void initState() {
    super.initState();

    // ── Fix 4: detect stock prefill from screener ──────────────────────────
    final sym = widget.prefillSymbol;
    if (sym != null) {
      if (_kIndexes.contains(sym.toUpperCase())) {
        // Came from an index context — stays Options
        _underlying = sym.toUpperCase();
      } else {
        // Came from a stock screener row — switch to Stocks flow
        _stratType   = _StratType.stocks;
        _stockSymbol = sym.toUpperCase();
        _stockName   = widget.prefillName ?? '';
        _nameCtrl.text = _stockName.isNotEmpty
            ? '$_stockName Strategy'
            : '$_stockSymbol Strategy';
        // Reset conditions to stock-safe defaults
        _entryConds
          ..clear()
          ..addAll([
            _Condition(indicator: 'EMA', op: '>', valueA: '', paramA: '20', paramB: '50'),
            _Condition(indicator: 'RSI', op: '>', valueA: '50', paramA: '14'),
          ]);
      }
    }

    if (widget.prefillName != null && sym != null && _kIndexes.contains(sym.toUpperCase())) {
      _nameCtrl.text = widget.prefillName!;
    }

    final pd = widget.prefillData;
    if (pd != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) { if (mounted) _applyPrefill(pd); });
    }
  }

  // ── Fix 2: full state restore from Firestore doc when editing ─────────────
  void _applyPrefill(Map<String, dynamic> d) {
    setState(() {
      // Strategy type
      final typeStr = d['strategy_type'] as String? ?? 'options';
      _stratType = typeStr == 'stocks' ? _StratType.stocks : _StratType.options;
      final isOpt = _stratType == _StratType.options;

      // Step 1 — Setup
      _nameCtrl.text = d['name'] as String? ?? _nameCtrl.text;
      if (isOpt) {
        _market     = d['market']         as String? ?? _market;
        _underlying = d['underlying']     as String? ?? _underlying;
        _expiry     = d['expiry']         as String? ?? _expiry;
        _style      = d['strategy_style'] as String? ?? _style;
        _tf         = d['timeframe']      as String? ?? _tf;
        _optUnderlying = d['opt_underlying_type'] as String? ?? _optUnderlying;
      } else {
        _stockMarket   = d['market']         as String? ?? _stockMarket;
        _stockSymbol   = d['underlying']     as String? ?? _stockSymbol;
        _stockName     = d['stock_name']     as String? ?? _stockName;
        _stockProduct  = d['product_type']   as String? ?? _stockProduct;
        _stockStyle    = d['strategy_style'] as String? ?? _stockStyle;
        _stockTf       = d['timeframe']      as String? ?? _stockTf;
      }

      // Step 2 — Conditions
      void loadConds(String key, List<_Condition> target) {
        final raw = d[key] as List<dynamic>?;
        if (raw == null || raw.isEmpty) return;
        target
          ..clear()
          ..addAll(raw.cast<Map<String, dynamic>>().map((m) => _Condition(
            lhsType:   m['lhs_type']         as String? ?? 'Indicator',
            indicator: m['indicator']        as String? ?? 'EMA',
            lhsPrice:  m['lhs_price']        as String? ?? 'Close',
            paramA:    m['param_a']          as String? ?? '',
            paramB:    m['param_b']          as String? ?? '',
            paramC:    m['param_c']          as String? ?? '',
            candleSrc: m['candle_src']       as String? ?? 'Current Candle',
            timeframe: m['timeframe']        as String? ?? '',
            op:        m['operator']         as String? ?? '>',
            rhsIsInd:  m['rhs_is_indicator'] as bool?   ?? false,
            valueA:    m['value_a']          as String? ?? '',
            valueB:    m['value_b']          as String? ?? '',
            paramC2:   m['rhs_period']       as String? ?? '',
            logic:     m['logic']            as String? ?? 'AND',
          )));
      }
      loadConds('entry_conditions',  _entryConds);
      loadConds('exit_conditions',   _exitConds);
      loadConds('filter_conditions', _filterConds);

      // Step 3 — Legs (options only)
      if (isOpt) {
        final rawLegs = d['legs'] as List<dynamic>?;
        if (rawLegs != null && rawLegs.isNotEmpty) {
          _legs
            ..clear()
            ..addAll(rawLegs.cast<Map<String, dynamic>>().map((m) => _Leg(
              side:           m['side']           as String? ?? 'Buy',
              optType:        m['option_type']    as String? ?? 'Call',
              qty:            (m['quantity']      as num?)?.toInt()    ?? 1,
              strikeMode:     m['strike_mode']    as String? ?? 'ATM+N',
              strikeN:        (m['strike_n']      as num?)?.toInt()    ?? 0,
              delta:          (m['delta']         as num?)?.toDouble() ?? 0.30,
              useSetupExpiry: m['use_setup_expiry'] as bool? ?? true,
              expiry:         m['expiry']         as String? ?? 'Current Week',
            )));
        }
      }

      // Step 3 — Position sizing
      _orderType  = d['order_type']      as String? ?? _orderType;
      _posSizing  = d['position_sizing'] as String? ?? _posSizing;
      _stockSizing = _posSizing;
      final lots    = d['lots']           as int?;
      final shares  = d['shares']        as int?;
      final capital = d['capital_amount'] as double?;
      final capPct  = d['capital_pct']   as double?;
      if (lots    != null) _lotsCtrl.text    = '$lots';
      if (shares  != null) _sharesCtrl.text  = '$shares';
      if (capital != null) _capitalCtrl.text = '$capital';
      if (capPct  != null) _pctCapCtrl.text  = '$capPct';

      // Step 4 — Risk & Exit
      final sl      = d['sl_pct']            as double?;
      final tgt     = d['target_pct']        as double?;
      final maxLoss = d['max_loss']          as double?;
      final lockAt  = d['locked_profit_at']  as double?;
      final lockMin = d['locked_profit_min'] as double?;
      if (sl      != null) _slCtrl.text           = '$sl';
      if (tgt     != null) _tgtCtrl.text          = '$tgt';
      if (maxLoss != null) _maxLossCtrl.text       = '$maxLoss';
      if (lockAt  != null) _lockAtCtrl.text        = '$lockAt';
      if (lockMin != null) _lockedProfitCtrl.text  = '$lockMin';
      _trailSl    = d['trailing_sl']   as bool?   ?? _trailSl;
      _paperTrade = d['paper_trade']   as bool?   ?? _paperTrade;
      _timeExit   = d['time_exit']     as String? ?? _timeExit;

      // Trading schedule
      _startTime = d['start_time'] as String? ?? _startTime;
      _endTime   = d['end_time']   as String? ?? _endTime;
      final days = d['trading_days'] as List<dynamic>?;
      if (days != null && days.isNotEmpty) {
        _tradingDays
          ..clear()
          ..addAll(days.cast<String>());
      }

      // Re-entry
      _reEntry     = d['re_entry']       as bool?   ?? _reEntry;
      _reEntryMode = d['re_entry_mode']  as String? ?? _reEntryMode;
      final reWait = d['re_entry_wait_min'] as int?;
      if (reWait != null) _reEntryWait = '$reWait';

      // Backtest range
      _btRange = d['backtest_range'] as String? ?? _btRange;

      // Entry trigger (engine fields)
      _entryTriggerType = d['entry_condition_type'] as String? ?? _entryTriggerType;
      final trigPrice   = d['entry_condition_price'] as num?;
      if (trigPrice != null) _entryTriggerPriceCtrl.text = '$trigPrice';
    });
  }

  @override
  void dispose() {
    _scrollCtrl.dispose();
    _nameCtrl.dispose();
    _slCtrl.dispose(); _tgtCtrl.dispose(); _maxLossCtrl.dispose();
    _capitalCtrl.dispose(); _lotsCtrl.dispose(); _pctCapCtrl.dispose();
    _sharesCtrl.dispose(); _lockedProfitCtrl.dispose(); _lockAtCtrl.dispose();
    _entryTriggerPriceCtrl.dispose();
    super.dispose();
  }

  void _back() => context.pop();

  // ── Backtest ───────────────────────────────────────────────────────────────
  Future<void> _runBacktest() async {
    setState(() { _btRunning = true; _btResult = null; });
    try {
      final user  = FirebaseAuth.instance.currentUser;
      final token = user != null ? await user.getIdToken(true) : null;
      final headers = <String, String>{
        'Content-Type': 'application/json', 'Accept': 'application/json',
        if (token != null) 'Authorization': 'Bearer $token',
      };
      final payload = <String, dynamic>{
        'underlying': _stratType == _StratType.options ? _underlying : _stockSymbol,
        'timeframe':  _stratType == _StratType.options ? _tf : _stockTf,
        'slPct':      _slCtrl.text.trim().isEmpty  ? '50'  : _slCtrl.text.trim(),
        'tgtPct':     _tgtCtrl.text.trim().isEmpty ? '100' : _tgtCtrl.text.trim(),
        'range':      _btRange,
        'entryConds': _entryConds.map((c) => c.toMap()).toList(),
        'exitConds':  _exitConds.map((c) => c.toMap()).toList(),
        if (_stratType == _StratType.options)
          'legs': _legs.map((l) => l.toMap()).toList(),
      };
      final res = await http
          .post(Uri.parse('$_kServerUrl/backtest'), headers: headers, body: jsonEncode(payload))
          .timeout(const Duration(seconds: 30));
      if (!mounted) return;
      if (res.statusCode == 429) { _snack('Backtest already running — please wait.', err: true); return; }
      if (res.statusCode != 200) {
        String errMsg = 'Server error ${res.statusCode}';
        try { final body = jsonDecode(res.body) as Map<String, dynamic>; errMsg = body['error'] as String? ?? errMsg; } catch (_) {}
        _snack('Backtest failed: $errMsg', err: true); return;
      }
      final body = jsonDecode(res.body) as Map<String, dynamic>;
      if (body['success'] != true) { _snack('Backtest failed: ${body['error'] ?? 'Unknown error'}', err: true); return; }
      setState(() => _btResult = _BacktestResult.fromJson(body));
    } on TimeoutException {
      if (mounted) _snack('Backtest timed out — try a higher timeframe.', err: true);
    } catch (e) {
      if (mounted) _snack('Backtest error: $e', err: true);
    } finally {
      if (mounted) setState(() => _btRunning = false);
    }
  }

  // ── Apply preset ───────────────────────────────────────────────────────────
  void _applyPreset(_Preset p) {
    // Close the sheet first, then apply state on the next frame so the
    // parent widget is fully back in the tree before we mutate it.
    Navigator.of(context).pop();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      setState(() {
        _nameCtrl.text = p.name;
        _style         = p.style;

        // Rebuild legs from preset, preserving the current expiry setting
        _legs
          ..clear()
          ..addAll(p.legs.map((l) => _Leg(
            side:           l.side,
            optType:        l.optType,
            qty:            l.qty,
            strikeMode:     l.strikeMode,
            strikeN:        l.strikeN,
            delta:          l.delta,
            useSetupExpiry: true,
            expiry:         _expiry,
          )));

        // Rebuild entry conditions, preserving all fields including logic gate
        _entryConds
          ..clear()
          ..addAll(p.entryConds.map((c) => _Condition(
            lhsType:   c.lhsType,
            indicator: c.indicator,
            lhsPrice:  c.lhsPrice,
            paramA:    c.paramA,
            paramB:    c.paramB,
            paramC:    c.paramC,
            candleSrc: c.candleSrc,
            timeframe: c.timeframe,
            op:        c.op,
            rhsIsInd:  c.rhsIsInd,
            valueA:    c.valueA,
            valueB:    c.valueB,
            paramC2:   c.paramC2,
            logic:     c.logic,
          )));

        // Also clear exit/filter conditions so stale data from a previous
        // preset doesn't bleed through
        _exitConds.clear();
        _filterConds.clear();
      });

      // Navigate to top so the user sees the populated fields.
      _scrollCtrl.animateTo(0, duration: const Duration(milliseconds: 300), curve: Curves.easeInOut);

      _snack('✅ "${p.name}" template applied');
    });
  }

  // ── Clone ──────────────────────────────────────────────────────────────────
  Future<void> _cloneStrategy() async {
    final auth = context.read<AuthBloc>().state;
    if (auth is! AuthAuthenticated) return;
    setState(() => _saving = true);
    try {
      final doc = _buildDoc(auth.uid, status: 'active');
      doc['name'] = '${_nameCtrl.text.trim()} (Copy)';
      doc['created_at'] = FieldValue.serverTimestamp();
      await FirebaseFirestore.instance.collection('users').doc(auth.uid).collection('strategies').add(doc);
      _snack('Strategy cloned!');
    } catch (e) {
      _snack('Clone failed: $e', err: true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  // ── Save / Deploy ──────────────────────────────────────────────────────────
  /// Save as draft — engine ignores it until explicitly deployed.
  Future<void> _saveDraft() async => _saveWithStatus('active');

  /// Deploy immediately — sets status='watching' so the engine picks it up.
  Future<void> _deployNow() async => _saveWithStatus('watching');

  Future<void> _saveWithStatus(String status) async {
    final auth = context.read<AuthBloc>().state;
    if (auth is! AuthAuthenticated) return;
    setState(() => _saving = true);
    try {
      final doc  = _buildDoc(auth.uid, status: status);
      final coll = FirebaseFirestore.instance.collection('users').doc(auth.uid).collection('strategies');
      if (_editing && widget.editDocId != null) {
        doc.remove('created_at');
        await coll.doc(widget.editDocId).update(doc);
        _snack(status == 'watching' ? '🚀 Strategy deployed!' : 'Strategy updated.');
      } else {
        await coll.add(doc);
        _snack(status == 'watching' ? '🚀 Strategy deployed and watching!' : 'Strategy saved as draft.');
      }
      if (mounted) context.pop();
    } catch (e) {
      _snack('Failed: $e', err: true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Map<String, dynamic> _buildDoc(String uid, {String status = 'active'}) {
    final isOpt  = _stratType == _StratType.options;
    final sym    = isOpt ? _underlying : _stockSymbol;
    final action = isOpt
        ? (_style == 'Selling' ? 'SELL' : 'BUY')
        : (_stockStyle == 'Long' ? 'BUY' : 'SELL');

    // Compute flat ₹ entry/target/SL from prefillPrice or live price
    final liveSpotValue = _liveSpot(sym);
    final slPct    = double.tryParse(_slCtrl.text.trim());
    final tgtPct   = double.tryParse(_tgtCtrl.text.trim());
    final entryPrice = widget.prefillPrice ?? liveSpotValue;
    final slAbs    = (slPct  != null && entryPrice > 0) ? entryPrice * (1 - slPct  / 100) : null;
    final tgtAbs   = (tgtPct != null && entryPrice > 0) ? entryPrice * (1 + tgtPct / 100) : null;

    // Entry trigger fields — what the engine evaluates every minute
    final triggerPrice = double.tryParse(_entryTriggerPriceCtrl.text.trim());
    final orderTypeNorm = _orderType.toUpperCase().replaceAll(' ORDER', '').replaceAll(' ', '_');

    return {
      'name':             _nameCtrl.text.trim(),
      'strategy_type':    isOpt ? 'options' : 'stocks',
      'market':           isOpt ? _market : _stockMarket,
      'instrument_type':  isOpt ? 'Index Options' : 'Stocks',
      'underlying':       sym,
      'stock_name':       isOpt ? '' : _stockName,

      // ── nested stock map — read by engine + StrategyCard ─────────────────
      'stock': {
        'symbol':   sym,
        'name':     isOpt ? sym : (_stockName.isNotEmpty ? _stockName : sym),
        'exchange': isOpt ? 'NSE' : (_stockMarket.contains('BSE') ? 'BSE' : 'NSE'),
      },

      // ── nested trade map — read by engine + StrategyCard ─────────────────
      'trade': {
        'action':       action,
        'entry_price':  widget.prefillPrice ?? liveSpotValue,
        'order_type':   orderTypeNorm,
        if (isOpt) 'expiry': _expiry,
        if (!isOpt) 'product_type': _stockProduct,
      },

      // ── nested analysis map — read by position monitor ────────────────────
      'analysis': {
        if (tgtAbs != null) 'target':   tgtAbs,
        if (slAbs  != null) 'stoploss': slAbs,
        'duration': _tf,
      },

      // ── engine entry condition fields ─────────────────────────────────────
      'entry_condition_type':  _entryTriggerType,
      if (triggerPrice != null) 'entry_condition_price': triggerPrice,
      'auto_execute': true,

      // ── position sizing ───────────────────────────────────────────────────
      'position_sizing':   isOpt ? _posSizing : _stockSizing,
      if (isOpt)  'lots':  int.tryParse(_lotsCtrl.text.trim()),
      if (!isOpt) 'shares': int.tryParse(_sharesCtrl.text.trim()),
      if (isOpt) 'lot_size': (_kLotSizes[_underlying] ?? 50).toInt(),
      'capital_amount':    double.tryParse(_capitalCtrl.text.trim()),
      'capital_pct':       double.tryParse(_pctCapCtrl.text.trim()),

      // ── order config ──────────────────────────────────────────────────────
      'order_type':        orderTypeNorm,
      'product_type':      isOpt ? 'NRML' : (_stockProduct == 'Intraday' ? 'MIS' : 'CNC'),
      'validity':          'DAY',

      // ── trailing SL ───────────────────────────────────────────────────────
      'trailing_sl_enabled': _trailSl,
      'trailing_sl_mode':    'pct',
      'trailing_sl_value':   0,

      // ── risk / exit fields (both flat % and computed ₹) ──────────────────
      if (isOpt)  'expiry':     _expiry,
      'strategy_style':   isOpt ? _style : _stockStyle,
      'timeframe':        isOpt ? _tf : _stockTf,
      'sl_pct':           slPct,
      'target_pct':       tgtPct,
      'max_loss':         double.tryParse(_maxLossCtrl.text.trim()),
      'locked_profit_at': double.tryParse(_lockAtCtrl.text.trim()),
      'locked_profit_min': double.tryParse(_lockedProfitCtrl.text.trim()),
      'paper_trade':      _paperTrade,
      'time_exit':        _timeExit,
      'start_time':       _startTime,
      'end_time':         _endTime,
      'trading_days':     _tradingDays.toList(),
      're_entry':         _reEntry,
      're_entry_mode':    _reEntryMode,
      're_entry_wait_min': int.tryParse(_reEntryWait),
      'backtest_range':   _btRange,
      if (isOpt) 'opt_underlying_type': _optUnderlying,

      // ── conditions (for future advanced engine evaluation) ────────────────
      'entry_conditions':  _entryConds.map((c) => c.toMap()).toList(),
      'exit_conditions':   _exitConds.map((c) => c.toMap()).toList(),
      'filter_conditions': _filterConds.map((c) => c.toMap()).toList(),
      'advanced_options':  _advSel.toList(),
      if (isOpt)  'legs':  _legs.map((l) => l.toMap()).toList(),
      if (!isOpt) 'stock_side': _stockStyle == 'Long' ? 'Buy' : 'Sell',

      // ── metadata ──────────────────────────────────────────────────────────
      'created_at': FieldValue.serverTimestamp(),
      'user_id':    uid,
      'source':     'user',
      'status':     status,   // 'active' (draft) or 'watching' (deployed)
      'category':   isOpt ? 'options' : 'stocks',
      'type':       isOpt ? 'options_strategy' : 'stocks_strategy',
    };
  }

  void _snack(String msg, {bool err = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Row(children: [
        Icon(err ? Icons.error_outline_rounded : Icons.check_circle_outline_rounded, color: Colors.white, size: 18),
        const SizedBox(width: 10),
        Expanded(child: Text(msg)),
      ]),
      backgroundColor: err ? _K.loss : _K.t1,
      behavior: SnackBarBehavior.floating,
      margin: const EdgeInsets.all(16),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
    ));
  }

  // ── Build ──────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: _K.bg,
    appBar: _appBar(),
    body: CustomScrollView(
      controller: _scrollCtrl,
      slivers: [
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(16, 18, 16, 120),
          sliver: SliverList(
            delegate: SliverChildListDelegate([
              // ── Strategy type ──────────────────────────────────────────────
              _TypeSelector(
                selected: _stratType,
                onChanged: (t) => setState(() {
                  _stratType = t;
                  _nameCtrl.text = t == _StratType.options ? 'My Options Strategy' : 'My Stock Strategy';
                  _entryConds
                    ..clear()
                    ..addAll(t == _StratType.options
                      ? [
                          _Condition(indicator: 'EMA',          op: '>', valueA: '',   paramA: '20', paramB: '50'),
                          _Condition(indicator: 'RSI',          op: '>', valueA: '60', paramA: '14'),
                          _Condition(indicator: 'IV / IV Rank', op: '<', valueA: '30'),
                        ]
                      : [
                          _Condition(indicator: 'EMA', op: '>', valueA: '',   paramA: '20', paramB: '50'),
                          _Condition(indicator: 'RSI', op: '>', valueA: '50', paramA: '14'),
                        ]);
                  _exitConds.clear();
                  _filterConds.clear();
                }),
              ),
              const SizedBox(height: 20),

              // ── SECTION 1: Setup ───────────────────────────────────────────
              _SectionCard(
                title: '1  Setup',
                icon: Icons.tune_rounded,
                expanded: _secSetup,
                onToggle: () => setState(() => _secSetup = !_secSetup),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  _Label('Strategy Name'),
                  _TxtInput(ctrl: _nameCtrl, hint: _stratType == _StratType.options ? 'My Options Strategy' : 'My Stock Strategy'),
                  const SizedBox(height: 16),
                  if (_stratType == _StratType.options) ..._optionsSetupFields(),
                  if (_stratType == _StratType.stocks)  ..._stocksSetupFields(),
                ]),
              ),
              const SizedBox(height: 12),

              // ── SECTION 2: Conditions ──────────────────────────────────────
              _SectionCard(
                title: '2  Conditions',
                icon: Icons.account_tree_rounded,
                expanded: _secConditions,
                onToggle: () => setState(() => _secConditions = !_secConditions),
                child: _conditionsContent(),
              ),
              const SizedBox(height: 12),

              // ── SECTION 3: Legs / Position ─────────────────────────────────
              _SectionCard(
                title: _stratType == _StratType.options ? '3  Option Legs' : '3  Position',
                icon: _stratType == _StratType.options ? Icons.layers_rounded : Icons.bar_chart_rounded,
                expanded: _secLegs,
                onToggle: () => setState(() => _secLegs = !_secLegs),
                child: _stratType == _StratType.options ? _legsContent2() : _stockPositionContent(),
              ),
              const SizedBox(height: 12),

              // ── SECTION 4: Risk & Exit ─────────────────────────────────────
              _SectionCard(
                title: '4  Risk & Exit',
                icon: Icons.shield_outlined,
                expanded: _secRisk,
                onToggle: () => setState(() => _secRisk = !_secRisk),
                child: _riskContent(),
              ),
              const SizedBox(height: 12),

              // ── SECTION 5: Backtest ────────────────────────────────────────
              _SectionCard(
                title: '5  Backtest',
                icon: Icons.analytics_rounded,
                expanded: _secBacktest,
                onToggle: () => setState(() => _secBacktest = !_secBacktest),
                child: _backtestContent(),
              ),
            ]),
          ),
        ),
      ],
    ),
    bottomNavigationBar: _bottomBar(),
  );

  AppBar _appBar() => AppBar(
    backgroundColor: _K.surface, elevation: 0,
    scrolledUnderElevation: 0, surfaceTintColor: Colors.transparent,
    leading: IconButton(
      icon: const Icon(Icons.arrow_back_rounded, color: _K.t1, size: 22),
      onPressed: _back,
    ),
    title: Text(
      _editing ? 'Edit Strategy' : 'Create Strategy',
      style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: _K.t1, letterSpacing: -0.3),
    ),
    actions: [
      if (_stratType == _StratType.options)
        IconButton(
          icon: const Icon(Icons.auto_awesome_rounded, color: _K.primary, size: 20),
          tooltip: 'Templates',
          onPressed: _showTemplatesSheet,
        ),
      if (_editing)
        IconButton(
          icon: const Icon(Icons.copy_rounded, color: _K.t2, size: 18),
          tooltip: 'Clone Strategy',
          onPressed: _saving ? null : _cloneStrategy,
        ),
      Padding(
        padding: const EdgeInsets.only(right: 8),
        child: Container(
          width: 32, height: 32,
          decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: _K.divider), color: _K.surface),
          child: const Icon(Icons.help_outline_rounded, size: 15, color: _K.t2),
        ),
      ),
    ],
  );

  Widget _bottomBar() => SafeArea(
    top: false,
    child: Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            begin: Alignment.topLeft, end: Alignment.bottomRight,
            colors: [Color(0xFF1D4ED8), Color(0xFF4F46E5)],
          ),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Colors.white.withValues(alpha: 0.15)),
          boxShadow: [
            BoxShadow(color: const Color(0xFF2563EB).withValues(alpha: 0.35), blurRadius: 24, spreadRadius: -4, offset: const Offset(0, 8)),
          ],
        ),
        child: Row(children: [
          Expanded(child: _OutlineBtn(
            label: _saving ? 'Saving…' : 'Save Draft',
            onTap: _saving ? () {} : _saveDraft,
            dark: true,
          )),
          const SizedBox(width: 10),
          Expanded(
            flex: 2,
            child: _PrimaryBtn(
              label: _saving ? 'Deploying…' : '🚀 Deploy Now',
              loading: _saving,
              onTap: _saving ? null : _deployNow,
            ),
          ),
        ]),
      ),
    ),
  );

  // ── Templates sheet ─────────────────────────────────────────────────────────
  void _showTemplatesSheet() {
    final presets = _buildPresets();
    showModalBottomSheet<void>(
      context: context, isScrollControlled: true, backgroundColor: Colors.transparent,
      builder: (_) => DraggableScrollableSheet(
        initialChildSize: 0.75, maxChildSize: 0.92, minChildSize: 0.4,
        builder: (__, sc) => Container(
          decoration: const BoxDecoration(color: _K.surface, borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
          child: Column(children: [
            const SizedBox(height: 8),
            Container(width: 40, height: 4, decoration: BoxDecoration(color: _K.divider, borderRadius: BorderRadius.circular(2))),
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 16, 20, 4),
              child: Align(alignment: Alignment.centerLeft,
                child: Text('Strategy Templates', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: _K.t1))),
            ),
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 0, 20, 12),
              child: Align(alignment: Alignment.centerLeft,
                child: Text('Pick a preset to auto-fill the strategy builder', style: TextStyle(fontSize: 13, color: _K.t3))),
            ),
            Expanded(child: ListView.separated(
              controller: sc,
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
              itemCount: presets.length,
              separatorBuilder: (_, __) => const SizedBox(height: 10),
              itemBuilder: (_, i) {
                final p = presets[i];
                return GestureDetector(
                  onTap: () => _applyPreset(p),
                  child: Container(
                    padding: const EdgeInsets.all(16), decoration: _K.card(),
                    child: Row(children: [
                      Container(
                        width: 44, height: 44,
                        decoration: BoxDecoration(color: _K.primaryBg, borderRadius: BorderRadius.circular(12)),
                        child: Center(child: Text(p.icon, style: const TextStyle(fontSize: 22))),
                      ),
                      const SizedBox(width: 14),
                      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(p.name, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: _K.t1)),
                        const SizedBox(height: 3),
                        Text(p.description, style: const TextStyle(fontSize: 11, color: _K.t3)),
                        const SizedBox(height: 6),
                        Wrap(spacing: 6, children: [
                          _RChip(label: p.style, color: _K.primary),
                          _RChip(label: '${p.legs.length} legs', color: _K.t2),
                        ]),
                      ])),
                      const Icon(Icons.arrow_forward_ios_rounded, size: 14, color: _K.t4),
                    ]),
                  ),
                );
              },
            )),
          ]),
        ),
      ),
    );
  }

  // ════════════════════════════════════════════════════════════════════════════
  // SECTION 1 — SETUP fields
  // ════════════════════════════════════════════════════════════════════════════
  List<Widget> _optionsSetupFields() => [
    _Label('Market'),
    _Chips(options: const ['NSE F&O', 'BSE F&O', 'MCX'], sel: _market, onTap: (v) => setState(() => _market = v)),
    const SizedBox(height: 16),
    Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        _Label('Underlying'),
        _Drop(value: _underlying, items: _kIndexes, onChanged: (v) => setState(() => _underlying = v!)),
      ])),
      const SizedBox(width: 12),
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        _Label('Expiry'),
        _Drop(
          value: _expiry,
          items: const ['Current Week', 'Next Week', 'Monthly', 'Far Month'],
          onChanged: (v) => setState(() {
            _expiry = v!;
            for (final l in _legs) { if (l.useSetupExpiry) l.expiry = _expiry; }
          }),
        ),
      ])),
    ]),
    const SizedBox(height: 16),
    _Label('Underlying Type'),
    _Chips(options: const ['Cash', 'Futures'], sel: _optUnderlying, onTap: (v) => setState(() => _optUnderlying = v)),
    const SizedBox(height: 16),
    _Label('Strategy Style'),
    _Chips(options: const ['Buying', 'Selling', 'Spread', 'Hedged'], sel: _style, onTap: (v) => setState(() => _style = v)),
    const SizedBox(height: 16),
    _Label('Time Frame'),
    _Chips(options: const ['1m', '3m', '5m', '15m', '1H', '1D'], sel: _tf, onTap: (v) => setState(() => _tf = v)),
    const SizedBox(height: 16),
    _buildEntryTriggerCard(),
  ];

  List<Widget> _stocksSetupFields() => [
    _Label('Market'),
    _Chips(options: const ['NSE Equity', 'BSE Equity'], sel: _stockMarket, onTap: (v) => setState(() => _stockMarket = v)),
    const SizedBox(height: 16),
    _Label('Stock Symbol'),
    _StockSearchField(
      value: _stockSymbol, displayName: _stockName,
      onSelected: (inst) => setState(() { _stockSymbol = inst.symbol; _stockName = inst.name; }),
    ),
    const SizedBox(height: 16),
    _Label('Product Type'),
    _Chips(options: const ['Intraday', 'Delivery'], sel: _stockProduct, onTap: (v) => setState(() => _stockProduct = v)),
    const SizedBox(height: 16),
    _Label('Direction'),
    _Chips(options: const ['Long', 'Short'], sel: _stockStyle, onTap: (v) => setState(() => _stockStyle = v)),
    const SizedBox(height: 16),
    _Label('Time Frame'),
    _Chips(options: const ['1m', '3m', '5m', '15m', '1H', '1D', '1W'], sel: _stockTf, onTap: (v) => setState(() => _stockTf = v)),
    const SizedBox(height: 16),
    _buildEntryTriggerCard(),
  ];

  Widget _buildEntryTriggerCard() {
    final sym       = _stratType == _StratType.options ? _underlying : _stockSymbol;
    final livePrice = _liveSpot(sym);
    final hint      = livePrice > 0 ? livePrice.toStringAsFixed(0) : 'e.g. 24500';
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _K.surface, borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _K.primary.withValues(alpha: 0.35), width: 1.5),
        boxShadow: _K.shadow,
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(width: 32, height: 32, decoration: BoxDecoration(color: _K.primaryBg, borderRadius: BorderRadius.circular(9)),
            child: const Icon(Icons.bolt_rounded, color: _K.primary, size: 17)),
          const SizedBox(width: 10),
          const Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Entry Trigger', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: _K.t1)),
            Text('Engine checks this every minute', style: TextStyle(fontSize: 10, color: _K.t3)),
          ])),
          Container(padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
            decoration: BoxDecoration(color: _K.profit.withValues(alpha: 0.10), borderRadius: BorderRadius.circular(6)),
            child: const Text('REQUIRED', style: TextStyle(fontSize: 9, fontWeight: FontWeight.w800, color: _K.profit, letterSpacing: 0.5))),
        ]),
        const SizedBox(height: 12),
        Row(children: [
          Expanded(child: _TriggerTypeBtn(label: '↑ Above', sel: _entryTriggerType == 'above', onTap: () => setState(() => _entryTriggerType = 'above'))),
          const SizedBox(width: 8),
          Expanded(child: _TriggerTypeBtn(label: '↓ Below', sel: _entryTriggerType == 'below', onTap: () => setState(() => _entryTriggerType = 'below'))),
          const SizedBox(width: 8),
          Expanded(child: _TriggerTypeBtn(label: '⚡ Market', sel: _entryTriggerType == 'at_market', onTap: () => setState(() => _entryTriggerType = 'at_market'))),
        ]),
        if (_entryTriggerType != 'at_market') ...[
          const SizedBox(height: 12),
          _NumField(ctrl: _entryTriggerPriceCtrl, label: 'Trigger Price', hint: hint, prefix: '₹'),
        ] else ...[
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(color: _K.surfaceAlt, borderRadius: BorderRadius.circular(10)),
            child: const Row(children: [
              Icon(Icons.flash_on_rounded, size: 13, color: _K.warning), SizedBox(width: 6),
              Expanded(child: Text('Market order placed immediately when deployed.', style: TextStyle(fontSize: 11, color: _K.t2, height: 1.4))),
            ]),
          ),
        ],
      ]),
    );
  }

  // ════════════════════════════════════════════════════════════════════════════
  // SECTION 2 — CONDITIONS
  // ════════════════════════════════════════════════════════════════════════════
  Widget _conditionsContent() {
    final conds = _conds;
    final isOpt = _stratType == _StratType.options;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _SegBar(options: const ['Entry', 'Exit', 'Filters'], sel: _condTab, onChanged: (v) => setState(() => _condTab = v)),
      const SizedBox(height: 14),
      if (conds.isEmpty)
        _CondEmptyState(condTab: _condTab, onAdd: () => setState(() => conds.add(_Condition())))
      else ...[
        ...List.generate(conds.length, (i) {
          final isLast = i == conds.length - 1;
          return Column(children: [
            _CondRow(
              index: i, cond: conds[i],
              isOptions: _stratType == _StratType.options,
              strategyTf: _stratType == _StratType.options ? _tf : _stockTf,
              onDelete: conds.length > 1 ? () => setState(() => conds.removeAt(i)) : null,
              onChanged: (_) => setState(() {}),
            ),
            if (!isLast)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Center(
                  child: GestureDetector(
                    onTap: () => setState(() { conds[i].logic = conds[i].logic == 'AND' ? 'OR' : 'AND'; }),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
                      decoration: BoxDecoration(color: conds[i].logic == 'AND' ? _K.primary : _K.warning, borderRadius: BorderRadius.circular(20)),
                      child: Text(conds[i].logic, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: Colors.white, letterSpacing: 0.5)),
                    ),
                  ),
                ),
              ),
          ]);
        }),
        const SizedBox(height: 10),
        GestureDetector(
          onTap: () => setState(() => conds.add(_Condition())),
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 12),
            decoration: BoxDecoration(color: _K.primaryBg, borderRadius: BorderRadius.circular(12), border: Border.all(color: _K.primary.withValues(alpha: 0.3))),
            child: const Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              Icon(Icons.add_circle_rounded, color: _K.primary, size: 18), SizedBox(width: 6),
              Text('Add Condition', style: TextStyle(color: _K.primary, fontWeight: FontWeight.w700, fontSize: 13)),
            ]),
          ),
        ),
      ],
      if (isOpt) ...[
        const SizedBox(height: 16),
        _AdvPanel(
          selected: _advSel, expanded: _advExp,
          onToggleExpand: () => setState(() => _advExp = !_advExp),
          onToggleOpt: (o) => setState(() { if (_advSel.contains(o)) _advSel.remove(o); else _advSel.add(o); }),
        ),
      ],
    ]);
  }

  // ════════════════════════════════════════════════════════════════════════════
  // SECTION 3 — LEGS (Options)
  // ════════════════════════════════════════════════════════════════════════════
  Widget _legsContent2() {
    final spot    = _liveSpot(_underlying);
    final lotSize = _kLotSizes[_underlying] ?? 50.0;

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      // Legs tab bar: Legs | Payoff
      _SegBar(options: const ['Strategy Legs', 'Payoff'], sel: _legsTab, onChanged: (v) => setState(() => _legsTab = v)),
      const SizedBox(height: 14),
      if (_legsTab == 'Strategy Legs') ...[
        ...List.generate(_legs.length, (i) => _LegCard(
          index: i, leg: _legs[i], underlying: _underlying, setupExpiry: _expiry,
          onDelete: _legs.length > 1 ? () => setState(() => _legs.removeAt(i)) : null,
          onChanged: (_) => setState(() {}),
        )),
        const SizedBox(height: 8),
        GestureDetector(
          onTap: () => setState(() => _legs.add(_Leg(useSetupExpiry: true, expiry: _expiry))),
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 12),
            decoration: _K.card(),
            child: const Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              Icon(Icons.add_circle_outline_rounded, color: _K.primary, size: 18), SizedBox(width: 8),
              Text('Add Leg', style: TextStyle(color: _K.primary, fontWeight: FontWeight.w700, fontSize: 13)),
            ]),
          ),
        ),
        const SizedBox(height: 16),
        _Label('Order Type'),
        _Drop(value: _orderType, items: const ['Market Order', 'Limit Order', 'SL Order', 'SL-M Order'], onChanged: (v) => setState(() => _orderType = v!)),
        const SizedBox(height: 16),
        _Label('Position Sizing'),
        _Chips(options: const ['Fixed Lots', '% of Capital'], sel: _posSizing, onTap: (v) => setState(() => _posSizing = v)),
        const SizedBox(height: 12),
        _PositionSizingInputs(mode: _posSizing, lotsCtrl: _lotsCtrl, capitalCtrl: _capitalCtrl, pctCapCtrl: _pctCapCtrl, lotSize: _kLotSizes[_underlying] ?? 50, underlying: _underlying),
        const SizedBox(height: 14),
        _MarginEstimate(legs: _legs, underlying: _underlying, lots: int.tryParse(_lotsCtrl.text) ?? 1, lotSize: lotSize, spotPrice: spot),
      ],
      if (_legsTab == 'Payoff') _payoffContent(),
    ]);
  }

  Widget _payoffContent() {
    final spot    = _liveSpot(_underlying);
    final lotSize = _kLotSizes[_underlying] ?? 50.0;
    final pts     = _computePayoff(legs: _legs, spotPrice: spot, lotSize: lotSize);
    final maxPnl  = pts.map((p) => p.pnl).reduce(math.max);
    final minPnl  = pts.map((p) => p.pnl).reduce(math.min);
    final range   = (maxPnl - minPnl).abs().clamp(1.0, double.infinity);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        _PayoffMetric(label: 'Max Profit', value: maxPnl >= 1e9 ? 'Unlimited' : '₹${_fmt(maxPnl)}', color: maxPnl >= 0 ? _K.profit : _K.loss),
        const SizedBox(width: 12),
        _PayoffMetric(label: 'Max Loss', value: minPnl <= -1e9 ? 'Unlimited' : '₹${_fmt(minPnl)}', color: minPnl < 0 ? _K.loss : _K.profit),
      ]),
      const SizedBox(height: 16),
      Container(height: 200, padding: const EdgeInsets.all(16), decoration: _K.card(),
        child: CustomPaint(painter: _PayoffPainter(points: pts, minPnl: minPnl, range: range), child: const SizedBox.expand())),
      const SizedBox(height: 8),
      Center(child: Text('Spot range: ₹${_fmt(pts.first.spot)} – ₹${_fmt(pts.last.spot)}', style: const TextStyle(fontSize: 11, color: _K.t3))),
      const SizedBox(height: 16),
      ...List.generate(_legs.length, (i) {
        final l = _legs[i]; final g = _Greeks.estimate(l, _underlying);
        return Container(
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10), decoration: _K.card(),
          child: Row(children: [
            Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(color: l.side == 'Buy' ? _K.profitBg : _K.lossBg, borderRadius: BorderRadius.circular(6)),
              child: Text(l.side, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: l.side == 'Buy' ? _K.profit : _K.loss))),
            const SizedBox(width: 8),
            Expanded(child: Text('Leg ${i+1}: ${l.optType} ${l.strikeLabel}', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: _K.t1))),
            _GreekChip(label: 'Δ', value: g.delta.toStringAsFixed(2)), const SizedBox(width: 4),
            _GreekChip(label: 'θ', value: g.theta.toStringAsFixed(1)), const SizedBox(width: 4),
            _GreekChip(label: 'IV', value: '${g.iv.toStringAsFixed(1)}%'),
          ]),
        );
      }),
    ]);
  }

  // ════════════════════════════════════════════════════════════════════════════
  // SECTION 3 — POSITION (Stocks)
  // ════════════════════════════════════════════════════════════════════════════
  Widget _stockPositionContent() => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
    Container(
      padding: const EdgeInsets.all(14), decoration: _K.card(border: _K.primary.withValues(alpha: 0.2)),
      child: Row(children: [
        Container(width: 40, height: 40, decoration: BoxDecoration(color: _K.primaryBg, borderRadius: BorderRadius.circular(10)),
          child: const Center(child: Icon(Icons.bar_chart_rounded, color: _K.primary, size: 20))),
        const SizedBox(width: 12),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(_stockSymbol.isEmpty ? 'No symbol selected' : _stockSymbol, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: _K.t1)),
          Text(_stockName.isNotEmpty ? _stockName : '$_stockMarket · $_stockProduct', style: const TextStyle(fontSize: 11, color: _K.t3)),
        ])),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(color: _stockStyle == 'Long' ? _K.profitBg : _K.lossBg, borderRadius: BorderRadius.circular(8)),
          child: Text(_stockStyle == 'Long' ? '↑ Long' : '↓ Short', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: _stockStyle == 'Long' ? _K.profit : _K.loss)),
        ),
      ]),
    ),
    const SizedBox(height: 16),
    _Label('Order Type'),
    _Drop(value: _orderType, items: const ['Market Order', 'Limit Order', 'SL Order', 'SL-M Order'], onChanged: (v) => setState(() => _orderType = v!)),
    const SizedBox(height: 16),
    _Label('Position Sizing'),
    _Chips(options: const ['Fixed Shares', '% of Capital'], sel: _stockSizing, onTap: (v) => setState(() => _stockSizing = v)),
    const SizedBox(height: 12),
    _StockPositionSizingInputs(mode: _stockSizing, sharesCtrl: _sharesCtrl, capitalCtrl: _capitalCtrl, pctCapCtrl: _pctCapCtrl, symbol: _stockSymbol),
  ]);

  // ════════════════════════════════════════════════════════════════════════════
  // SECTION 4 — RISK & EXIT
  // ════════════════════════════════════════════════════════════════════════════
  Widget _riskContent() => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
    // SL + Target side by side at the top — QuantMan style
    Row(children: [
      Expanded(child: _NumField(ctrl: _slCtrl,  label: 'Stop Loss %',  hint: 'e.g. 50',  suffix: '%')),
      const SizedBox(width: 12),
      Expanded(child: _NumField(ctrl: _tgtCtrl, label: 'Target %',     hint: 'e.g. 100', suffix: '%')),
    ]),
    const SizedBox(height: 12),
    Row(children: [
      Expanded(child: _NumField(ctrl: _maxLossCtrl, label: 'Max Loss ₹', hint: 'e.g. 5000', prefix: '₹')),
      const SizedBox(width: 12),
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('Trailing SL', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: _K.t3)),
        const SizedBox(height: 4),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(color: _K.surfaceAlt, borderRadius: BorderRadius.circular(10), border: Border.all(color: _K.divider)),
          child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            const Text('Enabled', style: TextStyle(fontSize: 12, color: _K.t2)),
            SizedBox(height: 20, child: Switch.adaptive(value: _trailSl, onChanged: (v) => setState(() => _trailSl = v), activeColor: _K.primary)),
          ]),
        ),
      ])),
    ]),
    const SizedBox(height: 16),
    Divider(color: _K.divider),
    const SizedBox(height: 12),
    // Locked profit
    Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
      const Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('Locked Profit', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: _K.t1)),
        SizedBox(height: 2),
        Text('Lock a floor once a profit threshold is hit', style: TextStyle(fontSize: 11, color: _K.t3)),
      ]),
      Switch(
        value: _lockedProfitCtrl.text.isNotEmpty || _lockAtCtrl.text.isNotEmpty,
        onChanged: (v) => setState(() { if (!v) { _lockedProfitCtrl.clear(); _lockAtCtrl.clear(); } }),
        activeColor: _K.profit,
      ),
    ]),
    if (_lockedProfitCtrl.text.isNotEmpty || _lockAtCtrl.text.isNotEmpty) ...[
      const SizedBox(height: 10),
      Row(children: [
        Expanded(child: _NumField(ctrl: _lockAtCtrl,       label: 'Profit hits ₹',  hint: 'e.g. 6000', prefix: '₹')),
        const SizedBox(width: 12),
        Expanded(child: _NumField(ctrl: _lockedProfitCtrl, label: 'Lock minimum ₹', hint: 'e.g. 3000', prefix: '₹')),
      ]),
    ],
    const SizedBox(height: 16),
    Divider(color: _K.divider),
    const SizedBox(height: 12),
    // Time exit
    _Label('Square-off Time'),
    _Drop(
      value: _timeExit,
      items: const ['Square off at 3:15 PM', 'Square off at 3:00 PM', 'Square off at 2:30 PM', 'No time-based exit'],
      onChanged: (v) => setState(() => _timeExit = v!),
    ),
    const SizedBox(height: 16),
    // Trading schedule
    Row(children: [
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('Start Time', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: _K.t3)),
        const SizedBox(height: 4),
        _MiniDrop(value: _startTime, items: const ['09:15 AM', '09:20 AM', '09:30 AM', '10:00 AM', '10:30 AM', '11:00 AM'], onChanged: (v) => setState(() => _startTime = v!)),
      ])),
      const SizedBox(width: 12),
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('End Time', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: _K.t3)),
        const SizedBox(height: 4),
        _MiniDrop(value: _endTime, items: const ['01:00 PM', '02:00 PM', '02:30 PM', '03:00 PM', '03:15 PM'], onChanged: (v) => setState(() => _endTime = v!)),
      ])),
    ]),
    const SizedBox(height: 12),
    const Text('Trading Days', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: _K.t3)),
    const SizedBox(height: 8),
    Wrap(spacing: 8, runSpacing: 8, children: ['Mon', 'Tue', 'Wed', 'Thu', 'Fri'].map((day) {
      final sel = _tradingDays.contains(day);
      return GestureDetector(
        onTap: () => setState(() { if (sel) { if (_tradingDays.length > 1) _tradingDays.remove(day); } else _tradingDays.add(day); }),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          width: 48, height: 36,
          decoration: BoxDecoration(color: sel ? _K.primary : _K.surfaceAlt, borderRadius: BorderRadius.circular(10), border: Border.all(color: sel ? _K.primary : _K.divider)),
          child: Center(child: Text(day, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: sel ? Colors.white : _K.t2))),
        ),
      );
    }).toList()),
    const SizedBox(height: 16),
    Divider(color: _K.divider),
    const SizedBox(height: 12),
    // Paper trade
    Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
      const Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [Text('🧪 ', style: TextStyle(fontSize: 15)), Text('Paper Trade', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: _K.t1))]),
        SizedBox(height: 2),
        Text('Simulate without real orders', style: TextStyle(fontSize: 11, color: _K.t3)),
      ]),
      Switch(value: _paperTrade, onChanged: (v) => setState(() => _paperTrade = v), activeColor: const Color(0xFFD97706)),
    ]),
    const SizedBox(height: 16),
    Divider(color: _K.divider),
    const SizedBox(height: 12),
    // Re-entry
    Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
      const Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [Icon(Icons.replay_rounded, color: _K.primary, size: 15), SizedBox(width: 6), Text('Re-entry After Exit', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: _K.t1))]),
        SizedBox(height: 2),
        Text('Re-enter after SL or target hit', style: TextStyle(fontSize: 11, color: _K.t3)),
      ]),
      Switch(value: _reEntry, onChanged: (v) => setState(() => _reEntry = v), activeColor: _K.primary),
    ]),
    if (_reEntry) ...[
      const SizedBox(height: 12),
      _Chips(options: const ['Time-based', 'Signal-based'], sel: _reEntryMode, onTap: (v) => setState(() => _reEntryMode = v)),
      if (_reEntryMode == 'Time-based') ...[
        const SizedBox(height: 10),
        Row(children: [
          const Expanded(child: Text('Wait (minutes) before re-entering', style: TextStyle(fontSize: 11, color: _K.t3))),
          SizedBox(width: 70, child: _MiniField(hint: '30', initial: _reEntryWait, onChanged: (v) => setState(() => _reEntryWait = v))),
        ]),
      ],
    ],
  ]);

  // ════════════════════════════════════════════════════════════════════════════
  // SECTION 5 — BACKTEST
  // ════════════════════════════════════════════════════════════════════════════
  Widget _backtestContent() => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
    const Text('Period', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: _K.t3)),
    const SizedBox(height: 8),
    Wrap(spacing: 8, runSpacing: 8, children: ['1 Month', '3 Months', '6 Months', '1 Year', '2 Years'].map((r) {
      final sel = _btRange == r;
      return GestureDetector(
        onTap: () => setState(() { _btRange = r; _btResult = null; }),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
          decoration: BoxDecoration(color: sel ? _K.primary : _K.surfaceAlt, borderRadius: BorderRadius.circular(20), border: Border.all(color: sel ? _K.primary : _K.divider)),
          child: Text(r, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: sel ? Colors.white : _K.t2)),
        ),
      );
    }).toList()),
    const SizedBox(height: 14),
    _BacktestPanel(result: _btResult, running: _btRunning, onRun: _runBacktest),
  ]);

  // ── Helpers ────────────────────────────────────────────────────────────────
  String _fmt(double v) {
    final a = v.abs();
    if (a >= 100000) return '${(v / 100000).toStringAsFixed(1)}L';
    if (a >= 1000)   return '${(v / 1000).toStringAsFixed(1)}K';
    return v.toStringAsFixed(0);
  }

  // ── Fix 3: live spot price helper ─────────────────────────────────────────
  static const _kStaticSpot = {
    'NIFTY': 24500.0, 'BANKNIFTY': 52000.0, 'FINNIFTY': 23000.0,
    'MIDCPNIFTY': 12000.0, 'SENSEX': 80000.0,
  };
  double _liveSpot(String symbol) =>
      LivePriceService.instance.getPrice(symbol)?.ltp ??
      _kStaticSpot[symbol] ??
      24500.0;

} // end _CSS
// ─────────────────────────────────────────────────────────────────────────────
// Section card — collapsible section wrapper for the single-scroll layout
// ─────────────────────────────────────────────────────────────────────────────
class _SectionCard extends StatelessWidget {
  const _SectionCard({
    required this.title,
    required this.icon,
    required this.expanded,
    required this.onToggle,
    required this.child,
  });
  final String title;
  final IconData icon;
  final bool expanded;
  final VoidCallback onToggle;
  final Widget child;

  @override
  Widget build(BuildContext context) => Container(
    decoration: _K.card(),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      // Header — always visible, tapping collapses / expands
      InkWell(
        onTap: onToggle,
        borderRadius: expanded
            ? const BorderRadius.vertical(top: Radius.circular(16))
            : BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
          child: Row(children: [
            Container(
              width: 32, height: 32,
              decoration: BoxDecoration(color: _K.primaryBg, borderRadius: BorderRadius.circular(9)),
              child: Icon(icon, color: _K.primary, size: 17),
            ),
            const SizedBox(width: 12),
            Expanded(child: Text(title, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: _K.t1))),
            AnimatedRotation(
              turns: expanded ? 0.5 : 0,
              duration: const Duration(milliseconds: 200),
              child: const Icon(Icons.keyboard_arrow_down_rounded, color: _K.t3, size: 22),
            ),
          ]),
        ),
      ),
      // Body — animated show/hide
      AnimatedCrossFade(
        firstChild: const SizedBox.shrink(),
        secondChild: Column(children: [
          Divider(height: 1, color: _K.divider),
          Padding(padding: const EdgeInsets.fromLTRB(16, 14, 16, 16), child: child),
        ]),
        crossFadeState: expanded ? CrossFadeState.showSecond : CrossFadeState.showFirst,
        duration: const Duration(milliseconds: 220),
        sizeCurve: Curves.easeInOut,
      ),
    ]),
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// Strategy Type Selector widget (Options / Stocks cards)
// ─────────────────────────────────────────────────────────────────────────────
class _TypeSelector extends StatelessWidget {
  const _TypeSelector({required this.selected, required this.onChanged});
  final _StratType selected;
  final ValueChanged<_StratType> onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Text('Strategy Type', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: _K.t1)),
      const SizedBox(height: 10),
      Row(children: [
        Expanded(child: _TypeCard(
          type: _StratType.options,
          icon: '📊',
          title: 'Options',
          subtitle: 'F&O · Index · Multi-leg',
          selected: selected == _StratType.options,
          onTap: () => onChanged(_StratType.options),
        )),
        const SizedBox(width: 12),
        Expanded(child: _TypeCard(
          type: _StratType.stocks,
          icon: '🏢',
          title: 'Stocks',
          subtitle: 'Equity · Intraday · Delivery',
          selected: selected == _StratType.stocks,
          onTap: () => onChanged(_StratType.stocks),
        )),
      ]),
    ]);
  }
}

class _TypeCard extends StatelessWidget {
  const _TypeCard({required this.type, required this.icon, required this.title, required this.subtitle, required this.selected, required this.onTap});
  final _StratType type; final String icon, title, subtitle; final bool selected; final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: AnimatedContainer(
      duration: const Duration(milliseconds: 160),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: selected ? _K.primaryBg : _K.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: selected ? _K.primary : _K.divider, width: selected ? 2 : 1),
        boxShadow: selected ? null : _K.shadow,
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Text(icon, style: const TextStyle(fontSize: 22)),
          const Spacer(),
          if (selected)
            Container(
              width: 18, height: 18,
              decoration: const BoxDecoration(shape: BoxShape.circle, color: _K.primary),
              child: const Icon(Icons.check_rounded, size: 12, color: Colors.white),
            ),
        ]),
        const SizedBox(height: 8),
        Text(title, style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: selected ? _K.primary : _K.t1)),
        const SizedBox(height: 3),
        Text(subtitle, style: const TextStyle(fontSize: 10, color: _K.t3)),
      ]),
    ),
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// Async stock search field — queries price server /search-instruments,
// falls back to Firestore instrument_tokens
// ─────────────────────────────────────────────────────────────────────────────
class _StockSearchField extends StatefulWidget {
  const _StockSearchField({
    required this.value,
    required this.displayName,
    required this.onSelected,
  });
  final String value;          // currently selected symbol (shown in field)
  final String displayName;    // currently selected company name
  final ValueChanged<_StockInstrument> onSelected;

  @override
  State<_StockSearchField> createState() => _StockSearchFieldState();
}

class _StockSearchFieldState extends State<_StockSearchField> {
  late TextEditingController _ctrl;
  bool   _open    = false;
  bool   _loading = false;
  List<_StockInstrument> _results = [];
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    // Show selected symbol in the field; empty means "type to search"
    _ctrl = TextEditingController(
      text: widget.value.isNotEmpty ? widget.value : '',
    );
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _ctrl.dispose();
    super.dispose();
  }

  void _onTextChanged(String q) {
    _debounce?.cancel();
    if (q.trim().isEmpty) {
      setState(() { _open = false; _results = []; _loading = false; });
      return;
    }
    setState(() { _loading = true; _open = true; _results = []; });
    _debounce = Timer(const Duration(milliseconds: 350), () async {
      final res = await _searchStockInstruments(q);
      if (mounted) setState(() { _results = res; _loading = false; });
    });
  }

  void _select(_StockInstrument inst) {
    _ctrl.text = inst.symbol;
    widget.onSelected(inst);
    setState(() { _open = false; _results = []; });
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      // Input field
      Container(
        decoration: BoxDecoration(
          color: _K.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: _open ? _K.primary : _K.divider),
          boxShadow: _K.shadow,
        ),
        child: Row(children: [
          Expanded(child: TextField(
            controller: _ctrl,
            onChanged: _onTextChanged,
            onTap: () {
              if (_ctrl.text.isNotEmpty) _onTextChanged(_ctrl.text);
            },
            textCapitalization: TextCapitalization.characters,
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: _K.t1),
            decoration: InputDecoration(
              hintText: widget.value.isEmpty
                  ? 'Search symbol or company name…'
                  : widget.value,
              hintStyle: const TextStyle(fontSize: 13, color: _K.t3),
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              border: InputBorder.none,
            ),
          )),
          // Trailing: spinner or search icon
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: _loading
                ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: _K.primary))
                : const Icon(Icons.search_rounded, color: _K.t3, size: 18),
          ),
        ]),
      ),
      // Selected instrument chip (shown when a selection has been made)
      if (widget.value.isNotEmpty && !_open) ...[
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: _K.primaryBg,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: _K.primary.withValues(alpha: 0.25)),
          ),
          child: Row(children: [
            const Icon(Icons.check_circle_rounded, size: 14, color: _K.profit),
            const SizedBox(width: 8),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(widget.value, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: _K.t1)),
              if (widget.displayName.isNotEmpty)
                Text(widget.displayName, style: const TextStyle(fontSize: 11, color: _K.t3)),
            ])),
            GestureDetector(
              onTap: () {
                _ctrl.clear();
                widget.onSelected(const _StockInstrument(symbol: '', name: '', exchange: 'NSE'));
              },
              child: const Icon(Icons.close_rounded, size: 16, color: _K.t3),
            ),
          ]),
        ),
      ],
      // Results dropdown
      if (_open) ...[
        const SizedBox(height: 4),
        Container(
          constraints: const BoxConstraints(maxHeight: 240),
          decoration: BoxDecoration(
            color: _K.surface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: _K.divider),
            boxShadow: _K.shadow,
          ),
          child: _loading && _results.isEmpty
              ? const Padding(
                  padding: EdgeInsets.all(16),
                  child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                    SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: _K.primary)),
                    SizedBox(width: 10),
                    Text('Searching…', style: TextStyle(fontSize: 12, color: _K.t3)),
                  ]),
                )
              : _results.isEmpty
                  ? const Padding(
                      padding: EdgeInsets.all(16),
                      child: Text('No instruments found', style: TextStyle(fontSize: 12, color: _K.t3)),
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      shrinkWrap: true,
                      itemCount: _results.length,
                      separatorBuilder: (_, __) => Divider(height: 1, color: _K.divider),
                      itemBuilder: (_, i) {
                        final inst = _results[i];
                        return InkWell(
                          onTap: () => _select(inst),
                          borderRadius: BorderRadius.circular(8),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                            child: Row(children: [
                              Container(
                                width: 36, height: 36,
                                decoration: BoxDecoration(color: _K.primaryBg, borderRadius: BorderRadius.circular(8)),
                                child: Center(child: Text(
                                  inst.symbol.length > 3 ? inst.symbol.substring(0, 3) : inst.symbol,
                                  style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: _K.primary),
                                )),
                              ),
                              const SizedBox(width: 12),
                              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                Text(inst.symbol, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: _K.t1)),
                                if (inst.name.isNotEmpty && inst.name != inst.symbol)
                                  Text(inst.name, style: const TextStyle(fontSize: 11, color: _K.t3), maxLines: 1, overflow: TextOverflow.ellipsis),
                              ])),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                                decoration: BoxDecoration(color: _K.surfaceAlt, borderRadius: BorderRadius.circular(6), border: Border.all(color: _K.divider)),
                                child: Text(inst.exchange, style: const TextStyle(fontSize: 9, fontWeight: FontWeight.w700, color: _K.t2, letterSpacing: 0.3)),
                              ),
                            ]),
                          ),
                        );
                      },
                    ),
        ),
      ],
    ],
  );
}


// ─────────────────────────────────────────────────────────────────────────────
// Stock position sizing inputs
// ─────────────────────────────────────────────────────────────────────────────
class _StockPositionSizingInputs extends StatelessWidget {
  const _StockPositionSizingInputs({required this.mode, required this.sharesCtrl, required this.capitalCtrl, required this.pctCapCtrl, required this.symbol});
  final String mode, symbol;
  final TextEditingController sharesCtrl, capitalCtrl, pctCapCtrl;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(14), decoration: _K.card(),
    child: mode == 'Fixed Shares'
        ? Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            _NumField(ctrl: sharesCtrl, label: 'Number of Shares', hint: '10'),
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(color: _K.primaryBg, borderRadius: BorderRadius.circular(10)),
              child: Row(children: [
                const Icon(Icons.info_outline_rounded, size: 13, color: _K.primary),
                const SizedBox(width: 6),
                ValueListenableBuilder<TextEditingValue>(
                  valueListenable: sharesCtrl,
                  builder: (_, v, __) {
                    final qty = int.tryParse(v.text) ?? 0;
                    return Text('$qty shares of $symbol per trade', style: const TextStyle(fontSize: 11, color: _K.primary, fontWeight: FontWeight.w600));
                  },
                ),
              ]),
            ),
          ])
        : Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Expanded(child: _NumField(ctrl: pctCapCtrl, label: '% of Capital', hint: '5', suffix: '%')),
              const SizedBox(width: 12),
              Expanded(child: _NumField(ctrl: capitalCtrl, label: 'Total Capital', hint: '1,00,000', prefix: '₹')),
            ]),
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(color: _K.primaryBg, borderRadius: BorderRadius.circular(10)),
              child: Row(children: [
                const Icon(Icons.info_outline_rounded, size: 13, color: _K.primary),
                const SizedBox(width: 6),
                Expanded(child: Builder(builder: (_) {
                  final pct = double.tryParse(pctCapCtrl.text) ?? 5.0;
                  final cap = double.tryParse(capitalCtrl.text.replaceAll(',', '')) ?? 100000.0;
                  return Text('Approx ₹${(cap * pct / 100).toStringAsFixed(0)} per trade', style: const TextStyle(fontSize: 11, color: _K.primary, fontWeight: FontWeight.w600));
                })),
              ]),
            ),
          ]),
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// Options position sizing inputs
// ─────────────────────────────────────────────────────────────────────────────
class _PositionSizingInputs extends StatelessWidget {
  const _PositionSizingInputs({required this.mode, required this.lotsCtrl, required this.capitalCtrl, required this.pctCapCtrl, required this.lotSize, required this.underlying});
  final String mode, underlying;
  final TextEditingController lotsCtrl, capitalCtrl, pctCapCtrl;
  final double lotSize;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(14), decoration: _K.card(),
    child: mode == 'Fixed Lots'
        ? Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Expanded(child: _NumField(ctrl: lotsCtrl, label: 'Number of Lots', hint: '1')),
              const SizedBox(width: 12),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('Lot size', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: _K.t3)),
                const SizedBox(height: 4),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 13),
                  decoration: BoxDecoration(color: _K.surfaceAlt, borderRadius: BorderRadius.circular(10), border: Border.all(color: _K.divider)),
                  child: Text('${lotSize.toInt()} ($underlying)', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: _K.t2)),
                ),
              ])),
            ]),
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(color: _K.primaryBg, borderRadius: BorderRadius.circular(10)),
              child: Row(children: [
                const Icon(Icons.info_outline_rounded, size: 13, color: _K.primary),
                const SizedBox(width: 6),
                Expanded(child: ValueListenableBuilder<TextEditingValue>(
                  valueListenable: lotsCtrl,
                  builder: (_, v, __) {
                    final lots = int.tryParse(v.text) ?? 1;
                    return Text('Total qty: ${lots * lotSize.toInt()} units of $underlying', style: const TextStyle(fontSize: 11, color: _K.primary, fontWeight: FontWeight.w600));
                  },
                )),
              ]),
            ),
          ])
        : Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Expanded(child: _NumField(ctrl: pctCapCtrl, label: '% of Capital', hint: '5', suffix: '%')),
              const SizedBox(width: 12),
              Expanded(child: _NumField(ctrl: capitalCtrl, label: 'Total Capital', hint: '1,00,000', prefix: '₹')),
            ]),
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(color: _K.primaryBg, borderRadius: BorderRadius.circular(10)),
              child: Row(children: [
                const Icon(Icons.info_outline_rounded, size: 13, color: _K.primary),
                const SizedBox(width: 6),
                Expanded(child: Builder(builder: (_) {
                  final pct = double.tryParse(pctCapCtrl.text) ?? 5.0;
                  final cap = double.tryParse(capitalCtrl.text.replaceAll(',', '')) ?? 100000.0;
                  return Text('Approx allocated: ₹${(cap * pct / 100).toStringAsFixed(0)} per trade', style: const TextStyle(fontSize: 11, color: _K.primary, fontWeight: FontWeight.w600));
                })),
              ]),
            ),
          ]),
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// Backtest panel
// ─────────────────────────────────────────────────────────────────────────────
class _BacktestPanel extends StatelessWidget {
  const _BacktestPanel({required this.result, required this.running, required this.onRun});
  final _BacktestResult? result; final bool running; final VoidCallback onRun;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(16),
    decoration: _K.card(border: _K.primary.withValues(alpha: 0.2)),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Container(
          width: 36, height: 36,
          decoration: BoxDecoration(color: _K.primaryBg, borderRadius: BorderRadius.circular(10)),
          child: const Icon(Icons.analytics_rounded, color: _K.primary, size: 20),
        ),
        const SizedBox(width: 12),
        const Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Backtest', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: _K.t1)),
          Text('Simulate on real Angel One candle data', style: TextStyle(fontSize: 11, color: _K.t3)),
        ])),
        if (!running && result == null)
          GestureDetector(
            onTap: onRun,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(color: _K.primary, borderRadius: BorderRadius.circular(20)),
              child: const Text('Run', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: Colors.white)),
            ),
          ),
        if (running)
          const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2, color: _K.primary)),
        if (!running && result != null)
          GestureDetector(onTap: onRun, child: const Text('Re-run', style: TextStyle(fontSize: 12, color: _K.primary, fontWeight: FontWeight.w700))),
      ]),
      if (result != null) ...[
        const SizedBox(height: 16),
        SizedBox(height: 80, child: CustomPaint(painter: _EquityCurvePainter(curve: result!.equityCurve), child: const SizedBox.expand())),
        const SizedBox(height: 16),
        Row(children: [
          _BtMetric(label: 'Net P&L',  value: '₹${_fmtBt(result!.totalPnl)}',              color: result!.totalPnl >= 0 ? _K.profit : _K.loss),
          _BtMetric(label: 'Win Rate', value: '${result!.winRate.toStringAsFixed(1)}%',     color: result!.winRate >= 50 ? _K.profit : _K.warning),
          _BtMetric(label: 'Trades',   value: '${result!.totalTrades}',                    color: _K.t2),
          _BtMetric(label: 'Max DD',   value: '₹${_fmtBt(result!.maxDrawdown)}',           color: _K.loss),
        ]),
        if (result!.candleCount != null || result!.fromDate != null) ...[
          const SizedBox(height: 8),
          Row(children: [
            const Icon(Icons.bar_chart_rounded, size: 12, color: _K.t3), const SizedBox(width: 4),
            Expanded(child: Text(
              [
                if (result!.candleCount != null) '${result!.candleCount} bars',
                if (result!.interval != null) result!.interval!,
                if (result!.fromDate != null && result!.toDate != null)
                  '${result!.fromDate!.substring(0, 10)} → ${result!.toDate!.substring(0, 10)}',
              ].join('  ·  '),
              style: const TextStyle(fontSize: 10, color: _K.t3),
            )),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(color: _K.profitBg, borderRadius: BorderRadius.circular(4)),
              child: const Text('LIVE DATA', style: TextStyle(fontSize: 8, fontWeight: FontWeight.w800, color: _K.profit, letterSpacing: 0.5)),
            ),
          ]),
        ],
        const SizedBox(height: 10),
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(color: _K.surfaceAlt, borderRadius: BorderRadius.circular(10)),
          child: const Row(children: [
            Icon(Icons.info_outline_rounded, size: 13, color: _K.t3), SizedBox(width: 6),
            Expanded(child: Text('Simulated results. Past performance does not guarantee future returns.', style: TextStyle(fontSize: 10, color: _K.t3))),
          ]),
        ),
      ],
    ]),
  );

  static String _fmtBt(double v) {
    final a = v.abs(); final sign = v < 0 ? '-' : '';
    if (a >= 100000) return '$sign${(a / 100000).toStringAsFixed(1)}L';
    if (a >= 1000)   return '$sign${(a / 1000).toStringAsFixed(1)}K';
    return v.toStringAsFixed(0);
  }
}

class _BtMetric extends StatelessWidget {
  const _BtMetric({required this.label, required this.value, required this.color});
  final String label, value; final Color color;
  @override
  Widget build(BuildContext context) => Expanded(child: Column(children: [
    Text(value, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: color)),
    const SizedBox(height: 2),
    Text(label, style: const TextStyle(fontSize: 10, color: _K.t3)),
  ]));
}

// ─────────────────────────────────────────────────────────────────────────────
// Equity curve painter
// ─────────────────────────────────────────────────────────────────────────────
class _EquityCurvePainter extends CustomPainter {
  const _EquityCurvePainter({required this.curve});
  final List<double> curve;

  @override
  void paint(Canvas canvas, Size size) {
    if (curve.isEmpty) return;
    final minV  = curve.reduce(math.min);
    final maxV  = curve.reduce(math.max);
    final range = (maxV - minV).abs().clamp(1.0, double.infinity);
    final path  = Path(); final fillP = Path();
    final pts   = curve.asMap().entries.map((e) {
      final x = e.key / (curve.length - 1) * size.width;
      final y = size.height - ((e.value - minV) / range * size.height);
      return Offset(x, y);
    }).toList();
    path.moveTo(pts.first.dx, pts.first.dy);
    fillP.moveTo(0, size.height);
    fillP.lineTo(pts.first.dx, pts.first.dy);
    for (int i = 1; i < pts.length; i++) { path.lineTo(pts[i].dx, pts[i].dy); fillP.lineTo(pts[i].dx, pts[i].dy); }
    fillP.lineTo(size.width, size.height); fillP.close();
    final lineColor = curve.last >= 0 ? _K.profit : _K.loss;
    canvas.drawPath(fillP, Paint()..shader = LinearGradient(colors: [lineColor.withValues(alpha: 0.15), lineColor.withValues(alpha: 0.0)], begin: Alignment.topCenter, end: Alignment.bottomCenter).createShader(Offset.zero & size));
    canvas.drawPath(path, Paint()..color = lineColor..strokeWidth = 2..style = PaintingStyle.stroke..strokeCap = StrokeCap.round..strokeJoin = StrokeJoin.round);
    if (minV < 0 && maxV > 0) {
      final zeroY = size.height - ((0 - minV) / range * size.height);
      canvas.drawLine(Offset(0, zeroY), Offset(size.width, zeroY), Paint()..color = _K.t4..strokeWidth = 1..style = PaintingStyle.stroke);
    }
  }

  @override bool shouldRepaint(covariant CustomPainter old) => true;
}

// ─────────────────────────────────────────────────────────────────────────────
// Payoff diagram painter
// ─────────────────────────────────────────────────────────────────────────────
class _PayoffPainter extends CustomPainter {
  const _PayoffPainter({required this.points, required this.minPnl, required this.range});
  final List<_PayoffPoint> points; final double minPnl, range;

  @override
  void paint(Canvas canvas, Size size) {
    if (points.isEmpty) return;
    final path = Path(); final fPath = Path();
    final pts = points.asMap().entries.map((e) {
      final x = e.key / (points.length - 1) * size.width;
      final y = size.height - ((e.value.pnl - minPnl) / range * size.height);
      return Offset(x, y);
    }).toList();
    path.moveTo(pts.first.dx, pts.first.dy);
    fPath.moveTo(0, size.height); fPath.lineTo(pts.first.dx, pts.first.dy);
    for (int i = 1; i < pts.length; i++) {
      final prev = pts[i - 1]; final curr = pts[i];
      final cp1 = Offset((prev.dx + curr.dx) / 2, prev.dy); final cp2 = Offset((prev.dx + curr.dx) / 2, curr.dy);
      path.cubicTo(cp1.dx, cp1.dy, cp2.dx, cp2.dy, curr.dx, curr.dy);
      fPath.cubicTo(cp1.dx, cp1.dy, cp2.dx, cp2.dy, curr.dx, curr.dy);
    }
    fPath.lineTo(size.width, size.height); fPath.close();
    canvas.drawPath(fPath, Paint()..shader = const LinearGradient(colors: [Color(0x1A2563EB), Color(0x002563EB)], begin: Alignment.topCenter, end: Alignment.bottomCenter).createShader(Offset.zero & size));
    canvas.drawPath(path, Paint()..color = _K.primary..strokeWidth = 2.5..style = PaintingStyle.stroke..strokeCap = StrokeCap.round..strokeJoin = StrokeJoin.round);
    final zeroY = size.height - ((0 - minPnl) / range * size.height);
    canvas.drawLine(Offset(0, zeroY), Offset(size.width, zeroY), Paint()..color = _K.t4..strokeWidth = 1..style = PaintingStyle.stroke);
    final tpProfit = TextPainter(text: const TextSpan(text: 'Profit', style: TextStyle(fontSize: 9, color: _K.profit, fontWeight: FontWeight.w700)), textDirection: TextDirection.ltr)..layout();
    tpProfit.paint(canvas, Offset(4, zeroY - 14));
    final tpLoss = TextPainter(text: const TextSpan(text: 'Loss', style: TextStyle(fontSize: 9, color: _K.loss, fontWeight: FontWeight.w700)), textDirection: TextDirection.ltr)..layout();
    tpLoss.paint(canvas, Offset(4, zeroY + 4));
  }

  @override bool shouldRepaint(covariant CustomPainter old) => true;
}

// ─────────────────────────────────────────────────────────────────────────────
// Payoff metric tile
// ─────────────────────────────────────────────────────────────────────────────
class _PayoffMetric extends StatelessWidget {
  const _PayoffMetric({required this.label, required this.value, required this.color});
  final String label, value; final Color color;
  @override
  Widget build(BuildContext context) => Expanded(
    child: Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.06), borderRadius: BorderRadius.circular(12), border: Border.all(color: color.withValues(alpha: 0.15))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label, style: const TextStyle(fontSize: 10, color: _K.t3, fontWeight: FontWeight.w500)),
        const SizedBox(height: 4),
        Text(value, style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: color)),
      ]),
    ),
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// Greek chip
// ─────────────────────────────────────────────────────────────────────────────
class _GreekChip extends StatelessWidget {
  const _GreekChip({required this.label, required this.value});
  final String label, value;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
    decoration: BoxDecoration(color: _K.surfaceAlt, borderRadius: BorderRadius.circular(6), border: Border.all(color: _K.divider)),
    child: RichText(text: TextSpan(children: [
      TextSpan(text: '$label ', style: const TextStyle(fontSize: 9, color: _K.t3, fontWeight: FontWeight.w500)),
      TextSpan(text: value,    style: const TextStyle(fontSize: 10, color: _K.t1, fontWeight: FontWeight.w700)),
    ])),
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// Margin Estimate widget (uTrade feature)
// Heuristic approx margin — real SPAN margin requires broker API.
// Buy legs consume premium; sell legs require margin (NRML/MIS).
// ─────────────────────────────────────────────────────────────────────────────
class _MarginEstimate extends StatelessWidget {
  const _MarginEstimate({
    required this.legs,
    required this.underlying,
    required this.lots,
    required this.lotSize,
    required this.spotPrice,
  });
  final List<_Leg> legs;
  final String underlying;
  final int lots;
  final double lotSize;
  final double spotPrice; // live price, falls back to static in caller

  @override
  Widget build(BuildContext context) {
    if (legs.isEmpty) return const SizedBox.shrink();

    final spot     = spotPrice;
    final premium  = spot * 0.02;                      // ATM premium estimate
    final sellLegs = legs.where((l) => l.side == 'Sell').toList();
    final buyLegs  = legs.where((l) => l.side == 'Buy').toList();

    // Sell legs need margin: ~12–15% of notional for intraday (MIS)
    // Buy legs need only premium outflow
    double sellMargin = 0;
    for (final l in sellLegs) {
      sellMargin += spot * lotSize * l.qty * lots * 0.12; // ~12% SPAN approx
    }
    double premiumPaid = 0;
    for (final l in buyLegs) {
      premiumPaid += premium * lotSize * l.qty * lots;
    }
    // Hedged strategies get ~40% margin discount on sell legs
    final isHedged = buyLegs.isNotEmpty && sellLegs.isNotEmpty;
    if (isHedged) sellMargin *= 0.60;

    final totalMargin = sellMargin + premiumPaid;
    final misMargin   = totalMargin * 0.40; // MIS intraday ~40% of NRML

    String _fmt(double v) {
      if (v >= 100000) return '₹${(v / 100000).toStringAsFixed(1)}L';
      if (v >= 1000)   return '₹${(v / 1000).toStringAsFixed(1)}K';
      return '₹${v.toStringAsFixed(0)}';
    }

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [const Color(0xFF1E3A8A).withValues(alpha: 0.06), const Color(0xFF4F46E5).withValues(alpha: 0.04)],
          begin: Alignment.topLeft, end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _K.primary.withValues(alpha: 0.18)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(
            width: 32, height: 32,
            decoration: BoxDecoration(color: _K.primaryBg, borderRadius: BorderRadius.circular(8)),
            child: const Icon(Icons.account_balance_wallet_rounded, color: _K.primary, size: 16),
          ),
          const SizedBox(width: 10),
          const Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Approx Margin Required', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: _K.t1)),
            Text('Heuristic estimate · confirm with broker', style: TextStyle(fontSize: 10, color: _K.t3)),
          ])),
          if (isHedged)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
              decoration: BoxDecoration(color: _K.profitBg, borderRadius: BorderRadius.circular(6)),
              child: const Text('HEDGED\n−40%', textAlign: TextAlign.center, style: TextStyle(fontSize: 8, fontWeight: FontWeight.w800, color: _K.profit, height: 1.3)),
            ),
        ]),
        const SizedBox(height: 14),
        Row(children: [
          Expanded(child: _MarginTile(label: 'NRML', sublabel: 'Overnight', value: _fmt(totalMargin), color: _K.primary)),
          const SizedBox(width: 10),
          Expanded(child: _MarginTile(label: 'MIS',  sublabel: 'Intraday',  value: _fmt(misMargin),   color: _K.warning)),
        ]),
        const SizedBox(height: 10),
        Row(children: [
          const Icon(Icons.info_outline_rounded, size: 12, color: _K.t3),
          const SizedBox(width: 6),
          Expanded(child: Text(
            'Based on ${legs.length} leg${legs.length > 1 ? "s" : ""} · $lots lot${lots > 1 ? "s" : ""} · ${lotSize.toInt()} qty/lot. Actual SPAN margin may differ.',
            style: const TextStyle(fontSize: 10, color: _K.t3),
          )),
        ]),
      ]),
    );
  }
}

class _MarginTile extends StatelessWidget {
  const _MarginTile({required this.label, required this.sublabel, required this.value, required this.color});
  final String label, sublabel, value; final Color color;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
    decoration: BoxDecoration(color: color.withValues(alpha: 0.07), borderRadius: BorderRadius.circular(10), border: Border.all(color: color.withValues(alpha: 0.2))),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Text(label, style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: color, letterSpacing: 0.4)),
        const SizedBox(width: 4),
        Text(sublabel, style: const TextStyle(fontSize: 9, color: _K.t3)),
      ]),
      const SizedBox(height: 4),
      Text(value, style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: color)),
    ]),
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// Condition empty-state widget
// ─────────────────────────────────────────────────────────────────────────────
class _CondEmptyState extends StatelessWidget {
  const _CondEmptyState({required this.condTab, required this.onAdd});
  final String condTab;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    final isExit    = condTab == 'Exit';
    final isFilter  = condTab == 'Filters';
    final icon      = isExit ? Icons.logout_rounded : isFilter ? Icons.filter_list_rounded : Icons.add_chart_rounded;
    final title     = isExit
        ? 'No exit conditions set'
        : isFilter
            ? 'No filter conditions set'
            : 'No entry conditions set';
    final body = isExit
        ? 'The strategy will exit based on Stop-Loss / Target in Step 4.\nAdd a condition here for indicator-based exits (e.g. RSI > 70).'
        : isFilter
            ? 'Filters run before entry — useful for market regime checks (e.g. VIX < 20).'
            : 'Add at least one condition to define when the strategy should enter.';

    return Column(children: [
      Container(
        padding: const EdgeInsets.all(20),
        decoration: _K.card(),
        child: Column(children: [
          Container(
            width: 48, height: 48,
            decoration: BoxDecoration(color: _K.primaryBg, borderRadius: BorderRadius.circular(14)),
            child: Icon(icon, color: _K.primary, size: 22),
          ),
          const SizedBox(height: 12),
          Text(title, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: _K.t1)),
          const SizedBox(height: 6),
          Text(body, style: const TextStyle(fontSize: 12, color: _K.t3, height: 1.5), textAlign: TextAlign.center),
          const SizedBox(height: 16),
          GestureDetector(
            onTap: onAdd,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
              decoration: BoxDecoration(color: _K.primary, borderRadius: BorderRadius.circular(20)),
              child: const Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(Icons.add_circle_rounded, color: Colors.white, size: 16),
                SizedBox(width: 6),
                Text('Add Condition', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 13)),
              ]),
            ),
          ),
        ]),
      ),
    ]);
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Condition row
// ─────────────────────────────────────────────────────────────────────────────

/// Returns the parameter labels for a given indicator.
List<String> _indParams(String ind) {
  switch (ind) {
    case 'EMA':
    case 'SMA':              return ['Period'];
    case 'RSI':              return ['Period'];
    case 'MACD':             return ['Fast', 'Slow', 'Signal'];
    case 'Bollinger Bands':  return ['Period', 'Std Dev'];
    case 'Stochastic':       return ['%K Period', '%D Period'];
    case 'ADX':              return ['Period'];
    case 'ATR':              return ['Period'];
    case 'CCI':              return ['Period'];
    case 'Supertrend':       return ['Period', 'Multiplier'];
    case 'VWAP':             return [];          // no configurable params
    case 'Volume':           return [];
    case 'IV / IV Rank':
    case 'OI':
    case 'PCR':
    case 'Option Premium':   return [];
    default:                 return ['Period'];
  }
}

class _CondRow extends StatelessWidget {
  const _CondRow({
    required this.index,
    required this.cond,
    required this.isOptions,
    required this.strategyTf,
    this.onDelete,
    this.onChanged,
  });
  final int index;
  final _Condition cond;
  final bool isOptions;
  final String strategyTf;
  final VoidCallback? onDelete;
  final ValueChanged<_Condition>? onChanged;

  static const _indsOptions = [
    'EMA', 'SMA', 'RSI', 'MACD', 'Bollinger Bands', 'Stochastic',
    'ADX', 'ATR', 'Volume', 'VWAP', 'Option Premium', 'OI', 'PCR', 'IV / IV Rank',
  ];
  static const _indsStocks = [
    'EMA', 'SMA', 'RSI', 'MACD', 'Bollinger Bands', 'Stochastic',
    'ADX', 'ATR', 'Volume', 'VWAP', 'CCI', 'Supertrend',
  ];
  static const _priceFields  = ['Close', 'Open', 'High', 'Low', 'LTP', 'Volume'];
  static const _ops          = ['>', '<', '>=', '<=', '==', 'Crosses Above', 'Crosses Below'];
  static const _candleOptions = ['Current Candle', 'Previous Candle', '2 Candles Ago'];
  static const _tfOptions    = [
    'Same as strategy', '1min', '3min', '5min', '15min', '30min', '1hr', '1D',
  ];

  // ── RHS options depend on what the LHS indicator is ────────────────────────
  // Returns the dropdown items for the "Compare to" selector.
  // 'Value' is always first. Indicator options follow only when meaningful.
  static List<String> _rhsOptionsFor(String lhsType, String indicator, String lhsPrice) {
    if (lhsType == 'Price') {
      // Price field vs Value or trend indicator
      return ['Value', 'EMA', 'SMA', 'VWAP'];
    }
    switch (indicator) {
      // Oscillators — only sensible to compare to a numeric value
      case 'RSI':
      case 'Stochastic':
      case 'ADX':
      case 'CCI':
        return ['Value'];

      // Trend indicators — compare to Value or another MA
      case 'EMA':
      case 'SMA':
        return ['Value', 'EMA', 'SMA'];

      case 'VWAP':
        return ['Value', 'EMA', 'SMA', 'VWAP'];

      // Volume — compare to a number
      case 'Volume':
        return ['Value', 'Volume'];

      // MACD histogram — only numeric
      case 'MACD':
        return ['Value'];

      // Bollinger / ATR — numeric or EMA
      case 'Bollinger Bands':
      case 'ATR':
      case 'Supertrend':
        return ['Value', 'EMA', 'SMA'];

      // Options-specific — only numeric comparison makes sense
      case 'Option Premium':
      case 'OI':
      case 'PCR':
      case 'IV / IV Rank':
        return ['Value'];

      default:
        return ['Value', 'EMA', 'SMA'];
    }
  }

  // ── Context-aware value hint for the numeric RHS field ─────────────────────
  static String _valueHint(String lhsType, String indicator, String lhsPrice) {
    if (lhsType == 'Price') {
      return lhsPrice == 'Volume' ? 'e.g. 5000000' : 'e.g. 24500';
    }
    switch (indicator) {
      case 'RSI':              return '0 – 100 (e.g. 60)';
      case 'ADX':              return '0 – 100 (e.g. 25)';
      case 'CCI':              return 'e.g. 100 or -100';
      case 'Stochastic':       return '0 – 100 (e.g. 80)';
      case 'MACD':             return 'e.g. 0 (zero line)';
      case 'Bollinger Bands':  return 'e.g. 24500';
      case 'ATR':              return 'e.g. 100';
      case 'Volume':           return 'e.g. 5000000';
      case 'Option Premium':   return 'e.g. 100 (₹)';
      case 'OI':               return 'e.g. 1000000';
      case 'PCR':              return '0 – 2 (e.g. 1.2)';
      case 'IV / IV Rank':     return '0 – 100 (e.g. 50)';
      case 'Supertrend':       return 'e.g. 24500';
      case 'VWAP':             return 'e.g. 24500';
      default:                 return 'e.g. 50'; // EMA / SMA period value
    }
  }

  // ── Default period strings ──────────────────────────────────────────────────
  static String _defaultParam(String ind, int idx) {
    // Industry-standard defaults matching QuantMan / Streak / Sensibull
    // Index 0 = first param, 1 = second, 2 = third
    const defaults = <String, List<String>>{
      'EMA':             ['20', '50', ''],    // single period; '50' used when comparing EMA vs EMA
      'SMA':             ['20', '50', ''],
      'RSI':             ['14', '', ''],
      'MACD':            ['12', '26', '9'],   // Fast=12, Slow=26, Signal=9
      'Bollinger Bands': ['20', '2', ''],     // Period=20, Std Dev=2
      'Stochastic':      ['14', '3', ''],     // %K=14, %D=3
      'ADX':             ['14', '', ''],
      'ATR':             ['14', '', ''],
      'CCI':             ['20', '', ''],
      'Supertrend':      ['7',  '3', ''],     // Period=7, Multiplier=3
      'VWAP':            ['', '', ''],
      'Volume':          ['', '', ''],
      'OI':              ['', '', ''],
      'PCR':             ['', '', ''],
      'IV / IV Rank':    ['', '', ''],
      'Option Premium':  ['', '', ''],
    };
    final list = defaults[ind] ?? ['', '', ''];
    return idx < list.length ? list[idx] : '';
  }

  @override
  Widget build(BuildContext context) {
    final inds = isOptions ? _indsOptions : _indsStocks;

    // Guard: if current LHS indicator is invalid for strategy type, reset it
    if (cond.lhsType == 'Indicator' && !inds.contains(cond.indicator)) {
      cond.indicator = inds.first; cond.paramA = ''; cond.paramB = ''; cond.paramC = '';
    }
    final safeInd = inds.contains(cond.indicator) ? cond.indicator : inds.first;
    final params  = cond.lhsType == 'Indicator' ? _indParams(safeInd) : <String>[];

    // Compute valid RHS options for this LHS
    final rhsOptions = _rhsOptionsFor(cond.lhsType, safeInd, cond.lhsPrice);
    // If the stored RHS is no longer valid, snap to 'Value'
    final currentRhsInd = cond.rhsIsInd ? (cond.valueB.isEmpty ? rhsOptions.firstWhere((o) => o != 'Value', orElse: () => 'Value') : cond.valueB) : 'Value';
    final safeRhs = rhsOptions.contains(currentRhsInd) ? currentRhsInd : 'Value';
    if (safeRhs == 'Value' && cond.rhsIsInd) {
      // snap the model silently — can't call setState from build, mark via flag
      cond.rhsIsInd = false;
    }

    final isCross     = cond.op == 'Crosses Above' || cond.op == 'Crosses Below';
    final valueHint   = _valueHint(cond.lhsType, safeInd, cond.lhsPrice);

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: _K.card(),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [

        // ── Header: badge + LHS type toggle + delete ─────────────────────────
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
          child: Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
            Container(
              width: 24, height: 24,
              decoration: BoxDecoration(color: _K.primaryBg, borderRadius: BorderRadius.circular(6)),
              child: Center(child: Text('${index + 1}', style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: _K.primary))),
            ),
            const SizedBox(width: 8),
            _LhsTypeToggle(
              value: cond.lhsType,
              onChanged: (v) { cond.lhsType = v; onChanged?.call(cond); },
            ),
            const Spacer(),
            GestureDetector(
              onTap: onDelete,
              child: Icon(Icons.delete_outline_rounded, size: 18, color: onDelete != null ? _K.t3 : _K.t4),
            ),
          ]),
        ),

        Divider(height: 1, color: _K.divider),

        Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [

            // ── LHS ──────────────────────────────────────────────────────────
            if (cond.lhsType == 'Indicator') ...[
              _SectionLabel('Indicator'),
              const SizedBox(height: 4),
              _MiniDrop(value: safeInd, items: inds, onChanged: (v) {
                cond.indicator = v!;
                cond.paramA = _defaultParam(v, 0);
                cond.paramB = _defaultParam(v, 1);
                cond.paramC = _defaultParam(v, 2);
                // Reset RHS if it's no longer valid for the new indicator
                final newRhs = _rhsOptionsFor('Indicator', v, '');
                if (cond.rhsIsInd && !newRhs.contains(cond.valueB)) {
                  cond.rhsIsInd = false; cond.valueB = '';
                }
                onChanged?.call(cond);
              }),
              if (params.isNotEmpty) ...[
                const SizedBox(height: 8),
                Row(children: [
                  Expanded(child: _LabeledMiniField(
                    label: params[0],
                    hint: _defaultParam(safeInd, 0),
                    initial: cond.paramA,
                    onChanged: (v) { cond.paramA = v; onChanged?.call(cond); },
                  )),
                  if (params.length >= 2) ...[
                    const SizedBox(width: 8),
                    Expanded(child: _LabeledMiniField(
                      label: params[1],
                      hint: _defaultParam(safeInd, 1),
                      initial: cond.paramB,
                      onChanged: (v) { cond.paramB = v; onChanged?.call(cond); },
                    )),
                  ],
                  if (params.length >= 3) ...[
                    const SizedBox(width: 8),
                    Expanded(child: _LabeledMiniField(
                      label: params[2],
                      hint: _defaultParam(safeInd, 2),
                      initial: cond.paramC,
                      onChanged: (v) { cond.paramC = v; onChanged?.call(cond); },
                    )),
                  ],
                ]),
              ],
            ] else ...[
              _SectionLabel('Price Field'),
              const SizedBox(height: 4),
              _MiniDrop(
                value: _priceFields.contains(cond.lhsPrice) ? cond.lhsPrice : 'Close',
                items: _priceFields,
                onChanged: (v) { cond.lhsPrice = v!; onChanged?.call(cond); },
              ),
            ],

            const SizedBox(height: 10),

            // ── Candle + Timeframe ────────────────────────────────────────────
            Row(children: [
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                _SectionLabel('Candle'),
                const SizedBox(height: 4),
                _MiniDrop(
                  value: _candleOptions.contains(cond.candleSrc) ? cond.candleSrc : 'Current Candle',
                  items: _candleOptions,
                  onChanged: (v) { cond.candleSrc = v!; onChanged?.call(cond); },
                ),
              ])),
              const SizedBox(width: 8),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                _SectionLabel('Timeframe'),
                const SizedBox(height: 4),
                _MiniDrop(
                  value: cond.timeframe.isEmpty ? 'Same as strategy' : cond.timeframe,
                  items: _tfOptions,
                  onChanged: (v) {
                    cond.timeframe = (v == 'Same as strategy') ? '' : v!;
                    onChanged?.call(cond);
                  },
                ),
              ])),
            ]),

            if (cond.timeframe.isNotEmpty) ...[
              const SizedBox(height: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(color: _K.primaryBg, borderRadius: BorderRadius.circular(8)),
                child: Row(children: [
                  const Icon(Icons.schedule_rounded, size: 12, color: _K.primary),
                  const SizedBox(width: 6),
                  Expanded(child: Text(
                    'Evaluating on ${cond.timeframe} candles (strategy runs on $strategyTf)',
                    style: const TextStyle(fontSize: 10, color: _K.primary, height: 1.4),
                  )),
                ]),
              ),
            ],

            const SizedBox(height: 10),

            // ── Operator ─────────────────────────────────────────────────────
            _SectionLabel('Condition'),
            const SizedBox(height: 4),
            _MiniDrop(value: cond.op, items: _ops, onChanged: (v) { cond.op = v!; onChanged?.call(cond); }),

            if (isCross) ...[
              const SizedBox(height: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: _K.warning.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: _K.warning.withValues(alpha: 0.3)),
                ),
                child: Row(children: [
                  Icon(Icons.info_outline_rounded, size: 12, color: _K.warning),
                  const SizedBox(width: 6),
                  const Expanded(child: Text(
                    'Crossover checks current vs previous candle. Supported in backtest & advanced live mode.',
                    style: TextStyle(fontSize: 10, color: _K.warning, height: 1.4),
                  )),
                ]),
              ),
            ],

            const SizedBox(height: 10),

            // ── RHS: Compare to ───────────────────────────────────────────────
            _SectionLabel('Compare to'),
            const SizedBox(height: 4),
            Row(children: [
              // Type selector — only shows options valid for the chosen LHS
              Expanded(child: _MiniDrop(
                value: safeRhs,
                items: rhsOptions,
                onChanged: (v) {
                  cond.rhsIsInd = v != 'Value';
                  cond.valueB   = cond.rhsIsInd ? v! : '';
                  if (!cond.rhsIsInd) cond.paramC2 = '';
                  onChanged?.call(cond);
                },
              )),
              const SizedBox(width: 8),
              if (!cond.rhsIsInd) ...[
                // Numeric value — hint is indicator-aware
                Expanded(child: _MiniField(
                  hint: valueHint,
                  initial: cond.valueA,
                  onChanged: (v) { cond.valueA = v; onChanged?.call(cond); },
                )),
              ] else ...[
                // RHS indicator period
                Expanded(child: _LabeledMiniField(
                  label: 'Period',
                  hint: _defaultParam(cond.valueB, 0).isEmpty ? '20' : _defaultParam(cond.valueB, 0),
                  initial: cond.paramC2,
                  onChanged: (v) { cond.paramC2 = v; onChanged?.call(cond); },
                )),
              ],
            ]),
          ]),
        ),
      ]),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Small helper: section label inside a condition card
// ─────────────────────────────────────────────────────────────────────────────
class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);
  final String text;
  @override
  Widget build(BuildContext context) =>
    Text(text, style: const TextStyle(fontSize: 9, fontWeight: FontWeight.w700, color: _K.t3, letterSpacing: 0.4));
}

// ─────────────────────────────────────────────────────────────────────────────
// LHS type toggle: Indicator vs Price
// ─────────────────────────────────────────────────────────────────────────────
class _LhsTypeToggle extends StatelessWidget {
  const _LhsTypeToggle({required this.value, required this.onChanged});
  final String value;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 26,
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        color: _K.surfaceAlt,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: _K.divider),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        _ToggleSegment(label: '📈 Indicator', sel: value == 'Indicator', onTap: () => onChanged('Indicator')),
        const SizedBox(width: 2),
        _ToggleSegment(label: '💲 Price', sel: value == 'Price', onTap: () => onChanged('Price')),
      ]),
    );
  }
}

class _ToggleSegment extends StatelessWidget {
  const _ToggleSegment({required this.label, required this.sel, required this.onTap});
  final String label; final bool sel; final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: AnimatedContainer(
      duration: const Duration(milliseconds: 120),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: sel ? _K.primary : Colors.transparent,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(label, style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: sel ? Colors.white : _K.t2)),
    ),
  );
}

class _LabeledMiniField extends StatelessWidget {
  const _LabeledMiniField({required this.label, required this.hint, required this.initial, required this.onChanged});
  final String label, hint, initial; final ValueChanged<String> onChanged;
  @override
  Widget build(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
    Text(label, style: const TextStyle(fontSize: 9, fontWeight: FontWeight.w600, color: _K.t3)),
    const SizedBox(height: 3),
    _MiniField(hint: hint, initial: initial, onChanged: onChanged),
  ]);
}

// ─────────────────────────────────────────────────────────────────────────────
// Advanced options panel
// ─────────────────────────────────────────────────────────────────────────────
class _AdvPanel extends StatelessWidget {
  const _AdvPanel({required this.selected, required this.expanded, required this.onToggleExpand, required this.onToggleOpt});
  final Set<String> selected; final bool expanded;
  final VoidCallback onToggleExpand; final ValueChanged<String> onToggleOpt;

  static const _opts = [
    'Candle Pattern', 'Open Interest (OI)', 'Put Call Ratio (PCR)',
    'Greeks (Delta / Gamma / Theta)', 'IV / IV Rank', 'Option Chain Data Filter',
  ];

  @override
  Widget build(BuildContext context) => Container(
    decoration: _K.card(),
    child: Column(children: [
      InkWell(
        onTap: onToggleExpand, borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(children: [
            const Icon(Icons.settings_suggest_rounded, color: _K.primary, size: 18),
            const SizedBox(width: 10),
            const Expanded(child: Text('Advanced Options (Optional)', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: _K.t1))),
            Icon(expanded ? Icons.keyboard_arrow_up_rounded : Icons.keyboard_arrow_down_rounded, color: _K.t3),
          ]),
        ),
      ),
      if (expanded) ...[
        Divider(height: 1, color: _K.divider),
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 8, 14, 14),
          child: Column(children: _opts.map((o) {
            final sel = selected.contains(o);
            return InkWell(
              onTap: () => onToggleOpt(o),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Row(children: [
                  Container(
                    width: 20, height: 20,
                    decoration: BoxDecoration(color: sel ? _K.primary : Colors.transparent, borderRadius: BorderRadius.circular(5), border: Border.all(color: sel ? _K.primary : _K.t4, width: 1.5)),
                    child: sel ? const Icon(Icons.check_rounded, size: 13, color: Colors.white) : null,
                  ),
                  const SizedBox(width: 12),
                  Text(o, style: TextStyle(fontSize: 13, color: sel ? _K.t1 : _K.t2, fontWeight: sel ? FontWeight.w600 : FontWeight.w400)),
                ]),
              ),
            );
          }).toList()),
        ),
      ],
    ]),
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// Leg card
// ─────────────────────────────────────────────────────────────────────────────
class _LegCard extends StatelessWidget {
  const _LegCard({required this.index, required this.leg, required this.underlying, required this.setupExpiry, this.onDelete, this.onChanged});
  final int index; final _Leg leg; final String underlying, setupExpiry;
  final VoidCallback? onDelete; final ValueChanged<_Leg>? onChanged;
  static const _expiries = ['Current Week', 'Next Week', 'Monthly', 'Far Month'];

  @override
  Widget build(BuildContext context) {
    final isBuy   = leg.side == 'Buy';
    final greeks  = _Greeks.estimate(leg, underlying);
    const maxN    = 8;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14), decoration: _K.card(),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Text('Leg ${index+1}', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: _K.t1)),
          const SizedBox(width: 10),
          GestureDetector(
            onTap: () { leg.side = isBuy ? 'Sell' : 'Buy'; onChanged?.call(leg); },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(color: isBuy ? _K.profitBg : _K.lossBg, borderRadius: BorderRadius.circular(6)),
              child: Text(leg.side, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: isBuy ? _K.profit : _K.loss)),
            ),
          ),
          const Spacer(),
          _GreekChip(label: 'Δ', value: greeks.delta.toStringAsFixed(2)),
          const SizedBox(width: 4),
          _GreekChip(label: 'θ', value: greeks.theta.toStringAsFixed(1)),
          const SizedBox(width: 8),
          GestureDetector(onTap: onDelete, child: Icon(Icons.delete_outline_rounded, size: 18, color: onDelete != null ? _K.t3 : _K.t4)),
        ]),
        const SizedBox(height: 12),
        Row(children: [
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Option Type', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: _K.t3)),
            const SizedBox(height: 4),
            _MiniDrop(value: leg.optType, items: const ['Call', 'Put'], onChanged: (v) { leg.optType = v!; onChanged?.call(leg); }),
          ])),
          const SizedBox(width: 10),
          SizedBox(width: 110, child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Quantity (lots)', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: _K.t3)),
            const SizedBox(height: 4),
            _QtyCtr(
              value: leg.qty,
              onDec: leg.qty > 1 ? () { leg.qty--; onChanged?.call(leg); } : null,
              onInc: () { leg.qty++; onChanged?.call(leg); },
            ),
          ])),
        ]),
        const SizedBox(height: 12),
        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            const Text('Strike', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: _K.t3)),
            const Spacer(),
            _PillBtn(label: 'ATM+N', sel: leg.strikeMode == 'ATM+N', onTap: () { leg.strikeMode = 'ATM+N'; onChanged?.call(leg); }),
            const SizedBox(width: 6),
            _PillBtn(label: 'Delta', sel: leg.strikeMode == 'Delta',  onTap: () { leg.strikeMode = 'Delta'; onChanged?.call(leg); }),
          ]),
          const SizedBox(height: 8),
          if (leg.strikeMode == 'ATM+N') ...[
            Center(child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
              decoration: BoxDecoration(color: _K.primaryBg, borderRadius: BorderRadius.circular(20)),
              child: Text(leg.strikeLabel, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: _K.primary)),
            )),
            const SizedBox(height: 8),
            SliderTheme(
              data: SliderTheme.of(context).copyWith(
                activeTrackColor: _K.primary, thumbColor: _K.primary,
                inactiveTrackColor: _K.divider, overlayColor: _K.primary.withValues(alpha: 0.1),
                trackHeight: 3, thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 8),
              ),
              child: Slider(
                value: leg.strikeN.toDouble(), min: -maxN.toDouble(), max: maxN.toDouble(), divisions: maxN * 2,
                onChanged: (v) { leg.strikeN = v.round(); onChanged?.call(leg); },
              ),
            ),
            const Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              Text('ITM', style: TextStyle(fontSize: 9, color: _K.t3)),
              Text('ATM', style: TextStyle(fontSize: 9, color: _K.primary, fontWeight: FontWeight.w700)),
              Text('OTM', style: TextStyle(fontSize: 9, color: _K.t3)),
            ]),
          ] else ...[
            Row(children: [
              const Text('Target Delta (0.05 – 0.50)', style: TextStyle(fontSize: 11, color: _K.t3)),
              const Spacer(),
              SizedBox(width: 80, child: _MiniField(
                hint: '0.30', initial: leg.delta.toStringAsFixed(2),
                onChanged: (v) { leg.delta = (double.tryParse(v) ?? 0.30).clamp(0.05, 0.50); onChanged?.call(leg); },
              )),
            ]),
            const SizedBox(height: 6),
            Text('Approx strike: ATM ${leg.delta >= 0.50 ? "" : "+ ~${(0.50 - leg.delta).toStringAsFixed(2)} delta away"}', style: const TextStyle(fontSize: 10, color: _K.t3)),
          ],
        ]),
        const SizedBox(height: 12),
        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            const Text('Expiry', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: _K.t3)),
            const Spacer(),
            Row(children: [
              const Text('Follow setup', style: TextStyle(fontSize: 10, color: _K.t2)), const SizedBox(width: 6),
              GestureDetector(
                onTap: () { leg.useSetupExpiry = !leg.useSetupExpiry; if (leg.useSetupExpiry) leg.expiry = setupExpiry; onChanged?.call(leg); },
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  width: 36, height: 20,
                  decoration: BoxDecoration(color: leg.useSetupExpiry ? _K.primary : _K.divider, borderRadius: BorderRadius.circular(10)),
                  child: Align(
                    alignment: leg.useSetupExpiry ? Alignment.centerRight : Alignment.centerLeft,
                    child: Container(width: 16, height: 16, margin: const EdgeInsets.symmetric(horizontal: 2), decoration: const BoxDecoration(shape: BoxShape.circle, color: Colors.white)),
                  ),
                ),
              ),
            ]),
          ]),
          const SizedBox(height: 6),
          if (leg.useSetupExpiry)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(color: _K.primaryBg, borderRadius: BorderRadius.circular(10)),
              child: Row(children: [
                const Icon(Icons.link_rounded, size: 14, color: _K.primary), const SizedBox(width: 6),
                Text(setupExpiry, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: _K.primary)),
                const SizedBox(width: 4),
                const Text('(from setup)', style: TextStyle(fontSize: 10, color: _K.t3)),
              ]),
            )
          else
            _MiniDrop(value: leg.expiry, items: _expiries, onChanged: (v) { leg.expiry = v!; onChanged?.call(leg); }),
        ]),
      ]),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Trigger type button — used in the entry trigger card
// ─────────────────────────────────────────────────────────────────────────────
class _TriggerTypeBtn extends StatelessWidget {
  const _TriggerTypeBtn({required this.label, required this.sel, required this.onTap});
  final String label; final bool sel; final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: AnimatedContainer(
      duration: const Duration(milliseconds: 130),
      padding: const EdgeInsets.symmetric(vertical: 10),
      decoration: BoxDecoration(
        color: sel ? _K.primary : _K.surfaceAlt,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: sel ? _K.primary : _K.divider),
      ),
      child: Center(child: Text(label, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: sel ? Colors.white : _K.t2))),
    ),
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// Primitive widgets
// ─────────────────────────────────────────────────────────────────────────────

class _Label extends StatelessWidget {
  const _Label(this.text);
  final String text;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Text(text, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: _K.t1)),
  );
}

class _TxtInput extends StatelessWidget {
  const _TxtInput({required this.ctrl, required this.hint});
  final TextEditingController ctrl; final String hint;
  @override
  Widget build(BuildContext context) => Container(
    decoration: BoxDecoration(color: _K.surface, borderRadius: BorderRadius.circular(12), border: Border.all(color: _K.divider), boxShadow: _K.shadow),
    child: TextField(
      controller: ctrl,
      style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: _K.t1),
      decoration: InputDecoration(
        hintText: hint, hintStyle: const TextStyle(fontSize: 13, color: _K.t3),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        border: InputBorder.none,
      ),
    ),
  );
}

class _Chips extends StatelessWidget {
  const _Chips({required this.options, required this.sel, required this.onTap});
  final List<String> options; final String sel; final ValueChanged<String> onTap;
  @override
  Widget build(BuildContext context) => Wrap(
    spacing: 8, runSpacing: 8,
    children: options.map((o) {
      final s = o == sel;
      return GestureDetector(
        onTap: () => onTap(o),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 130),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
          decoration: BoxDecoration(
            color: s ? _K.primary : _K.surface, borderRadius: BorderRadius.circular(24),
            border: Border.all(color: s ? _K.primary : _K.divider, width: s ? 1.5 : 1),
            boxShadow: s ? null : _K.shadow,
          ),
          child: Text(o, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: s ? Colors.white : _K.t2)),
        ),
      );
    }).toList(),
  );
}

class _Drop extends StatelessWidget {
  const _Drop({required this.value, required this.items, required this.onChanged});
  final String value; final List<String> items; final ValueChanged<String?> onChanged;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
    decoration: BoxDecoration(color: _K.surface, borderRadius: BorderRadius.circular(12), border: Border.all(color: _K.divider), boxShadow: _K.shadow),
    child: DropdownButtonHideUnderline(child: DropdownButton<String>(
      value: value, isExpanded: true,
      icon: const Icon(Icons.keyboard_arrow_down_rounded, color: _K.t3, size: 18),
      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: _K.t1),
      onChanged: onChanged,
      items: items.map((e) => DropdownMenuItem(value: e, child: Text(e))).toList(),
    )),
  );
}

class _MiniDrop extends StatelessWidget {
  const _MiniDrop({required this.value, required this.items, required this.onChanged});
  final String value; final List<String> items; final ValueChanged<String?> onChanged;
  @override
  Widget build(BuildContext context) {
    final safe = items.contains(value) ? value : items.first;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(color: _K.surfaceAlt, borderRadius: BorderRadius.circular(8), border: Border.all(color: _K.divider)),
      child: DropdownButtonHideUnderline(child: DropdownButton<String>(
        value: safe, isExpanded: true, isDense: true,
        icon: const Icon(Icons.keyboard_arrow_down_rounded, color: _K.t3, size: 15),
        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: _K.t1),
        onChanged: onChanged,
        items: items.map((e) => DropdownMenuItem(value: e, child: Text(e))).toList(),
      )),
    );
  }
}

class _MiniField extends StatelessWidget {
  const _MiniField({required this.hint, this.initial = '', required this.onChanged});
  final String hint, initial; final ValueChanged<String> onChanged;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
    decoration: BoxDecoration(color: _K.surfaceAlt, borderRadius: BorderRadius.circular(8), border: Border.all(color: _K.divider)),
    child: TextFormField(
      initialValue: initial, onChanged: onChanged,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[\d.]'))],
      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: _K.t1),
      decoration: InputDecoration(hintText: hint, hintStyle: const TextStyle(fontSize: 12, color: _K.t3), isDense: true, contentPadding: EdgeInsets.zero, border: InputBorder.none),
    ),
  );
}

class _NumField extends StatelessWidget {
  const _NumField({required this.ctrl, required this.label, required this.hint, this.prefix, this.suffix});
  final TextEditingController ctrl; final String label, hint; final String? prefix, suffix;
  @override
  Widget build(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
    Text(label, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: _K.t3)),
    const SizedBox(height: 4),
    Container(
      decoration: BoxDecoration(color: _K.surfaceAlt, borderRadius: BorderRadius.circular(10), border: Border.all(color: _K.divider)),
      child: TextField(
        controller: ctrl,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[\d.]'))],
        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: _K.t1),
        decoration: InputDecoration(
          hintText: hint, hintStyle: const TextStyle(fontSize: 12, color: _K.t3),
          prefixText: prefix, suffixText: suffix,
          prefixStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: _K.t3),
          suffixStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: _K.t3),
          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          border: InputBorder.none,
        ),
      ),
    ),
  ]);
}

class _SegBar extends StatelessWidget {
  const _SegBar({required this.options, required this.sel, required this.onChanged});
  final List<String> options; final String sel; final ValueChanged<String> onChanged;
  @override
  Widget build(BuildContext context) => Container(
    height: 42, padding: const EdgeInsets.all(3),
    decoration: BoxDecoration(color: _K.surfaceAlt, borderRadius: BorderRadius.circular(12), border: Border.all(color: _K.divider)),
    child: Row(children: options.map((o) {
      final s = o == sel;
      return Expanded(child: GestureDetector(
        onTap: () => onChanged(o),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 130),
          decoration: BoxDecoration(color: s ? _K.primary : Colors.transparent, borderRadius: BorderRadius.circular(9)),
          child: Center(child: Text(o, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: s ? Colors.white : _K.t2))),
        ),
      ));
    }).toList()),
  );
}

class _PillBtn extends StatelessWidget {
  const _PillBtn({required this.label, required this.sel, required this.onTap});
  final String label; final bool sel; final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: AnimatedContainer(
      duration: const Duration(milliseconds: 120),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
      decoration: BoxDecoration(color: sel ? _K.primary : _K.surfaceAlt, borderRadius: BorderRadius.circular(20), border: Border.all(color: sel ? _K.primary : _K.divider)),
      child: Text(label, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: sel ? Colors.white : _K.t2)),
    ),
  );
}

class _QtyCtr extends StatelessWidget {
  const _QtyCtr({required this.value, this.onDec, required this.onInc});
  final int value; final VoidCallback? onDec, onInc;
  @override
  Widget build(BuildContext context) => Container(
    decoration: BoxDecoration(color: _K.surfaceAlt, borderRadius: BorderRadius.circular(8), border: Border.all(color: _K.divider)),
    child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
      GestureDetector(onTap: onDec, child: Padding(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8), child: Icon(Icons.remove_rounded, size: 14, color: onDec != null ? _K.t1 : _K.t4))),
      Text('$value', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: _K.t1)),
      GestureDetector(onTap: onInc, child: const Padding(padding: EdgeInsets.symmetric(horizontal: 8, vertical: 8), child: Icon(Icons.add_rounded, size: 14, color: _K.t1))),
    ]),
  );
}

class _PrimaryBtn extends StatelessWidget {
  const _PrimaryBtn({required this.label, required this.onTap, this.loading = false});
  final String label; final VoidCallback? onTap; final bool loading;
  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: Container(
      height: 48,
      decoration: BoxDecoration(
        color: onTap == null ? Colors.white.withValues(alpha: 0.2) : Colors.white.withValues(alpha: 0.22),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withValues(alpha: 0.35), width: 1.2),
      ),
      child: Center(child: loading
        ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
        : Text(label, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: Colors.white, letterSpacing: 0.1))),
    ),
  );
}

class _OutlineBtn extends StatelessWidget {
  const _OutlineBtn({required this.label, required this.onTap, this.dark = false});
  final String label; final VoidCallback onTap; final bool dark;
  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: Container(
      height: 48,
      decoration: BoxDecoration(
        color: dark ? Colors.white.withValues(alpha: 0.1) : _K.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: dark ? Colors.white.withValues(alpha: 0.18) : _K.divider, width: 1.5),
      ),
      child: Center(child: Text(label, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: dark ? Colors.white : _K.t2))),
    ),
  );
}
class _RChip extends StatelessWidget {
  const _RChip({required this.label, required this.color});
  final String label; final Color color;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
    decoration: BoxDecoration(color: color.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(20), border: Border.all(color: color.withValues(alpha: 0.2))),
    child: Text(label, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: color)),
  );
}
