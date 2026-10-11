import 'dart:async';

import 'package:equatable/equatable.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../repositories/user_repository.dart';
import '../services/auth_service.dart';

part 'auth_event.dart';
part 'auth_state.dart';

/// Regex for E.164 phone number format.
final _e164Regex = RegExp(r'^\+[1-9]\d{1,14}$');

class AuthBloc extends Bloc<AuthEvent, AuthState> {
  AuthBloc({
    required AuthService authService,
    required UserRepository userRepository,
  })  : _authService = authService,
        _userRepository = userRepository,
        super(AuthLoading()) {
    on<AuthPhoneSubmitted>(_onPhoneSubmitted);
    on<AuthOtpSubmitted>(_onOtpSubmitted);
    on<AuthResendOtpRequested>(_onResendOtp);
    on<AuthLogoutRequested>(_onLogoutRequested);
    on<_AuthUserChanged>(_onUserChanged);

    // Listen to Firebase's persisted auth state so the session survives
    // app restarts without requiring the user to log in again.
    _authStateSubscription = _authService.authStateChanges.listen(
      (user) => add(_AuthUserChanged(user)),
    );
  }

  final AuthService _authService;
  final UserRepository _userRepository;
  late final StreamSubscription<User?> _authStateSubscription;

  Future<void> _onUserChanged(
    _AuthUserChanged event,
    Emitter<AuthState> emit,
  ) async {
    final user = event.user;
    if (user != null) {
      if (state is AuthInitial || state is AuthFailure ||
          state is AuthLoading || state is AuthOtpFailure) {
        // Ensure the Firestore document exists before any subsequent writes
        // (e.g. FCM token updates) can fire. Uses merge:true so it's
        // idempotent and won't overwrite fields set during OTP sign-up.
        await _userRepository.createUserProfile(
          user.uid,
          user.phoneNumber ?? '',
        );
        emit(AuthAuthenticated(
          uid: user.uid,
          phoneNumber: user.phoneNumber ?? '',
        ));
      }
    } else {
      emit(AuthInitial());
    }
  }

  Future<void> _onPhoneSubmitted(
    AuthPhoneSubmitted event,
    Emitter<AuthState> emit,
  ) async {
    if (!_e164Regex.hasMatch(event.phoneNumber)) {
      emit(const AuthFailure('Invalid phone number format'));
      return;
    }

    emit(AuthPhoneSubmitting());
    try {
      final verificationId =
          await _authService.verifyPhoneNumber(event.phoneNumber);
      emit(AuthOtpSent(
          verificationId: verificationId, phoneNumber: event.phoneNumber));
    } catch (e) {
      emit(AuthFailure(e.toString()));
    }
  }

  Future<void> _onOtpSubmitted(
    AuthOtpSubmitted event,
    Emitter<AuthState> emit,
  ) async {
    emit(AuthOtpVerifying());
    try {
      final credential = await _authService.verifySmsCode(
        event.verificationId,
        event.smsCode,
      );
      final uid = credential.user!.uid;
      final phoneNumber = credential.user!.phoneNumber ?? '';
      await _userRepository.createUserProfile(uid, phoneNumber);
      emit(AuthAuthenticated(uid: uid, phoneNumber: phoneNumber));
    } catch (e) {
      // Emit OtpFailure so the screen keeps verificationId + phoneNumber.
      emit(AuthOtpFailure(
        message: e.toString(),
        verificationId: event.verificationId,
        phoneNumber: event.phoneNumber,
      ));
    }
  }

  Future<void> _onResendOtp(
    AuthResendOtpRequested event,
    Emitter<AuthState> emit,
  ) async {
    emit(AuthPhoneSubmitting());
    try {
      final verificationId =
          await _authService.verifyPhoneNumber(event.phoneNumber);
      emit(AuthOtpSent(
          verificationId: verificationId, phoneNumber: event.phoneNumber));
    } catch (e) {
      emit(AuthFailure(e.toString()));
    }
  }

  Future<void> _onLogoutRequested(
    AuthLogoutRequested event,
    Emitter<AuthState> emit,
  ) async {
    final currentState = state;
    if (currentState is AuthAuthenticated) {
      await _userRepository.clearFcmToken(currentState.uid);
    }
    await _authService.logout();
    emit(AuthInitial());
  }

  @override
  Future<void> close() {
    _authStateSubscription.cancel();
    return super.close();
  }
}
