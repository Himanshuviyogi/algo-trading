import 'package:flutter/material.dart';

/// A modern, styled notification banner that appears at the top of the screen
class NotificationBanner extends StatelessWidget {
  const NotificationBanner({
    super.key,
    required this.title,
    required this.body,
    this.onTap,
    this.icon,
    this.backgroundColor,
    this.textColor,
  });

  final String title;
  final String body;
  final VoidCallback? onTap;
  final IconData? icon;
  final Color? backgroundColor;
  final Color? textColor;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bgColor = backgroundColor ?? theme.colorScheme.primary;
    final txtColor = textColor ?? theme.colorScheme.onPrimary;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: bgColor,
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.15),
                blurRadius: 20,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Row(
            children: [
              // Icon
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: txtColor.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  icon ?? Icons.notifications_active_rounded,
                  color: txtColor,
                  size: 24,
                ),
              ),
              const SizedBox(width: 12),
              // Content
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        color: txtColor,
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        height: 1.2,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (body.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        body,
                        style: TextStyle(
                          color: txtColor.withOpacity(0.9),
                          fontSize: 14,
                          height: 1.3,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 8),
              // Tap indicator
              if (onTap != null)
                Icon(
                  Icons.arrow_forward_ios_rounded,
                  color: txtColor.withOpacity(0.7),
                  size: 16,
                ),
            ],
          ),
        ),
      ),
    );
  }

  /// Shows a notification banner at the top of the screen.
  /// Pass the [OverlayState] directly to avoid context lookup issues.
  static void showOnOverlay(
    OverlayState overlay, {
    required String title,
    required String body,
    VoidCallback? onTap,
    IconData? icon,
    Color? backgroundColor,
    Color? textColor,
    Duration duration = const Duration(seconds: 4),
  }) {
    late OverlayEntry overlayEntry;

    overlayEntry = OverlayEntry(
      builder: (context) => Positioned(
        top: MediaQuery.of(context).padding.top,
        left: 0,
        right: 0,
        child: _AnimatedNotificationBanner(
          duration: duration,
          onDismiss: () => overlayEntry.remove(),
          child: NotificationBanner(
            title: title,
            body: body,
            onTap: () {
              overlayEntry.remove();
              onTap?.call();
            },
            icon: icon,
            backgroundColor: backgroundColor,
            textColor: textColor,
          ),
        ),
      ),
    );

    overlay.insert(overlayEntry);
  }

  /// Shows a notification banner at the top of the screen
  static void show(
    BuildContext context, {
    required String title,
    required String body,
    VoidCallback? onTap,
    IconData? icon,
    Color? backgroundColor,
    Color? textColor,
    Duration duration = const Duration(seconds: 4),
  }) {
    final overlay = Overlay.maybeOf(context);
    if (overlay == null) {
      print('❌ No Overlay found in context - cannot show notification banner');
      return;
    }
    showOnOverlay(
      overlay,
      title: title,
      body: body,
      onTap: onTap,
      icon: icon,
      backgroundColor: backgroundColor,
      textColor: textColor,
      duration: duration,
    );
  }
}

/// Animated wrapper for the notification banner
class _AnimatedNotificationBanner extends StatefulWidget {
  const _AnimatedNotificationBanner({
    required this.duration,
    required this.onDismiss,
    required this.child,
  });

  final Duration duration;
  final VoidCallback onDismiss;
  final Widget child;

  @override
  State<_AnimatedNotificationBanner> createState() =>
      _AnimatedNotificationBannerState();
}

class _AnimatedNotificationBannerState
    extends State<_AnimatedNotificationBanner>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<Offset> _slideAnimation;
  late Animation<double> _fadeAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );

    _slideAnimation = Tween<Offset>(
      begin: const Offset(0, -1),
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _controller,
      curve: Curves.easeOutCubic,
    ));

    _fadeAnimation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(
      parent: _controller,
      curve: Curves.easeOut,
    ));

    // Slide in
    _controller.forward();

    // Auto dismiss after duration
    Future.delayed(widget.duration, () {
      if (mounted) {
        _dismiss();
      }
    });
  }

  Future<void> _dismiss() async {
    await _controller.reverse();
    widget.onDismiss();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SlideTransition(
      position: _slideAnimation,
      child: FadeTransition(
        opacity: _fadeAnimation,
        child: GestureDetector(
          onVerticalDragEnd: (details) {
            // Swipe up to dismiss
            if (details.primaryVelocity != null &&
                details.primaryVelocity! < -500) {
              _dismiss();
            }
          },
          child: widget.child,
        ),
      ),
    );
  }
}
