import 'dart:ui';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../cubits/live_price_cubit.dart';
import '../services/live_price_service.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Design tokens — shared "trading terminal on paper" system used across the
// dashboard, market, and detail screens. Warm paper base, one flat ink
// surface for the price hero, hairline borders instead of stacked shadows.
// ─────────────────────────────────────────────────────────────────────────────

abstract final class _ST {
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
    double letterSpacing = -0.4,
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
    borderRadius: BorderRadius.circular(r14),
    border: Border.all(color: borderColor ?? divider, width: 1),
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// StrategyDetailScreen
//
// Receives route extra:
//   {
//     'docId':     String,
//     'uid':       String,
//     'isOwn':     bool,
//     'data': {
//       'label', 'symbol', 'category', 'type', 'action',
//       'entry', 'target', 'sl', 'duration', 'badge',
//       'status', 'dropEnabled', 'isPublished', 'confidence',
//       'tags', 'quantity', 'description'
//     }
//   }
// ─────────────────────────────────────────────────────────────────────────────

class StrategyDetailScreen extends StatefulWidget {
  final String docId;
  final String uid;
  final bool isOwn;
  final Map<String, dynamic> data;

  const StrategyDetailScreen({
    super.key,
    required this.docId,
    required this.uid,
    required this.isOwn,
    required this.data,
  });

  @override
  State<StrategyDetailScreen> createState() => _StrategyDetailScreenState();
}

class _StrategyDetailScreenState extends State<StrategyDetailScreen> {
  bool _closing   = false;
  bool _deploying = false;

  // Convenience getters
  String get _label       => widget.data['label'] as String? ?? '—';
  String get _symbol      => widget.data['symbol'] as String? ?? '';
  String get _category    => widget.data['category'] as String? ?? 'stocks';
  String get _type        => widget.data['type'] as String? ?? '';
  String get _action      => widget.data['action'] as String? ?? 'BUY';
  double get _entry       => (widget.data['entry']  as num?)?.toDouble()  ?? 0;
  double get _target      => (widget.data['target'] as num?)?.toDouble()  ?? 0;
  double get _target2     => (widget.data['target2'] as num?)?.toDouble() ?? 0;
  double get _sl          => (widget.data['sl']     as num?)?.toDouble()  ?? 0;
  String get _duration    => widget.data['duration']    as String? ?? '';
  String get _status      => widget.data['status']      as String? ?? 'live';
  bool   get _dropEnabled => widget.data['dropEnabled'] as bool?   ?? false;
  bool   get _isPaperTrade => widget.data['paper_trade'] as bool?  ?? false;
  bool   get _isPublished => widget.data['isPublished'] as bool?   ?? true;
  String get _confidence  => widget.data['confidence']  as String? ?? '';
  List<String> get _tags  => List<String>.from(widget.data['tags'] as List? ?? []);
  int    get _quantity    => (widget.data['quantity']   as num?)?.toInt()  ?? 1;
  String get _description => widget.data['description'] as String? ?? '';
  // New fields
  String get _orderType     => widget.data['orderType']     as String? ?? 'LIMIT';
  String get _execMode      => widget.data['execMode']      as String? ?? 'immediate';
  bool   get _trailSL       => widget.data['trailingSL']    as bool?   ?? false;
  String get _trailSLMode   => widget.data['trailingSLMode'] as String? ?? 'points';
  double get _trailSLValue  => (widget.data['trailingSLValue'] as num?)?.toDouble() ?? 0;
  bool   get _autoExecute   => widget.data['autoExecute']   as bool?   ?? false;
  String get _sizeMode      => widget.data['sizeMode']      as String? ?? 'qty';
  bool   get _isBracket     => widget.data['bracketOrder']  as bool?   ?? false;
  // Product type / validity / valid-till
  String get _productType   => widget.data['productType']   as String? ?? 'CNC';
  String get _validity      => widget.data['validity']      as String? ?? 'DAY';
  DateTime? get _validTill  {
    final v = widget.data['validTill'];
    if (v is DateTime) return v;
    if (v is String) return DateTime.tryParse(v);
    return null;
  }

  bool get _isClosed => _status == 'closed' ||
      _status == 'target_hit' ||
      _status == 'sl_hit' ||
      _status == 'hit_target' ||    // legacy
      _status == 'stoploss_hit';    // legacy
  bool get _isWatching   => _status == 'watching';
  bool get _isInPosition => _status == 'in_position';
  bool get _isDraft      => _status == 'active';   // saved but not deployed
  bool get _isDropArmed  => _isWatching || (_dropEnabled && !_isPublished);
  bool get _isBuy        => _action.toUpperCase() == 'BUY';

