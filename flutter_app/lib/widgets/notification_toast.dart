import 'package:flutter/material.dart';

/// Different styles for notification toasts
enum NotificationToastStyle {
  success,
  error,
  warning,
  info,
  trade,
}

/// A modern toast-style notification that appears at the top
class NotificationToast extends StatelessWidget {
  const NotificationToast({
    super.key,
    required this.title,
    this.body,
    this.style = NotificationToastStyle.info,
    this.onTap,
    this.showCloseButton = true,
    this.onClose,
  });

  final String title;
  final String? body;
  final NotificationToastStyle style;
  final VoidCallback? onTap;
  final bool showCloseButton;
  final VoidCallback? onClose;

  @override
  Widget build(BuildContext context) {
    final config = _getStyleConfig(context);

    return Material(
      color: Colors.transparent,
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: config.backgroundColor,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: config.borderColor,
            width: 1.5,
          ),
          boxShadow: [
            BoxShadow(
              color: config.shadowColor,
              blurRadius: 16,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                // Icon
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: config.iconBackgroundColor,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(
                    config.icon,
                    color: config.iconColor,
                    size: 22,
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
                          color: config.titleColor,
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          height: 1.2,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (body != null && body!.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text(
                          body!,
                          style: TextStyle(
                            color: config.bodyColor,
                            fontSize: 13,
                            height: 1.3,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ],
                  ),
                ),
                // Close button
                if (showCloseButton) ...[
                  const SizedBox(width: 8),
                  IconButton(
                    icon: Icon(
                      Icons.close_rounded,
                      color: config.closeButtonColor,
                      size: 20,
                    ),
                    onPressed: onClose,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(
                      minWidth: 32,
                      minHeight: 32,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  _ToastStyleConfig _getStyleConfig(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    switch (style) {
      case NotificationToastStyle.success:
        return _ToastStyleConfig(
          icon: Icons.check_circle_rounded,
          iconColor: const Color(0xFF10B981),
          iconBackgroundColor: const Color(0xFF10B981).withOpacity(0.15),
          backgroundColor: isDark ? const Color(0xFF1F2937) : Colors.white,
          borderColor: const Color(0xFF10B981).withOpacity(0.3),
          titleColor: isDark ? Colors.white : const Color(0xFF111827),
          bodyColor: isDark ? const Color(0xFF9CA3AF) : const Color(0xFF6B7280),
          closeButtonColor: isDark ? const Color(0xFF9CA3AF) : const Color(0xFF6B7280),
          shadowColor: const Color(0xFF10B981).withOpacity(0.2),
        );

      case NotificationToastStyle.error:
        return _ToastStyleConfig(
          icon: Icons.error_rounded,
          iconColor: const Color(0xFFEF4444),
          iconBackgroundColor: const Color(0xFFEF4444).withOpacity(0.15),
          backgroundColor: isDark ? const Color(0xFF1F2937) : Colors.white,
          borderColor: const Color(0xFFEF4444).withOpacity(0.3),
          titleColor: isDark ? Colors.white : const Color(0xFF111827),
          bodyColor: isDark ? const Color(0xFF9CA3AF) : const Color(0xFF6B7280),
          closeButtonColor: isDark ? const Color(0xFF9CA3AF) : const Color(0xFF6B7280),
          shadowColor: const Color(0xFFEF4444).withOpacity(0.2),
        );

      case NotificationToastStyle.warning:
        return _ToastStyleConfig(
          icon: Icons.warning_amber_rounded,
          iconColor: const Color(0xFFF59E0B),
          iconBackgroundColor: const Color(0xFFF59E0B).withOpacity(0.15),
          backgroundColor: isDark ? const Color(0xFF1F2937) : Colors.white,
          borderColor: const Color(0xFFF59E0B).withOpacity(0.3),
          titleColor: isDark ? Colors.white : const Color(0xFF111827),
          bodyColor: isDark ? const Color(0xFF9CA3AF) : const Color(0xFF6B7280),
          closeButtonColor: isDark ? const Color(0xFF9CA3AF) : const Color(0xFF6B7280),
          shadowColor: const Color(0xFFF59E0B).withOpacity(0.2),
        );

      case NotificationToastStyle.trade:
        return _ToastStyleConfig(
          icon: Icons.trending_up_rounded,
          iconColor: const Color(0xFF3B82F6),
          iconBackgroundColor: const Color(0xFF3B82F6).withOpacity(0.15),
          backgroundColor: isDark ? const Color(0xFF1F2937) : Colors.white,
          borderColor: const Color(0xFF3B82F6).withOpacity(0.3),
          titleColor: isDark ? Colors.white : const Color(0xFF111827),
          bodyColor: isDark ? const Color(0xFF9CA3AF) : const Color(0xFF6B7280),
          closeButtonColor: isDark ? const Color(0xFF9CA3AF) : const Color(0xFF6B7280),
          shadowColor: const Color(0xFF3B82F6).withOpacity(0.2),
        );

      case NotificationToastStyle.info:
      default:
        return _ToastStyleConfig(
          icon: Icons.info_rounded,
          iconColor: const Color(0xFF3B82F6),
          iconBackgroundColor: const Color(0xFF3B82F6).withOpacity(0.15),
          backgroundColor: isDark ? const Color(0xFF1F2937) : Colors.white,
          borderColor: const Color(0xFF3B82F6).withOpacity(0.3),
          titleColor: isDark ? Colors.white : const Color(0xFF111827),
          bodyColor: isDark ? const Color(0xFF9CA3AF) : const Color(0xFF6B7280),
          closeButtonColor: isDark ? const Color(0xFF9CA3AF) : const Color(0xFF6B7280),
          shadowColor: const Color(0xFF3B82F6).withOpacity(0.2),
        );
    }
  }

  /// Shows a toast notification at the top of the screen
  static void show(
    BuildContext context, {
    required String title,
    String? body,
    NotificationToastStyle style = NotificationToastStyle.info,
    VoidCallback? onTap,
    Duration duration = const Duration(seconds: 4),
    bool showCloseButton = true,
  }) {
    final overlay = Overlay.of(context);
    late OverlayEntry overlayEntry;

    overlayEntry = OverlayEntry(
      builder: (context) => Positioned(
        top: MediaQuery.of(context).padding.top + 8,
        left: 0,
        right: 0,
        child: _AnimatedToast(
          duration: duration,
          onDismiss: () => overlayEntry.remove(),
          child: NotificationToast(
            title: title,
            body: body,
            style: style,
            onTap: () {
              overlayEntry.remove();
              onTap?.call();
            },
            showCloseButton: showCloseButton,
            onClose: () => overlayEntry.remove(),
          ),
        ),
      ),
    );

    overlay.insert(overlayEntry);
  }
}

/// Configuration for toast styling
class _ToastStyleConfig {
  const _ToastStyleConfig({
    required this.icon,
    required this.iconColor,
    required this.iconBackgroundColor,
    required this.backgroundColor,
    required this.borderColor,
    required this.titleColor,
    required this.bodyColor,
    required this.closeButtonColor,
    required this.shadowColor,
  });

  final IconData icon;
  final Color iconColor;
  final Color iconBackgroundColor;
  final Color backgroundColor;
  final Color borderColor;
  final Color titleColor;
  final Color bodyColor;
  final Color closeButtonColor;
  final Color shadowColor;
}

/// Animated wrapper for toast
class _AnimatedToast extends StatefulWidget {
  const _AnimatedToast({
    required this.duration,
    required this.onDismiss,
    required this.child,
  });

  final Duration duration;
  final VoidCallback onDismiss;
  final Widget child;

  @override
  State<_AnimatedToast> createState() => _AnimatedToastState();
}

class _AnimatedToastState extends State<_AnimatedToast>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<Offset> _slideAnimation;
  late Animation<double> _fadeAnimation;

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
    ).animate(CurvedAnimation(
      parent: _controller,
      curve: Curves.easeOutBack,
    ));

    _fadeAnimation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(
      parent: _controller,
      curve: const Interval(0.0, 0.5),
    ));

    _controller.forward();

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
            if (details.primaryVelocity != null &&
                details.primaryVelocity! < -300) {
              _dismiss();
            }
          },
          child: widget.child,
        ),
      ),
    );
  }
}
