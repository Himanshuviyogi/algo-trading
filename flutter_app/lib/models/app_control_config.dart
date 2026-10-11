/// Model for the Firestore document: app_config/control
///
/// Fields:
///   maintenance_mode      — bool:   show maintenance screen to all users
///   maintenance_message   — String: message shown on maintenance screen
///   min_version           — String: minimum required version e.g. "1.2.0"
///   min_build             — int:    minimum required build number e.g. 5
///   force_update_message  — String: message shown on force-update screen
///   app_store_url         — String: URL to Play Store / App Store listing
///   is_app_enabled        — bool:   global kill switch (false = maintenance)
class AppControlConfig {
  final bool maintenanceMode;
  final String maintenanceMessage;
  final String minVersion;
  final int minBuild;
  final String forceUpdateMessage;
  final String appStoreUrl;
  final bool isAppEnabled;

  const AppControlConfig({
    required this.maintenanceMode,
    required this.maintenanceMessage,
    required this.minVersion,
    required this.minBuild,
    required this.forceUpdateMessage,
    required this.appStoreUrl,
    required this.isAppEnabled,
  });

  /// Safe defaults — app is fully open with no restrictions.
  factory AppControlConfig.defaults() => const AppControlConfig(
        maintenanceMode: false,
        maintenanceMessage:
            "We're performing scheduled maintenance.\nWe'll be back shortly!",
        minVersion: '0.0.0',
        minBuild: 0,
        forceUpdateMessage:
            'A new version of the app is required to continue.\nPlease update to the latest version.',
        appStoreUrl: '',
        isAppEnabled: true,
      );

  factory AppControlConfig.fromMap(Map<String, dynamic> data) {
    return AppControlConfig(
      maintenanceMode: data['maintenance_mode'] as bool? ?? false,
      maintenanceMessage: data['maintenance_message'] as String? ??
          "We're performing scheduled maintenance.\nWe'll be back shortly!",
      minVersion: data['min_version'] as String? ?? '0.0.0',
      minBuild: (data['min_build'] as num?)?.toInt() ?? 0,
      forceUpdateMessage: data['force_update_message'] as String? ??
          'A new version of the app is required to continue.\nPlease update to the latest version.',
      appStoreUrl: data['app_store_url'] as String? ?? '',
      isAppEnabled: data['is_app_enabled'] as bool? ?? true,
    );
  }

  Map<String, dynamic> toMap() => {
        'maintenance_mode': maintenanceMode,
        'maintenance_message': maintenanceMessage,
        'min_version': minVersion,
        'min_build': minBuild,
        'force_update_message': forceUpdateMessage,
        'app_store_url': appStoreUrl,
        'is_app_enabled': isAppEnabled,
      };

  AppControlConfig copyWith({
    bool? maintenanceMode,
    String? maintenanceMessage,
    String? minVersion,
    int? minBuild,
    String? forceUpdateMessage,
    String? appStoreUrl,
    bool? isAppEnabled,
  }) {
    return AppControlConfig(
      maintenanceMode: maintenanceMode ?? this.maintenanceMode,
      maintenanceMessage: maintenanceMessage ?? this.maintenanceMessage,
      minVersion: minVersion ?? this.minVersion,
      minBuild: minBuild ?? this.minBuild,
      forceUpdateMessage: forceUpdateMessage ?? this.forceUpdateMessage,
      appStoreUrl: appStoreUrl ?? this.appStoreUrl,
      isAppEnabled: isAppEnabled ?? this.isAppEnabled,
    );
  }
}