  @override
  void initState() {
    super.initState();
    if (_symbol.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          context.read<LivePriceCubit>()
            ..connect()
            ..subscribe([_symbol]);
        }
      });
    }
  }

  // ── Close strategy ────────────────────────────────────────────────────────

  Future<void> _closeStrategy(double exitPrice) async {
    if (widget.uid.isEmpty || widget.docId.isEmpty) return;
    setState(() => _closing = true);

    try {
      await FirebaseFirestore.instance
          .collection('users')
          .doc(widget.uid)
          .collection('strategies')
          .doc(widget.docId)
          .update({
        'status': 'closed',
        'trade.exit_price': exitPrice,
        'trade.exit_date': FieldValue.serverTimestamp(),
        'meta.updated_at': FieldValue.serverTimestamp(),
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Strategy closed.'),
            backgroundColor: _ST.profit,
            behavior: SnackBarBehavior.floating,
            margin: const EdgeInsets.all(16),
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12)),
          ),
        );
        context.pop();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed: $e'),
            backgroundColor: _ST.loss,
            behavior: SnackBarBehavior.floating,
            margin: const EdgeInsets.all(16),
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12)),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _closing = false);
    }
  }

  // ── Deploy strategy (draft → watching) ────────────────────────────────────
  Future<void> _deployStrategy() async {
    if (widget.uid.isEmpty || widget.docId.isEmpty) return;
    setState(() => _deploying = true);
    try {
      await FirebaseFirestore.instance
          .collection('users')
          .doc(widget.uid)
          .collection('strategies')
          .doc(widget.docId)
          .update({
        'status': 'watching',
        'auto_execute': true,
        'meta.updated_at': FieldValue.serverTimestamp(),
        'deployed_at': FieldValue.serverTimestamp(),
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Row(children: [
              Icon(Icons.rocket_launch_rounded, color: Colors.white, size: 18),
              SizedBox(width: 10),
              Text('Strategy deployed! Engine is now watching.'),
            ]),
            backgroundColor: _ST.profit,
            behavior: SnackBarBehavior.floating,
            margin: const EdgeInsets.all(16),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
        );
        context.pop(); // go back to strategies list to see updated status
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Deploy failed: $e'),
            backgroundColor: _ST.loss,
            behavior: SnackBarBehavior.floating,
            margin: const EdgeInsets.all(16),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _deploying = false);
    }
  }

  Future<void> _showCloseDialog(double ltp) async {
    final ctrl = TextEditingController(text: ltp.toStringAsFixed(2));
    final confirm = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: _ST.surface,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20)),
        title: const Text('Close strategy',
            style: TextStyle(fontWeight: FontWeight.w800, color: _ST.t1)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Exit price (pre-filled with current LTP):',
                style: TextStyle(fontSize: 13, color: _ST.t2)),
            const SizedBox(height: 10),
            TextField(
              controller: ctrl,
              keyboardType:
              const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(
                prefixText: '₹',
                filled: true,
                fillColor: _ST.surface2,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Cancel', style: TextStyle(color: _ST.t2))),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            style: FilledButton.styleFrom(
                backgroundColor: _ST.loss,
                foregroundColor: Colors.white,
                elevation: 0,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12))),
            child: const Text('Close strategy'),
          ),
        ],
      ),
    );
    if (confirm == true) {
      final exit = double.tryParse(ctrl.text.trim());
      if (exit != null) _closeStrategy(exit);
    }
  }

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<LivePriceCubit, LivePriceState>(
      buildWhen: (prev, curr) =>
      prev.prices[_symbol]?.ltp != curr.prices[_symbol]?.ltp ||
          prev.isMarketClosed != curr.isMarketClosed,
      builder: (context, priceState) {
        final tick = priceState.prices[_symbol] ??
            LivePriceService.instance.getPrice(_symbol);
        final ltp = tick?.ltp ?? _entry;

        final gainPct = _entry > 0
            ? (_isBuy
            ? ((ltp - _entry) / _entry) * 100
            : ((_entry - ltp) / _entry) * 100)
            : 0.0;
        final gainRs = _entry > 0 ? (gainPct / 100) * _entry * _quantity : 0.0;
        final isProfit = gainPct >= 0;

        final riskRs = (_entry > 0 && _sl > 0)
            ? ((_entry - _sl).abs() * _quantity)
            : 0.0;

        return Scaffold(
          backgroundColor: _ST.bg,
          appBar: AppBar(
            backgroundColor: _ST.bg,
            elevation: 0,
            scrolledUnderElevation: 0,
            leading: IconButton(
              icon: const Icon(Icons.arrow_back_rounded, color: _ST.t1),
              onPressed: () => context.pop(),
            ),
            title: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(_label,
                    style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 17,
                        color: _ST.t1,
                        letterSpacing: -0.3)),
                Text(_symbol,
                    style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: _ST.primary)),
              ],
            ),
            actions: [
              // Edit button (only for own strategies)
              if (widget.isOwn && !_isClosed) ...[
                IconButton(
                  tooltip: 'Edit',
                  icon: Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: _ST.surface,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: _ST.divider, width: 1),
                    ),
                    child: const Icon(Icons.edit_outlined,
                        size: 18, color: _ST.primary),
                  ),
                  onPressed: () => context.push(
                    '/create-strategy',
                    extra: {
                      'editDocId': widget.docId,
                      'editUid': widget.uid,
                      'prefill': widget.data,
                    },
                  ),
                ),
              ],
              const SizedBox(width: 8),
            ],
          ),
          body: ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 120),
            children: [

              // ── Hero: live price + P&L ───────────────────────────────
              _LivePriceHero(
                symbol: _symbol,
                ltp: ltp,
                entry: _entry,
                gainPct: gainPct,
                gainRs: gainRs,
                isProfit: isProfit,
                isClosed: _isClosed,
                changePercent: tick?.changePercent ?? 0,
                isMarketClosed: priceState.isMarketClosed,
              ),

              const SizedBox(height: 14),

              // ── Paper Trade banner ───────────────────────────────────
              if (_isPaperTrade) ...[
                Container(
                  margin: const EdgeInsets.only(bottom: 14),
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFFBEB),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: const Color(0xFFFDE68A)),
                  ),
                  child: const Row(children: [
                    Text('🧪', style: TextStyle(fontSize: 18)),
                    SizedBox(width: 10),
                    Expanded(child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Paper Trade',
                            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800,
                                color: Color(0xFFD97706))),
                        SizedBox(height: 2),
                        Text('No real order is placed. P&L is simulated on live prices.',
                            style: TextStyle(fontSize: 11, color: Color(0xFFD97706), height: 1.4)),
                      ],
                    )),
                  ]),
                ),
              ],

              // ── Draft banner ─────────────────────────────────────────
              if (_isDraft) ...[
                _DraftBanner(strategyName: _label),
                const SizedBox(height: 14),
              ],

              // ── Drop Armed / Watching banner ─────────────────────────
              if (_isDropArmed) ...[
                _DropArmedBanner(
                  dropEnabled: _dropEnabled,
                  data: widget.data,
                ),
                const SizedBox(height: 14),
              ],

              // ── In Position banner ───────────────────────────────────
              if (_isInPosition) ...[
                _InPositionBanner(entryLtp: (widget.data['entry_ltp'] as num?)?.toDouble()),
                const SizedBox(height: 14),
              ],

              // ── Price Ladder ─────────────────────────────────────────
              if (_entry > 0 && _target > 0 && _sl > 0) ...[
                const _SectionHeader('Price ladder'),
                const SizedBox(height: 10),
                _PriceLadder(
                  sl: _sl,
                  entry: _entry,
                  ltp: ltp,
                  target: _target,
                  isBuy: _isBuy,
                  isProfit: isProfit,
                ),
                const SizedBox(height: 20),
              ],

              // ── Stats row ────────────────────────────────────────────
              const _SectionHeader('Trade stats'),
              const SizedBox(height: 10),
              _StatsGrid(
                action: _action,
                category: _category,
                type: _type,
                confidence: _confidence,
                quantity: _quantity,
                riskRs: riskRs,
                entry: _entry,
                target: _target,
                target2: _target2,
                sl: _sl,
                orderType: _orderType,
                execMode: _execMode,
                trailingSL: _trailSL,
                trailingSLMode: _trailSLMode,
                trailingSLValue: _trailSLValue,
                autoExecute: _autoExecute,
                sizeMode: _sizeMode,
                isBracket: _isBracket,
                productType: _productType,
                validity: _validity,
                validTill: _validTill,
              ),

              const SizedBox(height: 20),

              // ── Notes / Thesis ───────────────────────────────────────
              if (_description.isNotEmpty) ...[
                const _SectionHeader('Thesis'),
                const SizedBox(height: 10),
                _ThesisCard(
                    description: _description,
                    duration: _duration,
                    tags: _tags),
                const SizedBox(height: 14),
              ],

              // ── Tags row (standalone if no description) ──────────────
              if (_description.isEmpty && _tags.isNotEmpty) ...[
                const _SectionHeader('Tags'),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  children: _tags
                      .map((t) => _TagChip(tag: t))
                      .toList(),
                ),
                const SizedBox(height: 14),
              ],
            ],
          ),

          // ── Bottom action bar ────────────────────────────────────────
          bottomNavigationBar: widget.isOwn && !_isClosed
              ? (_isDraft
                  ? _DeployActions(
                      deploying: _deploying,
                      onDeploy: _deployStrategy,
                      onEdit: () => context.push('/create-strategy', extra: {
                        'editDocId': widget.docId,
                        'editUid': widget.uid,
                        'prefill': widget.data,
                      }),
                    )
                  : _BottomActions(
                      ltp: ltp,
                      closing: _closing,
                      onClose: () => _showCloseDialog(ltp),
                    ))
              : _isClosed
              ? _ClosedBanner(status: _status)
              : null,
        );
      },
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Live price hero card — flat ink surface, tabular numerals, a small
// signal-colored pulse for "live" instead of a glowing dot.
// ─────────────────────────────────────────────────────────────────────────────

