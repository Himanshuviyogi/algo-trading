part of 'auth_bloc.dart';

sealed class AuthEvent extends Equatable {
  const AuthEvent();
}

final class AuthPhoneSubmitted extends AuthEvent {
  const AuthPhoneSubmitted({required this.phoneNumber});

  final String phoneNumber;

  @override
  List<Object?> get props => [phoneNumber];
}

final class AuthOtpSubmitted extends AuthEvent {
  const AuthOtpSubmitted({
    required this.verificationId,
    required this.smsCode,
    required this.phoneNumber,
  });

  final String verificationId;
  final String smsCode;
  final String phoneNumber;

  @override
  List<Object?> get props => [verificationId, smsCode, phoneNumber];
}

final class AuthLogoutRequested extends AuthEvent {
  const AuthLogoutRequested();

  @override
  List<Object?> get props => [];
}

final class AuthResendOtpRequested extends AuthEvent {
  const AuthResendOtpRequested({required this.phoneNumber});
  final String phoneNumber;

  @override
  List<Object?> get props => [phoneNumber];
}

/// Internal event — fired by the Firebase auth state stream.
final class _AuthUserChanged extends AuthEvent {
  const _AuthUserChanged(this.user);

  final User? user;

  @override
  List<Object?> get props => [user?.uid];
}
