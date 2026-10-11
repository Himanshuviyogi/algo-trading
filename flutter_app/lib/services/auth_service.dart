import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';

/// Abstract interface for Firebase Phone Auth operations.
abstract class AuthService {
  /// Step 1: send OTP to the given phone number (E.164 format).
  /// Returns the [verificationId] needed for step 2.
  Future<String> verifyPhoneNumber(String phoneNumber);

  /// Step 2: confirm the OTP; returns a signed-in [UserCredential].
  Future<UserCredential> verifySmsCode(String verificationId, String smsCode);

  /// Signs the current user out.
  Future<void> logout();

  /// Stream of auth state changes (null when signed out).
  Stream<User?> get authStateChanges;
}

/// Concrete implementation wrapping [FirebaseAuth].
class AuthServiceImpl implements AuthService {
  AuthServiceImpl({FirebaseAuth? firebaseAuth})
      : _auth = firebaseAuth ?? FirebaseAuth.instance;

  final FirebaseAuth _auth;

  @override
  Stream<User?> get authStateChanges => _auth.authStateChanges();

  @override
  Future<String> verifyPhoneNumber(String phoneNumber) async {
    final completer = Completer<String>();

    await _auth.verifyPhoneNumber(
      phoneNumber: phoneNumber,
      verificationCompleted: (_) {
        // Auto-retrieval or instant verification — not used in manual OTP flow.
      },
      verificationFailed: (FirebaseAuthException e) {
        if (!completer.isCompleted) {
          completer.completeError(e);
        }
      },
      codeSent: (String verificationId, int? resendToken) {
        if (!completer.isCompleted) {
          completer.complete(verificationId);
        }
      },
      codeAutoRetrievalTimeout: (String verificationId) {
        // Timeout reached; complete with the verificationId if not already done.
        if (!completer.isCompleted) {
          completer.complete(verificationId);
        }
      },
    );

    return completer.future;
  }

  @override
  Future<UserCredential> verifySmsCode(
    String verificationId,
    String smsCode,
  ) async {
    final credential = PhoneAuthProvider.credential(
      verificationId: verificationId,
      smsCode: smsCode,
    );
    return _auth.signInWithCredential(credential);
  }

  @override
  Future<void> logout() => _auth.signOut();
}
