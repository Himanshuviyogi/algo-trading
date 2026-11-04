import 'dart:math' as math;
import 'package:flutter/material.dart';

// ─────────────────────────────────────────────────────────────────────────────
// PayoffThumbnail
//
// A tiny payoff-at-expiry diagram that can be dropped into any card.
// Needs only a list of (strikeN, optType, side) leg descriptors — no live data.
//
// Usage:
//   PayoffThumbnail(legs: myLegs, spotPrice: 24500, lotSize: 65)
//
// The widget is pure-math — no network calls, no state.
// ─────────────────────────────────────────────────────────────────────────────

// ── Minimal leg descriptor ────────────────────────────────────────────────────
class PayoffLeg {
  final String side;     // 'Buy' | 'Sell'
  final String optType;  // 'Call' | 'Put'
  final int    strikeN;  // ATM offset in steps (0 = ATM, +2 = OTM Call, -2 = ITM Call)
  final int    qty;
  const PayoffLeg({
    required this.side,
    required this.optType,
    required this.strikeN,
    this.qty = 1,
  });

  /// Build from a Firestore legs map entry.
  factory PayoffLeg.fromMap(Map<String, dynamic> m) => PayoffLeg(
    side:    m['side']        as String? ?? 'Buy',
    optType: m['option_type'] as String? ?? 'Call',
    strikeN: (m['strike_n']  as num?)?.toInt() ?? 0,
    qty:     (m['quantity']  as num?)?.toInt() ?? 1,
  );
}

// ── Point on the payoff curve ──────────────────────────────────────────────────
class _Pt { final double x, y; const _Pt(this.x, this.y); }

// ── Compute payoff across a ±10 % spot range ──────────────────────────────────
List<_Pt> _computeCurve(List<PayoffLeg> legs, double spot) {
  const steps   = 60;
  const spread  = 0.10; // ±10 %
  final low     = spot * (1 - spread);
  final high    = spot * (1 + spread);
  final premium = spot * 0.018;  // ATM premium heuristic ~1.8 %

  final pts = <_Pt>[];
  for (int i = 0; i <= steps; i++) {
    final s   = low + (high - low) * i / steps;
    double pnl = 0;
    for (final leg in legs) {
      final strikeOffset = leg.strikeN * spot * 0.005; // each step ≈ 0.5 % of spot
      final strike       = spot + strikeOffset;
      final intrinsic    = leg.optType == 'Call'
          ? math.max(0.0, s - strike)
          : math.max(0.0, strike - s);
      final legPnl = leg.side == 'Buy'
          ? (intrinsic - premium) * leg.qty
          : (premium - intrinsic) * leg.qty;
      pnl += legPnl;
    }
    pts.add(_Pt(i / steps, pnl));
  }
  return pts;
}

// ── Painter ───────────────────────────────────────────────────────────────────
class _PayoffThumbPainter extends CustomPainter {
  _PayoffThumbPainter({
    required this.pts,
    required this.minY,
    required this.maxY,
    required this.profitColor,
    required this.lossColor,
  });

  final List<_Pt> pts;
  final double minY, maxY;
  final Color profitColor, lossColor;

  // Map a pnl value to a canvas y coordinate (inverted — top = high pnl)
  double _toY(double pnl, double height) {
    final range = (maxY - minY).abs();
    if (range == 0) return height / 2;
    return height - ((pnl - minY) / range) * height;
  }

  // Canvas x from normalised [0,1]
  double _toX(double t, double width) => t * width;

  @override
  void paint(Canvas canvas, Size size) {
    if (pts.length < 2) return;

    final zeroY = _toY(0, size.height);

    // ── Build smooth path ─────────────────────────────────────────────────
    final curvePath = Path();
    final firstX = _toX(pts.first.x, size.width);
    final firstY = _toY(pts.first.y, size.height);
    curvePath.moveTo(firstX, firstY);

    for (int i = 1; i < pts.length; i++) {
      final prev = pts[i - 1];
      final curr = pts[i];
      final px   = _toX(prev.x, size.width);
      final py   = _toY(prev.y, size.height);
      final cx   = _toX(curr.x, size.width);
      final cy   = _toY(curr.y, size.height);
      final midX = (px + cx) / 2;
      curvePath.cubicTo(midX, py, midX, cy, cx, cy);
    }

    // ── Build fill paths (profit = above zero line, loss = below) ────────
    final profitFill = Path();
    final lossFill   = Path();

    // Walk through pairs and split at zero crossings
    for (int i = 0; i < pts.length - 1; i++) {
      final a  = pts[i];
      final b  = pts[i + 1];
      final ax = _toX(a.x, size.width);
      final ay = _toY(a.y, size.height);
      final bx = _toX(b.x, size.width);
      final by = _toY(b.y, size.height);

      if (a.y >= 0 && b.y >= 0) {
        // entirely above zero → profit fill
        profitFill.moveTo(ax, zeroY);
        profitFill.lineTo(ax, ay);
        final midX = (ax + bx) / 2;
        profitFill.cubicTo(midX, ay, midX, by, bx, by);
        profitFill.lineTo(bx, zeroY);
        profitFill.close();
      } else if (a.y <= 0 && b.y <= 0) {
        // entirely below zero → loss fill
        lossFill.moveTo(ax, zeroY);
        lossFill.lineTo(ax, ay);
        final midX = (ax + bx) / 2;
        lossFill.cubicTo(midX, ay, midX, by, bx, by);
        lossFill.lineTo(bx, zeroY);
        lossFill.close();
      } else {
        // crossing — compute intersection x
        final t     = a.y / (a.y - b.y);   // 0..1 along segment
        final crossX = ax + t * (bx - ax);

        if (a.y >= 0) {
          // a above, b below
          profitFill.moveTo(ax, zeroY);
          profitFill.lineTo(ax, ay);
          profitFill.lineTo(crossX, zeroY);
          profitFill.close();

          lossFill.moveTo(crossX, zeroY);
          lossFill.lineTo(bx, by);
          lossFill.lineTo(bx, zeroY);
          lossFill.close();
        } else {
          // a below, b above
          lossFill.moveTo(ax, zeroY);
          lossFill.lineTo(ax, ay);
          lossFill.lineTo(crossX, zeroY);
          lossFill.close();

          profitFill.moveTo(crossX, zeroY);
          profitFill.lineTo(bx, by);
          profitFill.lineTo(bx, zeroY);
          profitFill.close();
        }
      }
    }

    // ── Draw fills ────────────────────────────────────────────────────────
    canvas.drawPath(
      profitFill,
      Paint()..color = profitColor.withValues(alpha: 0.22)..style = PaintingStyle.fill,
    );
    canvas.drawPath(
      lossFill,
      Paint()..color = lossColor.withValues(alpha: 0.18)..style = PaintingStyle.fill,
    );

    // ── Zero line ─────────────────────────────────────────────────────────
    canvas.drawLine(
      Offset(0, zeroY),
      Offset(size.width, zeroY),
      Paint()
        ..color = Colors.black.withValues(alpha: 0.12)
        ..strokeWidth = 0.8
        ..style = PaintingStyle.stroke,
    );

    // ── Curve line ────────────────────────────────────────────────────────
    canvas.drawPath(
      curvePath,
      Paint()
        ..color = Colors.black.withValues(alpha: 0.72)
        ..strokeWidth = 1.6
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );
  }

