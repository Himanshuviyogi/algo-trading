import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:webview_flutter/webview_flutter.dart';

// ── URL ───────────────────────────────────────────────────────────────────────

String _chainUrl(String symbol) =>
    'https://web.sensibull.com/option-chain?instrument=${Uri.encodeComponent(symbol)}';

// ── How many px of Sensibull's own header to hide via negative scroll offset.
// Sensibull renders a ~60px nav bar at the top. We shift the WebView up by
// this amount so the nav slides under our Flutter AppBar and is never visible.
const double _kSensibullNavHeight = 60.0;

// ── Screen ────────────────────────────────────────────────────────────────────

class OptionChainScreen extends StatefulWidget {
  const OptionChainScreen({super.key, this.initialSymbol = 'NIFTY'});
  final String initialSymbol;

  @override
  State<OptionChainScreen> createState() => _OptionChainScreenState();
}

class _OptionChainScreenState extends State<OptionChainScreen>
    with SingleTickerProviderStateMixin {
  late final WebViewController _controller;
  bool _isLoading = true;
  bool _hasError = false;
  late final AnimationController _shimmerCtrl;

  @override
  void initState() {
    super.initState();

    _shimmerCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat();

    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(Colors.white)
      ..setNavigationDelegate(NavigationDelegate(
        onPageStarted: (_) {
          if (mounted) setState(() { _isLoading = true; _hasError = false; });
        },
        onPageFinished: (url) {
          // Scroll the page down by the nav height so Sensibull's header
          // is pushed behind our Flutter AppBar — simple, reliable.
          _controller.runJavaScript(
            'window.scrollTo({top: $_kSensibullNavHeight, behavior: "instant"});',
          );
          if (mounted) setState(() => _isLoading = false);
        },
        onWebResourceError: (err) {
          if ((err.isForMainFrame ?? true) && mounted) {
            setState(() { _isLoading = false; _hasError = true; });
          }
        },
        onNavigationRequest: (req) {
          // Keep user inside the option chain — block navigating away
          if (req.url.contains('web.sensibull.com')) {
            return NavigationDecision.navigate;
          }
          return NavigationDecision.prevent;
        },
      ))
      ..loadRequest(Uri.parse(_chainUrl(widget.initialSymbol)));
  }

  @override
  void dispose() {
    _shimmerCtrl.dispose();
    super.dispose();
  }

  void _onRefresh() {
    HapticFeedback.lightImpact();
    setState(() { _isLoading = true; _hasError = false; });
    _controller.reload();
  }

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.dark,
      child: Scaffold(
        backgroundColor: Colors.white,
        appBar: _buildAppBar(),
        body: _hasError ? _buildError() : _buildWebView(),
      ),
    );
  }

  // ── AppBar — matches recommendation_detail_screen style exactly ───────────

  PreferredSizeWidget _buildAppBar() {
    return AppBar(
      backgroundColor: Colors.white,
      elevation: 0,
      centerTitle: false,
      leading: IconButton(
        icon: const Icon(Icons.arrow_back_ios_new,
            color: Color(0xFF1E293B), size: 18),
        onPressed: () => Navigator.of(context).pop(),
      ),
      titleSpacing: 0,
      title: Row(
        children: [
          // Icon container — same pattern as recommendation detail
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: const Color(0xFF4C46E5).withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(
              Icons.waterfall_chart_rounded,
              color: Color(0xFF4C46E5),
              size: 20,
            ),
          ),
          const SizedBox(width: 10),
          // Title + subtitle
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Option Chain',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF1E293B),
                ),
              ),
              Row(
                children: [
                  const Text(
                    'NSE Live',
                    style: TextStyle(
                      fontSize: 11,
                      color: Colors.black45,
                      letterSpacing: 0.8,
                    ),
                  ),
                  const SizedBox(width: 5),
                  // Live dot — same as recommendation detail
                  Container(
                    width: 5,
                    height: 5,
                    decoration: const BoxDecoration(
                      color: Color(0xFF10B981),
                      shape: BoxShape.circle,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
      actions: [
        // Refresh
        Padding(
          padding: const EdgeInsets.only(right: 12),
          child: GestureDetector(
            onTap: _isLoading ? null : _onRefresh,
            child: Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: const Color(0xFF4C46E5).withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(10),
              ),
              child: _isLoading
                  ? const Padding(
                      padding: EdgeInsets.all(9),
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Color(0xFF4C46E5),
                      ),
                    )
                  : const Icon(
                      Icons.refresh_rounded,
                      size: 18,
                      color: Color(0xFF4C46E5),
                    ),
            ),
          ),
        ),
      ],
      // Bottom divider line — same as recommendation detail
      bottom: PreferredSize(
        preferredSize: const Size.fromHeight(1),
        child: Container(
          height: 1,
          color: Colors.grey.shade200,
        ),
      ),
    );
  }

  // ── WebView ───────────────────────────────────────────────────────────────
  // The WebView is shifted UP by _kSensibullNavHeight so Sensibull's own
  // header slides behind our Flutter AppBar. ClipRect prevents it showing.

  Widget _buildWebView() {
    return Stack(
      children: [
        // Shift the WebView up — Sensibull nav disappears behind AppBar
        Positioned(
          top: -_kSensibullNavHeight,
          left: 0,
          right: 0,
          bottom: 0,
          child: ClipRect(
            child: WebViewWidget(controller: _controller),
          ),
        ),
        if (_isLoading) _buildShimmer(),
      ],
    );
  }

  // ── Shimmer loader ────────────────────────────────────────────────────────

  Widget _buildShimmer() {
    return AnimatedBuilder(
      animation: _shimmerCtrl,
      builder: (_, __) {
        final t = _shimmerCtrl.value < 0.5
            ? _shimmerCtrl.value * 2
            : (1 - _shimmerCtrl.value) * 2;
        final base = Color.lerp(
            const Color(0xFFF3F4F6), const Color(0xFFE5E7EB), t)!;

        return Container(
          color: Colors.white,
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
          child: Column(
            children: [
              // Summary bar skeleton
              Container(
                height: 56,
                decoration: BoxDecoration(
                  color: base,
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              const SizedBox(height: 12),
              // Table header skeleton
              Container(
                height: 36,
                decoration: BoxDecoration(
                  color: base,
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              const SizedBox(height: 8),
              // Row skeletons
              ...List.generate(9, (i) => Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Container(
                  height: 42,
                  decoration: BoxDecoration(
                    color: Color.lerp(base, Colors.white, i * 0.08)!,
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
              )),
            ],
          ),
        );
      },
    );
  }

  // ── Error state ───────────────────────────────────────────────────────────

  Widget _buildError() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 68,
              height: 68,
              decoration: BoxDecoration(
                color: const Color(0xFFF3F4F6),
                shape: BoxShape.circle,
                border: Border.all(color: const Color(0xFFE5E7EB)),
              ),
              child: const Icon(Icons.wifi_off_rounded,
                  size: 30, color: Color(0xFF9CA3AF)),
            ),
            const SizedBox(height: 20),
            const Text(
              'Unable to connect',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: Color(0xFF1E293B),
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Check your internet connection and try again.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13,
                color: Color(0xFF6B7280),
                height: 1.5,
              ),
            ),
            const SizedBox(height: 28),
            GestureDetector(
              onTap: _onRefresh,
              child: Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 28, vertical: 13),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFF4C46E5), Color(0xFF7C3AED)],
                  ),
                  borderRadius: BorderRadius.circular(30),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF4C46E5).withValues(alpha: 0.3),
                      blurRadius: 12,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: const Text(
                  'Try Again',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
