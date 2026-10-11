import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

// ── Aurora Theme — Vibrant Gradient LIGHT ─────────────────────────────────────
//
// Design language:
//   • Bright white base:  #FFFFFF / #F6F5FF (faint lavender tint)
//   • Card surface:       pure white with coloured glow shadow
//   • Primary:            #7C3AED (vivid violet)
//   • Secondary:          #DB2777 (hot pink)
//   • Accent gradient:    violet → pink (CTAs, logo, highlights)
//   • Profit green:       #059669   Loss red: #E11D48
//   • Text primary:       #0F172A   Text secondary: #475569
//   • Background blobs:   violet 18%, pink 12%, teal 10%, amber 8% — pastel, not dark

abstract final class AuroraColors {
  // ── Surfaces ───────────────────────────────────────────────────────────────
  static const background   = Color(0xFFF6F5FF); // faint lavender tint
  static const surface      = Color(0xFFFFFFFF);
  static const card         = Color(0xFFFFFFFF);
  static const cardBorder   = Color(0xFFEDE9FE); // very light violet border

  // ── Brand gradient ─────────────────────────────────────────────────────────
  static const violet       = Color(0xFF7C3AED);
  static const pink         = Color(0xFFDB2777);
  static const violetLight  = Color(0xFF8B5CF6);
  static const pinkLight    = Color(0xFFEC4899);

  // ── Semantic ───────────────────────────────────────────────────────────────
  static const profit       = Color(0xFF059669);
  static const profitBg     = Color(0xFFD1FAE5);
  static const loss         = Color(0xFFE11D48);
  static const lossBg       = Color(0xFFFFE4E6);
  static const warning      = Color(0xFFD97706);
  static const warningBg    = Color(0xFFFEF3C7);
  static const info         = Color(0xFF0284C7);
  static const infoBg       = Color(0xFFE0F2FE);
  static const orange       = Color(0xFFEA580C);
  static const orangeBg     = Color(0xFFFFEDD5);

  // ── Text ───────────────────────────────────────────────────────────────────
  static const textPrimary  = Color(0xFF0F172A);
  static const textSecond   = Color(0xFF475569);
  static const textMuted    = Color(0xFF94A3B8);
  static const textDisabled = Color(0xFFCBD5E1);

