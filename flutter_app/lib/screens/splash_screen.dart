import 'dart:math';
import 'dart:ui';
import 'package:flutter/material.dart';

/// ======================================================
/// 🔥 SPLASH STYLE ENUM
/// ======================================================

enum SplashStyle {
  vibrant,
  glass,
  cyberpunk,
  minimal,
  aurora, // ✨ new
}

/// ======================================================
/// 🚀 MAIN SPLASH SCREEN
/// ======================================================

class SplashScreen extends StatelessWidget {
  const SplashScreen({super.key});

  /// 🔥 CHANGE STYLE HERE
  static const SplashStyle currentStyle = SplashStyle.aurora;

  @override
  Widget build(BuildContext context) {
    switch (currentStyle) {
      case SplashStyle.vibrant:
        return const VibrantSplash();
      case SplashStyle.glass:
        return const GlassSplash();
      case SplashStyle.cyberpunk:
        return const CyberpunkSplash();
      case SplashStyle.minimal:
        return const MinimalSplash();
      case SplashStyle.aurora:
        return const AuroraSplash();
    }
  }
}

/// ======================================================
/// ✨ 5. AURORA SPLASH  (new)
///
/// Design language:
///  • Pure white background — matches the app's light Aurora theme
///  • Animated violet → pink gradient blobs (same blobs as AuroraBackground)
///  • Logo mark inside a glowing gradient ring that breathes (scale pulse)
///  • App name slides up + fades in 300 ms after the logo
///  • Tag-line slides up 150 ms after the name
///  • Three animated gradient "signal bars" as the loader
/// ======================================================

class AuroraSplash extends StatefulWidget {
  const AuroraSplash({super.key});

  @override
  State<AuroraSplash> createState() => _AuroraSplashState();
}