class _LivePriceHero extends StatelessWidget {
  const _LivePriceHero({
    required this.symbol,
    required this.ltp,
    required this.entry,
    required this.gainPct,
    required this.gainRs,
    required this.isProfit,
    required this.isClosed,
    required this.changePercent,
    required this.isMarketClosed,
  });

  final String symbol;
  final double ltp, entry, gainPct, gainRs, changePercent;
  final bool isProfit, isClosed, isMarketClosed;

  @override
  Widget build(BuildContext context) {
    final moveColor = isProfit ? _ST.signal : const Color(0xFFFF8478);

    return Container(
      padding: const EdgeInsets.fromLTRB(20, 22, 20, 20),
      decoration: BoxDecoration(
        color: _ST.ink,
        borderRadius: BorderRadius.circular(_ST.r24),
      ),
      child: Column(
        children: [
          // LTP row
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                '₹${ltp.toStringAsFixed(2)}',
                style: _ST.numeral(size: 32, weight: FontWeight.w800, color: _ST.onInk1, letterSpacing: -1.0),
              ),
              const SizedBox(width: 8),
              if (!isMarketClosed && !isClosed)
                Container(
                  margin: const EdgeInsets.only(bottom: 6),
                  padding: const EdgeInsets.symmetric(
                      horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    '${changePercent >= 0 ? '+' : ''}${changePercent.toStringAsFixed(2)}%',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: changePercent >= 0 ? _ST.signal : const Color(0xFFFF8478),
                    ),
                  ),
                ),
            ],
          ),

