// ─────────────────────────────────────────────────────────────────────────────
// BacktestResultScreen — full uTrade-style backtest analytics
// Three tabs: Analysis · Transactions · Reports
// ─────────────────────────────────────────────────────────────────────────────
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../widgets/backtest_sheet.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Design tokens
// ─────────────────────────────────────────────────────────────────────────────
abstract final class _K {
  static const bg       = Color(0xFFF4F6FB);
  static const surface  = Color(0xFFFFFFFF);
  static const surface2 = Color(0xFFF0F3FA);
  static const divider  = Color(0xFFE4E8F2);
  static const primary  = Color(0xFF2563EB);
  static const primaryBg = Color(0xFFEEF3FE);
  static const profit   = Color(0xFF16A34A);
  static const loss     = Color(0xFFDC2626);
  static const warning  = Color(0xFFD97706);
  static const neutral  = Color(0xFF64748B);
  static const t1       = Color(0xFF0F172A);
  static const t2       = Color(0xFF475569);
  static const t3       = Color(0xFF94A3B8);
  static const t4       = Color(0xFFCBD5E1);

  static List<BoxShadow> get shadow => [
    BoxShadow(
      color: const Color(0xFF1E3A8A).withValues(alpha: 0.06),
      blurRadius: 12,
      offset: const Offset(0, 3),
    ),
  ];
}

// ─────────────────────────────────────────────────────────────────────────────
// BacktestResultScreen
// ─────────────────────────────────────────────────────────────────────────────
class BacktestResultScreen extends StatefulWidget {
  const BacktestResultScreen({
    super.key,
    required this.result,
    required this.strategyName,
  });

  final BtResult result;
  final String   strategyName;

  @override
  State<BacktestResultScreen> createState() => _BacktestResultScreenState();
}

