part of 'notification_cubit.dart';

sealed class NotificationState extends Equatable {
  const NotificationState();

  @override
  List<Object?> get props => [];
}

class NotificationInitial extends NotificationState {
  const NotificationInitial();
}

class NotificationPermissionGranted extends NotificationState {
  const NotificationPermissionGranted();
}

class NotificationPermissionDenied extends NotificationState {
  const NotificationPermissionDenied();
}

class NotificationForegroundMessage extends NotificationState {
  const NotificationForegroundMessage(this.message);

  final RemoteMessage message;

  @override
  List<Object?> get props => [message];
}

class NotificationError extends NotificationState {
  const NotificationError(this.message);

  final String message;

  @override
  List<Object?> get props => [message];
}
