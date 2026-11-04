// ─────────────────────────────────────────────────────────────────────────────
// Backtest Sheet — shared animated modal bottom sheet used in both
//   • UserStrategiesScreen  (strategy card "Backtest" button)
//   • CreateStrategyScreen  (Section 5 "Run Backtest" button)
//
// Opens via showBacktestSheet(), which returns the _BtResult when the user
// dismisses, so callers can persist it back to their own state.
// ─────────────────────────────────────────────────────────────────────────────
library;

import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../screens/backtest_result_screen.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Shared design tokens (neutral — works over both _K and _UT colour systems)
// ─────────────────────────────────────────────────────────────────────────────
abstract final class _C {
  static const surface  = Color(0xFFFFFFFF);
  static const surface2 = Color(0xFFF1F0EA);
  static const divider  = Color(0xFFE7E4DA);
  static const primary  = Color(0xFF2563EB);
  static const profit   = Color(0xFF0E7C6B);
  static const loss     = Color(0xFFD1483F);
  static const warning  = Color(0xFFBF7A16);
  static const info     = Color(0xFF2C6FB0);
  static const t1       = Color(0xFF14161D);
  static const t2       = Color(0xFF5B5D66);
  static const t3       = Color(0xFF9C9DA6);
}

// ─────────────────────────────────────────────────────────────────────────────
// Server URL — same env var used in create_strategy_screen
// ─────────────────────────────────────────────────────────────────────────────
const String _kBtUrl = String.fromEnvironment(
  'PRICE_SERVER_URL', defaultValue: 'http://31.172.87.141:3002',
);

// ─────────────────────────────────────────────────────────────────────────────
// BtTrade — one simulated trade returned by the server
// ─────────────────────────────────────────────────────────────────────────────
class BtTrade {
  final int    tradeNo;
  final String entryDate, exitDate, entryTime, exitTime;
  final double entryPrice, exitPrice, pnl, cumPnl;
  final String exitReason, result; // result: 'win' | 'loss' | 'breakeven'
  final int    duration;

  const BtTrade({
    required this.tradeNo,
    required this.entryDate,
    required this.exitDate,
    required this.entryTime,
    required this.exitTime,
    required this.entryPrice,
    required this.exitPrice,
    required this.pnl,
    required this.cumPnl,
    required this.exitReason,
    required this.result,
    required this.duration,
  });