class _BacktestResultScreenState extends State<BacktestResultScreen>
    with TickerProviderStateMixin {

  late TabController     _tabCtrl;
  late AnimationController _curveCtrl;
  late Animation<double>   _curveDraw;

  // Chart mode: 0 = Cumulative P&L, 1 = Drawdown
  int _chartMode = 0;

  @override
  void initState() {
    super.initState();
    _tabCtrl   = TabController(length: 3, vsync: this);
    _curveCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 1400))
      ..forward();
    _curveDraw = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _curveCtrl, curve: Curves.easeInOutCubic),
    );
  }

  @override
  void dispose() {
    _tabCtrl.dispose();
    _curveCtrl.dispose();
    super.dispose();
  }

  BtResult get r => widget.result;

  @override
  Widget build(BuildContext context) {
    final isProfit = r.totalPnl >= 0;
    final pnlColor = isProfit ? _K.profit : _K.loss;

    return Scaffold(
      backgroundColor: _K.bg,
      appBar: AppBar(
        backgroundColor: _K.surface,
        elevation: 0,
        scrolledUnderElevation: 0,
        surfaceTintColor: Colors.transparent,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded, color: _K.t1, size: 22),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Backtest Analysis',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: _K.t1),
            ),
            Text(widget.strategyName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 11, color: _K.t2)),
          ],
        ),
        actions: [
          if (r.fromDate != null)
            Padding(
              padding: const EdgeInsets.only(right: 14),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: _K.primaryBg,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(r.range,
                    style: const TextStyle(
                        fontSize: 11, fontWeight: FontWeight.w700, color: _K.primary)),
              ),
            ),
        ],
        bottom: TabBar(
          controller: _tabCtrl,
          labelColor: _K.primary,
          unselectedLabelColor: _K.t3,
          indicatorColor: _K.primary,
          indicatorSize: TabBarIndicatorSize.tab,
          labelStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
          tabs: const [
            Tab(text: 'Analysis'),
            Tab(text: 'Transactions'),
            Tab(text: 'Reports'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabCtrl,
        children: [
          _buildAnalysisTab(isProfit, pnlColor),
          _buildTransactionsTab(),
          _buildReportsTab(),
        ],
      ),
    );
  }

  // ══════════════════════════════════════════════════════════════════════════
  // TAB 1 — ANALYSIS
  // ══════════════════════════════════════════════════════════════════════════
  Widget _buildAnalysisTab(bool isProfit, Color pnlColor) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Date range
          if (r.fromDate != null && r.toDate != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 14),
              child: Row(children: [
                const Icon(Icons.date_range_rounded, size: 13, color: _K.t3),
                const SizedBox(width: 6),
                Text('${r.fromDate!.substring(0, 10)}  →  ${r.toDate!.substring(0, 10)}',
                    style: const TextStyle(fontSize: 12, color: _K.t2)),
                if (r.candleCount != null) ...[
                  const SizedBox(width: 8),
                  const Text('·', style: TextStyle(color: _K.t4)),
                  const SizedBox(width: 8),
                  Text('${r.candleCount} bars',
                      style: const TextStyle(fontSize: 12, color: _K.t3)),
                ],
              ]),
            ),

          // Row 1: hero P&L + 4 stats
          _buildHeroCard(isProfit, pnlColor),
          const SizedBox(height: 12),

          // Row 2: trade stats grid
          const _SectionLabel('TRADE STATISTICS'),
          const SizedBox(height: 8),
          _StatGrid(children: [
            _SmallStat(label: 'Signals',       value: '${r.signals}',          color: _K.t1),
            _SmallStat(label: 'Win Days',      value: '${r.winningDays}',       color: _K.profit),
            _SmallStat(label: 'Loss Days',     value: '${r.losingDays}',        color: _K.loss),
            _SmallStat(label: 'Win Streak',    value: '${r.winStreak}',         color: _K.profit),
            _SmallStat(label: 'Loss Streak',   value: '${r.lossStreak}',        color: _K.loss),
            _SmallStat(label: 'Max Recovery',  value: '${r.maxTimeToRecover}d', color: _K.warning),
          ]),
          const SizedBox(height: 12),

          // Row 3: P&L breakdown grid
          const _SectionLabel('P&L BREAKDOWN'),
          const SizedBox(height: 8),
          _StatGrid(children: [
            _SmallStat(label: 'Booked Profit',  value: '₹${BtResult.fmt(r.bookedProfit)}',           color: _K.profit),
            _SmallStat(label: 'Booked Loss',    value: '-₹${BtResult.fmt(r.bookedLoss.abs())}',      color: _K.loss),
            _SmallStat(label: 'Max Profit Day', value: '₹${BtResult.fmt(r.maxProfitDay)}',           color: _K.profit),
            _SmallStat(label: 'Max Loss Day',   value: '-₹${BtResult.fmt(r.maxLossDay.abs())}',      color: _K.loss),
            _SmallStat(label: 'Avg Win Day',    value: '₹${BtResult.fmt(r.avgProfitWinDays)}',       color: _K.profit),
            _SmallStat(label: 'Avg Loss Day',   value: '-₹${BtResult.fmt(r.avgLossLoseDays.abs())}', color: _K.loss),
          ]),
          const SizedBox(height: 16),

          // Chart
          _buildChartCard(),

          const SizedBox(height: 12),
          // Disclaimer
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: _K.surface2,
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.info_outline_rounded, size: 13, color: _K.t3),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Simulated results on historical data. Past performance does not '
                    'guarantee future returns.',
                    style: TextStyle(fontSize: 11, color: _K.t3, height: 1.4),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeroCard(bool isProfit, Color pnlColor) {
    return Container(
      decoration: BoxDecoration(
        color: _K.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: _K.divider),
        boxShadow: _K.shadow,
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
            decoration: BoxDecoration(
              color: pnlColor.withValues(alpha: 0.06),
              borderRadius: const BorderRadius.vertical(top: Radius.circular(18)),
            ),
            child: Row(children: [
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Text('NET P&L',
                      style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.w700,
                          color: _K.t3, letterSpacing: 0.8)),
                  const SizedBox(height: 4),
                  Text(
                    '${isProfit ? '' : '-'}₹${BtResult.fmt(r.totalPnl.abs())}',
                    style: TextStyle(
                      fontSize: 30, fontWeight: FontWeight.w900, color: pnlColor,
                      letterSpacing: -0.5,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                ]),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                decoration: BoxDecoration(
                  color: pnlColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(isProfit ? '✓  Profitable' : '✗  Loss',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: pnlColor)),
              ),
            ]),
          ),
          Row(children: [
            _TopStat(label: 'MAX DD',    value: '₹${BtResult.fmt(r.maxDrawdown)}',              color: _K.loss),
            _VDivider(),
            _TopStat(label: 'WIN RATE',  value: '${r.winRate.toStringAsFixed(0)}%',              color: r.winRate >= 50 ? _K.profit : _K.warning),
            _VDivider(),
            _TopStat(label: 'CALMAR',    value: r.calmar.toStringAsFixed(2),                     color: r.calmar >= 1 ? _K.profit : _K.t1),
            _VDivider(),
            _TopStat(label: 'TRADES',    value: '${r.totalTrades}',                              color: _K.t1),
          ]),
        ],
      ),
    );
  }

  Widget _buildChartCard() {
    final pnlCurve = r.equityCurve;
    final undCurve = r.underlyingCurve;
    final curve    = _chartMode == 0 ? pnlCurve : _drawdownCurve(pnlCurve);
    final hasUnderlying = undCurve.length >= 2 &&
        undCurve.any((v) => v != 0) && _chartMode == 0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _SectionLabel('CHART'),
        const SizedBox(height: 8),
        Container(
          decoration: BoxDecoration(
            color: _K.surface, borderRadius: BorderRadius.circular(18),
            border: Border.all(color: _K.divider), boxShadow: _K.shadow,
          ),
          child: Column(children: [
            // Header + toggle
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
              child: Row(children: [
                const Expanded(
                  child: Text('Cumulative P&L',
                      style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: _K.t1)),
                ),
                _ChartToggle(
                  options: const ['Cumulative P&L', 'Drawdown'],
                  selected: _chartMode,
                  onChanged: (i) => setState(() {
                    _chartMode = i;
                    _curveCtrl..reset()..forward();
                  }),
                ),
              ]),
            ),
            const SizedBox(height: 12),

            // Chart canvas
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: SizedBox(
                height: 200,
                child: AnimatedBuilder(
                  animation: _curveDraw,
                  builder: (_, __) => CustomPaint(
                    painter: _DualAxisPainter(
                      pnlCurve:      curve,
                      underlyingCurve: hasUnderlying ? undCurve : [],
                      animValue:     _curveDraw.value,
                      isDrawdown:    _chartMode == 1,
                    ),
                    child: const SizedBox.expand(),
                  ),
                ),
              ),
            ),

            // Y-axis labels (P&L left, underlying right if dual-axis)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 6, 16, 14),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  // Left axis labels
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: _yLabels(curve).map((v) =>
                      Text(_fmtLabel(v),
                          style: const TextStyle(fontSize: 9, color: _K.t3))).toList(),
                  ),
                  if (hasUnderlying)
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: _yLabels(undCurve).map((v) =>
                        Text(_fmtLabel(v),
                            style: const TextStyle(fontSize: 9, color: _K.warning))).toList(),
                    ),
                ],
              ),
            ),

            // Legend
            if (hasUnderlying)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
                child: Row(children: [
                  _LegendDot(color: r.totalPnl >= 0 ? _K.profit : _K.loss),
                  const SizedBox(width: 5),
                  const Text('Cumulative P&L',
                      style: TextStyle(fontSize: 10, color: _K.t2)),
                  const SizedBox(width: 16),
                  _LegendDot(color: _K.warning, dashed: true),
                  const SizedBox(width: 5),
                  const Text('Underlying Price',
                      style: TextStyle(fontSize: 10, color: _K.t2)),
                ]),
              ),
          ]),
        ),
      ],
    );
  }

  // ══════════════════════════════════════════════════════════════════════════
  // TAB 2 — TRANSACTIONS
  // ══════════════════════════════════════════════════════════════════════════
  Widget _buildTransactionsTab() {
    final trades = r.trades;
    if (trades.isEmpty) {
      return const Center(
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          Icon(Icons.receipt_long_rounded, size: 48, color: _K.t4),
          SizedBox(height: 12),
          Text('No trade data available',
              style: TextStyle(fontSize: 14, color: _K.t3)),
          SizedBox(height: 6),
          Text('Re-run the backtest to see per-trade details',
              style: TextStyle(fontSize: 12, color: _K.t4)),
        ]),
      );
    }

    return Column(
      children: [
        // Summary bar
        Container(
          color: _K.surface,
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
          child: Row(children: [
            _TxSummaryChip(label: 'Total', value: '${trades.length}', color: _K.t1),
            const SizedBox(width: 8),
            _TxSummaryChip(
              label: 'Wins',
              value: '${trades.where((t) => t.result == 'win').length}',
              color: _K.profit,
            ),
            const SizedBox(width: 8),
            _TxSummaryChip(
              label: 'Losses',
              value: '${trades.where((t) => t.result == 'loss').length}',
              color: _K.loss,
            ),
          ]),
        ),
        const Divider(height: 1, color: _K.divider),

        // Column header
        Container(
          color: _K.surface,
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
          child: Row(children: const [
            Expanded(flex: 1, child: _TxHeader('#')),
            Expanded(flex: 3, child: _TxHeader('Entry')),
            Expanded(flex: 3, child: _TxHeader('Exit')),
            Expanded(flex: 2, child: _TxHeader('P&L', right: true)),
          ]),
        ),
        const Divider(height: 1, color: _K.divider),

        Expanded(
          child: ListView.separated(
            padding: EdgeInsets.zero,
            itemCount: trades.length,
            separatorBuilder: (_, __) =>
                const Divider(height: 1, color: _K.divider),
            itemBuilder: (_, idx) {
              final t = trades[idx];
              final isWin = t.result == 'win';
              final pnlColor = isWin ? _K.profit : _K.loss;

              return Container(
                color: _K.surface,
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // #
                    Expanded(
                      flex: 1,
                      child: Container(
                        width: 22, height: 22,
                        decoration: BoxDecoration(
                          color: pnlColor.withValues(alpha: 0.10),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        alignment: Alignment.center,
                        child: Text('${t.tradeNo}',
                            style: TextStyle(
                                fontSize: 9.5, fontWeight: FontWeight.w700,
                                color: pnlColor)),
                      ),
                    ),
                    // Entry
                    Expanded(
                      flex: 3,
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(t.entryDate,
                            style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: _K.t1)),
                        Text('${t.entryTime}  ₹${BtResult.fmt(t.entryPrice)}',
                            style: const TextStyle(fontSize: 10, color: _K.t3)),
                      ]),
                    ),
                    // Exit
                    Expanded(
                      flex: 3,
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Row(children: [
                          Text(t.exitDate,
                              style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: _K.t1)),
                          const SizedBox(width: 4),
                          _ExitBadge(reason: t.exitReason),
                        ]),
                        Text('${t.exitTime}  ₹${BtResult.fmt(t.exitPrice)}',
                            style: const TextStyle(fontSize: 10, color: _K.t3)),
                      ]),
                    ),
                    // P&L
                    Expanded(
                      flex: 2,
                      child: Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                        Text(
                          '${t.pnl >= 0 ? '+' : ''}₹${BtResult.fmt(t.pnl)}',
                          style: TextStyle(
                            fontSize: 12, fontWeight: FontWeight.w800, color: pnlColor,
                            fontFeatures: const [FontFeature.tabularFigures()],
                          ),
                        ),
                        Text(t.result.toUpperCase(),
                            style: TextStyle(fontSize: 8.5, color: pnlColor, letterSpacing: 0.3)),
                      ]),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  // ══════════════════════════════════════════════════════════════════════════
  // TAB 3 — REPORTS (Monthly P&L)
  // ══════════════════════════════════════════════════════════════════════════
  Widget _buildReportsTab() {
    final monthly = r.monthlyPnl;
    if (monthly.isEmpty) {
      return const Center(
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          Icon(Icons.bar_chart_rounded, size: 48, color: _K.t4),
          SizedBox(height: 12),
          Text('No monthly data available',
              style: TextStyle(fontSize: 14, color: _K.t3)),
        ]),
      );
    }

    // Sort months
    final sortedMonths = monthly.keys.toList()..sort();
    final maxAbs = monthly.values.map((v) => v.abs()).reduce(math.max).clamp(1.0, double.infinity);

    // Year groups
    final yearMap = <String, List<String>>{};
    for (final m in sortedMonths) {
      final yr = m.substring(0, 4);
      yearMap.putIfAbsent(yr, () => []).add(m);
    }

    // Total
    final total = monthly.values.fold(0.0, (a, b) => a + b);

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Summary card
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: _K.surface, borderRadius: BorderRadius.circular(16),
              border: Border.all(color: _K.divider), boxShadow: _K.shadow,
            ),
            child: Row(children: [
              Expanded(child: _ReportSummaryItem(
                label: 'Total P&L',
                value: '${total >= 0 ? '+' : ''}₹${BtResult.fmt(total)}',
                color: total >= 0 ? _K.profit : _K.loss,
              )),
              Container(width: 1, height: 40, color: _K.divider),
              Expanded(child: _ReportSummaryItem(
                label: 'Profitable Months',
                value: '${monthly.values.where((v) => v > 0).length} / ${monthly.length}',
                color: _K.profit,
              )),
              Container(width: 1, height: 40, color: _K.divider),
              Expanded(child: _ReportSummaryItem(
                label: 'Best Month',
                value: '₹${BtResult.fmt(monthly.values.reduce(math.max))}',
                color: _K.profit,
              )),
            ]),
          ),
          const SizedBox(height: 20),

          // Year-grouped tables
          for (final yr in yearMap.keys) ...[
            Text(yr, style: const TextStyle(
                fontSize: 13, fontWeight: FontWeight.w800, color: _K.t1)),
            const SizedBox(height: 8),
            Container(
              decoration: BoxDecoration(
                color: _K.surface, borderRadius: BorderRadius.circular(16),
                border: Border.all(color: _K.divider), boxShadow: _K.shadow,
              ),
              clipBehavior: Clip.antiAlias,
              child: Column(
                children: yearMap[yr]!.asMap().entries.map((entry) {
                  final idx   = entry.key;
                  final month = entry.value;
                  final pnl   = monthly[month]!;
                  final isPos = pnl >= 0;
                  final barW  = (pnl.abs() / maxAbs).clamp(0.0, 1.0);
                  final color = isPos ? _K.profit : _K.loss;
                  final monthName = _monthName(month.substring(5, 7));

                  return Column(
                    children: [
                      if (idx > 0)
                        const Divider(height: 1, color: _K.divider),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                        child: Row(children: [
                          SizedBox(
                            width: 36,
                            child: Text(monthName,
                                style: const TextStyle(
                                    fontSize: 12, fontWeight: FontWeight.w700, color: _K.t1)),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: LayoutBuilder(builder: (_, c) => Stack(children: [
                              Container(height: 6,
                                  decoration: BoxDecoration(
                                    color: _K.surface2,
                                    borderRadius: BorderRadius.circular(3),
                                  )),
                              Container(
                                height: 6,
                                width: c.maxWidth * barW,
                                decoration: BoxDecoration(
                                  color: color,
                                  borderRadius: BorderRadius.circular(3),
                                ),
                              ),
                            ])),
                          ),
                          const SizedBox(width: 12),
                          SizedBox(
                            width: 72,
                            child: Text(
                              '${isPos ? '+' : ''}₹${BtResult.fmt(pnl)}',
                              textAlign: TextAlign.end,
                              style: TextStyle(
                                fontSize: 12, fontWeight: FontWeight.w800, color: color,
                                fontFeatures: const [FontFeature.tabularFigures()],
                              ),
                            ),
                          ),
                        ]),
                      ),
                    ],
                  );
                }).toList(),
              ),
            ),
            const SizedBox(height: 16),
          ],
        ],
      ),
    );
  }

  // ── Helpers ─────────────────────────────────────────────────────────────────
  List<double> _drawdownCurve(List<double> equity) {
    double peak = equity.isEmpty ? 0 : equity.first;
    return equity.map((v) {
      if (v > peak) peak = v;
      return peak == 0 ? 0.0 : ((v - peak) / peak.abs() * 100);
    }).toList();
  }

  List<double> _yLabels(List<double> curve) {
    if (curve.isEmpty) return [0, 0, 0];
    final minV = curve.reduce(math.min);
    final maxV = curve.reduce(math.max);
    return [minV, (minV + maxV) / 2, maxV];
  }

  String _fmtLabel(double v) {
    final a = v.abs();
    final s = v < 0 ? '-' : '';
    if (a >= 100000) return '$s${(a / 100000).toStringAsFixed(1)}L';
    if (a >= 1000)   return '$s${(a / 1000).toStringAsFixed(1)}K';
    return v.toStringAsFixed(0);
  }

  static String _monthName(String mm) {
    const names = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];
    final i = int.tryParse(mm);
    if (i == null || i < 1 || i > 12) return mm;
    return names[i - 1];
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Dual-axis animated curve painter
// ─────────────────────────────────────────────────────────────────────────────
class _DualAxisPainter extends CustomPainter {
  const _DualAxisPainter({
    required this.pnlCurve,
    required this.underlyingCurve,
    this.animValue  = 1.0,
    this.isDrawdown = false,
  });

