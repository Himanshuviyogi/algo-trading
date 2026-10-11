// import 'dart:async';
// import 'package:flutter/material.dart';
// import '../services/connectivity_service.dart';
//
// /// Wraps any widget and overlays a slim connectivity banner at the top.
// ///
// /// - Goes offline  → red "No internet connection" bar slides in
// /// - Comes online  → green "Back online" bar shows for 2s then slides out
// /// - Also triggers socket reconnect via [onReconnect] callback
// class ConnectivityBanner extends StatefulWidget {
//   const ConnectivityBanner({
//     super.key,
//     required this.child,
//     this.onReconnect,
//   });
//
//   final Widget child;
//
//   /// Called when connectivity is restored — use to reconnect the price socket.
//   final VoidCallback? onReconnect;
//
//   @override
//   State<ConnectivityBanner> createState() => _ConnectivityBannerState();
// }
//
// class _ConnectivityBannerState extends State<ConnectivityBanner>
//     with SingleTickerProviderStateMixin {
//   late AnimationController _controller;
//   late Animation<Offset> _slideAnim;
//
//   StreamSubscription<bool>? _sub;
//   bool _isOnline = true;
//   bool _showingOnline = false; // brief "back online" state
//   Timer? _onlineTimer;
//
//   @override
//   void initState() {
//     super.initState();
//
//     _controller = AnimationController(
//       vsync: this,
//       duration: const Duration(milliseconds: 300),
//     );
//     _slideAnim = Tween<Offset>(
//       begin: const Offset(0, -1),
//       end: Offset.zero,
//     ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOut));
//
//     _isOnline = ConnectivityService.instance.isOnline;
//
//     // Show banner immediately if already offline at startup
//     if (!_isOnline) _controller.forward();
//
//     _sub = ConnectivityService.instance.onlineStream.listen(_onConnectivityChange);
//   }
//
//   void _onConnectivityChange(bool online) {
//     if (!mounted) return;
//
//     setState(() {
//       _isOnline = online;
//       _showingOnline = online;
//     });
//
//     if (!online) {
//       // Went offline — slide banner in
//       _onlineTimer?.cancel();
//       _controller.forward();
//     } else {
//       // Came back online — show green banner briefly then slide out
//       widget.onReconnect?.call();
//       _onlineTimer?.cancel();
//       _onlineTimer = Timer(const Duration(seconds: 2), () {
//         if (mounted) {
//           _controller.reverse();
//           setState(() => _showingOnline = false);
//         }
//       });
//     }
//   }
//
//   @override
//   void dispose() {
//     _sub?.cancel();
//     _onlineTimer?.cancel();
//     _controller.dispose();
//     super.dispose();
//   }
//
//   @override
//   Widget build(BuildContext context) {
//     return Stack(
//       children: [
//         widget.child,
//
//         // Banner overlay
//         Positioned(
//           top: 0,
//           left: 0,
//           right: 0,
//           child: SlideTransition(
//             position: _slideAnim,
//             child: _Banner(isOnline: _isOnline || _showingOnline),
//           ),
//         ),
//       ],
//     );
//   }
// }
//
// class _Banner extends StatelessWidget {
//   const _Banner({required this.isOnline});
//   final bool isOnline;
//
//   @override
//   Widget build(BuildContext context) {
//     final topPadding = MediaQuery.of(context).padding.top;
//
//     return Container(
//       color: isOnline ? const Color(0xFF16A34A) : const Color(0xFFDC2626),
//       padding: EdgeInsets.only(
//         top: topPadding + 6,
//         bottom: 8,
//         left: 16,
//         right: 16,
//       ),
//       child: Row(
//         mainAxisAlignment: MainAxisAlignment.center,
//         children: [
//           Icon(
//             isOnline ? Icons.wifi_rounded : Icons.wifi_off_rounded,
//             color: Colors.white,
//             size: 16,
//           ),
//           const SizedBox(width: 8),
//           Text(
//             isOnline ? 'Back online' : 'No internet connection',
//             style: const TextStyle(
//               color: Colors.white,
//               fontSize: 13,
//               fontWeight: FontWeight.w600,
//             ),
//           ),
//         ],
//       ),
//     );
//   }
// }


import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';
import '../services/connectivity_service.dart';

/// Modern Connectivity Banner
///
/// Features:
/// ✓ Smooth slide + fade animation
/// ✓ Modern glassmorphism design
/// ✓ Rounded corners
/// ✓ Online/offline status
/// ✓ Auto-hide when back online
/// ✓ Socket reconnect callback
class ConnectivityBanner extends StatefulWidget {
  const ConnectivityBanner({
    super.key,
    required this.child,
    this.onReconnect,
  });

