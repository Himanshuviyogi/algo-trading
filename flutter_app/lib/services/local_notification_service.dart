import 'dart:typed_data';
import 'dart:ui';
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import '../config/notification_config.dart';

/// Handles local (on-device) notifications and in-app audio feedback.
///
/// Background notifications use per-type Android channels, each bound to its
/// own sound file in android/app/src/main/res/raw/.
///
/// Foreground notifications play the matching asset from assets/sounds/ via
/// audioplayers.
class LocalNotificationService {
  LocalNotificationService._();
  static final instance = LocalNotificationService._();

  final _plugin = FlutterLocalNotificationsPlugin();

  /// One AudioPlayer instance reused across calls (stopped before each play).
  final _audioPlayer = AudioPlayer();

  /// Called when the user taps "View Trade" on a background notification.
  void Function(String recommendationId)? onViewTrade;

  static const _actionView = 'view_trade';

  // ── Initialisation ─────────────────────────────────────────────────────────

  Future<void> initialize() async {
    const androidSettings =
        AndroidInitializationSettings('@mipmap/ic_launcher');
    const iosSettings = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );

    await _plugin.initialize(
      const InitializationSettings(android: androidSettings, iOS: iosSettings),
      onDidReceiveNotificationResponse: _onNotificationResponse,
      onDidReceiveBackgroundNotificationResponse:
          _onBackgroundNotificationResponse,
    );

