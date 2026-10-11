part of 'auth_bloc.dart';

sealed class AuthState extends Equatable {
  const AuthState();
}

/// Initial state before Firebase auth state is known.
final class AuthInitial extends AuthState {
  @override
  List<Object?> get props => [];
}

/// Waiting for Firebase to resolve the persisted auth state on startup.
final class AuthLoading extends AuthState {
  @override
  List<Object?> get props => [];
}

final class AuthPhoneSubmitting extends AuthState {
  @override
  List<Object?> get props => [];
}

final class AuthOtpSent extends AuthState {
  const AuthOtpSent({required this.verificationId, required this.phoneNumber});

  final String verificationId;
  final String phoneNumber;

  @override
  List<Object?> get props => [verificationId, phoneNumber];
}

final class AuthOtpVerifying extends AuthState {
  @override
  List<Object?> get props => [];
}

final class AuthAuthenticated extends AuthState {
  const AuthAuthenticated({required this.uid, required this.phoneNumber});

  final String uid;
  final String phoneNumber;

  @override
  List<Object?> get props => [uid, phoneNumber];
}

final class AuthFailure extends AuthState {
  const AuthFailure(this.message);

  final String message;

  @override
  List<Object?> get props => [message];
}

/// OTP-specific failure — keeps verificationId and phoneNumber so the
/// screen can retry without going back to phone entry.
final class AuthOtpFailure extends AuthState {
  const AuthOtpFailure({
    required this.message,
    required this.verificationId,
    required this.phoneNumber,
  });

  final String message;
  final String verificationId;
  final String phoneNumber;

  @override
  List<Object?> get props => [message, verificationId, phoneNumber];
}