  factory BtTrade.fromJson(Map<String, dynamic> j) => BtTrade(
    tradeNo:    (j['tradeNo']    as num?)?.toInt()    ?? 0,
    entryDate:  j['entryDate']  as String? ?? '',
    exitDate:   j['exitDate']   as String? ?? '',
    entryTime:  j['entryTime']  as String? ?? '',
    exitTime:   j['exitTime']   as String? ?? '',
    entryPrice: (j['entryPrice'] as num?)?.toDouble() ?? 0,
    exitPrice:  (j['exitPrice']  as num?)?.toDouble() ?? 0,
    pnl:        (j['pnl']        as num?)?.toDouble() ?? 0,
    cumPnl:     (j['cumPnl']     as num?)?.toDouble() ?? 0,
    exitReason: j['exitReason'] as String? ?? '',
    result:     j['result']     as String? ?? 'loss',
    duration:   (j['duration']  as num?)?.toInt()    ?? 0,
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// BtResult — the model returned to callers after a successful run
// ─────────────────────────────────────────────────────────────────────────────
class BtResult {
  // ── Core ──────────────────────────────────────────────────────────────────
  final double totalPnl, maxDrawdown, winRate;
  final int    totalTrades, winTrades;
  final List<double> equityCurve;
  final List<double> underlyingCurve;
  final String? interval, fromDate, toDate, source;
  final int?    candleCount;
  final String  range;

  // ── Extended analytics (server-computed) ──────────────────────────────────
  final double calmar;
  final double bookedProfit, bookedLoss;
  final double maxProfitDay, maxLossDay;
  final double avgProfitWinDays, avgLossLoseDays;
  final int    signals, winningDays, losingDays;
  final int    winStreak, lossStreak, maxTimeToRecover;

  // ── Trade log & monthly summary ────────────────────────────────────────────
  final List<BtTrade>      trades;
  final Map<String,double> monthlyPnl; // { 'YYYY-MM': pnl }

  const BtResult({
    required this.totalPnl,
    required this.totalTrades,
    required this.winTrades,
    required this.maxDrawdown,
    required this.winRate,
    required this.equityCurve,
    required this.underlyingCurve,
    required this.range,
    this.interval,
    this.candleCount,
    this.fromDate,
    this.toDate,
    this.source,
    this.calmar             = 0,
    this.bookedProfit       = 0,
    this.bookedLoss         = 0,
    this.maxProfitDay       = 0,
    this.maxLossDay         = 0,
    this.avgProfitWinDays   = 0,
    this.avgLossLoseDays    = 0,
    this.signals            = 0,
    this.winningDays        = 0,
    this.losingDays         = 0,
    this.winStreak          = 0,
    this.lossStreak         = 0,
    this.maxTimeToRecover   = 0,
    this.trades             = const [],
    this.monthlyPnl         = const {},
  });

  factory BtResult.fromJson(Map<String, dynamic> j, {required String range}) {
    List<double> _parseDoubles(String key) =>
        (j[key] as List<dynamic>? ?? [])
            .map((v) => (v as num).toDouble())
            .toList();

    final equity     = _parseDoubles('equityCurve');
    final underlying = _parseDoubles('underlyingCurve');

    // Monthly P&L map
    final rawMonthly = j['monthlyPnl'] as Map<String, dynamic>? ?? {};
    final monthly    = rawMonthly.map((k, v) => MapEntry(k, (v as num).toDouble()));

    // Trade list
    final rawTrades = (j['trades'] as List<dynamic>? ?? [])
        .cast<Map<String, dynamic>>()
        .map(BtTrade.fromJson)
        .toList();

    return BtResult(
      totalPnl:          (j['totalPnl']    as num?)?.toDouble() ?? 0,
      totalTrades:       (j['totalTrades'] as num?)?.toInt()    ?? 0,
      winTrades:         (j['winTrades']   as num?)?.toInt()    ?? 0,
      maxDrawdown:       (j['maxDrawdown'] as num?)?.toDouble() ?? 0,
      winRate:           (j['winRate']     as num?)?.toDouble() ?? 0,
      equityCurve:       equity.isEmpty ? [0.0, 0.0] : equity,
      underlyingCurve:   underlying.isEmpty ? [0.0, 0.0] : underlying,
      range:             range,
      interval:          j['interval']    as String?,
      candleCount:       (j['candleCount'] as num?)?.toInt(),
      fromDate:          j['fromDate']    as String?,
      toDate:            j['toDate']      as String?,
      source:            j['source']      as String?,
      calmar:            (j['calmar']           as num?)?.toDouble() ?? 0,
      bookedProfit:      (j['bookedProfit']      as num?)?.toDouble() ?? 0,
      bookedLoss:        (j['bookedLoss']        as num?)?.toDouble() ?? 0,
      maxProfitDay:      (j['maxProfitDay']      as num?)?.toDouble() ?? 0,
      maxLossDay:        (j['maxLossDay']        as num?)?.toDouble() ?? 0,
      avgProfitWinDays:  (j['avgProfitWinDays']  as num?)?.toDouble() ?? 0,
      avgLossLoseDays:   (j['avgLossLoseDays']   as num?)?.toDouble() ?? 0,
      signals:           (j['signals']           as num?)?.toInt()    ?? 0,
      winningDays:       (j['winningDays']       as num?)?.toInt()    ?? 0,
      losingDays:        (j['losingDays']        as num?)?.toInt()    ?? 0,
      winStreak:         (j['winStreak']          as num?)?.toInt()    ?? 0,
      lossStreak:        (j['lossStreak']         as num?)?.toInt()    ?? 0,
      maxTimeToRecover:  (j['maxTimeToRecover']  as num?)?.toInt()    ?? 0,
      trades:            rawTrades,
      monthlyPnl:        monthly,
    );
  }

  /// Format a monetary value compactly (e.g. 12500 → "12.5K").
  static String fmt(double v) {
    final a = v.abs();
    final sign = v < 0 ? '-' : '';
    if (a >= 100000) return '$sign${(a / 100000).toStringAsFixed(1)}L';
    if (a >= 1000)   return '$sign${(a / 1000).toStringAsFixed(1)}K';
    return v.toStringAsFixed(0);
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Public entry-point — open the sheet and await the result.
// Returns the BtResult if the user ran a successful backtest, null otherwise.
// ─────────────────────────────────────────────────────────────────────────────
Future<BtResult?> showBacktestSheet(
  BuildContext context, {
  required String strategyName,
  required Map<String, dynamic> payload,   // ready-to-POST backtest payload
  String initialRange = '3 Months',
  BtResult? existingResult,               // show a previous result immediately
}) {
  return showModalBottomSheet<BtResult>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    barrierColor: Colors.black.withValues(alpha: 0.55),
    useSafeArea: true,
    builder: (_) => BacktestSheet(
      strategyName:   strategyName,
      payload:        payload,
      initialRange:   initialRange,
      existingResult: existingResult,
    ),
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// BacktestSheet widget
// ─────────────────────────────────────────────────────────────────────────────
class BacktestSheet extends StatefulWidget {
  const BacktestSheet({
    super.key,
    required this.strategyName,
    required this.payload,
    this.initialRange = '3 Months',
    this.existingResult,
  });

  final String strategyName;
  final Map<String, dynamic> payload;  // base payload — range is injected per run
  final String initialRange;
  final BtResult? existingResult;

  @override
  State<BacktestSheet> createState() => _BacktestSheetState();
}

class _BacktestSheetState extends State<BacktestSheet>
    with TickerProviderStateMixin {

  static const _ranges = ['1 Month', '3 Months', '6 Months', '1 Year', '2 Years'];

  late String _range;
  bool    _running = false;
  BtResult? _result;
  String? _error;

  // Sheet entrance
  late final AnimationController _sheetCtrl;
  late final Animation<Offset>   _slideAnim;
  late final Animation<double>   _fadeAnim;

  // Equity curve draw-on
  late final AnimationController _curveCtrl;
  late final Animation<double>   _curveDraw;

  // Metrics fade-in
  late final AnimationController _metricsCtrl;
  late final Animation<double>   _metricsFade;

  @override
  void initState() {
    super.initState();
    _range  = widget.initialRange;
    _result = widget.existingResult;

    _sheetCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 380))
      ..forward();
    _curveCtrl   = AnimationController(vsync: this, duration: const Duration(milliseconds: 1200));
    _metricsCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 400));

    _slideAnim = Tween<Offset>(begin: const Offset(0, 0.12), end: Offset.zero)
        .animate(CurvedAnimation(parent: _sheetCtrl, curve: Curves.easeOutCubic));
    _fadeAnim = Tween<double>(begin: 0.0, end: 1.0)
        .animate(CurvedAnimation(parent: _sheetCtrl, curve: Curves.easeOut));
    _curveDraw = Tween<double>(begin: 0.0, end: 1.0)
        .animate(CurvedAnimation(parent: _curveCtrl, curve: Curves.easeInOutCubic));
    _metricsFade = Tween<double>(begin: 0.0, end: 1.0)
        .animate(CurvedAnimation(parent: _metricsCtrl, curve: Curves.easeOut));

    // If we already have a result from before, play animations immediately
    if (_result != null) {
      _curveCtrl.forward();
      _metricsCtrl.forward();
    }
  }

  @override
  void dispose() {
    _sheetCtrl.dispose();
    _curveCtrl.dispose();
    _metricsCtrl.dispose();
    super.dispose();
  }

  Future<void> _run() async {
    setState(() { _running = true; _result = null; _error = null; });
    _curveCtrl.reset();
    _metricsCtrl.reset();

    try {
      final user  = FirebaseAuth.instance.currentUser;
      final token = user != null ? await user.getIdToken(true) : null;

      final body = Map<String, dynamic>.from(widget.payload)..['range'] = _range;

      final res = await http
          .post(
            Uri.parse('$_kBtUrl/backtest'),
            headers: {
              'Content-Type': 'application/json',
              'Accept': 'application/json',
              if (token != null) 'Authorization': 'Bearer $token',
            },
            body: jsonEncode(body),
          )
          .timeout(const Duration(seconds: 60));

      if (!mounted) return;

      if (res.statusCode == 429) {
        setState(() => _error = 'Backtest already running — please wait.');
        return;
      }
      if (res.statusCode != 200) {
        String msg = 'Server error ${res.statusCode}';
        try {
          final b = jsonDecode(res.body) as Map<String, dynamic>;
          msg = b['error'] as String? ?? msg;
        } catch (_) {}
        setState(() => _error = msg);
        return;
      }

      final json = jsonDecode(res.body) as Map<String, dynamic>;
      if (json['success'] != true) {
        setState(() => _error = json['error'] as String? ?? 'Unknown error');
        return;
      }

      final result = BtResult.fromJson(json, range: _range);
      setState(() => _result = result);
      await _curveCtrl.forward();
      await _metricsCtrl.forward();
    } on TimeoutException {
      if (mounted) {
        setState(() => _error = 'Backtest timed out — try a shorter range or higher timeframe.');
      }
    } catch (e) {
      if (mounted) setState(() => _error = 'Error: $e');
    } finally {
      if (mounted) setState(() => _running = false);
    }
  }

  /// Pop the sheet, returning the latest result to the caller.
  void _close() => Navigator.of(context).pop(_result);

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _fadeAnim,
      child: SlideTransition(
        position: _slideAnim,
        child: Container(
          decoration: const BoxDecoration(
            color: _C.surface,
            borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // ── Drag handle ──────────────────────────────────────────
              const SizedBox(height: 12),
              Center(
                child: Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: _C.divider,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 16),

              // ── Header row ───────────────────────────────────────────
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Row(
                  children: [
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: _C.primary.withValues(alpha: 0.10),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(Icons.analytics_rounded, color: _C.primary, size: 22),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Backtest',
                            style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: _C.t1),
                          ),
                          Text(
                            widget.strategyName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 12, color: _C.t2),
                          ),
                        ],
                      ),
                    ),
                    GestureDetector(
                      onTap: _close,
                      child: Container(
                        width: 32,
                        height: 32,
                        decoration: BoxDecoration(
                          color: _C.surface2,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Icon(Icons.close_rounded, size: 18, color: _C.t2),
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 20),

              // ── Scrollable body ──────────────────────────────────────
              Flexible(
                child: SingleChildScrollView(
                  physics: const BouncingScrollPhysics(),
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 32),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Period chips
                      const Text(
                        'PERIOD',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          color: _C.t3,
                          letterSpacing: 0.8,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: _ranges.map((r) {
                          final sel = _range == r;
                          return GestureDetector(
                            onTap: () {
                              if (_running) return;
                              setState(() {
                                _range  = r;
                                _result = null;
                                _error  = null;
                              });
                              _curveCtrl.reset();
                              _metricsCtrl.reset();
                            },
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 140),
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                              decoration: BoxDecoration(
                                color: sel ? _C.primary : _C.surface2,
                                borderRadius: BorderRadius.circular(20),
                                border: Border.all(
                                  color: sel ? _C.primary : _C.divider,
                                ),
                              ),
                              child: Text(
                                r,
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                  color: sel ? Colors.white : _C.t2,
                                ),
                              ),
                            ),
                          );
                        }).toList(),
                      ),