          if (isMarketClosed)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text('Market closed',
                  style: TextStyle(
                      fontSize: 11.5,
                      color: _ST.onInk2,
                      fontWeight: FontWeight.w600)),
            ),

          const SizedBox(height: 16),
          Container(height: 1, color: Colors.white.withValues(alpha: 0.08)),
          const SizedBox(height: 16),

          // P&L row
          if (entry > 0) ...[
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _HeroStat(
                  label: 'Entry',
                  value: '₹${entry.toStringAsFixed(2)}',
                ),
                Column(
                  children: [
                    Text(
                      '${isProfit ? '+' : ''}${gainPct.toStringAsFixed(2)}%',
                      style: _ST.numeral(size: 22, weight: FontWeight.w800, color: moveColor, letterSpacing: -0.6),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${isProfit ? '+' : ''}₹${gainRs.abs().toStringAsFixed(0)} P&L',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: moveColor,
                      ),
                    ),
                  ],
                ),
                isClosed
                    ? const _HeroStat(label: 'Status', value: 'Closed')
                    : const _HeroLiveStat(),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _HeroStat extends StatelessWidget {
  const _HeroStat({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(label,
            style: const TextStyle(
                fontSize: 11, color: _ST.onInk2, fontWeight: FontWeight.w600)),
        const SizedBox(height: 4),
        Text(value,
            style: _ST.numeral(size: 14, weight: FontWeight.w700, color: _ST.onInk1, letterSpacing: -0.2)),
      ],
    );
  }
}

class _HeroLiveStat extends StatelessWidget {
  const _HeroLiveStat();

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        const Text('Status',
            style: TextStyle(fontSize: 11, color: _ST.onInk2, fontWeight: FontWeight.w600)),
        const SizedBox(height: 6),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _PulseDot(color: _ST.signal),
            const SizedBox(width: 5),
            const Text('Live',
                style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w800, color: _ST.signal)),
          ],
        ),
      ],
    );
  }
}

/// Pulsing dot indicator.
class _PulseDot extends StatefulWidget {
  const _PulseDot({required this.color});
  final Color color;

  @override
  State<_PulseDot> createState() => _PulseDotState();
}

class _PulseDotState extends State<_PulseDot> with SingleTickerProviderStateMixin {
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
        height: 7, width: 7,
        decoration: BoxDecoration(color: widget.color, shape: BoxShape.circle),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Drop armed banner
// ─────────────────────────────────────────────────────────────────────────────

// ─────────────────────────────────────────────────────────────────────────────
// Draft banner — shown when strategy has status='active' (saved but not deployed)
// ─────────────────────────────────────────────────────────────────────────────
class _DraftBanner extends StatelessWidget {
  const _DraftBanner({required this.strategyName});
  final String strategyName;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
    decoration: BoxDecoration(
      color: const Color(0xFFFFFBEB),
      borderRadius: BorderRadius.circular(_ST.r14),
      border: Border.all(color: const Color(0xFFFDE68A)),
    ),
    child: Row(children: [
      const Text('📋', style: TextStyle(fontSize: 20)),
      const SizedBox(width: 12),
      const Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('Draft — not deployed', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: Color(0xFFD97706))),
        SizedBox(height: 2),
        Text('Tap "Deploy Now" below to activate the engine. It will watch the market and place orders when your trigger price is hit.', style: TextStyle(fontSize: 11, color: Color(0xFF92400E), height: 1.4)),
      ])),
    ]),
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// Deploy actions bar — replaces Close for draft strategies
// ─────────────────────────────────────────────────────────────────────────────
class _DeployActions extends StatelessWidget {
  const _DeployActions({required this.deploying, required this.onDeploy, required this.onEdit});
  final bool deploying;
  final VoidCallback onDeploy;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) => Container(
    padding: EdgeInsets.fromLTRB(16, 12, 16, MediaQuery.of(context).padding.bottom + 12),
    decoration: const BoxDecoration(
      color: _ST.surface,
      border: Border(top: BorderSide(color: _ST.divider, width: 1)),
    ),
    child: Row(children: [
      // Edit button
      Expanded(child: OutlinedButton.icon(
        onPressed: onEdit,
        style: OutlinedButton.styleFrom(
          foregroundColor: _ST.primary,
          side: const BorderSide(color: _ST.primary),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          minimumSize: const Size.fromHeight(50),
        ),
        icon: const Icon(Icons.edit_outlined, size: 18),
        label: const Text('Edit', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
      )),
      const SizedBox(width: 12),
      // Deploy button
      Expanded(flex: 2, child: ElevatedButton.icon(
        onPressed: deploying ? null : onDeploy,
        style: ElevatedButton.styleFrom(
          backgroundColor: _ST.profit,
          foregroundColor: Colors.white,
          elevation: 0,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          minimumSize: const Size.fromHeight(50),
        ),
        icon: deploying
            ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
            : const Icon(Icons.rocket_launch_rounded, size: 20),
        label: Text(
          deploying ? 'Deploying…' : 'Deploy Now',
          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
        ),
      )),
    ]),
  );
}

