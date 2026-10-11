import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../cubits/live_price_cubit.dart';

/// Returns the market closed label for a symbol, or empty string if open.
/// NSE/BSE close at 3:30 PM IST. MCX closes at 11:30 PM IST.
/// Both are closed on weekends.
String _marketStatusLabel(String symbol) {
  final ist = DateTime.now().toUtc().add(const Duration(hours: 5, minutes: 30));
  final dayOfWeek = ist.weekday; // 1=Mon, 7=Sun
  final isWeekend = dayOfWeek == 6 || dayOfWeek == 7;

  if (isWeekend) return 'Market Closed';

  final totalMin = ist.hour * 60 + ist.minute;
  const mcxSymbols = {'GOLD', 'SILVER', 'CRUDEOIL'};
  final isMcx = mcxSymbols.contains(symbol.toUpperCase());

  if (isMcx) {
    // MCX: 9:00 AM (540) – 11:30 PM (1410)
    if (totalMin >= 540 && totalMin < 1410) return '';
    return 'MCX Closed';
  } else {
    // NSE/BSE: 9:15 AM (555) – 3:30 PM (930)
    if (totalMin >= 555 && totalMin < 930) return '';
    return 'NSE Closed';
  }
}

/// Displays a live price for [symbol], falling back to [fallbackPrice]
/// when no Socket.IO price has been received yet.
///
/// Animates with a brief green/red flash when the price changes.
/// Shows exchange-specific closed label (NSE Closed / MCX Closed).
class LivePriceText extends StatefulWidget {
  final String symbol;
  final double fallbackPrice;
  final TextStyle? style;
  final String prefix;
  final bool showChange;

  const LivePriceText({
    super.key,
    required this.symbol,
    required this.fallbackPrice,
    this.style,
    this.prefix = '₹',
    this.showChange = false,
  });

  @override
  State<LivePriceText> createState() => _LivePriceTextState();
}

class _LivePriceTextState extends State<LivePriceText>
    with SingleTickerProviderStateMixin {
  late AnimationController _flashController;
  late Animation<Color?> _flashColor;
  double? _prevLtp;

  @override
  void initState() {
    super.initState();
    _flashController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );
    _flashColor = ColorTween(
      begin: Colors.transparent,
      end:   Colors.transparent,
    ).animate(_flashController);
  }

  @override
  void dispose() {
    _flashController.dispose();
    super.dispose();
  }

  void _triggerFlash(double newLtp) {
    if (_prevLtp == null) {
      _prevLtp = newLtp;
      return;
    }
    final isUp = newLtp > _prevLtp!;
    _prevLtp = newLtp;

    _flashColor = ColorTween(
      begin: isUp
          ? Colors.green.withOpacity(0.25)
          : Colors.red.withOpacity(0.25),
      end: Colors.transparent,
    ).animate(CurvedAnimation(
      parent: _flashController,
      curve: Curves.easeOut,
    ));

    _flashController.forward(from: 0);
  }

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<LivePriceCubit, LivePriceState>(
      buildWhen: (prev, curr) =>
          prev.prices[widget.symbol]?.ltp != curr.prices[widget.symbol]?.ltp ||
          prev.isMarketClosed != curr.isMarketClosed,
      builder: (context, state) {
        final tick = state.prices[widget.symbol];
        final ltp  = tick?.ltp ?? widget.fallbackPrice;

        // Per-symbol market status (NSE vs MCX have different hours)
        final symbolLabel = _marketStatusLabel(widget.symbol);
        final isMarketClosed = symbolLabel.isNotEmpty || state.isMarketClosed;
        final closedLabel = symbolLabel.isNotEmpty ? symbolLabel : 'Market Closed';

        if (tick != null && !isMarketClosed) _triggerFlash(ltp);

        return AnimatedBuilder(
          animation: _flashController,
          builder: (_, child) => Container(
            padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 1),
            decoration: BoxDecoration(
              color:        _flashColor.value,
              borderRadius: BorderRadius.circular(4),
            ),
            child: child,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '${widget.prefix}${ltp.toStringAsFixed(2)}',
                style: widget.style,
              ),
              if (isMarketClosed)
                Text(
                  closedLabel,
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                    color: Colors.grey.shade500,
                  ),
                )
              else if (widget.showChange && tick != null)
                Text(
                  '${tick.isPositive ? '+' : ''}${tick.changePercent.toStringAsFixed(2)}%',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: tick.isPositive
                        ? const Color(0xFF16A34A)
                        : const Color(0xFFDC2626),
                  ),
                ),            ],
          ),
        );
      },
    );
  }
}
