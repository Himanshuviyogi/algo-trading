import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Reads security config from Firestore and applies it to the app.
///
/// Config is loaded once at startup via [initialize()] — no persistent listener.
/// This avoids a permanent Firestore read stream. If the admin changes the
/// config, users will pick up the new values on their next app cold-start.
///
/// Firestore document: app_config/security
/// Fields:
///   - screenshot_prevention: bool  (Android FLAG_SECURE)
///   - watermark_enabled: bool      (user phone watermark on screens)
class SecurityService {
  SecurityService._();
  static final instance = SecurityService._();

  static const _channel = MethodChannel('com.stockara/security');

  bool _screenshotPrevention = false;
  bool _watermarkEnabled = false;

  bool get screenshotPrevention => _screenshotPrevention;
  bool get watermarkEnabled => _watermarkEnabled;

  /// Load config from Firestore once and apply. Call once in main().
  /// Uses a one-shot .get() — no persistent listener, no ongoing reads.
  Future<void> initialize() async {
    try {
      final doc = await FirebaseFirestore.instance
          .collection('app_config')
          .doc('security')
          .get();

      if (doc.exists) {
        _screenshotPrevention = doc.data()?['screenshot_prevention'] as bool? ?? false;
        _watermarkEnabled     = doc.data()?['watermark_enabled']     as bool? ?? false;
      }

      await _applyScreenshotPrevention(_screenshotPrevention);
      debugPrint('[Security] screenshot_prevention=$_screenshotPrevention watermark=$_watermarkEnabled');
    } catch (e) {
      debugPrint('[Security] Failed to load config: $e');
    }
  }

  Future<void> _applyScreenshotPrevention(bool enable) async {
    if (defaultTargetPlatform != TargetPlatform.android) return;
    try {
      await _channel.invokeMethod(
        enable ? 'enableScreenshotPrevention' : 'disableScreenshotPrevention',
      );
    } catch (e) {
      debugPrint('[Security] FLAG_SECURE error: $e');
    }
  }
}
