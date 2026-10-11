import 'package:firebase_messaging/firebase_messaging.dart';

/// Abstract interface for Firebase Cloud Messaging operations.
abstract class NotificationService {
  /// Requests notification permission from the user.
  Future<void> requestPermission();

  /// Returns the current FCM token, or null if unavailable.
  Future<String?> getToken();

  /// Stream that emits a new token whenever the FCM token is refreshed.
  Stream<String> get onTokenRefresh;

  /// Subscribes the device to the given FCM topic.
  Future<void> subscribeToTopic(String topic);

  /// Unsubscribes the device from the given FCM topic.
  Future<void> unsubscribeFromTopic(String topic);

  /// Stream of [RemoteMessage]s received while the app is in the foreground.
  Stream<RemoteMessage> get onForegroundMessage;

  /// Returns the [RemoteMessage] that launched the app from a terminated state,
  /// or null if the app was not opened via a notification.
  Future<RemoteMessage?> getInitialMessage();

  /// Stream of [RemoteMessage]s for notifications tapped while the app was
  /// in the background (but not terminated).
  Stream<RemoteMessage> get onMessageOpenedApp;
}

/// Concrete implementation wrapping [FirebaseMessaging].
class NotificationServiceImpl implements NotificationService {
  NotificationServiceImpl({FirebaseMessaging? messaging})
      : _messaging = messaging ?? FirebaseMessaging.instance;

  final FirebaseMessaging _messaging;

  @override
  Future<void> requestPermission() async {
    await _messaging.requestPermission();
  }

  @override
  Future<String?> getToken() => _messaging.getToken();

  @override
  Stream<String> get onTokenRefresh => _messaging.onTokenRefresh;

  @override
  Future<void> subscribeToTopic(String topic) =>
      _messaging.subscribeToTopic(topic);

  @override
  Future<void> unsubscribeFromTopic(String topic) =>
      _messaging.unsubscribeFromTopic(topic);

  @override
  Stream<RemoteMessage> get onForegroundMessage =>
      FirebaseMessaging.onMessage;

  @override
  Future<RemoteMessage?> getInitialMessage() =>
      _messaging.getInitialMessage();

  @override
  Stream<RemoteMessage> get onMessageOpenedApp =>
      FirebaseMessaging.onMessageOpenedApp;
}
