import 'dart:async';
import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../models/broker_connection.dart';

// ── Exceptions ────────────────────────────────────────────────────────────────

class BrokerVerificationException implements Exception {
  const BrokerVerificationException(this.message);
  final String message;
  @override
  String toString() => 'BrokerVerificationException: $message';
}

// ── Abstract interface ────────────────────────────────────────────────────────

abstract class BrokerRepository {
  /// Real-time stream of all broker connections for [uid].
  Stream<List<BrokerConnection>> watchConnections(String uid);

  /// Writes broker credentials to Firestore and then calls the price server
  /// to verify them. Throws [BrokerVerificationException] on verify failure.
  Future<void> saveAndVerify(String uid, BrokerConnectionInput input);

  /// Removes a broker connection document from Firestore.
  Future<void> deleteConnection(String uid, String brokerId);

  /// Re-runs the price server verify call for an existing connection and
  /// updates [is_connected] + [last_verified_at] in Firestore.
  Future<void> reverify(String uid, String brokerId);
}

// ── Implementation ────────────────────────────────────────────────────────────

class BrokerRepositoryImpl implements BrokerRepository {
  BrokerRepositoryImpl({
    required FirebaseFirestore firestore,
    String? priceServerUrl,
  })  : _firestore = firestore,
        _priceServerUrl = priceServerUrl ??
            const String.fromEnvironment(
              'PRICE_SERVER_URL',
              defaultValue: 'http://31.172.87.141:3002',
            );

  final FirebaseFirestore _firestore;
  final String _priceServerUrl;

  static const Duration _timeout = Duration(seconds: 20);

  // ── Firestore path ─────────────────────────────────────────────────────────

  CollectionReference<Map<String, dynamic>> _connectionsRef(String uid) =>
      _firestore
          .collection('users')
          .doc(uid)
          .collection('broker_connections');

  // ── watchConnections ───────────────────────────────────────────────────────

  @override
  Stream<List<BrokerConnection>> watchConnections(String uid) {
    return _connectionsRef(uid).snapshots().map(
          (snap) => snap.docs
              .map(BrokerConnection.fromFirestore)
              .toList(),
        );
  }

  // ── saveAndVerify ──────────────────────────────────────────────────────────

  @override
  Future<void> saveAndVerify(String uid, BrokerConnectionInput input) async {
    final docRef = _connectionsRef(uid).doc(input.broker.id);

    // 1. Write credentials to Firestore (is_connected = false until verified).
    await docRef.set(input.toFirestore(), SetOptions(merge: true));
    debugPrint('[BrokerRepository] Credentials saved for ${input.broker.id}');

    // 2. Ask the price server to verify the credentials.
    try {
      await _callVerify(uid: uid, brokerId: input.broker.id);
    } catch (e) {
      // Mark as not connected so the UI reflects the failure.
      await docRef.update({'is_connected': false});
      rethrow;
    }

    // 3. Mark connected + record verification timestamp.
    await docRef.update({
      'is_connected':     true,
      'last_verified_at': FieldValue.serverTimestamp(),
    });
    debugPrint('[BrokerRepository] Verified ${input.broker.id} for user $uid');
  }

  // ── deleteConnection ───────────────────────────────────────────────────────

  @override
  Future<void> deleteConnection(String uid, String brokerId) async {
    await _connectionsRef(uid).doc(brokerId).delete();
    debugPrint('[BrokerRepository] Deleted $brokerId for user $uid');
  }

  // ── reverify ───────────────────────────────────────────────────────────────

  @override
  Future<void> reverify(String uid, String brokerId) async {
    final docRef = _connectionsRef(uid).doc(brokerId);

    try {
      await _callVerify(uid: uid, brokerId: brokerId);
    } catch (e) {
      await docRef.update({'is_connected': false});
      rethrow;
    }

    await docRef.update({
      'is_connected':     true,
      'last_verified_at': FieldValue.serverTimestamp(),
    });
    debugPrint('[BrokerRepository] Re-verified $brokerId for user $uid');
  }

  // ── _callVerify ────────────────────────────────────────────────────────────

  /// Calls `POST /broker/verify` on the price server.
  ///
  /// The server reads the credentials from Firestore itself (using Admin SDK),
  /// so we only pass uid + brokerId — no credentials travel over this call.
  Future<void> _callVerify({
    required String uid,
    required String brokerId,
  }) async {
    final token = await _getIdToken();

    final res = await http
        .post(
          Uri.parse('$_priceServerUrl/broker/verify'),
          headers: {
            'Content-Type':  'application/json',
            'Accept':        'application/json',
            'Authorization': 'Bearer $token',
          },
          body: jsonEncode({'uid': uid, 'brokerId': brokerId}),
        )
        .timeout(_timeout);

    debugPrint('[BrokerRepository] /broker/verify → ${res.statusCode}');

    if (res.statusCode >= 400) {
      String message = 'HTTP ${res.statusCode}';
      try {
        final body = jsonDecode(res.body) as Map<String, dynamic>;
        message = body['error'] as String? ?? message;
      } catch (_) {}
      throw BrokerVerificationException(message);
    }

    late Map<String, dynamic> body;
    try {
      body = jsonDecode(res.body) as Map<String, dynamic>;
    } catch (_) {
      throw const BrokerVerificationException('Invalid response from server');
    }

    final success = body['success'] as bool? ?? false;
    if (!success) {
      final error = body['error'] as String? ?? 'Verification failed';
      throw BrokerVerificationException(error);
    }
  }

  // ── _getIdToken ────────────────────────────────────────────────────────────

  Future<String> _getIdToken() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      throw const BrokerVerificationException('No authenticated user');
    }
    final token = await user.getIdToken(true);
    if (token == null || token.isEmpty) {
      throw const BrokerVerificationException('Empty Firebase ID token');
    }
    return token;
  }
}
