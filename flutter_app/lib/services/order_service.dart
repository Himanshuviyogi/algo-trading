import 'dart:async';
import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../models/order.dart';

// ── Exceptions ────────────────────────────────────────────────────────────────

/// Thrown when the price server returns a non-2xx HTTP status.
class OrderServerException implements Exception {
  const OrderServerException(this.message, {this.statusCode});

  final String message;
  final int? statusCode;

  @override
  String toString() =>
      'OrderServerException(${statusCode != null ? '$statusCode ' : ''}$message)';
}

/// Thrown when the server accepted the request but the risk manager blocked
/// the order (e.g. daily loss limit breached, max positions reached).
class OrderBlockedException implements Exception {
  const OrderBlockedException(this.reason);

  final String reason;

  @override
  String toString() => 'OrderBlockedException: $reason';
}

/// Thrown when the user has no active Firebase session when placing an order.
class OrderAuthException implements Exception {
  const OrderAuthException(this.message);

  final String message;

  @override
  String toString() => 'OrderAuthException: $message';
}

// ── OrderService ──────────────────────────────────────────────────────────────

/// Singleton REST client for the price-server order endpoints.
///
/// Usage:
/// ```dart
/// final firestoreId = await OrderService.instance.placeOrder(
///   userId:    currentUser.uid,
///   signalId:  signal.id,
///   symbol:    'RELIANCE',
///   exchange:  'NSE',
///   action:    'BUY',
///   orderType: 'LIMIT',
///   quantity:  1,
///   price:     2950.0,
/// );
/// ```
class OrderService {
  OrderService._();
  static final instance = OrderService._();

  // ── Configuration ──────────────────────────────────────────────────────────
  static const String _serverUrl = String.fromEnvironment(
    'PRICE_SERVER_URL',
    defaultValue: 'http://31.172.87.141:3002',
  );

  static const Duration _timeout = Duration(seconds: 15);

  // ── Auth helper ────────────────────────────────────────────────────────────

