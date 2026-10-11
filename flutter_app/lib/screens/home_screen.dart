import 'dart:ui';

import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../utils/app_theme.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key, required this.navigationShell});

  final StatefulNavigationShell navigationShell;

  void _onTap(BuildContext context, int index) {
    navigationShell.goBranch(
      index,
      initialLocation: index == navigationShell.currentIndex,
    );
  }

  @override
  Widget build(BuildContext context) {
    final isOnHomeTab = navigationShell.currentIndex == 0;
    final viewPadding = MediaQuery.of(context).viewPadding.bottom;

    return PopScope(
      canPop: isOnHomeTab,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) navigationShell.goBranch(0, initialLocation: true);
      },
      child: Scaffold(
        backgroundColor: Colors.transparent,
        extendBody: true,
        body: Stack(
          children: [
            // ── Main navigation content ─────────────────────────────────
            navigationShell,
          ],
        ),
        bottomNavigationBar: Padding(
          padding: EdgeInsets.fromLTRB(16, 0, 16, 12 + viewPadding),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(32),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 28, sigmaY: 28),
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 10),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(32),
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      AuroraColors.surface.withOpacity(0.90),
                      AuroraColors.card.withOpacity(0.85),
                    ],
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: AuroraColors.violet.withOpacity(0.16),
                      blurRadius: 28,
                      spreadRadius: 0,
                      offset: const Offset(0, 8),
                    ),
                    BoxShadow(
                      color: Colors.black.withOpacity(0.07),
                      blurRadius: 16,
                      offset: const Offset(0, 4),
                    ),
                  ],
                  border: Border.all(
                    color: AuroraColors.violet.withOpacity(0.18),
                    width: 1,
                  ),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    // index 0 — Home dashboard
                    _NavItem(
                      index: 0,
                      label: 'Home',
                      icon: const _HomeIcon(),
                      isSelected: navigationShell.currentIndex == 0,
                      onTap: () => _onTap(context, 0),
                    ),
                    // index 1 — Strategies
                    _NavItem(
                      index: 1,
                      label: 'Strategies',
                      icon: const _StrategiesIcon(),
                      isSelected: navigationShell.currentIndex == 1,
                      onTap: () => _onTap(context, 1),
                    ),
                    // index 2 — Orders
                    _NavItem(
                      index: 2,
                      label: 'Orders',
                      icon: const _OrdersIcon(),
                      isSelected: navigationShell.currentIndex == 2,
                      onTap: () => _onTap(context, 2),
                    ),
                    // index 3 — Positions
                    _NavItem(
                      index: 3,
                      label: 'Positions',
                      icon: const _PositionsIcon(),
                      isSelected: navigationShell.currentIndex == 3,
                      onTap: () => _onTap(context, 3),
                    ),
                    // index 4 — Profile
                    _NavItem(
                      index: 4,
                      label: 'Profile',
                      icon: const _ProfileIcon(),
                      isSelected: navigationShell.currentIndex == 4,
                      onTap: () => _onTap(context, 4),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ── Nav item wrapper ──────────────────────────────────────────────────────────

class _NavItem extends StatelessWidget {
  const _NavItem({
    required this.index,
    required this.label,
    required this.icon,
    required this.isSelected,
    required this.onTap,
  });

  final int index;
  final String label;
  final Widget icon;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 250),
              curve: Curves.easeOut,
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: isSelected
                    ? AuroraColors.violet.withOpacity(0.18)
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(12),
                border: isSelected
                    ? Border.all(color: AuroraColors.violet.withOpacity(0.35), width: 1)
                    : null,
              ),
              child: AnimatedScale(
                scale: isSelected ? 1.05 : 1.0,
                duration: const Duration(milliseconds: 250),
                curve: Curves.easeOut,
                child: SizedBox(width: 22, height: 22, child: icon),
              ),
            ),
            const SizedBox(height: 2),
            Text(
              label,
              style: TextStyle(
                fontSize: 11,
                fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                color: isSelected
                    ? AuroraColors.violet
                    : AuroraColors.textMuted,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── 3D-style icon painters ────────────────────────────────────────────────────

/// 🏠 Home — blue house with white walls, dark blue roof, green bush
class _HomeIcon extends StatelessWidget {
  const _HomeIcon();
  @override
  Widget build(BuildContext context) {
    return CustomPaint(painter: _HomePainter());
  }
}

class _HomePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;

    // ── Shadow under house ──
    final shadowPaint = Paint()
      ..color = Colors.black.withOpacity(0.12)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2);
    canvas.drawOval(
      Rect.fromCenter(center: Offset(w * 0.5, h * 0.92), width: w * 0.7, height: h * 0.1),
      shadowPaint,
    );

    // ── House body ──
    final bodyPath = Path()
      ..moveTo(w * 0.12, h * 0.55)
      ..lineTo(w * 0.88, h * 0.55)
      ..lineTo(w * 0.88, h * 0.88)
      ..lineTo(w * 0.12, h * 0.88)
      ..close();
    canvas.drawPath(bodyPath, Paint()..color = const Color(0xFFF0F4FF));
    final bodyRight = Path()
      ..moveTo(w * 0.88, h * 0.55)
      ..lineTo(w * 0.95, h * 0.60)
      ..lineTo(w * 0.95, h * 0.93)
      ..lineTo(w * 0.88, h * 0.88)
      ..close();
    canvas.drawPath(bodyRight, Paint()..color = const Color(0xFFD0D8F0));

    // ── Roof ──
    final roofPath = Path()
      ..moveTo(w * 0.50, h * 0.08)
      ..lineTo(w * 0.96, h * 0.52)
      ..lineTo(w * 0.04, h * 0.52)
      ..close();
    canvas.drawPath(
      roofPath,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [const Color(0xFF3D6FE8), const Color(0xFF1E3FC0)],
        ).createShader(Rect.fromLTWH(0, 0, w, h)),
    );
    final roofRight = Path()
      ..moveTo(w * 0.50, h * 0.08)
      ..lineTo(w * 0.96, h * 0.52)
      ..lineTo(w * 0.96, h * 0.58)
      ..lineTo(w * 0.50, h * 0.14)
      ..close();
    canvas.drawPath(roofRight, Paint()..color = const Color(0xFF1530A0));
    canvas.drawLine(
      Offset(w * 0.50, h * 0.08),
      Offset(w * 0.04, h * 0.52),
      Paint()
        ..color = Colors.white.withOpacity(0.4)
        ..strokeWidth = 1.5,
    );

    // ── Door ──
    final doorRect = RRect.fromRectAndCorners(
      Rect.fromLTWH(w * 0.38, h * 0.62, w * 0.24, h * 0.26),
      topLeft: const Radius.circular(4),
      topRight: const Radius.circular(4),
    );
    canvas.drawRRect(doorRect, Paint()..color = const Color(0xFF2255CC));
    canvas.drawRRect(
      RRect.fromRectAndCorners(
        Rect.fromLTWH(w * 0.39, h * 0.63, w * 0.06, h * 0.12),
        topLeft: const Radius.circular(2),
        topRight: const Radius.circular(2),
      ),
      Paint()..color = Colors.white.withOpacity(0.25),
    );
    canvas.drawCircle(Offset(w * 0.58, h * 0.76), w * 0.025, Paint()..color = const Color(0xFFFFD700));

    // ── Bush ──
    final bushPaint = Paint()
      ..shader = RadialGradient(
        colors: [const Color(0xFF4CD66B), const Color(0xFF1A9E35)],
      ).createShader(Rect.fromCircle(center: Offset(w * 0.22, h * 0.82), radius: w * 0.12));
    canvas.drawCircle(Offset(w * 0.18, h * 0.84), w * 0.09, bushPaint);
    canvas.drawCircle(Offset(w * 0.27, h * 0.82), w * 0.07, bushPaint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// 🤖 Strategies — robot / algo bot icon
class _StrategiesIcon extends StatelessWidget {
  const _StrategiesIcon();
  @override
  Widget build(BuildContext context) =>
      CustomPaint(painter: _StrategiesPainter());
}

class _StrategiesPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;

    // Shadow
    canvas.drawOval(
      Rect.fromCenter(
          center: Offset(w * 0.5, h * 0.96), width: w * 0.7, height: h * 0.08),
      Paint()
        ..color = Colors.black.withOpacity(0.10)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2),
    );

    // Antenna
    canvas.drawLine(
      Offset(w * 0.5, h * 0.04),
      Offset(w * 0.5, h * 0.18),
      Paint()
        ..color = const Color(0xFF4C46E5)
        ..strokeWidth = 2.0
        ..strokeCap = StrokeCap.round,
    );
    canvas.drawCircle(
      Offset(w * 0.5, h * 0.04),
      w * 0.055,
      Paint()..color = const Color(0xFF6366F1),
    );

    // Head body
    final headRect = RRect.fromRectAndRadius(
      Rect.fromLTWH(w * 0.12, h * 0.18, w * 0.76, h * 0.45),
      const Radius.circular(6),
    );
    canvas.drawRRect(
      headRect,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [const Color(0xFF5B5FF5), const Color(0xFF3730C4)],
        ).createShader(headRect.outerRect),
    );
    // Gloss
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(w * 0.16, h * 0.20, w * 0.68, h * 0.08),
        const Radius.circular(4),
      ),
      Paint()..color = Colors.white.withOpacity(0.20),
    );

    // Left eye
    canvas.drawRRect(
      RRect.fromRectAndRadius(
          Rect.fromLTWH(w * 0.22, h * 0.28, w * 0.20, h * 0.14),
          const Radius.circular(3)),
      Paint()..color = const Color(0xFF22C55E),
    );
    canvas.drawCircle(Offset(w * 0.32, h * 0.35), w * 0.05,
        Paint()..color = Colors.white.withOpacity(0.6));

    // Right eye
    canvas.drawRRect(
      RRect.fromRectAndRadius(
          Rect.fromLTWH(w * 0.58, h * 0.28, w * 0.20, h * 0.14),
          const Radius.circular(3)),
      Paint()..color = const Color(0xFF22C55E),
    );
    canvas.drawCircle(Offset(w * 0.68, h * 0.35), w * 0.05,
        Paint()..color = Colors.white.withOpacity(0.6));

    // Mouth bar (status LED strip)
    canvas.drawRRect(
      RRect.fromRectAndRadius(
          Rect.fromLTWH(w * 0.22, h * 0.50, w * 0.56, h * 0.06),
          const Radius.circular(3)),
      Paint()..color = const Color(0xFF10B981).withOpacity(0.8),
    );

    // Body
    final bodyRect = RRect.fromRectAndRadius(
      Rect.fromLTWH(w * 0.20, h * 0.64, w * 0.60, h * 0.26),
      const Radius.circular(5),
    );
    canvas.drawRRect(
      bodyRect,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [const Color(0xFF4C46E5), const Color(0xFF2D2AAA)],
        ).createShader(bodyRect.outerRect),
    );

    // Body circuit lines
    final linePaint = Paint()
      ..color = Colors.white.withOpacity(0.25)
      ..strokeWidth = 1.2
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(
        Offset(w * 0.30, h * 0.73), Offset(w * 0.70, h * 0.73), linePaint);
    canvas.drawLine(
        Offset(w * 0.30, h * 0.81), Offset(w * 0.55, h * 0.81), linePaint);

    // Side arms
    canvas.drawRRect(
      RRect.fromRectAndRadius(
          Rect.fromLTWH(w * 0.02, h * 0.65, w * 0.16, h * 0.18),
          const Radius.circular(4)),
      Paint()..color = const Color(0xFF3730C4),
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
          Rect.fromLTWH(w * 0.82, h * 0.65, w * 0.16, h * 0.18),
          const Radius.circular(4)),
      Paint()..color = const Color(0xFF3730C4),
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// 📊 Market — bar chart + green arrow
class _MarketIcon extends StatelessWidget {
  const _MarketIcon();
  @override
  Widget build(BuildContext context) => CustomPaint(painter: _MarketPainter());
}

