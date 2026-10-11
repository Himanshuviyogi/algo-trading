import 'dart:ui';
import 'package:flutter/material.dart';
import 'app_theme.dart';

class CustomAppBar extends StatelessWidget implements PreferredSizeWidget {
  const CustomAppBar({
    super.key,
    this.showBack = false,
    this.onBack,
  });

  final bool showBack;
  final VoidCallback? onBack;

  @override
  Size get preferredSize => const Size.fromHeight(85);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.only(
        top: MediaQuery.of(context).padding.top + 8,
        left: 12,
        right: 12,
        bottom: 6,
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(22),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
          child: Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  Colors.white.withOpacity(0.96),
                  Colors.white.withOpacity(0.90),
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(22),
              boxShadow: [
                BoxShadow(
                  color: AuroraColors.violet.withOpacity(0.14),
                  blurRadius: 24,
                  offset: const Offset(0, 8),
                ),
                BoxShadow(
                  color: Colors.black.withOpacity(0.06),
                  blurRadius: 12,
                  offset: const Offset(0, 3),
                ),
              ],
              border: Border.all(
                color: AuroraColors.violet.withOpacity(0.18),
                width: 1,
              ),
            ),
            child: Row(
              children: [
                // ── Back button ──────────────────────────────────────────
                if (showBack)
                  Padding(
                    padding: const EdgeInsets.only(left: 8),
                    child: IconButton(
                      icon: Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: AuroraColors.violetTint(0.18),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: AuroraColors.violetTint(0.30),
                            width: 1,
                          ),
                        ),
                        child: const Icon(
                          Icons.arrow_back_ios_new,
                          size: 16,
                          color: AuroraColors.violet,
                        ),
                      ),
                      onPressed: onBack ?? () => Navigator.pop(context),
                    ),
                  ),

                const SizedBox(width: 4),

                // ── Logo ─────────────────────────────────────────────────
                Container(
                  height: 40,
                  width: 40,
                  decoration: BoxDecoration(
                    gradient: AuroraColors.gradientBrand,
                    borderRadius: BorderRadius.circular(12),
                    boxShadow: [
                      BoxShadow(
                        color: AuroraColors.violet.withOpacity(0.40),
                        blurRadius: 12,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: Image.asset(
                      'assets/images/small_logo.png',
                      fit: BoxFit.cover,
                    ),
                  ),
                ),

                const SizedBox(width: 10),

                // ── Title ─────────────────────────────────────────────────
                const Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Stockara',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        color: AuroraColors.textPrimary,
                        letterSpacing: -0.3,
                      ),
                    ),
                    Text(
                      'SMART STOCKS • LIVE',
                      style: TextStyle(
                        fontSize: 10,
                        color: AuroraColors.textMuted,
                        letterSpacing: 0.8,
                      ),
                    ),
                  ],
                ),

                const Spacer(),

                // ── Notification icon ─────────────────────────────────────
                Container(
                  margin: const EdgeInsets.only(right: 10),
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: AuroraColors.violetTint(0.15),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: AuroraColors.violetTint(0.28),
                      width: 1,
                    ),
                  ),
                  child: const Icon(
                    Icons.notifications_none_rounded,
                    color: AuroraColors.violet,
                    size: 20,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