  final List<double> pnlCurve;
  final List<double> underlyingCurve;
  final double animValue;
  final bool   isDrawdown;

  @override
  void paint(Canvas canvas, Size size) {
    if (pnlCurve.length < 2) return;

    _drawCurve(
      canvas, size,
      curve:      pnlCurve,
      color:      isDrawdown ? _K.loss : (pnlCurve.last >= 0 ? _K.profit : _K.loss),
      lineWidth:  2.2,
      dashed:     false,
      normalized: false, // use own min/max
    );

    if (underlyingCurve.length >= 2 && !isDrawdown) {
      _drawCurve(
        canvas, size,
        curve:      underlyingCurve,
        color:      _K.warning,
        lineWidth:  1.5,
        dashed:     true,
        normalized: true, // normalise to 0-1 so it fits the same canvas
      );
    }
  }

  void _drawCurve(
    Canvas canvas,
    Size size, {
    required List<double> curve,
    required Color color,
    required double lineWidth,
    required bool dashed,
    required bool normalized,
  }) {
    final drawCount = ((curve.length - 1) * animValue).round() + 1;
    final minV  = normalized
        ? curve.reduce(math.min)
        : curve.reduce(math.min);
    final maxV  = normalized
        ? curve.reduce(math.max)
        : curve.reduce(math.max);
    final range = (maxV - minV).abs().clamp(1.0, double.infinity);

    // Grid (only for the first/primary curve)
    if (!dashed) {
      final gridPaint = Paint()
        ..color = _K.divider.withValues(alpha: 0.6)
        ..strokeWidth = 0.5;
      for (int i = 0; i <= 3; i++) {
        final y = size.height * i / 3;
        canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
      }
      // Zero baseline
      if (minV < 0 && maxV > 0) {
        final zeroY = size.height - ((0 - minV) / range * (size.height - 12)) - 6;
        canvas.drawLine(
          Offset(0, zeroY), Offset(size.width, zeroY),
          Paint()
            ..color = _K.t3.withValues(alpha: 0.5)
            ..strokeWidth = 1
            ..style = PaintingStyle.stroke,
        );
      }
    }

    final pts = <Offset>[];
    for (int i = 0; i < drawCount && i < curve.length; i++) {
      final x = i / (curve.length - 1) * size.width;
      final y = size.height - ((curve[i] - minV) / range * (size.height - 14)) - 7;
      pts.add(Offset(x, y));
    }
    if (pts.length < 2) return;

    // Fill (primary only)
    if (!dashed) {
      final fillPath = Path()
        ..moveTo(0, size.height)
        ..lineTo(pts.first.dx, pts.first.dy);
      for (int i = 1; i < pts.length; i++) {
        final mx = (pts[i-1].dx + pts[i].dx) / 2;
        fillPath.cubicTo(mx, pts[i-1].dy, mx, pts[i].dy, pts[i].dx, pts[i].dy);
      }
      fillPath..lineTo(pts.last.dx, size.height)..close();
      canvas.drawPath(fillPath, Paint()
        ..shader = LinearGradient(
          colors: [color.withValues(alpha: 0.16), color.withValues(alpha: 0.0)],
          begin: Alignment.topCenter, end: Alignment.bottomCenter,
        ).createShader(Offset.zero & size));
    }

    // Line
    if (dashed) {
      _drawDashedLine(canvas, pts, color, lineWidth);
    } else {
      final linePath = Path()..moveTo(pts.first.dx, pts.first.dy);
      for (int i = 1; i < pts.length; i++) {
        final mx = (pts[i-1].dx + pts[i].dx) / 2;
        linePath.cubicTo(mx, pts[i-1].dy, mx, pts[i].dy, pts[i].dx, pts[i].dy);
      }
      canvas.drawPath(linePath, Paint()
        ..color = color
        ..strokeWidth = lineWidth
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round);
    }

    // Animated leading dot (primary only)
    if (!dashed && animValue < 1.0) {
      canvas.drawCircle(pts.last, 4, Paint()..color = color.withValues(alpha: 0.25));
      canvas.drawCircle(pts.last, 3, Paint()..color = color);
      canvas.drawCircle(pts.last, 3,
          Paint()..color = Colors.white..strokeWidth = 1.5..style = PaintingStyle.stroke);
    }
  }