  // ── Gradient helpers ───────────────────────────────────────────────────────
  static const gradientBrand = LinearGradient(
    colors: [violet, pink],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const gradientBrandVertical = LinearGradient(
    colors: [violet, pink],
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
  );

  static const gradientSurface = LinearGradient(
    colors: [Color(0xFFFAF9FF), Color(0xFFFFFFFF)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  // Subtle card top-accent strip
  static const gradientBorder = LinearGradient(
    colors: [Color(0x297C3AED), Color(0x29DB2777)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static Color violetTint(double opacity) => violet.withOpacity(opacity);
  static Color pinkTint(double opacity)   => pink.withOpacity(opacity);
}

// ── ThemeData ─────────────────────────────────────────────────────────────────

final auroraTheme = ThemeData(
  brightness: Brightness.light,
  scaffoldBackgroundColor: AuroraColors.background,
  colorScheme: const ColorScheme.light(
    primary:    AuroraColors.violet,
    secondary:  AuroraColors.pink,
    surface:    AuroraColors.surface,
    error:      AuroraColors.loss,
    onPrimary:  Colors.white,
    onSecondary: Colors.white,
    onSurface:  AuroraColors.textPrimary,
    onError:    Colors.white,
  ),
  appBarTheme: const AppBarTheme(
    backgroundColor:        AuroraColors.surface,
    foregroundColor:        AuroraColors.textPrimary,
    elevation:              0,
    scrolledUnderElevation: 0,
    systemOverlayStyle: SystemUiOverlayStyle(
      statusBarBrightness:           Brightness.light,
      statusBarIconBrightness:       Brightness.dark,
      systemNavigationBarColor:      AuroraColors.surface,
      systemNavigationBarIconBrightness: Brightness.dark,
    ),
  ),
  cardTheme: CardThemeData(
    color: AuroraColors.card,
    elevation: 0,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(16),
      side: const BorderSide(color: AuroraColors.cardBorder, width: 1),
    ),
  ),
  dividerColor: AuroraColors.cardBorder,
  textTheme: const TextTheme(
    displayLarge:  TextStyle(color: AuroraColors.textPrimary, fontWeight: FontWeight.w900),
    displayMedium: TextStyle(color: AuroraColors.textPrimary, fontWeight: FontWeight.w800),
    titleLarge:    TextStyle(color: AuroraColors.textPrimary, fontWeight: FontWeight.w700, fontSize: 18),
    titleMedium:   TextStyle(color: AuroraColors.textPrimary, fontWeight: FontWeight.w600, fontSize: 15),
    titleSmall:    TextStyle(color: AuroraColors.textSecond,  fontWeight: FontWeight.w600, fontSize: 13),
    bodyLarge:     TextStyle(color: AuroraColors.textPrimary, fontSize: 15),
    bodyMedium:    TextStyle(color: AuroraColors.textSecond,  fontSize: 13),
    bodySmall:     TextStyle(color: AuroraColors.textMuted,   fontSize: 11),
    labelLarge:    TextStyle(color: AuroraColors.textPrimary, fontWeight: FontWeight.w700, fontSize: 14),
    labelSmall:    TextStyle(color: AuroraColors.textMuted,   fontWeight: FontWeight.w600, fontSize: 10, letterSpacing: 0.8),
  ),
  inputDecorationTheme: InputDecorationTheme(
    filled:    true,
    fillColor: AuroraColors.background,
    hintStyle: const TextStyle(color: AuroraColors.textMuted),
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: const BorderSide(color: AuroraColors.cardBorder),
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: const BorderSide(color: AuroraColors.cardBorder),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: const BorderSide(color: AuroraColors.violet, width: 1.5),
    ),
  ),
  elevatedButtonTheme: ElevatedButtonThemeData(
    style: ElevatedButton.styleFrom(
      backgroundColor: AuroraColors.violet,
      foregroundColor: Colors.white,
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 24),
      textStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
    ),
  ),
  progressIndicatorTheme: const ProgressIndicatorThemeData(
    color: AuroraColors.violet,
  ),
  iconTheme: const IconThemeData(color: AuroraColors.textSecond),
);

// ── Reusable widgets ──────────────────────────────────────────────────────────

/// White card with a 1-px violet→pink gradient border and a coloured glow.
class AuroraCard extends StatelessWidget {
  const AuroraCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.borderRadius = 18.0,
    this.glowColor,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final double borderRadius;
  final Color? glowColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(borderRadius),
        gradient: AuroraColors.gradientBorder,
      ),
      padding: const EdgeInsets.all(1),
      child: Container(
        padding: padding,
        decoration: BoxDecoration(
          color: AuroraColors.card,
          borderRadius: BorderRadius.circular(borderRadius - 1),
          boxShadow: [
            BoxShadow(
              color: (glowColor ?? AuroraColors.violet).withOpacity(0.12),
              blurRadius: 20,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: child,
      ),
    );
  }
}

/// Coloured pill badge.
class AuroraBadge extends StatelessWidget {
  const AuroraBadge({
    super.key,
    required this.label,
    this.color,
    this.textColor,
    this.small = false,
  });

  final String label;
  final Color? color;
  final Color? textColor;
  final bool small;

  @override
  Widget build(BuildContext context) {
    final accent = color ?? AuroraColors.violet;
    final fg = textColor ?? accent;
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: small ? 6 : 10,
        vertical:   small ? 2 : 4,
      ),
      decoration: BoxDecoration(
        color: accent.withOpacity(0.12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: accent.withOpacity(0.30), width: 1),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize:   small ? 9 : 11,
          fontWeight: FontWeight.w800,
          color:      fg,
          letterSpacing: 0.4,
        ),
      ),
    );
  }
}

/// Animated light Aurora background — soft pastel blobs on white/lavender.
class AuroraBackground extends StatefulWidget {
  const AuroraBackground({super.key, this.child});
  final Widget? child;

  @override
  State<AuroraBackground> createState() => _AuroraBackgroundState();
}

class _AuroraBackgroundState extends State<AuroraBackground>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 18),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (_, __) => Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [Color(0xFFF6F5FF), Color(0xFFFDF4FF)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: Stack(
          children: [
            // violet blob — top-left
            Positioned(
              top: -80 + (_ctrl.value * 80),
              left: -60 + (_ctrl.value * 30),
              child: _blob(220, AuroraColors.violet.withOpacity(0.14)),
            ),
            // pink blob — bottom-right
            Positioned(
              bottom: -100 + (_ctrl.value * 80),
              right: -60 - (_ctrl.value * 20),
              child: _blob(260, AuroraColors.pink.withOpacity(0.11)),
            ),
            // sky-blue blob — mid-right
            Positioned(
              top: 220 - (_ctrl.value * 60),
              right: -40 + (_ctrl.value * 20),
              child: _blob(160, AuroraColors.info.withOpacity(0.09)),
            ),
            // amber blob — upper-right
            Positioned(
              top: 60 + (_ctrl.value * 30),
              right: 80 - (_ctrl.value * 15),
              child: _blob(110, AuroraColors.orange.withOpacity(0.08)),
            ),
            if (widget.child != null) widget.child!,
          ],
        ),
      ),
    );
  }

  Widget _blob(double size, Color color) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        boxShadow: [BoxShadow(color: color, blurRadius: size * 0.6)],
      ),
    );
  }
}
