import 'package:flutter/material.dart';

import '../services/app_control_service.dart';

/// Full-screen overlay shown when the app is in maintenance mode.
/// Displayed to ALL users (including admins) when maintenance_mode is true
/// or is_app_enabled is false in Firestore app_config/control.
class MaintenanceScreen extends StatelessWidget {
  const MaintenanceScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final message = AppControlService.instance.config.maintenanceMessage;
    final isKillSwitch = !AppControlService.instance.config.isAppEnabled;

    return Scaffold(
      backgroundColor: const Color(0xFF0A0E1A),
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // Icon
                Container(
                  width: 96,
                  height: 96,
                  decoration: BoxDecoration(
                    color: const Color(0xFF1A2235),
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: const Color(0xFFFF6B35).withOpacity(0.4),
                      width: 2,
                    ),
                  ),
                  child: const Icon(
                    Icons.construction_rounded,
                    size: 48,
                    color: Color(0xFFFF6B35),
                  ),
                ),
                const SizedBox(height: 32),

                // Title
                Text(
                  isKillSwitch ? 'App Unavailable' : 'Under Maintenance',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 26,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.5,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),

                // Message
                Text(
                  message,
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.65),
                    fontSize: 15,
                    height: 1.6,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 48),

                // Divider with version info
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 12,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1A2235),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: Colors.white.withOpacity(0.06),
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.info_outline_rounded,
                        size: 15,
                        color: Colors.white.withOpacity(0.35),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'v${AppControlService.instance.currentVersion}'
                        '+${AppControlService.instance.currentBuildNumber}',
                        style: TextStyle(
                          color: Colors.white.withOpacity(0.35),
                          fontSize: 13,
                        ),
                      ),
                    ],
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
