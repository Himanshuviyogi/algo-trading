import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../models/app_control_config.dart';

/// Reads and watches the Firestore document `app_config/control`.
///
/// Exposes real-time getters for:
///   - [maintenanceMode]   — should the app show the maintenance screen?
///   - [isUpdateRequired]  — is the installed version below the minimum?
///   - [isAppEnabled]      — global kill switch
///   - [config]            — the full [AppControlConfig]
///
/// Usage:
///   await AppControlService.instance.initialize();
///   // then use getters or listen to watchConfig()
class AppControlService {
  AppControlService._();
  static final instance = AppControlService._();

  AppControlConfig _config = AppControlConfig.defaults();
  PackageInfo? _packageInfo;

  AppControlConfig get config => _config;

  /// True when admin has enabled maintenance mode OR the global kill switch
  /// is off.
  bool get maintenanceMode =>
      _config.maintenanceMode || !_config.isAppEnabled;

  /// True when the installed app version is below the required minimum.
  bool get isUpdateRequired {
    if (_packageInfo == null) return false;
    final currentVersion = _packageInfo!.version;       // e.g. "1.2.3"
    final currentBuild =
        int.tryParse(_packageInfo!.buildNumber) ?? 0;   // e.g. 5

    // Compare build number first (faster, unambiguous).
    if (currentBuild < _config.minBuild) return true;

    // Semantic version comparison (major.minor.patch).
    return _compareVersions(currentVersion, _config.minVersion) < 0;
  }

  /// The installed app version string (e.g. "1.0.0").
  String get currentVersion => _packageInfo?.version ?? '—';

  /// The installed app build number (e.g. "1").
  String get currentBuildNumber => _packageInfo?.buildNumber ?? '—';

  // ── Lifecycle ──────────────────────────────────────────────────────────────

  /// Load config from Firestore and package info once at startup.
  /// Uses a one-shot .get() — no persistent listener, no ongoing reads.
  /// If the admin changes maintenance/kill-switch settings, users will pick
  /// up the new values on their next cold-start.
  Future<void> initialize() async {
    try {
      _packageInfo = await PackageInfo.fromPlatform();
    } catch (e) {
      debugPrint('[AppControl] Failed to read package info: $e');
    }

    try {
      final doc = await FirebaseFirestore.instance
          .collection('app_config')
          .doc('control')
          .get();

      if (doc.exists && doc.data() != null) {
        _config = AppControlConfig.fromMap(doc.data()!);
      }

      debugPrint(
        '[AppControl] initialized — maintenance=$maintenanceMode '
        'updateRequired=$isUpdateRequired '
        'version=$currentVersion+$currentBuildNumber',
      );
    } catch (e) {
      debugPrint('[AppControl] Failed to load config, using defaults: $e');
    }
  }

  // ── Helpers ────────────────────────────────────────────────────────────────

  /// Returns negative if [a] < [b], zero if equal, positive if [a] > [b].
  /// Compares major.minor.patch segments numerically.
  int _compareVersions(String a, String b) {
    final aParts = a.split('.').map((s) => int.tryParse(s) ?? 0).toList();
    final bParts = b.split('.').map((s) => int.tryParse(s) ?? 0).toList();

    // Pad to same length.
    while (aParts.length < 3) { aParts.add(0); }
    while (bParts.length < 3) { bParts.add(0); }

    for (int i = 0; i < 3; i++) {
      if (aParts[i] != bParts[i]) return aParts[i] - bParts[i];
    }
    return 0;
  }
}