class _DropArmedBanner extends StatelessWidget {
  const _DropArmedBanner(
      {required this.dropEnabled, required this.data});

  final bool dropEnabled;
  final Map<String, dynamic> data;

  String _buildConditionText() {
    final triggerType  = data['entry_condition_type'] as String?
        ?? data['drop_trigger_type'] as String?
        ?? 'above';
    final triggerPrice = (data['entry_condition_price'] as num?)?.toDouble()
        ?? (data['drop_trigger_price'] as num?)?.toDouble();
    final triggerMin   = (data['drop_trigger_min'] as num?)?.toDouble();
    final triggerMax   = (data['drop_trigger_max'] as num?)?.toDouble();
    final symbol       = data['symbol'] as String? ?? 'price';

    switch (triggerType) {
      case 'below':
        return 'Engine will place order when $symbol drops below ₹${triggerPrice?.toStringAsFixed(2) ?? '—'}';
      case 'in_range':
        return 'Engine will place order when $symbol enters ₹${triggerMin?.toStringAsFixed(2) ?? '—'} – ₹${triggerMax?.toStringAsFixed(2) ?? '—'}';
      case 'at_market':
        return 'Engine will place order at current market price on next run';
      default:
        return 'Engine will place order when $symbol rises above ₹${triggerPrice?.toStringAsFixed(2) ?? '—'}';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: _ST.warning.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(_ST.r14),
        border: Border.all(color: _ST.warning.withValues(alpha: 0.28)),
      ),
      child: Row(
        children: [
          const Icon(Icons.radar_rounded, size: 20, color: _ST.warning),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Engine watching — waiting for entry',
                  style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                      color: _ST.warning),
                ),
                const SizedBox(height: 2),
                Text(
                  _buildConditionText(),
                  style: TextStyle(
                      fontSize: 11,
                      color: _ST.warning.withValues(alpha: 0.85)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Price ladder visualizer
// ─────────────────────────────────────────────────────────────────────────────

class _PriceLadder extends StatelessWidget {
  const _PriceLadder({
    required this.sl,
    required this.entry,
    required this.ltp,
    required this.target,
    required this.isBuy,
    required this.isProfit,
  });

  final double sl, entry, ltp, target;
  final bool isBuy, isProfit;

  @override
  Widget build(BuildContext context) {
    final profitColor = isProfit ? _ST.profit : _ST.loss;

    // % from entry
    final ltpPct = entry > 0 ? ((ltp - entry) / entry * 100) : 0.0;
    final tgtPct = entry > 0 ? ((target - entry) / entry * 100) : 0.0;
    final slPct  = entry > 0 ? ((sl - entry) / entry * 100) : 0.0;

    // Ordered levels top→bottom for BUY: target > ltp? > entry > ltp? > sl
    final levels = isBuy
        ? [
      _LadderLevel('Target',   target, tgtPct, _ST.profit, false),
      if (ltp > entry)
        _LadderLevel('Current ₹', ltp, ltpPct, profitColor, true),
      _LadderLevel('Entry',    entry,  0.0,    _ST.t2, false),
      if (ltp <= entry)
        _LadderLevel('Current ₹', ltp, ltpPct, profitColor, true),
      _LadderLevel('SL',       sl,   slPct,   _ST.loss,  false),
    ]
        : [
      // SELL: target is below entry
      _LadderLevel('Entry',    entry,  0.0,    _ST.t2, false),
      if (ltp > entry)
        _LadderLevel('Current ₹', ltp, ltpPct, profitColor, true),
      if (ltp <= entry)
        _LadderLevel('Current ₹', ltp, ltpPct, profitColor, true),
      _LadderLevel('Target',  target, tgtPct, _ST.profit,  false),
      _LadderLevel('SL',       sl,   slPct,   _ST.loss,   false),
    ];

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: _ST.card(),
      child: Column(
        children: [
          for (int i = 0; i < levels.length; i++) ...[
            _LadderRow(level: levels[i]),
            if (i < levels.length - 1)
              Padding(
                padding: const EdgeInsets.only(left: 19),
                child: Container(
                  width: 1.5,
                  height: 20,
                  color: _ST.divider,
                ),
              ),
          ],
        ],
      ),
    );
  }
}

class _LadderLevel {
  const _LadderLevel(
      this.label, this.price, this.pct, this.color, this.isCurrent);
  final String label;
  final double price;
  final double pct;
  final Color color;
  final bool isCurrent;
}

class _LadderRow extends StatelessWidget {
  const _LadderRow({required this.level});
  final _LadderLevel level;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        // Node circle
        Container(
          width: 10,
          height: 10,
          margin: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: level.isCurrent
                ? level.color
                : level.color.withValues(alpha: 0.25),
            border: Border.all(color: level.color, width: 1.5),
          ),
        ),
        // Label
        Expanded(
          child: Text(
            level.label,
            style: TextStyle(
              fontSize: level.isCurrent ? 13 : 12,
              fontWeight: level.isCurrent
                  ? FontWeight.w800
                  : FontWeight.w600,
              color: level.isCurrent ? level.color : _ST.t2,
            ),
          ),
        ),
        // Price
        Text(
          '₹${level.price.toStringAsFixed(2)}',
          style: _ST.numeral(
            size: level.isCurrent ? 15 : 13,
            weight: FontWeight.w800,
            color: level.isCurrent ? level.color : _ST.t1,
          ),
        ),
        const SizedBox(width: 12),
        // % chip
        SizedBox(
          width: 58,
          child: level.pct != 0
              ? Container(
            padding: const EdgeInsets.symmetric(
                horizontal: 6, vertical: 3),
            decoration: BoxDecoration(
              color: level.color.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              '${level.pct >= 0 ? '+' : ''}${level.pct.toStringAsFixed(2)}%',
              textAlign: TextAlign.center,
              style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  color: level.color),
            ),
          )
              : const SizedBox.shrink(),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Stats grid
// ─────────────────────────────────────────────────────────────────────────────

class _StatsGrid extends StatelessWidget {
  const _StatsGrid({
    required this.action,
    required this.category,
    required this.type,
    required this.confidence,
    required this.quantity,
    required this.riskRs,
    required this.entry,
    required this.target,
    required this.sl,
    this.target2 = 0,
    this.orderType = 'LIMIT',
    this.execMode = 'immediate',
    this.trailingSL = false,
    this.trailingSLMode = 'points',
    this.trailingSLValue = 0,
    this.autoExecute = false,
    this.sizeMode = 'qty',
    this.isBracket = false,
    this.productType = 'CNC',
    this.validity = 'DAY',
    this.validTill,
  });

  final String action, category, type, confidence;
  final int quantity;
  final double riskRs, entry, target, sl;
  final double target2;
  final String orderType, execMode, sizeMode;
  final bool trailingSL, autoExecute, isBracket;
  final String trailingSLMode;
  final double trailingSLValue;
  final String productType;
  final String validity;
  final DateTime? validTill;

  double? get _rr {
    if (entry <= 0 || target <= 0 || sl <= 0) return null;
    final up = (target - entry).abs();
    final dn = (entry - sl).abs();
    return dn > 0 ? up / dn : null;
  }

  String _typeLabel() {
    switch (type) {
      case 'intraday':    return 'Intraday';
      case 'short_term':  return 'Short-term';
      case 'medium_term': return 'Medium-term';
      case 'long_term':   return 'Long-term';
      default:            return type;
    }
  }

  String _execLabel() {
    switch (execMode) {
      case 'conditional': return 'Conditional';
      case 'bracket':     return 'Bracket (OCO)';
      default:            return 'Immediate';
    }
  }

  String _sizeModeLabel() {
    switch (sizeMode) {
      case 'capitalPct': return '% Capital';
      case 'fixedRs':    return 'Fixed ₹';
      default:           return 'Qty';
    }
  }

  @override
  Widget build(BuildContext context) {
    final rr = _rr;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: _ST.card(),
      child: Column(
        children: [
          // Row 1: Direction + Category
          Row(
            children: [
              _StatTile(
                  icon: Icons.swap_vert_rounded,
                  label: 'Direction',
                  value: action,
                  color: action.toUpperCase() == 'BUY' ? _ST.profit : _ST.loss),
              _StatTile(
                  icon: Icons.category_rounded,
                  label: 'Category',
                  value: category[0].toUpperCase() + category.substring(1),
                  color: _ST.primary),
            ],
          ),
          const SizedBox(height: 14),
          // Row 2: Timeframe + Confidence
          Row(
            children: [
              _StatTile(
                  icon: Icons.schedule_rounded,
                  label: 'Timeframe',
                  value: _typeLabel(),
                  color: _ST.info),
              if (confidence.isNotEmpty)
                _StatTile(
                  icon: Icons.emoji_events_outlined,
                  label: 'Confidence',
                  value: confidence[0].toUpperCase() + confidence.substring(1),
                  color: confidence == 'high'
                      ? _ST.profit
                      : confidence == 'medium'
                      ? _ST.warning
                      : _ST.t3,
                )
              else
                _StatTile(
                    icon: Icons.layers_rounded,
                    label: 'Quantity',
                    value: '$quantity',
                    color: _ST.t2),
            ],
          ),
          const SizedBox(height: 14),
          // Row 3: Risk + R:R
          Row(
            children: [
              _StatTile(
                icon: Icons.shield_outlined,
                label: 'Risk (₹)',
                value: riskRs > 0 ? '₹${riskRs.toStringAsFixed(0)}' : '—',
                color: _ST.loss,
              ),
              _StatTile(
                icon: Icons.balance_rounded,
                label: 'R:R ratio',
                value: rr != null ? '${rr.toStringAsFixed(2)}x' : '—',
                color: rr != null && rr >= 2 ? _ST.profit : _ST.warning,
              ),
            ],
          ),
          const SizedBox(height: 14),
          // Row 4: Order type + Execution mode
          Row(
            children: [
              _StatTile(
                icon: Icons.receipt_long_outlined,
                label: 'Order type',
                value: orderType,
                color: _ST.primary,
              ),
              _StatTile(
                icon: isBracket
                    ? Icons.account_tree_outlined
                    : execMode == 'conditional'
                        ? Icons.radio_button_checked_rounded
                        : Icons.flash_on_rounded,
                label: 'Execution',
                value: _execLabel(),
                color: execMode == 'conditional'
                    ? _ST.warning
                    : execMode == 'bracket'
                        ? _ST.info
                        : _ST.profit,
              ),
            ],
          ),
          const SizedBox(height: 14),
          // Row 5: Quantity/sizing + auto-execute
          Row(
            children: [
              _StatTile(
                icon: Icons.layers_rounded,
                label: 'Qty  (${_sizeModeLabel()})',
                value: '$quantity',
                color: _ST.t2,
              ),
              _StatTile(
                icon: autoExecute
                    ? Icons.smart_toy_outlined
                    : Icons.person_outline_rounded,
                label: 'Execute via',
                value: autoExecute ? 'Algo engine' : 'Manual',
                color: autoExecute ? _ST.profit : _ST.t3,
              ),
            ],
          ),
          // Row 6: T2 target (if set)
          if (target2 > 0) ...[
            const SizedBox(height: 14),
            Row(
              children: [
                _StatTile(
                  icon: Icons.outlined_flag_rounded,
                  label: 'Target 2 (T2)',
                  value: '₹${target2.toStringAsFixed(2)}',
                  color: const Color(0xFF0A916B),
                ),
                _StatTile(
                  icon: Icons.trending_up_rounded,
                  label: 'T2 upside',
                  value: entry > 0
                      ? '+${((target2 - entry) / entry * 100).toStringAsFixed(1)}%'
                      : '—',
                  color: const Color(0xFF0A916B),
                ),
              ],
            ),
          ],
          // Row 7: Trailing SL (if enabled)
          if (trailingSL) ...[
            const SizedBox(height: 14),
            Row(
              children: [
                _StatTile(
                  icon: Icons.linear_scale_rounded,
                  label: 'Trailing SL',
                  value: trailingSLMode == 'pct'
                      ? '${trailingSLValue.toStringAsFixed(1)}%'
                      : '₹${trailingSLValue.toStringAsFixed(2)}',
                  color: _ST.warning,
                ),
                _StatTile(
                  icon: Icons.track_changes_rounded,
                  label: 'Trail mode',
                  value: trailingSLMode == 'pct' ? '% of LTP' : 'Fixed points',
                  color: _ST.warning,
                ),
              ],
            ),
          ],
          // Row 8: Product type + Order validity
          const SizedBox(height: 14),
          Row(
            children: [
              _StatTile(
                icon: Icons.account_balance_outlined,
                label: 'Product type',
                value: productType,
                color: productType == 'MIS'
                    ? _ST.warning
                    : productType == 'NRML'
                        ? _ST.info
                        : _ST.profit,
              ),
              _StatTile(
                icon: Icons.access_time_rounded,
                label: 'Order validity',
                value: validity,
                color: _ST.t2,
              ),
            ],
          ),
          // Row 9: Valid-till (conditional strategies)
          if (validTill != null) ...[
            const SizedBox(height: 14),
            Row(
              children: [
                _StatTile(
                  icon: Icons.event_outlined,
                  label: 'Expires on',
                  value:
                      '${validTill!.day}/${validTill!.month}/${validTill!.year}',
                  color: DateTime.now().isAfter(validTill!)
                      ? _ST.loss
                      : _ST.warning,
                ),
                _StatTile(
                  icon: Icons.hourglass_bottom_rounded,
                  label: 'Days left',
                  value: DateTime.now().isAfter(validTill!)
                      ? 'Expired'
                      : '${validTill!.difference(DateTime.now()).inDays}d',
                  color: DateTime.now().isAfter(validTill!)
                      ? _ST.loss
                      : _ST.t2,
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _StatTile extends StatelessWidget {
  const _StatTile({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
  });

  final IconData icon;
  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Row(
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, size: 15, color: color),
          ),
          const SizedBox(width: 10),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: const TextStyle(fontSize: 10, color: _ST.t3)),
              const SizedBox(height: 2),
              Text(value,
                  style: _ST.numeral(size: 13, weight: FontWeight.w700, color: color, letterSpacing: -0.1)),
            ],
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Thesis card
// ─────────────────────────────────────────────────────────────────────────────

class _ThesisCard extends StatelessWidget {
  const _ThesisCard({
    required this.description,
    required this.duration,
    required this.tags,
  });

  final String description;
  final String duration;
  final List<String> tags;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: _ST.card(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (duration.isNotEmpty) ...[
            Row(
              children: [
                Icon(Icons.schedule_rounded, size: 14, color: _ST.t3),
                const SizedBox(width: 6),
                Text('Expected: $duration',
                    style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: _ST.t2)),
              ],
            ),
            const SizedBox(height: 10),
          ],
          Text(
            description,
            style: const TextStyle(
              fontSize: 14,
              height: 1.6,
              color: _ST.t1,
            ),
          ),
          if (tags.isNotEmpty) ...[
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: tags.map((t) => _TagChip(tag: t)).toList(),
            ),
          ],
        ],
      ),
    );
  }
}

class _TagChip extends StatelessWidget {
  const _TagChip({required this.tag});
  final String tag;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: _ST.primary.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: _ST.primary.withValues(alpha: 0.22)),
      ),
      child: Text(
        '#$tag',
        style: const TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: _ST.primary,
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Bottom action bar
// ─────────────────────────────────────────────────────────────────────────────

class _BottomActions extends StatelessWidget {
  const _BottomActions({
    required this.ltp,
    required this.closing,
    required this.onClose,
  });

  final double ltp;
  final bool closing;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.fromLTRB(
          16, 12, 16, MediaQuery.of(context).padding.bottom + 12),
      decoration: const BoxDecoration(
        color: _ST.surface,
        border: Border(top: BorderSide(color: _ST.divider, width: 1)),
      ),
      child: SizedBox(
        width: double.infinity,
        height: 50,
        child: ElevatedButton.icon(
          onPressed: closing ? null : onClose,
          style: ElevatedButton.styleFrom(
            backgroundColor: _ST.loss,
            foregroundColor: Colors.white,
            elevation: 0,
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14)),
          ),
          icon: closing
              ? const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(
                  strokeWidth: 2, color: Colors.white))
              : const Icon(Icons.close_rounded, size: 20),
          label: Text(
            closing ? 'Closing…' : 'Close strategy',
            style: const TextStyle(
                fontSize: 15, fontWeight: FontWeight.w700),
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// In-position banner
// ─────────────────────────────────────────────────────────────────────────────

class _InPositionBanner extends StatelessWidget {
  const _InPositionBanner({required this.entryLtp});
  final double? entryLtp;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: _ST.info.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(_ST.r14),
        border: Border.all(color: _ST.info.withValues(alpha: 0.28)),
      ),
      child: Row(
        children: [
          const Icon(Icons.trending_up_rounded, size: 20, color: _ST.info),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'In position — engine monitoring SL & target',
                  style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                      color: _ST.info),
                ),
                if (entryLtp != null)
                  Text(
                    'Entered @ ₹${entryLtp!.toStringAsFixed(2)} · Auto-exit on target or SL',
                    style: TextStyle(
                        fontSize: 11,
                        color: _ST.info.withValues(alpha: 0.85)),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Closed banner (shown for closed strategies)
// ─────────────────────────────────────────────────────────────────────────────

class _ClosedBanner extends StatelessWidget {
  const _ClosedBanner({required this.status});
  final String status;

  @override
  Widget build(BuildContext context) {
    Color color;
    String label;
    IconData icon;
    switch (status) {
      case 'target_hit':
      case 'hit_target':    // legacy
        color = _ST.profit;
        label = 'Target hit — strategy closed';
        icon  = Icons.emoji_events_rounded;
        break;
      case 'sl_hit':
      case 'stoploss_hit':  // legacy
        color = _ST.loss;
        label = 'Stop-loss hit — strategy closed';
        icon  = Icons.shield_outlined;
        break;
      default:
        color = _ST.t2;
        label = 'Strategy closed';
        icon  = Icons.check_circle_outline_rounded;
    }

    return Container(
      padding: EdgeInsets.fromLTRB(
          16, 12, 16, MediaQuery.of(context).padding.bottom + 12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.06),
        border: Border(top: BorderSide(color: color.withValues(alpha: 0.2))),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(width: 8),
          Text(label,
              style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: color)),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Section header label
// ─────────────────────────────────────────────────────────────────────────────

class _SectionHeader extends StatelessWidget {
  const _SectionHeader(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: const TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.w800,
        color: _ST.t1,
        letterSpacing: -0.1,
      ),
    );
  }
}