class _MarketPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;

    canvas.drawOval(
      Rect.fromCenter(center: Offset(w * 0.5, h * 0.95), width: w * 0.75, height: h * 0.07),
      Paint()
        ..color = Colors.black.withOpacity(0.10)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2),
    );
    canvas.drawLine(Offset(w * 0.06, h * 0.88), Offset(w * 0.94, h * 0.88),
        Paint()..color = const Color(0xFF1A1A2E)..strokeWidth = 1.5..strokeCap = StrokeCap.round);

    final bars = [
      (0.08, 0.62, 0.16, const Color(0xFFEF4444), const Color(0xFFCC1111)),
      (0.28, 0.48, 0.16, const Color(0xFFFBBF24), const Color(0xFFD99510)),
      (0.48, 0.35, 0.16, const Color(0xFF3B82F6), const Color(0xFF1D5FD4)),
      (0.68, 0.22, 0.16, const Color(0xFF22C55E), const Color(0xFF10882E)),
    ];

    for (final b in bars) {
      final x = b.$1 as double; final topY = b.$2 as double; final bw = b.$3 as double;
      final c1 = b.$4 as Color; final c2 = b.$5 as Color;
      final rect = Rect.fromLTWH(w * x, h * topY, w * bw, h * (0.88 - topY));
      final rr = RRect.fromRectAndCorners(rect, topLeft: const Radius.circular(3), topRight: const Radius.circular(3));
      canvas.drawRRect(rr, Paint()..shader = LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [c1, c2]).createShader(rect));
      canvas.drawRRect(RRect.fromRectAndCorners(Rect.fromLTWH(w * x + 2, h * topY + 2, w * bw - 4, h * 0.05), topLeft: const Radius.circular(2), topRight: const Radius.circular(2)),
          Paint()..color = Colors.white.withOpacity(0.3));
    }

    final arrowPaint = Paint()..color = const Color(0xFF16A34A)..strokeWidth = 2.2..strokeCap = StrokeCap.round..style = PaintingStyle.stroke;
    canvas.drawPath(Path()..moveTo(w * 0.10, h * 0.75)..lineTo(w * 0.35, h * 0.50)..lineTo(w * 0.55, h * 0.62)..lineTo(w * 0.82, h * 0.20), arrowPaint);
    final tip = Offset(w * 0.82, h * 0.20);
    canvas.drawPath(Path()..moveTo(tip.dx, tip.dy)..lineTo(tip.dx - w * 0.12, tip.dy + h * 0.06)..lineTo(tip.dx - w * 0.02, tip.dy + h * 0.14)..close(),
        Paint()..color = const Color(0xFF16A34A));
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// 💎 Plans — gold/purple star badge
class _PlansIcon extends StatelessWidget {
  const _PlansIcon();
  @override
  Widget build(BuildContext context) => CustomPaint(painter: _PlansPainter());
}