  void _drawDashedLine(Canvas canvas, List<Offset> pts, Color color, double width) {
    const dashLen = 6.0, gapLen = 4.0;
    double remaining = 0;
    bool   drawing   = true;
    for (int i = 1; i < pts.length; i++) {
      final from = pts[i - 1];
      final to   = pts[i];
      final dx   = to.dx - from.dx;
      final dy   = to.dy - from.dy;
      final len  = math.sqrt(dx * dx + dy * dy);
      final ux   = dx / len;
      final uy   = dy / len;
      double done = 0;
      while (done < len) {
        final segLen = drawing ? dashLen : gapLen;
        final step   = math.min(segLen - remaining, len - done);
        final cx     = from.dx + ux * done;
        final cy     = from.dy + uy * done;
        if (drawing) {
          canvas.drawLine(
            Offset(cx, cy),
            Offset(cx + ux * step, cy + uy * step),
            Paint()..color = color..strokeWidth = width..strokeCap = StrokeCap.round,
          );
        }
        done      += step;
        remaining += step;
        if (remaining >= segLen) { remaining = 0; drawing = !drawing; }
      }
    }
  }

  @override
  bool shouldRepaint(covariant _DualAxisPainter old) =>
      old.animValue   != animValue   ||
      old.pnlCurve    != pnlCurve    ||
      old.underlyingCurve != underlyingCurve ||
      old.isDrawdown  != isDrawdown;
}

