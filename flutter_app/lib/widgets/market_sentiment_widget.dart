import 'dart:math' as math;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../cubits/live_price_cubit.dart';

// ── Trend data model ──────────────────────────────────────────────────────────

enum _TrendSignal { bullish, bearish, neutral }

class _IndexTrend {
  final String name;
  final _TrendSignal signal;
  final int confidence;

  const _IndexTrend({
    required this.name,
    required this.signal,
    required this.confidence,
  });
}

_TrendSignal _signalFromChange(double change) {
  if (change > 0.3) return _TrendSignal.bullish;
  if (change < -0.3) return _TrendSignal.bearish;
  return _TrendSignal.neutral;
}

/// Confidence is 50–95 mapped from absolute percent change.
int _confidenceFrom(double change) {
  final abs = change.abs().clamp(0.0, 3.0);
  return (50 + (abs / 3.0) * 45).round();
}

// ── Main widget ───────────────────────────────────────────────────────────────

class MarketSentimentWidget extends StatelessWidget {
  const MarketSentimentWidget({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<LivePriceCubit, LivePriceState>(
      buildWhen: (p, c) {
        final pNifty = p.prices['NIFTY']?.changePercent;
        final cNifty = c.prices['NIFTY']?.changePercent;
        final pBank  = p.prices['BANKNIFTY']?.changePercent;
        final cBank  = c.prices['BANKNIFTY']?.changePercent;
        return pNifty != cNifty || pBank != cBank;
      },
      builder: (context, state) {
        final niftyChange    = state.prices['NIFTY']?.changePercent    ?? 0.65;
        final bankChange     = state.prices['BANKNIFTY']?.changePercent ?? 0.42;

        final niftyTrend = _IndexTrend(
          name:       'NIFTY 50',
          signal:     _signalFromChange(niftyChange),
          confidence: _confidenceFrom(niftyChange),
        );
        final bankTrend = _IndexTrend(
          name:       'BANK NIFTY',
          signal:     _signalFromChange(bankChange),
          confidence: _confidenceFrom(bankChange),
        );

        // gauge score: 0–100 mapped from combined change
        final combined = (niftyChange + bankChange) / 2;
        final gaugeScore = ((combined + 3.0) / 6.0 * 100).clamp(0.0, 100.0);

        return _AiTrendInsightCard(
          niftyTrend:  niftyTrend,
          bankTrend:   bankTrend,
          gaugeScore:  gaugeScore,
        );
      },
    );
  }
}

// ── Card ──────────────────────────────────────────────────────────────────────

class _AiTrendInsightCard extends StatelessWidget {
  final _IndexTrend niftyTrend;
  final _IndexTrend bankTrend;
  final double gaugeScore;

  const _AiTrendInsightCard({
    required this.niftyTrend,
    required this.bankTrend,
    required this.gaugeScore,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.07),
            blurRadius: 20,
            spreadRadius: 0,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Header ──────────────────────────────────────────────────────
            Row(
              children: [
                Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    color: Color(0xFFEEF2FF),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  alignment: Alignment.center,
                  child: const Text('🧠', style: TextStyle(fontSize: 18)),
                ),
                const SizedBox(width: 10),
                const Text(
                  'AI Trend Insight',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF111827),
                    letterSpacing: -0.3,
                  ),
                ),
              ],
            ),

            const SizedBox(height: 16),

            // ── Body: index badges + gauge ───────────────────────────────────
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                // Left: NIFTY 50
                Expanded(child: _IndexSignalColumn(trend: niftyTrend, align: CrossAxisAlignment.start,textAlign: TextAlign.left,)),

                // Centre: gauge
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: _GaugeWidget(score: gaugeScore),
                ),

                // Right: BANK NIFTY
                Expanded(child: _IndexSignalColumn(trend: bankTrend, align: CrossAxisAlignment.end,textAlign: TextAlign.right,)),
              ],
            ),

            const SizedBox(height: 12),

            // ── Smart money flow ticker ──────────────────────────────────────
            const _SmartMoneyTicker(),
          ],
        ),
      ),
    );
  }
}

// ── Index signal column ───────────────────────────────────────────────────────

class _IndexSignalColumn extends StatelessWidget {
  final _IndexTrend trend;
  final CrossAxisAlignment align;
  final TextAlign textAlign;

  const _IndexSignalColumn({required this.trend, required this.align,required this.textAlign});