class _PlansPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;

    canvas.drawOval(
      Rect.fromCenter(center: Offset(w * 0.5, h * 0.96), width: w * 0.6, height: h * 0.07),
      Paint()..color = Colors.black.withOpacity(0.10)..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2),
    );

    final circleRect = Rect.fromCircle(center: Offset(w * 0.5, h * 0.5), radius: w * 0.44);
    canvas.drawOval(circleRect, Paint()..shader = RadialGradient(colors: [const Color(0xFF9B5DE5), const Color(0xFF5A0EC0)], stops: const [0.3, 1.0]).createShader(circleRect));
    canvas.drawArc(Rect.fromCircle(center: Offset(w * 0.5, h * 0.5), radius: w * 0.44), -2.4, 1.8, false,
        Paint()..color = Colors.white.withOpacity(0.25)..strokeWidth = w * 0.05..style = PaintingStyle.stroke);

    _drawStar(canvas, Offset(w * 0.5, h * 0.5), w * 0.28, w * 0.13, 5, const Color(0xFFFFD700), const Color(0xFFFF9500));
  }

  void _drawStar(Canvas canvas, Offset center, double outerR, double innerR, int points, Color c1, Color c2) {
    final path = Path();
    final angle = (3.14159265 * 2) / points;
    final halfAngle = angle / 2;
    for (int i = 0; i < points; i++) {
      final outerX = center.dx + outerR * _cos(-3.14159265 / 2 + angle * i);
      final outerY = center.dy + outerR * _sin(-3.14159265 / 2 + angle * i);
      final innerX = center.dx + innerR * _cos(-3.14159265 / 2 + angle * i + halfAngle);
      final innerY = center.dy + innerR * _sin(-3.14159265 / 2 + angle * i + halfAngle);
      if (i == 0) path.moveTo(outerX, outerY); else path.lineTo(outerX, outerY);
      path.lineTo(innerX, innerY);
    }
    path.close();
    final bounds = path.getBounds();
    canvas.drawPath(path, Paint()..shader = LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [c1, c2]).createShader(bounds));
    canvas.drawPath(path, Paint()..color = Colors.white.withOpacity(0.20)..style = PaintingStyle.stroke..strokeWidth = 0.8);
  }

  double _cos(double rad) => rad == 0 ? 1.0 : (1.0 - rad * rad / 2 + rad * rad * rad * rad / 24);
  double _sin(double x) {
    double result = x; double term = x;
    for (int i = 1; i < 10; i++) { term *= -x * x / ((2 * i) * (2 * i + 1)); result += term; }
    return result;
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// 👤 Profile — blue circle with white person silhouette
class _ProfileIcon extends StatelessWidget {
  const _ProfileIcon();
  @override
  Widget build(BuildContext context) => CustomPaint(painter: _ProfilePainter());
}

class _ProfilePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;

    canvas.drawOval(
      Rect.fromCenter(center: Offset(w * 0.5, h * 0.96), width: w * 0.65, height: h * 0.07),
      Paint()..color = Colors.black.withOpacity(0.12)..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2),
    );

    final circleRect = Rect.fromCircle(center: Offset(w * 0.5, h * 0.5), radius: w * 0.45);
    canvas.drawOval(circleRect, Paint()..shader = RadialGradient(center: const Alignment(-0.3, -0.3), colors: [const Color(0xFF5BA3F5), const Color(0xFF1A6FD4)]).createShader(circleRect));
    canvas.drawArc(Rect.fromCircle(center: Offset(w * 0.5, h * 0.5), radius: w * 0.45), -2.5, 1.6, false,
        Paint()..color = Colors.white.withOpacity(0.30)..strokeWidth = w * 0.06..style = PaintingStyle.stroke);

    canvas.save();
    canvas.clipPath(Path()..addOval(circleRect));
    canvas.drawCircle(Offset(w * 0.5, h * 0.38), w * 0.155, Paint()..color = Colors.white);
    canvas.drawPath(
      Path()..moveTo(w * 0.14, h * 0.95)..quadraticBezierTo(w * 0.14, h * 0.65, w * 0.50, h * 0.60)..quadraticBezierTo(w * 0.86, h * 0.65, w * 0.86, h * 0.95)..close(),
      Paint()..color = Colors.white,
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// 📋 Orders — receipt/list icon in orange
class _OrdersIcon extends StatelessWidget {
  const _OrdersIcon();
  @override
  Widget build(BuildContext context) => CustomPaint(painter: _OrdersPainter());
}

class _OrdersPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;

    // Shadow
    canvas.drawOval(
      Rect.fromCenter(center: Offset(w * 0.5, h * 0.95), width: w * 0.7, height: h * 0.08),
      Paint()
        ..color = Colors.black.withOpacity(0.10)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2),
    );

    // Paper body
    final bodyRect = RRect.fromRectAndRadius(
      Rect.fromLTWH(w * 0.12, h * 0.08, w * 0.76, h * 0.80),
      const Radius.circular(4),
    );
    canvas.drawRRect(
      bodyRect,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [const Color(0xFFFFF7ED), const Color(0xFFFFEDD5)],
        ).createShader(bodyRect.outerRect),
    );

    // Orange left accent bar
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(w * 0.12, h * 0.08, w * 0.07, h * 0.80),
        const Radius.circular(4),
      ),
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [const Color(0xFFF59E0B), const Color(0xFFD97706)],
        ).createShader(Rect.fromLTWH(0, 0, w, h)),
    );

    // Lines
    final linePaint = Paint()
      ..color = const Color(0xFFD97706).withOpacity(0.5)
      ..strokeWidth = 1.5
      ..strokeCap = StrokeCap.round;
    for (final yFrac in [0.30, 0.47, 0.64]) {
      canvas.drawLine(
        Offset(w * 0.28, h * yFrac),
        Offset(w * 0.80, h * yFrac),
        linePaint,
      );
    }

    // Short bottom line
    canvas.drawLine(
      Offset(w * 0.28, h * 0.76),
      Offset(w * 0.60, h * 0.76),
      linePaint,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// 📈 Positions — candlestick chart in green/red
class _PositionsIcon extends StatelessWidget {
  const _PositionsIcon();
  @override
  Widget build(BuildContext context) =>
      CustomPaint(painter: _PositionsPainter());
}

class _PositionsPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;

    // Shadow
    canvas.drawOval(
      Rect.fromCenter(center: Offset(w * 0.5, h * 0.95), width: w * 0.75, height: h * 0.08),
      Paint()
        ..color = Colors.black.withOpacity(0.10)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2),
    );

    // Baseline
    canvas.drawLine(
      Offset(w * 0.06, h * 0.88),
      Offset(w * 0.94, h * 0.88),
      Paint()
        ..color = const Color(0xFF1A1A2E)
        ..strokeWidth = 1.5
        ..strokeCap = StrokeCap.round,
    );

    void _drawCandle(
      double xFrac,
      double bodyTop,
      double bodyBot,
      double wickTop,
      double wickBot,
      Color color,
    ) {
      final x = w * xFrac;
      final bw = w * 0.12;
      // Wick
      canvas.drawLine(
        Offset(x + bw / 2, h * wickTop),
        Offset(x + bw / 2, h * wickBot),
        Paint()
          ..color = color
          ..strokeWidth = 1.5
          ..strokeCap = StrokeCap.round,
      );
      // Body
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(x, h * bodyTop, bw, h * (bodyBot - bodyTop)),
          const Radius.circular(2),
        ),
        Paint()..color = color,
      );
      // Highlight
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(x + 2, h * bodyTop + 2, bw - 4, h * 0.04),
          const Radius.circular(1),
        ),
        Paint()..color = Colors.white.withOpacity(0.35),
      );
    }

    // candle 1 — red (bear)
    _drawCandle(0.08, 0.40, 0.72, 0.28, 0.82, const Color(0xFFEF4444));
    // candle 2 — green (bull, tall)
    _drawCandle(0.30, 0.22, 0.60, 0.14, 0.70, const Color(0xFF22C55E));
    // candle 3 — red (small bear)
    _drawCandle(0.52, 0.45, 0.65, 0.38, 0.75, const Color(0xFFEF4444));
    // candle 4 — green (bull)
    _drawCandle(0.74, 0.30, 0.60, 0.20, 0.70, const Color(0xFF22C55E));
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