class _AuroraSplashState extends State<AuroraSplash>
    with TickerProviderStateMixin {
  // blob drift
  late final AnimationController _blobCtrl;

  // logo ring pulse
  late final AnimationController _pulseCtrl;
  late final Animation<double> _pulse;

  // staggered entrance
  late final AnimationController _entranceCtrl;
  late final Animation<double> _logoFade;
  late final Animation<double> _logoScale;
  late final Animation<Offset> _titleSlide;
  late final Animation<double> _titleFade;
  late final Animation<Offset> _taglineSlide;
  late final Animation<double> _taglineFade;
  late final Animation<double> _loaderFade;

  @override
  void initState() {
    super.initState();

    // blobs drift slowly forever
    _blobCtrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 12),
    )..repeat(reverse: true);

    // ring breathes
    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    )..repeat(reverse: true);
    _pulse = Tween<double>(begin: 0.95, end: 1.04).animate(
      CurvedAnimation(parent: _pulseCtrl, curve: Curves.easeInOut),
    );

    // entrance — 1400 ms total
    _entranceCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1600),
    )..forward();

    // logo: 0 → 700 ms
    _logoFade = _interval(0.00, 0.44, Curves.easeOut);
    _logoScale = Tween<double>(begin: 0.6, end: 1.0).animate(
      CurvedAnimation(
        parent: _entranceCtrl,
        curve: const Interval(0.00, 0.50, curve: Curves.elasticOut),
      ),
    );

    // title: 400 → 900 ms
    _titleFade  = _interval(0.25, 0.60, Curves.easeOut);
    _titleSlide = Tween<Offset>(
      begin: const Offset(0, 0.5),
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _entranceCtrl,
      curve: const Interval(0.25, 0.65, curve: Curves.easeOutCubic),
    ));

    // tagline: 550 → 950 ms
    _taglineFade  = _interval(0.38, 0.70, Curves.easeOut);
    _taglineSlide = Tween<Offset>(
      begin: const Offset(0, 0.5),
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _entranceCtrl,
      curve: const Interval(0.38, 0.72, curve: Curves.easeOutCubic),
    ));

    // loader bar: 700 ms → end
    _loaderFade = _interval(0.60, 0.90, Curves.easeOut);
  }

  Animation<double> _interval(
      double begin, double end, Curve curve) {
    return CurvedAnimation(
      parent: _entranceCtrl,
      curve: Interval(begin, end, curve: curve),
    );
  }

  @override
  void dispose() {
    _blobCtrl.dispose();
    _pulseCtrl.dispose();
    _entranceCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;

    return Scaffold(
      backgroundColor: const Color(0xFFF6F5FF),
      body: AnimatedBuilder(
        animation: _blobCtrl,
        builder: (_, child) {
          final t = _blobCtrl.value;
          return Stack(
            children: [
              // ── background blobs ─────────────────────────
              Positioned(
                top: -100 + t * 60,
                left: -80 + t * 40,
                child: _Blob(
                  size: 300,
                  color: const Color(0xFF7C3AED).withOpacity(0.13),
                ),
              ),
              Positioned(
                bottom: -120 + t * 70,
                right: -80 - t * 30,
                child: _Blob(
                  size: 340,
                  color: const Color(0xFFDB2777).withOpacity(0.10),
                ),
              ),
              Positioned(
                top: size.height * 0.38 - t * 40,
                right: -50 + t * 25,
                child: _Blob(
                  size: 180,
                  color: const Color(0xFF0284C7).withOpacity(0.08),
                ),
              ),
              Positioned(
                top: size.height * 0.18 + t * 20,
                right: size.width * 0.15 - t * 10,
                child: _Blob(
                  size: 120,
                  color: const Color(0xFFEA580C).withOpacity(0.07),
                ),
              ),

              // ── centred content ──────────────────────────
              child!,
            ],
          );
        },
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // ── LOGO RING ──────────────────────────────
              FadeTransition(
                opacity: _logoFade,
                child: ScaleTransition(
                  scale: _logoScale,
                  child: ScaleTransition(
                    scale: _pulse,
                    child: _LogoRing(),
                  ),
                ),
              ),

              const SizedBox(height: 32),

              // ── APP NAME ───────────────────────────────
              FadeTransition(
                opacity: _titleFade,
                child: SlideTransition(
                  position: _titleSlide,
                  child: _GradientText(
                    text: 'AlgoEdge',
                    fontSize: 34,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 0.5,
                  ),
                ),
              ),

              const SizedBox(height: 8),

              // ── TAGLINE ───────────────────────────────
              FadeTransition(
                opacity: _taglineFade,
                child: SlideTransition(
                  position: _taglineSlide,
                  child: const Text(
                    'AI-Powered Algo Trading',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      color: Color(0xFF94A3B8),
                      letterSpacing: 0.3,
                    ),
                  ),
                ),
              ),

              const SizedBox(height: 52),

              // ── SIGNAL BAR LOADER ─────────────────────
              FadeTransition(
                opacity: _loaderFade,
                child: const _SignalBarsLoader(),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  Logo ring — gradient border circle with the logo inside
// ─────────────────────────────────────────────────────────────────────────────

class _LogoRing extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      width: 126,
      height: 126,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: const LinearGradient(
          colors: [Color(0xFF7C3AED), Color(0xFFDB2777)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF7C3AED).withOpacity(0.30),
            blurRadius: 32,
            offset: const Offset(0, 10),
          ),
          BoxShadow(
            color: const Color(0xFFDB2777).withOpacity(0.20),
            blurRadius: 48,
            offset: const Offset(0, 16),
          ),
        ],
      ),
      padding: const EdgeInsets.all(3),  // ring thickness
      child: Container(
        decoration: const BoxDecoration(
          shape: BoxShape.circle,
          color: Color(0xFFF6F5FF),
        ),
        padding: const EdgeInsets.all(20),
        child: Image.asset(
          'assets/images/small_logo.png',
          fit: BoxFit.contain,
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  Gradient shimmer text
// ─────────────────────────────────────────────────────────────────────────────

class _GradientText extends StatelessWidget {
  const _GradientText({
    required this.text,
    this.fontSize = 28,
    this.fontWeight = FontWeight.w700,
    this.letterSpacing = 0,
  });

  final String text;
  final double fontSize;
  final FontWeight fontWeight;
  final double letterSpacing;

  @override
  Widget build(BuildContext context) {
    return ShaderMask(
      blendMode: BlendMode.srcIn,
      shaderCallback: (bounds) => const LinearGradient(
        colors: [Color(0xFF7C3AED), Color(0xFFDB2777)],
        begin: Alignment.centerLeft,
        end: Alignment.centerRight,
      ).createShader(bounds),
      child: Text(
        text,
        style: TextStyle(
          fontSize: fontSize,
          fontWeight: fontWeight,
          letterSpacing: letterSpacing,
          color: Colors.white, // masked by ShaderMask
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  Three animated signal bars — trading-themed loader
// ─────────────────────────────────────────────────────────────────────────────

class _SignalBarsLoader extends StatefulWidget {
  const _SignalBarsLoader();

  @override
  State<_SignalBarsLoader> createState() => _SignalBarsLoaderState();
}

class _SignalBarsLoaderState extends State<_SignalBarsLoader>
    with TickerProviderStateMixin {
  final List<AnimationController> _ctrls = [];
  final List<Animation<double>> _anims = [];

  final List<double> _heights = [14, 22, 30, 22, 14];
  final List<int> _delays   = [0, 120, 240, 360, 480];

  @override
  void initState() {
    super.initState();
    for (var i = 0; i < _heights.length; i++) {
      final ctrl = AnimationController(
        vsync: this,
        duration: const Duration(milliseconds: 600),
      );
      final anim = Tween<double>(begin: 0.4, end: 1.0).animate(
        CurvedAnimation(parent: ctrl, curve: Curves.easeInOut),
      );
      _ctrls.add(ctrl);
      _anims.add(anim);

      Future.delayed(Duration(milliseconds: _delays[i]), () {
        if (mounted) ctrl.repeat(reverse: true);
      });
    }
  }

  @override
  void dispose() {
    for (final c in _ctrls) c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: List.generate(_heights.length, (i) {
        return AnimatedBuilder(
          animation: _anims[i],
          builder: (_, __) {
            return Container(
              margin: const EdgeInsets.symmetric(horizontal: 3),
              width: 5,
              height: _heights[i] * _anims[i].value,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(3),
                gradient: const LinearGradient(
                  colors: [Color(0xFF7C3AED), Color(0xFFDB2777)],
                  begin: Alignment.bottomCenter,
                  end: Alignment.topCenter,
                ),
              ),
            );
          },
        );
      }),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  Blob helper
// ─────────────────────────────────────────────────────────────────────────────

class _Blob extends StatelessWidget {
  const _Blob({required this.size, required this.color});
  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: color,
        boxShadow: [BoxShadow(color: color, blurRadius: size * 0.5)],
      ),
    );
  }
}

/// ======================================================
/// 🌈 1. VIBRANT SPLASH
/// ======================================================

class VibrantSplash extends StatefulWidget {
  const VibrantSplash({super.key});

  @override
  State<VibrantSplash> createState() => _VibrantSplashState();
}

class _VibrantSplashState extends State<VibrantSplash>
    with TickerProviderStateMixin {

  late final AnimationController _mainController;
  late final AnimationController _pulseController;
  late final Animation<double> _fade;
  late final Animation<double> _scale;

  @override
  void initState() {
    super.initState();

    _mainController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    )..forward();

    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat(reverse: true);

    _fade = CurvedAnimation(
      parent: _mainController,
      curve: Curves.easeIn,
    );

    _scale = Tween<double>(
      begin: 0.7,
      end: 1,
    ).animate(
      CurvedAnimation(
        parent: _mainController,
        curve: Curves.elasticOut,
      ),
    );
  }

  @override
  void dispose() {
    _mainController.dispose();
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {

    return Scaffold(
      body: Stack(
        children: [

          /// BACKGROUND
          Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  Color(0xFF0F172A),
                  Color(0xFF1E1B4B),
                  Color(0xFF312E81),
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
          ),

          /// GLOW
          Positioned(
            top: -100,
            left: -80,
            child: _glow(
              const Color(0xFF8B5CF6),
            ),
          ),

          Positioned(
            bottom: -100,
            right: -80,
            child: _glow(
              const Color(0xFF06B6D4),
            ),
          ),

          /// CONTENT
          Center(
            child: FadeTransition(
              opacity: _fade,
              child: ScaleTransition(
                scale: _scale,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [

                    AnimatedBuilder(
                      animation: _pulseController,
                      builder: (_, __) {
                        return Container(
                          width: 170,
                          height: 170,
                          padding: const EdgeInsets.all(22),
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            gradient: const LinearGradient(
                              colors: [
                                Color(0xFF8B5CF6),
                                Color(0xFF06B6D4),
                              ],
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.cyan.withOpacity(0.45),
                                blurRadius: 40,
                              ),
                            ],
                          ),
                          child: Image.asset(
                            'assets/images/small_logo.png',
                          ),
                        );
                      },
                    ),

                    const SizedBox(height: 32),

                    Image.asset(
                      'assets/images/logo.png',
                      height: 40,
                    ),

                    const SizedBox(height: 14),

                    Text(
                      "AI Powered Algo Trading",
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.7),
                        fontSize: 14,
                      ),
                    ),

                    /// LOADER
                    const SizedBox(height: 34),

                    Row(
                      mainAxisAlignment:
                      MainAxisAlignment.center,
                      children: List.generate(
                        3,
                            (index) => TweenAnimationBuilder(
                          tween: Tween<double>(
                            begin: 0.6,
                            end: 1,
                          ),
                          duration: Duration(
                            milliseconds:
                            600 + (index * 200),
                          ),
                          curve: Curves.easeInOut,
                          builder:
                              (_, double value, child) {
                            return Transform.scale(
                              scale: value,
                              child: Container(
                                margin:
                                const EdgeInsets.symmetric(
                                  horizontal: 6,
                                ),
                                width: 10,
                                height: 10,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  gradient:
                                  const LinearGradient(
                                    colors: [
                                      Color(0xFF06B6D4),
                                      Color(0xFF8B5CF6),
                                    ],
                                  ),
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.cyan
                                          .withOpacity(0.5),
                                      blurRadius: 12,
                                    ),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                      ),
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

  Widget _glow(Color color) {
    return Container(
      width: 260,
      height: 260,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: color.withOpacity(0.28),
      ),
      child: BackdropFilter(
        filter: ImageFilter.blur(
          sigmaX: 100,
          sigmaY: 100,
        ),
        child: Container(),
      ),
    );
  }
}

/// ======================================================
/// 🧊 2. GLASS SPLASH
/// ======================================================

class GlassSplash extends StatefulWidget {
  const GlassSplash({super.key});

  @override
  State<GlassSplash> createState() => _GlassSplashState();
}

class _GlassSplashState extends State<GlassSplash>
    with SingleTickerProviderStateMixin {

  late final AnimationController _controller;
  late final Animation<double> _fade;

  @override
  void initState() {
    super.initState();

    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1600),
    )..forward();

    _fade = CurvedAnimation(
      parent: _controller,
      curve: Curves.easeIn,
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {

    return Scaffold(
      body: Stack(
        children: [

          Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  Color(0xFF0B1120),
                  Color(0xFF1E1B4B),
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
          ),

          Center(
            child: FadeTransition(
              opacity: _fade,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(34),
                child: BackdropFilter(
                  filter: ImageFilter.blur(
                    sigmaX: 25,
                    sigmaY: 25,
                  ),
                  child: Container(
                    width: 270,
                    padding: const EdgeInsets.all(30),
                    decoration: BoxDecoration(
                      borderRadius:
                      BorderRadius.circular(34),
                      color: Colors.white.withOpacity(0.08),
                      border: Border.all(
                        color:
                        Colors.white.withOpacity(0.12),
                      ),
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [

                        Image.asset(
                          'assets/images/small_logo.png',
                          height: 110,
                        ),

                        const SizedBox(height: 28),

                        Image.asset(
                          'assets/images/logo.png',
                          height: 36,
                        ),

                        const SizedBox(height: 14),

                        Text(
                          "Modern AI Experience",
                          style: TextStyle(
                            color:
                            Colors.white.withOpacity(0.7),
                            fontSize: 13,
                          ),
                        ),

                        /// LOADER
                        const SizedBox(height: 30),

                        ClipRRect(
                          borderRadius:
                          BorderRadius.circular(30),
                          child: SizedBox(
                            width: 120,
                            child: LinearProgressIndicator(
                              minHeight: 4,
                              backgroundColor:
                              Colors.white
                                  .withOpacity(0.08),
                              valueColor:
                              AlwaysStoppedAnimation(
                                Colors.white
                                    .withOpacity(0.8),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// ======================================================
/// ⚡ 3. CYBERPUNK SPLASH
/// ======================================================

class CyberpunkSplash extends StatefulWidget {
  const CyberpunkSplash({super.key});

  @override
  State<CyberpunkSplash> createState() =>
      _CyberpunkSplashState();
}

class _CyberpunkSplashState
    extends State<CyberpunkSplash>
    with TickerProviderStateMixin {

  late final AnimationController _rotationController;
  late final AnimationController _pulseController;

  @override
  void initState() {
    super.initState();

    _rotationController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 10),
    )..repeat();

    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _rotationController.dispose();
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {

    return Scaffold(
      backgroundColor: const Color(0xFF050816),

      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [

            AnimatedBuilder(
              animation: _rotationController,
              builder: (_, child) {
                return Transform.rotate(
                  angle:
                  _rotationController.value * 2 * pi,
                  child: child,
                );
              },
              child: Stack(
                alignment: Alignment.center,
                children: [

                  Container(
                    width: 240,
                    height: 240,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: Colors.cyanAccent,
                        width: 2,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.cyanAccent
                              .withOpacity(0.5),
                          blurRadius: 35,
                        ),
                      ],
                    ),
                  ),

                  Container(
                    width: 180,
                    height: 180,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: Colors.purpleAccent,
                        width: 2,
                      ),
                    ),
                  ),

                  AnimatedBuilder(
                    animation: _pulseController,
                    builder: (_, __) {
                      return Transform.scale(
                        scale: 0.95 +
                            (_pulseController.value *
                                0.08),
                        child: Container(
                          width: 120,
                          height: 120,
                          padding:
                          const EdgeInsets.all(18),
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color:
                            Colors.white.withOpacity(
                              0.06,
                            ),
                          ),
                          child: Image.asset(
                            'assets/images/small_logo.png',
                          ),
                        ),
                      );
                    },
                  ),
                ],
              ),
            ),

            const SizedBox(height: 42),

            Image.asset(
              'assets/images/logo.png',
              height: 40,
            ),

            const SizedBox(height: 14),

            Text(
              "Future of Algo Trading",
              style: TextStyle(
                color: Colors.white.withOpacity(0.7),
                fontSize: 14,
              ),
            ),

            /// LOADER
            const SizedBox(height: 36),

            SizedBox(
              width: 130,
              child: LinearProgressIndicator(
                minHeight: 3,
                borderRadius:
                BorderRadius.circular(40),
                backgroundColor: Colors.white12,
                valueColor:
                const AlwaysStoppedAnimation(
                  Colors.cyanAccent,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// ======================================================
/// 🖤 4. MINIMAL SPLASH
/// ======================================================

class MinimalSplash extends StatefulWidget {
  const MinimalSplash({super.key});

  @override
  State<MinimalSplash> createState() =>
      _MinimalSplashState();
}

class _MinimalSplashState extends State<MinimalSplash>
    with SingleTickerProviderStateMixin {

  late final AnimationController _controller;
  late final Animation<double> _fade;

  @override
  void initState() {
    super.initState();

    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..forward();

    _fade = CurvedAnimation(
      parent: _controller,
      curve: Curves.easeIn,
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {

    return Scaffold(
      backgroundColor: const Color(0xFF050505),

      body: FadeTransition(
        opacity: _fade,
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [

              Container(
                width: 170,
                height: 170,
                padding: const EdgeInsets.all(38),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white.withOpacity(0.03),
                  border: Border.all(
                    color: Colors.white.withOpacity(0.06),
                  ),
                ),
                child: Image.asset(
                  'assets/images/small_logo.png',
                ),
              ),

              const SizedBox(height: 42),

              Image.asset(
                'assets/images/logo.png',
                height: 38,
              ),

              const SizedBox(height: 14),

              Text(
                "Simple. Smart. Powerful.",
                style: TextStyle(
                  color: Colors.white.withOpacity(0.45),
                  fontSize: 14,
                ),
              ),

              /// LOADER
              const SizedBox(height: 42),

              SizedBox(
                width: 70,
                child: LinearProgressIndicator(
                  minHeight: 2,
                  borderRadius:
                  BorderRadius.circular(30),
                  backgroundColor: Colors.white10,
                  valueColor:
                  AlwaysStoppedAnimation(
                    Colors.white.withOpacity(0.55),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
