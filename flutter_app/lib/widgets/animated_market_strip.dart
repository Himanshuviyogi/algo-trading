import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../cubits/live_price_cubit.dart';
import '../services/live_price_service.dart';

/// Fixed list of 12 reputed Indian stocks/indices shown in the scrolling strip.
/// These must be in `instrument_tokens` on the price server.
const List<_StripSymbol> _kStripSymbols = [
  _StripSymbol('NIFTY',      'Nifty 50'),
  _StripSymbol('BANKNIFTY',  'Bank Nifty'),
  _StripSymbol('SENSEX',     'Sensex'),
  _StripSymbol('RELIANCE',   'Reliance'),
  _StripSymbol('TCS',        'TCS'),
  _StripSymbol('HDFCBANK',   'HDFC Bank'),
  _StripSymbol('INFY',       'Infosys'),
  _StripSymbol('SBIN',       'SBI'),
  _StripSymbol('ICICIBANK',  'ICICI Bank'),
  _StripSymbol('GOLD',       'Gold'),
  _StripSymbol('CRUDEOIL',   'Crude Oil'),
  _StripSymbol('USDINR',     'USD/INR'),
];

class _StripSymbol {
  final String symbol;
  final String label;
  const _StripSymbol(this.symbol, this.label);
}

/// Horizontally auto-scrolling price strip driven by the price server
/// (Socket.IO via LivePriceCubit) — real-time, no Finnhub API needed.
class AnimatedMarketStrip extends StatefulWidget {
  const AnimatedMarketStrip({super.key});

  @override
  State<AnimatedMarketStrip> createState() => _AnimatedMarketStripState();
}

class _AnimatedMarketStripState extends State<AnimatedMarketStrip>
    with SingleTickerProviderStateMixin {
  late final ScrollController _scrollController;
  late final AnimationController _animController;
  DateTime? _lastTick;

  static const double _pixelsPerSecond = 40.0;

  @override
  void initState() {
    super.initState();
    _scrollController = ScrollController();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 1),
    )..repeat();
    _animController.addListener(_onAnimTick);

    // Subscribe the strip symbols to the live price feed
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      context.read<LivePriceCubit>().subscribe(
        _kStripSymbols.map((s) => s.symbol).toList(),
      );
    });
  }

  void _onAnimTick() {
    if (!_scrollController.hasClients) return;
    final pos = _scrollController.position;
    if (pos.maxScrollExtent <= 0) return;

    final now = DateTime.now();
    final elapsed = _lastTick == null
        ? 0.0
        : now.difference(_lastTick!).inMicroseconds / 1e6;
    _lastTick = now;

    final next = pos.pixels + _pixelsPerSecond * elapsed;
    final singlePassWidth = pos.maxScrollExtent / 100;
    if (pos.pixels >= singlePassWidth) {
      _scrollController.jumpTo(pos.pixels - singlePassWidth);
    } else {
      _scrollController.jumpTo(next.clamp(0.0, pos.maxScrollExtent));
    }
  }

  @override
  void dispose() {
    _animController.removeListener(_onAnimTick);
    _animController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<LivePriceCubit, LivePriceState>(
      // Only rebuild when one of the strip symbols changes
      buildWhen: (prev, curr) => _kStripSymbols.any((s) =>
          prev.prices[s.symbol]?.ltp != curr.prices[s.symbol]?.ltp),
      builder: (context, state) {
        // Show strip even with partial data (cached prices)
        final hasAny = _kStripSymbols.any((s) => state.prices[s.symbol] != null);
        if (!hasAny) return const SizedBox.shrink();

        return GestureDetector(
          onTap: () => context.push('/market'),
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            height: 42,
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.7),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.grey.shade200),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.04),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: AnimatedBuilder(
                animation: _animController,
                builder: (_, __) => ListView.builder(
                  controller: _scrollController,
                  scrollDirection: Axis.horizontal,
                  physics: const NeverScrollableScrollPhysics(),
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  itemCount: _kStripSymbols.length * 100,
                  itemBuilder: (_, i) {
                    final sym = _kStripSymbols[i % _kStripSymbols.length];
                    final tick = state.prices[sym.symbol];
                    if (tick == null) return const SizedBox(width: 8);
                    return _StripItem(label: sym.label, tick: tick);
                  },
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

// ── Single item ──────────────────────────────────────────────────────────────

class _StripItem extends StatelessWidget {
  final String label;
  final PriceTick tick;
  const _StripItem({required this.label, required this.tick});

  @override
  Widget build(BuildContext context) {
    final isUp = tick.isPositive;
    final color = isUp ? const Color(0xFF16A34A) : const Color(0xFFDC2626);
    final sign  = isUp ? '+' : '';

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label,
              style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 13,
                  color: Color(0xFF111827))),
          const SizedBox(width: 6),
          Text(tick.ltp.toStringAsFixed(2),
              style: const TextStyle(fontSize: 13, color: Color(0xFF374151))),
          const SizedBox(width: 4),
          Icon(isUp ? Icons.arrow_drop_up : Icons.arrow_drop_down,
              size: 16, color: color),
          Text(
            '$sign${tick.changePercent.abs().toStringAsFixed(2)}%',
            style: TextStyle(
                fontSize: 12, color: color, fontWeight: FontWeight.w600),
          ),
          const SizedBox(width: 12),
          Container(width: 1, height: 18, color: Colors.grey.shade200),
        ],
      ),
    );
  }
}