  @override
  bool shouldRepaint(covariant _PayoffThumbPainter old) =>
      old.pts != pts || old.minY != minY || old.maxY != maxY;
}

// ── Public widget ─────────────────────────────────────────────────────────────
class PayoffThumbnail extends StatelessWidget {
  const PayoffThumbnail({
    super.key,
    required this.legs,
    this.spotPrice = 24500.0,
    this.width  = 120,
    this.height = 64,
    this.profitColor = const Color(0xFF0E7C6B),
    this.lossColor   = const Color(0xFFD1483F),
    this.borderRadius = 10.0,
    this.backgroundColor,
  });

  final List<PayoffLeg> legs;
  final double spotPrice;
  final double width;
  final double height;
  final Color profitColor;
  final Color lossColor;
  final double borderRadius;
  final Color? backgroundColor;

  @override
  Widget build(BuildContext context) {
    if (legs.isEmpty) return SizedBox(width: width, height: height);

    final pts  = _computeCurve(legs, spotPrice);
    final minY = pts.map((p) => p.y).reduce(math.min);
    final maxY = pts.map((p) => p.y).reduce(math.max);
    // Give a small padding so the curve doesn't clip at edges
    final padded = (maxY - minY).abs() < 1 ? 1.0 : (maxY - minY) * 0.15;

    return ClipRRect(
      borderRadius: BorderRadius.circular(borderRadius),
      child: Container(
        width: width, height: height,
        color: backgroundColor ?? Colors.transparent,
        child: CustomPaint(
          painter: _PayoffThumbPainter(
            pts:         pts,
            minY:        minY - padded,
            maxY:        maxY + padded,
            profitColor: profitColor,
            lossColor:   lossColor,
          ),
        ),
      ),
    );
  }
}

// ── Convenience: build legs from a Firestore rawData map ──────────────────────
List<PayoffLeg> payoffLegsFromRaw(Map<String, dynamic> raw) {
  final legsRaw = raw['legs'] as List<dynamic>?;
  if (legsRaw == null || legsRaw.isEmpty) {
    // Stocks / no legs — return a simple directional line
    final action = (raw['trade'] as Map?)?['action'] as String? ?? 'BUY';
    return [
      PayoffLeg(side: 'Buy', optType: action == 'BUY' ? 'Call' : 'Put', strikeN: 0),
    ];
  }
  return legsRaw
      .cast<Map<String, dynamic>>()
      .map(PayoffLeg.fromMap)
      .toList();
}

// ── Preset payoff leg definitions matching _buildPresets() in create_strategy_screen ──
const Map<String, List<PayoffLeg>> kPresetLegs = {
  'Bull Call Spread': [
    PayoffLeg(side: 'Buy',  optType: 'Call', strikeN: 0),
    PayoffLeg(side: 'Sell', optType: 'Call', strikeN: 2),
  ],
  'Bear Put Spread': [
    PayoffLeg(side: 'Buy',  optType: 'Put', strikeN:  0),
    PayoffLeg(side: 'Sell', optType: 'Put', strikeN: -2),
  ],
  'Straddle': [
    PayoffLeg(side: 'Buy', optType: 'Call', strikeN: 0),
    PayoffLeg(side: 'Buy', optType: 'Put',  strikeN: 0),
  ],
  'Strangle': [
    PayoffLeg(side: 'Buy', optType: 'Call', strikeN:  2),
    PayoffLeg(side: 'Buy', optType: 'Put',  strikeN: -2),
  ],
  'Iron Condor': [
    PayoffLeg(side: 'Buy',  optType: 'Put',  strikeN: -4),
    PayoffLeg(side: 'Sell', optType: 'Put',  strikeN: -2),
    PayoffLeg(side: 'Sell', optType: 'Call', strikeN:  2),
    PayoffLeg(side: 'Buy',  optType: 'Call', strikeN:  4),
  ],
  'Covered Call': [
    PayoffLeg(side: 'Buy',  optType: 'Call', strikeN: -6),
    PayoffLeg(side: 'Sell', optType: 'Call', strikeN:  2),
  ],
};
