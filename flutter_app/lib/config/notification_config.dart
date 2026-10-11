/// ─────────────────────────────────────────────────────────────────────────────
/// Notification Configuration
/// ─────────────────────────────────────────────────────────────────────────────
/// Edit this file to configure notification behavior without touching logic.
///
/// BACKGROUND notifications (app killed / minimized):
///   - Uses the Android notification channel sound + vibration
///   - Sound files must be placed in android/app/src/main/res/raw/
///
/// FOREGROUND notifications (app is open):
///   - Shown as an in-app banner (NotificationBanner widget)
///   - Audio played via audioplayers using assets/sounds/<file>
///
/// SOUND FILE SLOTS (replace placeholders with real audio):
///   android/app/src/main/res/raw/trade_alert.mp3       → new trade call
///   android/app/src/main/res/raw/target_hit.mp3        → target achieved
///   android/app/src/main/res/raw/stoploss_hit.mp3      → stoploss triggered
///   android/app/src/main/res/raw/daily_news.mp3        → daily news / market update
///   android/app/src/main/res/raw/subscription_expiry.mp3 → subscription expiring
///   assets/sounds/ must contain the same files (same names) for foreground playback
/// ─────────────────────────────────────────────────────────────────────────────

class NotificationConfig {

  // ── Per-type foreground sound assets ────────────────────────────────────────
  // Map of notification type → asset path inside assets/sounds/
  // Set a value to null to skip audio for that type.
  static const Map<String, String?> foregroundSoundAssets = {
    'trade':                'sounds/trade_alert.mp3',
    'recommendation':       'sounds/trade_alert.mp3',
    'target_hit':           'sounds/target_hit.mp3',
    'stoploss_hit':         'sounds/stoploss_hit.mp3',
    'alert':                'sounds/daily_news.mp3',
    'daily_news':           'sounds/daily_news.mp3',
    'subscription_expiry':  'sounds/subscription_expiry.mp3',
    'order_placed':         'sounds/trade_alert.mp3',
    'order_filled':         'sounds/target_hit.mp3',
    'order_rejected':       'sounds/stoploss_hit.mp3',
  };

  // Fallback asset used when a type is not in the map above.
  static const String fallbackForegroundSoundAsset = 'sounds/trade_alert.mp3';

  // ── Per-type background sound names (Android res/raw, no extension) ─────────
  // Map of notification type → file name in android/app/src/main/res/raw/
  // Set a value to null to use the device default notification sound.
  static const Map<String, String?> backgroundSoundNames = {
    'trade':                'trade_alert',
    'recommendation':       'trade_alert',
    'target_hit':           'target_hit',
    'stoploss_hit':         'stoploss_hit',
    'alert':                'daily_news',
    'daily_news':           'daily_news',
    'subscription_expiry':  'subscription_expiry',
    'order_placed':         'trade_alert',
    'order_filled':         'target_hit',
    'order_rejected':       'stoploss_hit',
  };

  // Fallback sound name when a type is not in the map above.
  static const String fallbackBackgroundSoundName = 'trade_alert';

  // ── Background notification vibration ──────────────────────────────────────
  // Vibration pattern in milliseconds: [delay, vibrate, pause, vibrate, ...]
  // null = device default vibration
  static const List<int>? vibrationPattern = [0, 300, 100, 300];

  // ── Foreground notification: vibration ─────────────────────────────────────
  static const bool foregroundVibration = true;

  // ── Foreground notification: sound ─────────────────────────────────────────
  static const bool foregroundSound = true;

  // ── Foreground sound style ──────────────────────────────────────────────────
  // 'light'  → soft click  (HapticFeedback.lightImpact)
  // 'medium' → medium tap  (HapticFeedback.mediumImpact)
  // 'heavy'  → strong punch (HapticFeedback.heavyImpact)
  static const String foregroundHapticStyle = 'heavy';

  // ── Notification channel IDs ────────────────────────────────────────────────
  // Each type gets its own Android channel so each carries a distinct sound.
  // Changing a channel ID resets user-visible channel settings on Android 8+.
  static const String channelId              = 'trade_alerts_v3';
  static const String channelName            = 'Trade Alerts';
  static const String channelDesc            = 'Real-time trade signals and updates';

  static const String targetChannelId        = 'target_hit_v1';
  static const String targetChannelName      = 'Target Hit';
  static const String targetChannelDesc      = 'Notifications when a trade target is achieved';

  static const String stoplossChannelId      = 'stoploss_hit_v1';
  static const String stoplossChannelName    = 'Stoploss Hit';
  static const String stoplossChannelDesc    = 'Notifications when a stoploss is triggered';

  static const String dailyNewsChannelId     = 'daily_news_v1';
  static const String dailyNewsChannelName   = 'Daily News';
  static const String dailyNewsChannelDesc   = 'Daily market news and alerts';

  static const String subscriptionChannelId  = 'subscription_v1';
  static const String subscriptionChannelName = 'Subscription';
  static const String subscriptionChannelDesc = 'Subscription renewal reminders';

  static const String orderChannelId         = 'order_updates_v1';
  static const String orderChannelName       = 'Order Updates';
  static const String orderChannelDesc       = 'Order filled, rejected, and placement notifications';

  // ── Helpers ─────────────────────────────────────────────────────────────────

  /// Returns the foreground asset path for the given notification [type].
  static String? foregroundAssetForType(String? type) =>
      foregroundSoundAssets[type ?? ''] ?? fallbackForegroundSoundAsset;

  /// Returns the background (res/raw) sound name for the given [type].
  static String? backgroundSoundForType(String? type) =>
      backgroundSoundNames[type ?? ''] ?? fallbackBackgroundSoundName;

  /// Returns the Android channel ID that should be used for [type].
  static String channelIdForType(String? type) {
    switch (type) {
      case 'target_hit':          return targetChannelId;
      case 'stoploss_hit':        return stoplossChannelId;
      case 'daily_news':
      case 'alert':               return dailyNewsChannelId;
      case 'subscription_expiry': return subscriptionChannelId;
      case 'order_placed':
      case 'order_filled':
      case 'order_rejected':      return orderChannelId;
      default:                    return channelId;
    }
  }

  /// Returns the Android channel name for [type].
  static String channelNameForType(String? type) {
    switch (type) {
      case 'target_hit':          return targetChannelName;
      case 'stoploss_hit':        return stoplossChannelName;
      case 'daily_news':
      case 'alert':               return dailyNewsChannelName;
      case 'subscription_expiry': return subscriptionChannelName;
      case 'order_placed':
      case 'order_filled':
      case 'order_rejected':      return orderChannelName;
      default:                    return channelName;
    }
  }

  /// Returns the Android channel description for [type].
  static String channelDescForType(String? type) {
    switch (type) {
      case 'target_hit':          return targetChannelDesc;
      case 'stoploss_hit':        return stoplossChannelDesc;
      case 'daily_news':
      case 'alert':               return dailyNewsChannelDesc;
      case 'subscription_expiry': return subscriptionChannelDesc;
      case 'order_placed':
      case 'order_filled':
      case 'order_rejected':      return orderChannelDesc;
      default:                    return channelDesc;
    }
  }
}