  @override
  Widget build(BuildContext context) {
    final isBullish = trend.signal == _TrendSignal.bullish;
    final isBearish = trend.signal == _TrendSignal.bearish;

    final Color badgeColor;
    final String badgeLabel;
    final String arrow;

    if (isBullish) {
      badgeColor = const Color(0xFF16A34A);
      badgeLabel = 'BULLISH';
      arrow = ' ↗';
    } else if (isBearish) {
      badgeColor = const Color(0xFFDC2626);
      badgeLabel = 'BEARISH';
      arrow = ' ↘';
    } else {
      badgeColor = const Color(0xFFCA8A04);
      badgeLabel = 'NEUTRAL';
      arrow = ' →';
    }

    return Column(
      crossAxisAlignment: align,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          trend.name,
          style: const TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            color: Color(0xFF374151),
            letterSpacing: 0.2,
          ),
        ),
        const SizedBox(height: 6),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
            color: badgeColor,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(
            '$badgeLabel$arrow',
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w800,
              color: Colors.white,
              letterSpacing: 0.4,
            ),
          ),
        ),
        const SizedBox(height: 6),
        Align(
          alignment: Alignment.centerRight,

          child: RichText(
            textAlign: textAlign,
            text: TextSpan(
              style: const TextStyle(
                fontSize: 11,
                color: Color(0xFF6B7280),
              ),
              children: [
                const TextSpan(text: 'AI Confidence  '),
                TextSpan(
                  text: '${trend.confidence}%',

                  style: TextStyle(

                    fontWeight: FontWeight.w800,
                    color: badgeColor,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

// ── Speedometer gauge ─────────────────────────────────────────────────────────

class _GaugeWidget extends StatelessWidget {
  final double score; // 0 – 100

  const _GaugeWidget({required this.score});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 110,
      height: 72,
      child: CustomPaint(
        painter: _SpeedometerPainter(score: score),
      ),
    );
  }
}

class _SpeedometerPainter extends CustomPainter {
  final double score;
  const _SpeedometerPainter({required this.score});

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final cy = size.height - 8;
    final radius = size.width / 2 - 6;
    const strokeW = 10.0;

    // ── Track ────────────────────────────────────────────────────────────────
    final trackPaint = Paint()
      ..color = const Color(0xFFF1F5F9)
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeW
      ..strokeCap = StrokeCap.round;

    canvas.drawArc(
      Rect.fromCircle(center: Offset(cx, cy), radius: radius),
      math.pi,
      math.pi,
      false,
      trackPaint,
    );

    // ── Gradient arc ─────────────────────────────────────────────────────────
    final sweep = (score / 100.0) * math.pi;
    if (sweep > 0) {
      final arcRect = Rect.fromCircle(center: Offset(cx, cy), radius: radius);
      final shader = SweepGradient(
        startAngle: math.pi,
        endAngle: math.pi * 2,
        colors: const [
          Color(0xFFEF4444),
          Color(0xFFF97316),
          Color(0xFFEAB308),
          Color(0xFF84CC16),
          Color(0xFF22C55E),
        ],
      ).createShader(arcRect);

      final arcPaint = Paint()
        ..shader = shader
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeW
        ..strokeCap = StrokeCap.round;

      canvas.drawArc(arcRect, math.pi, sweep, false, arcPaint);
    }

    // ── Needle ───────────────────────────────────────────────────────────────
    final needleAngle = math.pi + (score / 100.0) * math.pi;
    final outerR = radius - strokeW / 2 - 2;
    final innerR = 10.0;

    final nx = cx + outerR * math.cos(needleAngle);
    final ny = cy + outerR * math.sin(needleAngle);
    final bx = cx + innerR * math.cos(needleAngle + math.pi);
    final by = cy + innerR * math.sin(needleAngle + math.pi);

    // shadow
    canvas.drawLine(
      Offset(bx, by),
      Offset(nx, ny),
      Paint()
        ..color = Colors.black.withValues(alpha: 0.18)
        ..strokeWidth = 4
        ..strokeCap = StrokeCap.round
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2),
    );
    // needle
    canvas.drawLine(
      Offset(bx, by),
      Offset(nx, ny),
      Paint()
        ..color = const Color(0xFF1F2937)
        ..strokeWidth = 2.5
        ..strokeCap = StrokeCap.round,
    );

    // pivot
    canvas.drawCircle(Offset(cx, cy), 6, Paint()..color = const Color(0xFF1F2937));
    canvas.drawCircle(Offset(cx, cy), 3, Paint()..color = Colors.white);
  }

  @override
  bool shouldRepaint(_SpeedometerPainter old) => old.score != score;
}

// ── Smart money flow ticker ───────────────────────────────────────────────────
// Reads from Firestore `market_data/fii_dii` + live NIFTY price to generate
// a contextual message instead of showing a hardcoded string.

class _SmartMoneyTicker extends StatelessWidget {
  const _SmartMoneyTicker();

  /// Shared, app-lifetime stream for `market_data/fii_dii`.
  /// Static so all instances of this widget reuse the same Firestore listener
  /// instead of each opening a new one (and charging an extra read).
  static final Stream<DocumentSnapshot> _fiiDiiStream =
      FirebaseFirestore.instance
          .collection('market_data')
          .doc('fii_dii')
          .snapshots()
          .asBroadcastStream();

  /// Builds a human-readable insight from real FII/DII data + live price.
  static String _buildMessage({
    required double fiiNet,      // crores; positive = buying
    required double diiNet,
    required double niftyLtp,    // 0 if unavailable
    required double niftyChange, // % change
  }) {
    final fiiFlow = fiiNet > 0 ? 'positive' : fiiNet < 0 ? 'negative' : null;
    final diiFlow = diiNet > 0 ? 'buying' : diiNet < 0 ? 'selling' : null;

    // Format a crore value: ₹1.2K Cr or ₹450 Cr
    String fmt(double v) {
      final abs = v.abs();
      if (abs >= 1000) return '₹${(abs / 1000).toStringAsFixed(1)}K Cr';
      return '₹${abs.toStringAsFixed(0)} Cr';
    }

    // Approximate support/resistance from live price (rounded to nearest 100)
    String support(double ltp) {
      if (ltp <= 0) return '';
      final lvl = (ltp / 100).floor() * 100;
      return lvl > 0 ? _fmt(lvl.toDouble()) : '';
    }

    final parts = <String>[];

    if (fiiFlow != null) {
      parts.add('FII flow is $fiiFlow (${fmt(fiiNet)})');
    }
    if (diiFlow != null) {
      parts.add('DII $diiFlow (${fmt(diiNet)})');
    }

    if (parts.isEmpty) {
      // Fall back to pure price-based message
      if (niftyChange > 0.5) {
        return 'NIFTY momentum is bullish. Smart money accumulating at dips.';
      } else if (niftyChange < -0.5) {
        return 'NIFTY under pressure. Watch for support near ${support(niftyLtp)}.';
      }
      return 'NIFTY trading sideways. Await directional breakout.';
    }

    final base = parts.join('. ');

    // Add price context if available
    if (niftyLtp > 0) {
      final sup = support(niftyLtp);
      if (fiiNet > 0) {
        return '$base. Support near $sup.';
      } else {
        return '$base. Watch support near $sup.';
      }
    }

    return base;
  }

  static String _fmt(double v) {
    // Format number with comma: 23800 → 23,800
    final s = v.toStringAsFixed(0);
    final buf = StringBuffer();
    for (int i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) buf.write(',');
      buf.write(s[i]);
    }
    return buf.toString();
  }

  @override
  Widget build(BuildContext context) {
    // NOTE: The stream below reads market_data/fii_dii — same doc as _FiiDiiCard.
    // A shared cubit/provider would eliminate this second listener entirely, but
    // storing the stream as a field (in the enclosing StatefulWidget) at minimum
    // prevents re-subscription on every rebuild of the parent.
    //
    // This widget is used inside MarketSentimentWidget (a StatelessWidget), so
    // we store the stream as a static field so it is truly created only once
    // for the lifetime of the app, not once per widget instance.
    return StreamBuilder<DocumentSnapshot>(
      stream: _SmartMoneyTicker._fiiDiiStream,
      builder: (context, snap) {
        double fiiNet = 0, diiNet = 0;

        if (snap.hasData && snap.data!.exists) {
          final d = snap.data!.data() as Map<String, dynamic>? ?? {};
          if (d['status'] == 'ok') {
            fiiNet = (d['fii']?['total_net'] as num?)?.toDouble() ?? 0;
            diiNet = (d['dii']?['total_net'] as num?)?.toDouble() ?? 0;
          }
        }

        return BlocBuilder<LivePriceCubit, LivePriceState>(
          buildWhen: (p, c) =>
              p.prices['NIFTY']?.ltp != c.prices['NIFTY']?.ltp ||
              p.prices['NIFTY']?.changePercent != c.prices['NIFTY']?.changePercent,
          builder: (context, priceState) {
            final niftyLtp    = priceState.prices['NIFTY']?.ltp            ?? 0.0;
            final niftyChange = priceState.prices['NIFTY']?.changePercent  ?? 0.0;

            final message = _buildMessage(
              fiiNet:      fiiNet,
              diiNet:      diiNet,
              niftyLtp:    niftyLtp,
              niftyChange: niftyChange,
            );

            final isPositive = fiiNet > 0 || niftyChange > 0;
            final iconEmoji  = isPositive ? '⭐' : '⚠️';

            return Container(
              decoration: const BoxDecoration(
                border: Border(
                  top: BorderSide(color: Color(0xFFF3F4F6), width: 1),
                ),
              ),
              padding: const EdgeInsets.symmetric(vertical: 10),
              child: Row(
                children: [
                  Container(
                    width: 28,
                    height: 28,
                    decoration: BoxDecoration(
                      color: const Color(0xFF6366F1).withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    alignment: Alignment.center,
                    child: Text(iconEmoji, style: const TextStyle(fontSize: 13)),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      message,
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF374151),
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 6),
                  // const Icon(
                  //   Icons.chevron_right_rounded,
                  //   size: 18,
                  //   color: Color(0xFF9CA3AF),
                  // ),
                ],
              ),
            );
          },
        );
      },
    );
  }
}