// ─────────────────────────────────────────────────────────────────────────────
// Reusable sub-widgets
// ─────────────────────────────────────────────────────────────────────────────

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);
  final String text;
  @override
  Widget build(BuildContext context) => Text(text,
      style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w700,
          color: _K.t3, letterSpacing: 0.8));
}

class _TopStat extends StatelessWidget {
  const _TopStat({required this.label, required this.value, required this.color});
  final String label, value;
  final Color  color;
  @override
  Widget build(BuildContext context) => Expanded(
    child: Padding(
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 4),
      child: Column(children: [
        Text(value, style: TextStyle(
            fontSize: 14, fontWeight: FontWeight.w800, color: color,
            fontFeatures: const [FontFeature.tabularFigures()])),
        const SizedBox(height: 2),
        Text(label, style: const TextStyle(fontSize: 9, color: _K.t3, letterSpacing: 0.3)),
      ]),
    ),
  );
}

class _VDivider extends StatelessWidget {
  @override
  Widget build(BuildContext context) =>
      Container(width: 1, height: 36, color: _K.divider);
}

class _StatGrid extends StatelessWidget {
  const _StatGrid({required this.children});
  final List<Widget> children;
  @override
  Widget build(BuildContext context) {
    final rows = <Widget>[];
    for (int i = 0; i < children.length; i += 3) {
      final row = children.sublist(i, math.min(i + 3, children.length));
      while (row.length < 3) row.add(const SizedBox.shrink());
      rows.add(Row(children: row.map((w) => Expanded(child: w)).toList()));
      if (i + 3 < children.length) rows.add(const SizedBox(height: 8));
    }
    return Column(children: rows);
  }
}