    // Register one Android channel per notification type so each type can
    // carry its own sound.  Channels are cheap and cached by the OS.
    await _ensureChannels();
  }

  /// Creates all required Android notification channels.
  Future<void> _ensureChannels() async {
    final androidPlugin = _plugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>();
    if (androidPlugin == null) return;

    final types = [
      null,                 // default / trade channel
      'target_hit',
      'stoploss_hit',
      'daily_news',
      'subscription_expiry',
    ];

    for (final type in types) {
      final soundName = NotificationConfig.backgroundSoundForType(type);
      final soundSource = soundName != null
          ? UriAndroidNotificationSound(
              'android.resource://com.stock.algo/raw/$soundName',
            )
          : null;

      final channel = AndroidNotificationChannel(
        NotificationConfig.channelIdForType(type),
        NotificationConfig.channelNameForType(type),
        description: NotificationConfig.channelDescForType(type),
        importance: Importance.max,
        playSound: true,
        sound: soundSource,
        enableVibration: true,
        vibrationPattern: NotificationConfig.vibrationPattern != null
            ? Int64List.fromList(NotificationConfig.vibrationPattern!)
            : null,
        ledColor: const Color(0xFF6366F1),
      );

      await androidPlugin.createNotificationChannel(channel);
    }
  }

  // ── Notification response handlers ─────────────────────────────────────────

  void _onNotificationResponse(NotificationResponse response) {
    final payload = response.payload;
    if (payload != null && payload.isNotEmpty) {
      onViewTrade?.call(payload);
    }
  }

  // ── Foreground feedback ────────────────────────────────────────────────────

  /// Triggers haptic + plays the correct sound for the given notification [type].
  ///
  /// Call this when a foreground FCM message arrives.
  Future<void> triggerForegroundFeedback({String? type}) async {
    if (NotificationConfig.foregroundVibration) {
      switch (NotificationConfig.foregroundHapticStyle) {
        case 'light':
          await HapticFeedback.lightImpact();
          break;
        case 'medium':
          await HapticFeedback.mediumImpact();
          break;
        case 'heavy':
        default:
          await HapticFeedback.heavyImpact();
          break;
      }
    }

    if (NotificationConfig.foregroundSound) {
      final asset = NotificationConfig.foregroundAssetForType(type);
      if (asset != null) {
        try {
          await _audioPlayer.stop();
          await _audioPlayer.play(AssetSource(asset), volume: 1.0);
        } catch (_) {
          // Fallback to system click if audio fails.
          await SystemSound.play(SystemSoundType.click);
        }
      }
    }
  }

  // ── Background (OS) notification ───────────────────────────────────────────

  /// Shows a local notification with the correct channel/sound for [type].
  Future<void> showTradeNotification({
    required String title,
    required String body,
    required String type,
    String? recommendationId,
  }) async {
    final color  = _colorForType(type);
    final label  = _labelForType(type);
    final emoji  = _emojiForType(type);

    final channelId   = NotificationConfig.channelIdForType(type);
    final channelName = NotificationConfig.channelNameForType(type);
    final channelDesc = NotificationConfig.channelDescForType(type);
    final soundName   = NotificationConfig.backgroundSoundForType(type);

    final soundSource = soundName != null
        ? UriAndroidNotificationSound(
            'android.resource://com.stock.algo/raw/$soundName',
          )
        : null;

    final androidDetails = AndroidNotificationDetails(
      channelId,
      channelName,
      channelDescription: channelDesc,
      importance: Importance.max,
      priority: Priority.max,
      color: color,
      colorized: true,
      icon: '@mipmap/ic_launcher',
      largeIcon: const DrawableResourceAndroidBitmap('@mipmap/ic_launcher'),
      sound: soundSource,
      playSound: true,
      enableVibration: true,
      vibrationPattern: NotificationConfig.vibrationPattern != null
          ? Int64List.fromList(NotificationConfig.vibrationPattern!)
          : null,
      styleInformation: BigTextStyleInformation(
        '$emoji $body',
        contentTitle: '$emoji $title',
        summaryText: label,
      ),
      groupKey: 'trade_updates_group',
      actions: recommendationId != null
          ? [
              AndroidNotificationAction(
                _actionView,
                '📊 View Trade',
                showsUserInterface: true,
                cancelNotification: true,
              ),
            ]
          : [],
      ticker: '$emoji $title',
      subText: label,
      visibility: NotificationVisibility.public,
      category: AndroidNotificationCategory.message,
    );

    const iosDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
      interruptionLevel: InterruptionLevel.timeSensitive,
    );

    await _plugin.show(
      (recommendationId ?? DateTime.now().toString()).hashCode,
      '$emoji $title',
      body,
      NotificationDetails(android: androidDetails, iOS: iosDetails),
      payload: recommendationId,
    );
  }

  // ── Type mappings ──────────────────────────────────────────────────────────

  Color _colorForType(String type) {
    switch (type) {
      case 'trade':               return const Color(0xFF22C55E);
      case 'recommendation':      return const Color(0xFF6366F1);
      case 'target_hit':          return const Color(0xFF16A34A);
      case 'stoploss_hit':        return const Color(0xFFDC2626);
      case 'alert':               return const Color(0xFFF59E0B);
      case 'daily_news':          return const Color(0xFF0EA5E9);
      case 'subscription_expiry': return const Color(0xFFF97316);
      default:                    return const Color(0xFF4F46E5);
    }
  }

  String _labelForType(String type) {
    switch (type) {
      case 'trade':               return 'New Trade Call';
      case 'recommendation':      return 'Trade Update';
      case 'target_hit':          return 'Target Achieved';
      case 'stoploss_hit':        return 'Stoploss Triggered';
      case 'alert':               return 'Market Alert';
      case 'daily_news':          return 'Daily News';
      case 'subscription_expiry': return 'Subscription Expiring';
      default:                    return 'Notification';
    }
  }

  String _emojiForType(String type) {
    switch (type) {
      case 'trade':               return '📈';
      case 'recommendation':      return '💡';
      case 'target_hit':          return '🎯';
      case 'stoploss_hit':        return '🛑';
      case 'alert':               return '⚠️';
      case 'daily_news':          return '📰';
      case 'subscription_expiry': return '⏳';
      default:                    return '🔔';
    }
  }
}

@pragma('vm:entry-point')
void _onBackgroundNotificationResponse(NotificationResponse response) {}