  final Widget child;

  /// Called when internet returns.
  final VoidCallback? onReconnect;

  @override
  State<ConnectivityBanner> createState() => _ConnectivityBannerState();
}

class _ConnectivityBannerState extends State<ConnectivityBanner>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<Offset> _slideAnimation;
  late Animation<double> _fadeAnimation;

  StreamSubscription<bool>? _subscription;
  Timer? _onlineTimer;

  bool _isOnline = true;
  bool _showingOnline = false;

  // Cached so build() never calls MediaQuery.of(context) directly —
  // that call is unsafe when the widget is inside a closing BottomSheet.
  double _topPadding = 0;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _topPadding = MediaQuery.of(context).padding.top;
  }

  @override
  void initState() {
    super.initState();

    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 350),
    );

    _slideAnimation = Tween<Offset>(
      begin: const Offset(0, -1.2),
      end: Offset.zero,
    ).animate(
      CurvedAnimation(
        parent: _controller,
        curve: Curves.easeOutCubic,
      ),
    );

    _fadeAnimation = CurvedAnimation(
      parent: _controller,
      curve: Curves.easeInOut,
    );

    _isOnline = ConnectivityService.instance.isOnline;

    // If app starts offline
    if (!_isOnline) {
      _controller.forward();
    }

    _subscription = ConnectivityService.instance.onlineStream.listen(
      _handleConnectivityChange,
    );
  }

  void _handleConnectivityChange(bool online) {
    if (!mounted) return;

    if (!online) {
      _onlineTimer?.cancel();

      setState(() {
        _isOnline = false;
        _showingOnline = false;
      });

      _controller.forward();
    } else {
      widget.onReconnect?.call();

      setState(() {
        _isOnline = true;
        _showingOnline = true;
      });

      _controller.forward();

      _onlineTimer?.cancel();
      _onlineTimer = Timer(const Duration(seconds: 2), () {
        if (!mounted) return;

        _controller.reverse();

        Future.delayed(const Duration(milliseconds: 300), () {
          if (mounted) {
            setState(() {
              _showingOnline = false;
            });
          }
        });
      });
    }
  }

  @override
  void dispose() {
    _subscription?.cancel();
    _onlineTimer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final showBanner = !_isOnline || _showingOnline;
    // Use the cached value — never call MediaQuery.of(context) here, as build
    // can be invoked with a deactivated context when inside a closing BottomSheet.

    return Stack(
      children: [
        widget.child,

        if (showBanner)
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: FadeTransition(
              opacity: _fadeAnimation,
              child: SlideTransition(
                position: _slideAnimation,
                child: _ModernBanner(
                  isOnline: _isOnline,
                  topPadding: _topPadding,
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _ModernBanner extends StatelessWidget {
  const _ModernBanner({
    required this.isOnline,
    required this.topPadding,
  });

  final bool isOnline;
  final double topPadding;

  @override
  Widget build(BuildContext context) {
    final Color backgroundColor = isOnline
        ? const Color(0xFF10B981)
        : const Color(0xFFEF4444);

    return Padding(
      padding: EdgeInsets.only(
        top: topPadding + 8,
        left: 12,
        right: 12,
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(18),
        child: BackdropFilter(
          filter: ImageFilter.blur(
            sigmaX: 15,
            sigmaY: 15,
          ),
          child: Container(
            decoration: BoxDecoration(
              color: backgroundColor.withOpacity(0.95),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(
                color: Colors.white.withOpacity(0.15),
              ),
              boxShadow: [
                BoxShadow(
                  color: backgroundColor.withOpacity(0.30),
                  blurRadius: 20,
                  spreadRadius: 1,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: 18,
                vertical: 14,
              ),
              child: Row(
                children: [
                  Container(
                    width: 34,
                    height: 34,
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.18),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      isOnline
                          ? Icons.wifi_rounded
                          : Icons.wifi_off_rounded,
                      color: Colors.white,
                      size: 18,
                    ),
                  ),

                  const SizedBox(width: 12),

                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          isOnline
                              ? 'Back Online'
                              : 'No Internet Connection',
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w700,
                            fontSize: 14,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          isOnline
                              ? 'Connection restored successfully'
                              : 'Please check your network',
                          style: TextStyle(
                            color: Colors.white.withOpacity(0.90),
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),

                  if (isOnline)
                    const Icon(
                      Icons.check_circle_rounded,
                      color: Colors.white,
                      size: 20,
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}