                      const SizedBox(height: 20),

                      // State card
                      AnimatedSwitcher(
                        duration: const Duration(milliseconds: 300),
                        transitionBuilder: (child, anim) => FadeTransition(
                          opacity: anim,
                          child: SlideTransition(
                            position: Tween<Offset>(
                              begin: const Offset(0, 0.06),
                              end: Offset.zero,
                            ).animate(anim),
                            child: child,
                          ),
                        ),
                        child: _running
                            ? _buildLoadingCard()
                            : _error != null
                                ? _buildErrorCard()
                                : _result == null
                                    ? _buildIdleCard()
                                    : _buildResultCard(),
                      ),

                      const SizedBox(height: 16),

                      // Disclaimer
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: _C.surface2,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Icon(Icons.info_outline_rounded, size: 14, color: _C.t3),
                            SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                'Simulated results. Past performance does not guarantee future returns.',
                                style: TextStyle(fontSize: 11, color: _C.t3, height: 1.4),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── Idle ────────────────────────────────────────────────────────────────────
  Widget _buildIdleCard() => Container(
    key: const ValueKey('idle'),
    padding: const EdgeInsets.all(24),
    decoration: BoxDecoration(
      color: _C.primary.withValues(alpha: 0.04),
      borderRadius: BorderRadius.circular(20),
      border: Border.all(color: _C.primary.withValues(alpha: 0.18)),
    ),
    child: Column(
      children: [
        Container(
          width: 56,
          height: 56,
          decoration: BoxDecoration(
            color: _C.primary.withValues(alpha: 0.10),
            shape: BoxShape.circle,
          ),
          child: const Icon(Icons.play_circle_outline_rounded, color: _C.primary, size: 28),
        ),
        const SizedBox(height: 14),
        const Text(
          'Run Backtest',
          style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: _C.t1),
        ),
        const SizedBox(height: 6),
        const Text(
          'Simulate this strategy on real Angel One candle data',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 12, color: _C.t2, height: 1.4),
        ),
        const SizedBox(height: 20),
        GestureDetector(
          onTap: _run,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 13),
            decoration: BoxDecoration(
              color: _C.primary,
              borderRadius: BorderRadius.circular(14),
              boxShadow: [
                BoxShadow(
                  color: _C.primary.withValues(alpha: 0.30),
                  blurRadius: 16,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.bolt_rounded, color: Colors.white, size: 18),
                SizedBox(width: 8),
                Text(
                  'Run Backtest',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: Colors.white),
                ),
              ],
            ),
          ),
        ),
      ],
    ),
  );

  // ── Loading ─────────────────────────────────────────────────────────────────
  Widget _buildLoadingCard() => Container(
    key: const ValueKey('loading'),
    padding: const EdgeInsets.all(32),
    decoration: BoxDecoration(
      color: _C.surface,
      borderRadius: BorderRadius.circular(20),
      border: Border.all(color: _C.divider),
    ),
    child: Column(
      children: [
        _PulsingRingLoader(color: _C.primary),
        const SizedBox(height: 20),
        const Text(
          'Running backtest…',
          style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: _C.t1),
        ),
        const SizedBox(height: 6),
        const Text(
          'Fetching candle data and simulating trades',
          style: TextStyle(fontSize: 12, color: _C.t2),
        ),
      ],
    ),
  );

  // ── Error ────────────────────────────────────────────────────────────────────
  Widget _buildErrorCard() => Container(
    key: const ValueKey('error'),
    padding: const EdgeInsets.all(20),
    decoration: BoxDecoration(
      color: _C.loss.withValues(alpha: 0.05),
      borderRadius: BorderRadius.circular(20),
      border: Border.all(color: _C.loss.withValues(alpha: 0.25)),
    ),
    child: Column(
      children: [
        const Icon(Icons.error_outline_rounded, color: _C.loss, size: 32),
        const SizedBox(height: 12),
        Text(
          _error ?? 'Unknown error',
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 13, color: _C.t1, height: 1.4),
        ),
        const SizedBox(height: 16),
        GestureDetector(
          onTap: _run,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 10),
            decoration: BoxDecoration(
              color: _C.surface2,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: _C.divider),
            ),
            child: const Text(
              'Try again',
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: _C.t1),
            ),
          ),
        ),
      ],
    ),
  );

  // ── Result ──────────────────────────────────────────────────────────────────
  Widget _buildResultCard() {
    final r = _result!;
    final isProfit = r.totalPnl >= 0;
    final pnlColor = isProfit ? _C.profit : _C.loss;

    return Container(
      key: const ValueKey('result'),
      decoration: BoxDecoration(
        color: _C.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: _C.divider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Hero P&L
          Container(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
            decoration: BoxDecoration(
              color: pnlColor.withValues(alpha: 0.06),
              borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
            ),
            child: Row(
              children: [
                FadeTransition(
                  opacity: _metricsFade,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${isProfit ? '+' : ''}₹${BtResult.fmt(r.totalPnl)}',
                        style: TextStyle(
                          fontSize: 28,
                          fontWeight: FontWeight.w900,
                          color: pnlColor,
                          letterSpacing: -0.5,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Net P&L  ·  ${r.range}',
                        style: const TextStyle(fontSize: 12, color: _C.t2),
                      ),
                    ],
                  ),
                ),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: pnlColor.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    isProfit ? '✓ Profitable' : '✗ Loss',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                      color: pnlColor,
                    ),
                  ),
                ),
              ],
            ),
          ),

          // Equity curve
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'EQUITY CURVE',
                  style: TextStyle(
                    fontSize: 9.5,
                    fontWeight: FontWeight.w700,
                    color: _C.t3,
                    letterSpacing: 0.8,
                  ),
                ),
                const SizedBox(height: 8),
                SizedBox(
                  height: 100,
                  child: AnimatedBuilder(
                    animation: _curveDraw,
                    builder: (_, __) => CustomPaint(
                      painter: BtEquityCurvePainter(
                        curve:     r.equityCurve,
                        animValue: _curveDraw.value,
                      ),
                      child: const SizedBox.expand(),
                    ),
                  ),
                ),
                if (r.fromDate != null && r.toDate != null) ...[
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      const Icon(Icons.date_range_rounded, size: 11, color: _C.t3),
                      const SizedBox(width: 4),
                      Text(
                        '${r.fromDate!.substring(0, 10)} → ${r.toDate!.substring(0, 10)}',
                        style: const TextStyle(fontSize: 10, color: _C.t3),
                      ),
                      if (r.candleCount != null) ...[
                        const SizedBox(width: 6),
                        const Text('·', style: TextStyle(fontSize: 10, color: _C.t3)),
                        const SizedBox(width: 6),
                        Text('${r.candleCount} bars', style: const TextStyle(fontSize: 10, color: _C.t3)),
                      ],
                      const Spacer(),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: _C.profit.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: const Text(
                          'LIVE DATA',
                          style: TextStyle(
                            fontSize: 8,
                            fontWeight: FontWeight.w800,
                            color: _C.profit,
                            letterSpacing: 0.5,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),

          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16),
            child: Divider(color: _C.divider, height: 24),
          ),

          // 2×2 metric grid
          FadeTransition(
            opacity: _metricsFade,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
              child: Column(
                children: [
                  Row(
                    children: [
                      _MetricTile(
                        label: 'Win Rate',
                        value: '${r.winRate.toStringAsFixed(1)}%',
                        icon: Icons.emoji_events_rounded,
                        color: r.winRate >= 50 ? _C.profit : _C.warning,
                      ),
                      const SizedBox(width: 10),
                      _MetricTile(
                        label: 'Total Trades',
                        value: '${r.totalTrades}',
                        icon: Icons.swap_horiz_rounded,
                        color: _C.info,
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      _MetricTile(
                        label: 'Wins',
                        value: '${r.winTrades}',
                        icon: Icons.trending_up_rounded,
                        color: _C.profit,
                      ),
                      const SizedBox(width: 10),
                      _MetricTile(
                        label: 'Max Drawdown',
                        value: '₹${BtResult.fmt(r.maxDrawdown)}',
                        icon: Icons.trending_down_rounded,
                        color: _C.loss,
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),

          // View Full Analysis button
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
            child: GestureDetector(
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => BacktestResultScreen(
                    result:       r,
                    strategyName: widget.strategyName,
                  ),
                ),
              ),
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 13),
                decoration: BoxDecoration(
                  color: _C.primary,
                  borderRadius: BorderRadius.circular(14),
                  boxShadow: [
                    BoxShadow(
                      color: _C.primary.withValues(alpha: 0.25),
                      blurRadius: 14,
                      offset: const Offset(0, 5),
                    ),
                  ],
                ),
                child: const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.bar_chart_rounded, size: 17, color: Colors.white),
                    SizedBox(width: 8),
                    Text(
                      'View Full Analysis',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                        color: Colors.white,
                      ),
                    ),
                    SizedBox(width: 6),
                    Icon(Icons.arrow_forward_rounded, size: 14, color: Colors.white),
                  ],
                ),
              ),
            ),
          ),

          // Re-run
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
            child: GestureDetector(
              onTap: _run,
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 12),
                decoration: BoxDecoration(
                  color: _C.surface2,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: _C.divider),
                ),
                child: const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.refresh_rounded, size: 16, color: _C.t2),
                    SizedBox(width: 6),
                    Text(
                      'Re-run',
                      style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: _C.t2),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// BtEquityCurvePainter — animated draw-on curve