class _SmallStat extends StatelessWidget {
  const _SmallStat({required this.label, required this.value, required this.color});
  final String label, value;
  final Color  color;
  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.all(3),
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
    decoration: BoxDecoration(
      color: _K.surface, borderRadius: BorderRadius.circular(14),
      border: Border.all(color: _K.divider), boxShadow: _K.shadow,
    ),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(label, style: const TextStyle(fontSize: 9.5, color: _K.t3, letterSpacing: 0.2)),
      const SizedBox(height: 4),
      Text(value, style: TextStyle(
          fontSize: 15, fontWeight: FontWeight.w800, color: color,
          fontFeatures: const [FontFeature.tabularFigures()])),
    ]),
  );
}

class _ChartToggle extends StatelessWidget {
  const _ChartToggle({required this.options, required this.selected, required this.onChanged});
  final List<String> options;
  final int selected;
  final ValueChanged<int> onChanged;
  @override
  Widget build(BuildContext context) => Container(
    decoration: BoxDecoration(
      color: _K.surface2, borderRadius: BorderRadius.circular(20),
      border: Border.all(color: _K.divider),
    ),
    child: Row(mainAxisSize: MainAxisSize.min,
      children: List.generate(options.length, (i) {
        final sel = i == selected;
        return GestureDetector(
          onTap: () => onChanged(i),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: sel ? _K.primary : Colors.transparent,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(options[i],
                style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700,
                    color: sel ? Colors.white : _K.t2)),
          ),
        );
      }),
    ),
  );
}