  /// Fetches a fresh Firebase ID token. Force-refreshes to avoid sending an
  /// expired token after the app resumes from background — same pattern as
  /// LivePriceService.connect().
  Future<String> _getIdToken() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      throw const OrderAuthException('No authenticated user — cannot place order');
    }
    try {
      final token = await user.getIdToken(true); // force refresh
      if (token == null || token.isEmpty) {
        throw const OrderAuthException('Firebase returned an empty ID token');
      }
      return token;
    } on FirebaseAuthException catch (e) {
      throw OrderAuthException('Firebase token refresh failed: ${e.message}');
    }
  }

  /// Builds the standard headers for every request:
  /// - Content-Type / Accept
  /// - Bearer token from Firebase Auth
  Future<Map<String, String>> _buildHeaders() async {
    final token = await _getIdToken();
    return {
      'Content-Type':  'application/json',
      'Accept':        'application/json',
      'Authorization': 'Bearer $token',
    };
  }

  // ── Response handling ──────────────────────────────────────────────────────

  /// Parses the response body and throws typed exceptions for error cases.
  ///
  /// The server can respond in three ways:
  ///   1. HTTP 4xx / 5xx → [OrderServerException]
  ///   2. HTTP 200 with `{ "success": false, "allowed": false }` → [OrderBlockedException]
  ///   3. HTTP 200 with `{ "success": false }` → [OrderServerException] (broker error)
  ///   4. HTTP 200 with `{ "success": true }` → returns the parsed body
  Map<String, dynamic> _handleResponse(http.Response res, String endpoint) {
    debugPrint('[OrderService] $endpoint → ${res.statusCode}');

    if (res.statusCode >= 400) {
      String message = 'HTTP ${res.statusCode}';
      try {
        final body = jsonDecode(res.body) as Map<String, dynamic>;
        message = body['error'] as String? ?? message;
      } catch (_) {}
      throw OrderServerException(message, statusCode: res.statusCode);
    }

    late Map<String, dynamic> body;
    try {
      body = jsonDecode(res.body) as Map<String, dynamic>;
    } catch (_) {
      throw OrderServerException(
        'Invalid JSON response from server',
        statusCode: res.statusCode,
      );
    }

    final success = body['success'] as bool? ?? true;
    if (!success) {
      // Risk-manager blocked the order
      final allowed = body['allowed'] as bool? ?? true;
      if (!allowed) {
        final reason = body['reason'] as String? ?? 'Order blocked by risk check';
        throw OrderBlockedException(reason);
      }
      // Generic server-side failure (broker error, validation, etc.)
      final error = body['error'] as String? ?? 'Order request failed';
      throw OrderServerException(error, statusCode: res.statusCode);
    }

    return body;
  }

  // ── placeOrder ─────────────────────────────────────────────────────────────

  /// Place a new order via the price server.
  ///
  /// Returns the Firestore document ID of the created order so the caller
  /// can stream updates from `orders/{firestoreOrderId}`.
  ///
  /// Throws:
  /// - [OrderAuthException]    — no authenticated user
  /// - [OrderBlockedException] — risk check blocked the order
  /// - [OrderServerException]  — broker error or HTTP failure
  /// - [TimeoutException]      — server didn't respond within 15s
  Future<PlaceOrderResult> placeOrder({
    required String userId,
    required String signalId,
    required String symbol,
    required String exchange,
    required String action,
    required String orderType,
    required int quantity,
    required double price,
    double? triggerPrice,
  }) async {
    const endpoint = '/place-order';
    debugPrint(
      '[OrderService] placeOrder $action $quantity $symbol @ ₹$price '
      '(userId=$userId signalId=$signalId)',
    );

    final headers = await _buildHeaders();

    final payload = <String, dynamic>{
      'userId':       userId,
      'signalId':     signalId,
      'symbol':       symbol,
      'exchange':     exchange,
      'action':       action,
      'orderType':    orderType,
      'quantity':     quantity,
      'price':        price,
      'triggerPrice': triggerPrice ?? 0,
    };

    final res = await http
        .post(
          Uri.parse('$_serverUrl$endpoint'),
          headers: headers,
          body: jsonEncode(payload),
        )
        .timeout(_timeout);

    final body = _handleResponse(res, endpoint);

    final firestoreOrderId = body['firestoreOrderId'] as String? ?? '';
    final angelOrderId     = body['angelOrderId']     as String?;

    debugPrint(
      '[OrderService] ✅ placeOrder success — '
      'firestoreId=$firestoreOrderId angelId=$angelOrderId',
    );

    return PlaceOrderResult(
      firestoreOrderId: firestoreOrderId,
      angelOrderId:     angelOrderId,
    );
  }

  // ── cancelOrder ────────────────────────────────────────────────────────────

  /// Cancel an open order.
  ///
  /// Throws [OrderServerException] if the server rejects the cancellation,
  /// or [OrderAuthException] if there is no active session.
  Future<void> cancelOrder({
    required String angelOrderId,
    required String userId,
  }) async {
    const endpoint = '/cancel-order';
    debugPrint('[OrderService] cancelOrder angelOrderId=$angelOrderId userId=$userId');

    final headers = await _buildHeaders();

    final payload = <String, dynamic>{
      'angelOrderId': angelOrderId,
      'userId':       userId,
    };

    final res = await http
        .post(
          Uri.parse('$_serverUrl$endpoint'),
          headers: headers,
          body: jsonEncode(payload),
        )
        .timeout(_timeout);

    _handleResponse(res, endpoint);
    debugPrint('[OrderService] ✅ cancelOrder success — angelOrderId=$angelOrderId');
  }

  // ── modifyOrder ────────────────────────────────────────────────────────────

  /// Modify the price and/or quantity of an open order.
  ///
  /// [orderType] must be provided because Angel One requires it even when
  /// only changing the price (the existing order type must be re-stated).
  Future<void> modifyOrder({
    required String angelOrderId,
    required String orderType,
    required int quantity,
    required double price,
    double? triggerPrice,
  }) async {
    const endpoint = '/modify-order';
    debugPrint(
      '[OrderService] modifyOrder angelOrderId=$angelOrderId '
      'qty=$quantity price=₹$price',
    );

    final headers = await _buildHeaders();

    final payload = <String, dynamic>{
      'angelOrderId': angelOrderId,
      'orderType':    orderType,
      'quantity':     quantity,
      'price':        price,
      'triggerPrice': triggerPrice ?? 0,
    };

    final res = await http
        .post(
          Uri.parse('$_serverUrl$endpoint'),
          headers: headers,
          body: jsonEncode(payload),
        )
        .timeout(_timeout);

    _handleResponse(res, endpoint);
    debugPrint('[OrderService] ✅ modifyOrder success — angelOrderId=$angelOrderId');
  }

  // ── fetchOrderBook ─────────────────────────────────────────────────────────

  /// Sync Angel One → Firestore for [userId] and return the latest order list.
  ///
  /// The server syncs before responding, so the returned list is always
  /// up-to-date. Use this for a manual pull-to-refresh; real-time updates
  /// should come from a Firestore stream in the repository layer.
  Future<List<AlgoOrder>> fetchOrderBook(String userId) async {
    final endpoint = '/order-book/$userId';
    debugPrint('[OrderService] fetchOrderBook userId=$userId');

    final headers = await _buildHeaders();

    final res = await http
        .get(
          Uri.parse('$_serverUrl$endpoint'),
          headers: headers,
        )
        .timeout(_timeout);

    final body = _handleResponse(res, endpoint);

    final rawOrders = body['orders'] as List<dynamic>? ?? [];
    final orders = rawOrders
        .whereType<Map<String, dynamic>>()
        .map((o) {
          // The REST response uses the same field names as Firestore,
          // but we don't have a DocumentSnapshot here — parse directly.
          return AlgoOrder(
            id:              o['id']              as String? ?? '',
            signalId:        o['signal_id']        as String? ?? '',
            userId:          o['user_id']          as String? ?? '',
            symbol:          o['symbol']           as String? ?? '',
            exchange:        o['exchange']         as String? ?? '',
            action:          o['action']           as String? ?? '',
            orderType:       o['order_type']       as String? ?? '',
            quantity:        (o['quantity']        as num?)?.toInt()    ?? 0,
            price:           (o['price']           as num?)?.toDouble() ?? 0.0,
            triggerPrice:    (o['trigger_price']   as num?)?.toDouble(),
            angelOrderId:    o['angel_order_id']   as String?,
            status:          _parseOrderStatus(o['status'] as String?),
            rejectionReason: o['rejection_reason'] as String?,
            placedAt:        _parseTimestamp(o['placed_at']),
            updatedAt:       _parseTimestamp(o['updated_at']),
          );
        })
        .toList();

    debugPrint('[OrderService] fetchOrderBook: ${orders.length} order(s)');
    return orders;
  }
}