// ─────────────────────────────────────────────────────────────────────────────
class BtEquityCurvePainter extends CustomPainter {
  const BtEquityCurvePainter({required this.curve, this.animValue = 1.0});
  final List<double> curve;
  final double animValue; // 0→1, controls how many points are drawn

  @override
  void paint(Canvas canvas, Size size) {
    if (curve.isEmpty) return;
    final minV  = curve.reduce(math.min);
    final maxV  = curve.reduce(math.max);
    final range = (maxV - minV).abs().clamp(1.0, double.infinity);

    final drawCount = ((curve.length - 1) * animValue).round() + 1;
    final pts = <Offset>[];
    for (int i = 0; i < drawCount && i < curve.length; i++) {
      final x = i / (curve.length - 1) * size.width;
      final y = size.height - ((curve[i] - minV) / range * size.height);
      pts.add(Offset(x, y));
    }
    if (pts.length < 2) return;

    final lineColor = curve.last >= 0 ? _C.profit : _C.loss;

    // Fill
    final fillPath = Path()
      ..moveTo(0, size.height)
      ..lineTo(pts.first.dx, pts.first.dy);
    for (final p in pts.skip(1)) fillPath.lineTo(p.dx, p.dy);
    fillPath
      ..lineTo(pts.last.dx, size.height)
      ..close();

    canvas.drawPath(
      fillPath,
      Paint()
        ..shader = LinearGradient(
          colors: [lineColor.withValues(alpha: 0.20), lineColor.withValues(alpha: 0.0)],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        ).createShader(Offset.zero & size),
    );

    // Line
    final linePath = Path()..moveTo(pts.first.dx, pts.first.dy);
    for (final p in pts.skip(1)) linePath.lineTo(p.dx, p.dy);
    canvas.drawPath(
      linePath,
      Paint()
        ..color = lineColor
        ..strokeWidth = 2.5
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );

    // Zero baseline
    if (minV < 0 && maxV > 0) {
      final zeroY = size.height - ((0 - minV) / range * size.height);
      canvas.drawLine(
        Offset(0, zeroY), Offset(size.width, zeroY),
        Paint()
          ..color = _C.t3.withValues(alpha: 0.5)
          ..strokeWidth = 1
          ..style = PaintingStyle.stroke,
      );
    }

    // Animated leading dot
    if (animValue < 1.0) {
      final last = pts.last;
      canvas.drawCircle(last, 4, Paint()..color = lineColor);
      canvas.drawCircle(
        last, 4,
        Paint()
          ..color = Colors.white
          ..strokeWidth = 1.5
          ..style = PaintingStyle.stroke,
      );
    }
  }