class _LegendDot extends StatelessWidget {
  const _LegendDot({required this.color, this.dashed = false});
  final Color color;
  final bool  dashed;
  @override
  Widget build(BuildContext context) => Container(
    width: 18, height: 3,
    decoration: BoxDecoration(
      color: dashed ? Colors.transparent : color,
      borderRadius: BorderRadius.circular(2),
      border: dashed ? Border(bottom: BorderSide(color: color, width: 1.5)) : null,
    ),
  );
}

// ── Transactions tab sub-widgets ─────────────────────────────────────────────

class _TxSummaryChip extends StatelessWidget {
  const _TxSummaryChip({required this.label, required this.value, required this.color});
  final String label, value;
  final Color  color;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.08),
      borderRadius: BorderRadius.circular(20),
      border: Border.all(color: color.withValues(alpha: 0.2)),
    ),
    child: RichText(
      text: TextSpan(children: [
        TextSpan(text: '$label  ',
            style: const TextStyle(fontSize: 11, color: _K.t3)),
        TextSpan(text: value,
            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: color)),
      ]),
    ),
  );
}

class _TxHeader extends StatelessWidget {
  const _TxHeader(this.text, {this.right = false});
  final String text;
  final bool   right;
  @override
  Widget build(BuildContext context) => Text(text,
      textAlign: right ? TextAlign.end : TextAlign.start,
      style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w700,
          color: _K.t3, letterSpacing: 0.5));
}

class _ExitBadge extends StatelessWidget {
  const _ExitBadge({required this.reason});
  final String reason;
  @override
  Widget build(BuildContext context) {
    Color c;
    String label;
    switch (reason) {
      case 'target':   c = _K.profit;  label = 'TGT'; break;
      case 'stoploss': c = _K.loss;    label = 'SL';  break;
      case 'signal':   c = _K.primary; label = 'SIG'; break;
      default:         c = _K.neutral; label = 'TOD'; break;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
      decoration: BoxDecoration(
        color: c.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(label,
          style: TextStyle(fontSize: 8, fontWeight: FontWeight.w800, color: c)),
    );
  }
}

// ── Reports tab sub-widgets ──────────────────────────────────────────────────

class _ReportSummaryItem extends StatelessWidget {
  const _ReportSummaryItem({required this.label, required this.value, required this.color});
  final String label, value;
  final Color  color;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 8),
    child: Column(children: [
      Text(value,
          style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: color,
              fontFeatures: const [FontFeature.tabularFigures()])),
      const SizedBox(height: 3),
      Text(label,
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 9.5, color: _K.t3)),
    ]),
  );
}