// ── Return type ───────────────────────────────────────────────────────────────

/// Result of a successful [OrderService.placeOrder] call.
class PlaceOrderResult {
  const PlaceOrderResult({
    required this.firestoreOrderId,
    this.angelOrderId,
  });

  /// Firestore `orders` document ID — use to stream real-time status updates.
  final String firestoreOrderId;

  /// Angel One order ID — use for cancel/modify calls.
  /// May be null briefly if the server write races with the Angel One response.
  final String? angelOrderId;

  @override
  String toString() =>
      'PlaceOrderResult(firestore=$firestoreOrderId angel=$angelOrderId)';
}

// ── Private helpers ───────────────────────────────────────────────────────────

OrderStatus _parseOrderStatus(String? raw) => switch (raw?.toLowerCase()) {
      'pending'   => OrderStatus.pending,
      'open'      => OrderStatus.open,
      'complete'  => OrderStatus.complete,
      'rejected'  => OrderStatus.rejected,
      'cancelled' => OrderStatus.cancelled,
      _           => OrderStatus.unknown,
    };

/// Parses a timestamp field from the REST response.
/// The server serialises Firestore Timestamps as `{ "_seconds": n, "_nanoseconds": n }`
/// when returned through JSON; plain ISO strings are also handled as a fallback.
DateTime _parseTimestamp(dynamic raw) {
  if (raw == null) return DateTime.now();
  if (raw is Map) {
    final seconds = (raw['_seconds'] as num?)?.toInt() ?? 0;
    return DateTime.fromMillisecondsSinceEpoch(seconds * 1000);
  }
  if (raw is String) {
    return DateTime.tryParse(raw) ?? DateTime.now();
  }
  return DateTime.now();
}
