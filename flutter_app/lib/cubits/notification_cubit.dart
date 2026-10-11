import 'dart:async';

import 'package:equatable/equatable.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../repositories/user_repository.dart';
import '../services/notification_service.dart';

part 'notification_state.dart';

class NotificationCubit extends Cubit<NotificationState> {
  NotificationCubit({
    required NotificationService notificationService,
    required UserRepository userRepository,
    required String userId,
  })  : _notificationService = notificationService,
        _userRepository = userRepository,
        _userId = userId,
        super(const NotificationInitial());

  final NotificationService _notificationService;
  final UserRepository _userRepository;
  String _userId; // mutable — updated on login

  StreamSubscription<String>? _tokenRefreshSub;
  StreamSubscription<RemoteMessage>? _foregroundMessageSub;

  Future<void> initialize() async {
    try {
      await _notificationService.requestPermission();

      final token = await _notificationService.getToken();

      // Writes to `algo_fcm_token` (not `fcm_token`) so this app does not
      // overwrite the token used by the live recom app on the same Firebase project.
      if (token != null && _userId.isNotEmpty) {
        await _userRepository.updateFcmToken(_userId, token);
        emit(const NotificationPermissionGranted());
      } else if (token != null) {
        emit(const NotificationPermissionGranted());
      } else {
        emit(const NotificationPermissionDenied());
      }

      if (_userId.isNotEmpty) {
        await _tokenRefreshSub?.cancel();
        _tokenRefreshSub = _notificationService.onTokenRefresh.listen(
          (newToken) => _userRepository.updateFcmToken(_userId, newToken),
        );
      }

      // Cancel any existing subscription before re-subscribing
      await _foregroundMessageSub?.cancel();
      _foregroundMessageSub = _notificationService.onForegroundMessage.listen(
        (message) {
          if (isClosed) return;
          print('🔔 [NotificationCubit] onForegroundMessage fired');
          print('🔔 [NotificationCubit] title: ${message.notification?.title}');
          print('🔔 [NotificationCubit] body: ${message.notification?.body}');
          print('🔔 [NotificationCubit] data: ${message.data}');
          print('🔔 [NotificationCubit] emitting NotificationForegroundMessage...');
          emit(NotificationForegroundMessage(message));
          print('🔔 [NotificationCubit] emit done, current state: ${state.runtimeType}');
        },
      );
      print('✅ [NotificationCubit] foreground subscription active (userId: ${_userId.isEmpty ? "empty" : _userId})');
    } catch (e) {
      print('❌ [NotificationCubit] initialize error: $e');
      emit(NotificationError(e.toString()));
    }
  }

  /// Call this after login to register the FCM token for the authenticated user.
  /// Does NOT recreate the foreground message subscription.
  Future<void> updateUserId(String userId) async {
    if (_userId == userId) return;
    _userId = userId;

    await _tokenRefreshSub?.cancel();
    _tokenRefreshSub = null;

    try {
      final token = await _notificationService.getToken();
      if (token != null && userId.isNotEmpty) {
        await _userRepository.updateFcmToken(userId, token);
      }
      if (userId.isNotEmpty) {
        _tokenRefreshSub = _notificationService.onTokenRefresh.listen(
          (newToken) => _userRepository.updateFcmToken(_userId, newToken),
        );
      }
    } catch (_) {}
  }

  @override
  Future<void> close() async {
    await _tokenRefreshSub?.cancel();
    await _foregroundMessageSub?.cancel();
    return super.close();
  }
}
