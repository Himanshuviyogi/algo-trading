import 'package:equatable/equatable.dart';

// ── OptionLeg ─────────────────────────────────────────────────────────────────
// One side (CE or PE) of a strike row.

class OptionLeg extends Equatable {
  const OptionLeg({
    required this.oi,
    required this.oiChange,
    required this.ltp,
    required this.ltpChange,
    required this.volume,
    required this.iv,
    this.delta,
    this.gamma,
    this.theta,
    this.vega,
    this.bidPrice,
    this.askPrice,
    this.bidQty,
    this.askQty,
  });

  final int    oi;
  final int    oiChange;
  final double ltp;
  final double ltpChange;
  final int    volume;
  final double iv;

  // Greeks — present when source is Angel One, null from NSE
  final double? delta;
  final double? gamma;
  final double? theta;
  final double? vega;

  // Bid/Ask
  final double? bidPrice;
  final double? askPrice;
  final int?    bidQty;
  final int?    askQty;

  /// OI in thousands for display (e.g. 418200 → 418.2K)
  double get oiK => oi / 1000.0;

  /// Positive OI change means fresh long buildup, negative = unwinding
  bool get isOiBuildUp => oiChange > 0;

  factory OptionLeg.fromMap(Map<String, dynamic> m) => OptionLeg(
        oi:        (m['oi']        as num?)?.toInt()    ?? 0,
        oiChange:  (m['oiChange']  as num?)?.toInt()    ?? 0,
        ltp:       (m['ltp']       as num?)?.toDouble() ?? 0,
        ltpChange: (m['ltpChange'] as num?)?.toDouble() ?? 0,
        volume:    (m['volume']    as num?)?.toInt()    ?? 0,
        iv:        (m['iv']        as num?)?.toDouble() ?? 0,
        delta:     (m['delta']     as num?)?.toDouble(),
        gamma:     (m['gamma']     as num?)?.toDouble(),
        theta:     (m['theta']     as num?)?.toDouble(),
        vega:      (m['vega']      as num?)?.toDouble(),
        bidPrice:  (m['bidPrice']  as num?)?.toDouble(),
        askPrice:  (m['askPrice']  as num?)?.toDouble(),
        bidQty:    (m['bidQty']    as num?)?.toInt(),
        askQty:    (m['askQty']    as num?)?.toInt(),
      );

  @override
  List<Object?> get props => [oi, oiChange, ltp, ltpChange, volume, iv];
}

// ── OptionStrike ──────────────────────────────────────────────────────────────
// A single strike row with CE + PE legs.

class OptionStrike extends Equatable {
  const OptionStrike({
    required this.strike,
    this.ce,
    this.pe,
    this.isAtm = false,
  });

  final double     strike;
  final OptionLeg? ce;
  final OptionLeg? pe;
  final bool       isAtm;

  factory OptionStrike.fromMap(Map<String, dynamic> m) => OptionStrike(
        strike: (m['strike'] as num?)?.toDouble() ?? 0,
        ce: m['ce'] != null
            ? OptionLeg.fromMap(Map<String, dynamic>.from(m['ce'] as Map))
            : null,
        pe: m['pe'] != null
            ? OptionLeg.fromMap(Map<String, dynamic>.from(m['pe'] as Map))
            : null,
      );

  OptionStrike copyWith({bool? isAtm}) => OptionStrike(
        strike: strike,
        ce: ce,
        pe: pe,
        isAtm: isAtm ?? this.isAtm,
      );

  @override
  List<Object?> get props => [strike, ce, pe, isAtm];
}

// ── OptionChainData ───────────────────────────────────────────────────────────
// Full chain for one symbol + expiry.

class OptionChainData extends Equatable {
  const OptionChainData({
    required this.symbol,
    required this.underlyingValue,
    required this.expiry,
    required this.allExpiries,
    required this.rows,
    required this.source,
    required this.fetchedAt,
    this.cached = false,
  });

  final String            symbol;
  final double            underlyingValue;
  final String?           expiry;
  final List<String>      allExpiries;
  final List<OptionStrike> rows;
  final String            source;    // 'nse' | 'angelone'
  final DateTime          fetchedAt;
  final bool              cached;

  // ── Derived metrics ────────────────────────────────────────────────────────

  /// Total CE open interest across all strikes
  int get totalCeOi => rows.fold(0, (s, r) => s + (r.ce?.oi ?? 0));

  /// Total PE open interest across all strikes
  int get totalPeOi => rows.fold(0, (s, r) => s + (r.pe?.oi ?? 0));

  /// Put-Call ratio (>1 = more puts = bearish pressure)
  double get pcr => totalCeOi > 0 ? totalPeOi / totalCeOi : 0;

  /// Strike with highest total OI (CE+PE) — used as "max pain" proxy
  double get maxPainStrike {
    if (rows.isEmpty) return 0;
    return rows
        .reduce((a, b) {
          final aOi = (a.ce?.oi ?? 0) + (a.pe?.oi ?? 0);
          final bOi = (b.ce?.oi ?? 0) + (b.pe?.oi ?? 0);
          return aOi > bOi ? a : b;
        })
        .strike;
  }

  /// Max OI value across all CE and PE legs — used to scale OI bars
  int get maxOi {
    int m = 0;
    for (final r in rows) {
      if ((r.ce?.oi ?? 0) > m) m = r.ce!.oi;
      if ((r.pe?.oi ?? 0) > m) m = r.pe!.oi;
    }
    return m;
  }

  factory OptionChainData.fromMap(Map<String, dynamic> m) {
    final rawRows = (m['rows'] as List?)
            ?.map((e) => OptionStrike.fromMap(Map<String, dynamic>.from(e as Map)))
            .toList() ??
        [];

    final underlying = (m['underlyingValue'] as num?)?.toDouble() ?? 0;

    // Mark the ATM row — strike closest to underlying value
    List<OptionStrike> rows = rawRows;
    if (underlying > 0 && rawRows.isNotEmpty) {
      double minDist = double.infinity;
      int atmIdx = 0;
      for (int i = 0; i < rawRows.length; i++) {
        final dist = (rawRows[i].strike - underlying).abs();
        if (dist < minDist) {
          minDist = dist;
          atmIdx = i;
        }
      }
      rows = [
        for (int i = 0; i < rawRows.length; i++)
          rawRows[i].copyWith(isAtm: i == atmIdx),
      ];
    }

    return OptionChainData(
      symbol:          m['symbol']          as String? ?? '',
      underlyingValue: underlying,
      expiry:          m['expiry']           as String?,
      allExpiries:     (m['allExpiries'] as List?)
                           ?.map((e) => e.toString())
                           .toList() ??
                       [],
      rows:    rows,
      source:  m['source']   as String? ?? 'nse',
      cached:  m['cached']   as bool?   ?? false,
      fetchedAt: DateTime.fromMillisecondsSinceEpoch(
        (m['fetchedAt'] as num?)?.toInt() ?? DateTime.now().millisecondsSinceEpoch,
      ),
    );
  }

  @override
  List<Object?> get props =>
      [symbol, underlyingValue, expiry, rows, source, fetchedAt];
}