  @override
  bool shouldRepaint(covariant BtEquityCurvePainter old) =>
      old.animValue != animValue || old.curve != curve;
}

// ─────────────────────────────────────────────────────────────────────────────
// Private helpers
// ─────────────────────────────────────────────────────────────────────────────

class _MetricTile extends StatelessWidget {
  const _MetricTile({
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
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: color.withValues(alpha: 0.18)),
        ),
        child: Row(
          children: [
            Container(
              width: 30,
              height: 30,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(icon, color: color, size: 16),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    value,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                      color: color,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                  Text(
                    label,
                    style: const TextStyle(fontSize: 10, color: _C.t3, height: 1.2),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PulsingRingLoader extends StatefulWidget {
  const _PulsingRingLoader({required this.color});
  final Color color;

  @override
  State<_PulsingRingLoader> createState() => _PulsingRingLoaderState();
}

class _PulsingRingLoaderState extends State<_PulsingRingLoader>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _scale;
  late Animation<double> _opacity;

  @override
  void initState() {
    super.initState();
    _ctrl    = AnimationController(vsync: this, duration: const Duration(milliseconds: 900))..repeat();
    _scale   = Tween<double>(begin: 0.7, end: 1.4).animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut));
    _opacity = Tween<double>(begin: 0.8, end: 0.0).animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeIn));
  }

  @override
  void dispose() { _ctrl.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 60,
      height: 60,
      child: Stack(alignment: Alignment.center, children: [
        AnimatedBuilder(
          animation: _ctrl,
          builder: (_, __) => Transform.scale(
            scale: _scale.value,
            child: Opacity(
              opacity: _opacity.value,
              child: Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: widget.color, width: 2),
                ),
              ),
            ),
          ),
        ),
        Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: widget.color.withValues(alpha: 0.12),
          ),
          child: Icon(Icons.analytics_rounded, color: widget.color, size: 18),
        ),
      ]),
    );
  }
}
