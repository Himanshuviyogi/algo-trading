import 'dart:async';
import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:socket_io_client/socket_io_client.dart' as sio;

/// A single price tick received from the price server.
class PriceTick {
  final String symbol;
  final double ltp;
  final double open;
  final double high;
  final double low;
  final double close;
  final double change;
  final double changePercent;
  final DateTime ts;

  const PriceTick({
    required this.symbol,
    required this.ltp,
    required this.open,
    required this.high,
    required this.low,
    required this.close,
    required this.change,
    required this.changePercent,
    required this.ts,
  });

  factory PriceTick.fromMap(Map<String, dynamic> m) => PriceTick(
        symbol:        m['symbol'] as String? ?? '',
        ltp:           (m['ltp']           as num?)?.toDouble() ?? 0,
        open:          (m['open']          as num?)?.toDouble() ?? 0,
        high:          (m['high']          as num?)?.toDouble() ?? 0,
        low:           (m['low']           as num?)?.toDouble() ?? 0,
        close:         (m['close']         as num?)?.toDouble() ?? 0,
        change:        (m['change']        as num?)?.toDouble() ?? 0,
        changePercent: (m['changePercent'] as num?)?.toDouble() ?? 0,
        ts:            DateTime.fromMillisecondsSinceEpoch(
                         (m['ts'] as num?)?.toInt() ?? 0),
      );

  bool get isPositive => change >= 0;

  @override
  String toString() =>
      'PriceTick($symbol ltp=$ltp change=$change changePercent=$changePercent%)';
}

/// Singleton service that manages the Socket.IO connection to the price server.
///
/// Usage:
/// ```dart
/// // Subscribe to a symbol
/// LivePriceService.instance.subscribe(['RELIANCE', 'TCS']);
///
/// // Listen to price updates
/// LivePriceService.instance.priceStream.listen((tick) {
///   print('${tick.symbol}: ₹${tick.ltp}');
/// });
///
/// // Get last known price
/// final tick = LivePriceService.instance.getPrice('RELIANCE');
/// ```
class LivePriceService {
  LivePriceService._();
  static final instance = LivePriceService._();

  // ── Debug flag ─────────────────────────────────────────────────────────────
  // Set to true to write socket lifecycle events to Firestore `socket_logs`.
  // Flip to false for production — no Firestore writes, only debugPrint.
  static const bool enableFirestoreLogs = false;

  // ── Configuration ──────────────────────────────────────────────────────────
  static const String _serverUrl = String.fromEnvironment(
    'PRICE_SERVER_URL',
    defaultValue: 'http://31.172.87.141:3002',
  );

  // ── State ──────────────────────────────────────────────────────────────────
  sio.Socket? _socket;
  bool _isConnected = false;
  bool _isMarketClosed = false;
  final Set<String> _subscribedSymbols = {};
  Timer? _heartbeatTimer;

  final Map<String, PriceTick> _priceCache = {};
  final _priceController = StreamController<PriceTick>.broadcast();
  final _marketStatusController = StreamController<bool>.broadcast();

  Stream<PriceTick> get priceStream => _priceController.stream;
  Stream<bool> get marketStatusStream => _marketStatusController.stream;
  bool get isConnected => _isConnected;
  bool get isMarketClosed => _isMarketClosed;

  // ── Firestore logger (public for lifecycle events from main.dart) ─────────
  void log(String event, {String? detail, Map<String, dynamic>? extra}) =>
      _log(event, detail: detail, extra: extra);

  void _log(String event, {String? detail, Map<String, dynamic>? extra}) {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    debugPrint('[LivePrice:LOG] $event${detail != null ? ': $detail' : ''} | uid=${uid ?? 'null'}');

    // Skip Firestore write when logging is disabled
    if (!enableFirestoreLogs) return;

    if (uid == null) return;

    final entry = <String, dynamic>{
      'event':  event,
      'ts_ms':  DateTime.now().millisecondsSinceEpoch,
      if (detail != null) 'detail': detail,
      if (extra != null) ...extra,
    };

    // Fire-and-forget — don't await, don't block the socket path
    FirebaseFirestore.instance
        .collection('socket_logs')
        .doc(uid)
        .set({
          'uid':      uid,
          'updated':  FieldValue.serverTimestamp(), // root-level only — valid here
          'logs':     FieldValue.arrayUnion([entry]), // no FieldValue inside array
        }, SetOptions(merge: true))
        .then((_) => debugPrint('[LivePrice:LOG] ✅ wrote $event to Firestore'))
        .catchError((e) => debugPrint('[LivePrice:LOG] ❌ Firestore write failed: $e'));
  }

  // Trim the log to the last 50 entries (called after connect to avoid unbounded growth)
  void _trimLog() {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    FirebaseFirestore.instance
        .collection('socket_logs')
        .doc(uid)
        .get()
        .then((snap) {
          if (!snap.exists) return;
          final logs = List<dynamic>.from(snap.data()?['logs'] ?? []);
          if (logs.length > 50) {
            final trimmed = logs.sublist(logs.length - 50);
            FirebaseFirestore.instance
                .collection('socket_logs')
                .doc(uid)
                .update({'logs': trimmed})
                .catchError((_) {});
          }
        })
        .catchError((_) {});
  }

  // ── Connect ────────────────────────────────────────────────────────────────

  /// Connect to the price server. Safe to call multiple times.
  /// Tears down the old socket cleanly before creating a new one.
  Future<void> connect() async {
    _log('connect_called', detail: 'symbols=${_subscribedSymbols.length}');

    // Tear down old socket cleanly
    if (_socket != null) {
      _log('teardown_old_socket');
      _socket!.off('connect');
      _socket!.off('disconnect');
      _socket!.off('connect_error');
      _socket!.off('snapshot');
      _socket!.off('price');
      _socket!.off('prices_batch');
      _socket!.off('broker_status');
      _socket!.disconnect();
      _socket!.dispose();
      _socket = null;
      _isConnected = false;
    }

    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;

    await Future.delayed(const Duration(milliseconds: 100));

    String? idToken;
    try {
      // Force refresh=true to get a fresh token (avoids expired token after background)
      idToken = await FirebaseAuth.instance.currentUser?.getIdToken(true);
      _log('token_refreshed', detail: idToken != null ? 'ok (${idToken.length} chars)' : 'null - no user');
    } catch (e) {
      _log('token_error', detail: e.toString());
      // Still proceed — server allows connection without token in some configs
    }

    _log('creating_socket', detail: _serverUrl);

    _socket = sio.io(
      _serverUrl,
      sio.OptionBuilder()
          .setTransports(['websocket'])
          .setAuth({'token': idToken ?? ''})
          .disableAutoConnect()
          .enableReconnection()
          .setReconnectionAttempts(999999)
          .setReconnectionDelay(2000)
          .setReconnectionDelayMax(10000)
          .build(),
    );

    _socket!.onConnect((_) {
      _isConnected = true;
      _log('connected', extra: {'symbols': _subscribedSymbols.toList()});
      for (final symbol in _subscribedSymbols) {
        _socket!.emit('subscribe', symbol);
      }
      for (final symbol in _subscribedSymbols) {
        final cached = _priceCache[symbol];
        if (cached != null) _priceController.add(cached);
      }
      _startHeartbeat();
      _trimLog();
    });

    _socket!.onDisconnect((reason) {
      _isConnected = false;
      _log('disconnected', detail: reason?.toString() ?? 'unknown');
    });

    _socket!.onConnectError((err) {
      _log('connect_error', detail: err?.toString() ?? 'unknown');
      // Retry after 3s on auth errors — token may have been stale
      Future.delayed(const Duration(seconds: 3), () {
        if (!_isConnected && _socket != null) {
          _log('connect_error_retry');
          connect();
        }
      });
    });

    _socket!.on('reconnect_attempt', (attempt) {
      _log('reconnect_attempt', detail: 'attempt=$attempt');
    });

    _socket!.on('reconnect', (attempt) {
      _log('reconnected', detail: 'after $attempt attempts');
    });

    _socket!.on('snapshot', (data) {
      if (data is Map) {
        _log('snapshot', detail: '${data.keys.length} symbols');
        data.forEach((symbol, priceData) {
          if (priceData is Map) {
            final tick = PriceTick.fromMap({
              'symbol': symbol,
              ...Map<String, dynamic>.from(priceData),
            });
            _priceCache[symbol] = tick;
            _priceController.add(tick);
          }
        });
      }
    });

    _socket!.on('price', (data) {
      if (data is Map) {
        final tick = PriceTick.fromMap(Map<String, dynamic>.from(data));
        if (tick.symbol.isNotEmpty) {
          _priceCache[tick.symbol] = tick;
          _priceController.add(tick);
        }
      }
    });

    _socket!.on('prices_batch', (data) {
      if (data is Map) {
        for (final symbol in List<String>.from(_subscribedSymbols)) {
          final priceData = data[symbol];
          if (priceData is Map) {
            final tick = PriceTick.fromMap({
              'symbol': symbol,
              ...Map<String, dynamic>.from(priceData),
            });
            _priceCache[symbol] = tick;
            _priceController.add(tick);
          }
        }
      }
    });

    _socket!.on('broker_status', (data) {
      if (data is Map) {
        final status = data['status'] as String? ?? '';
        _log('broker_status', detail: status);
        if (status == 'market_closed') {
          _isMarketClosed = true;
          _marketStatusController.add(true);
        } else if (status == 'connected') {
          _isMarketClosed = false;
          _marketStatusController.add(false);
        }
      }
    });

    _log('socket_connect_start');
    _socket!.connect();
  }

  // ── Subscribe / Unsubscribe ────────────────────────────────────────────────

  /// Subscribe to live prices for the given symbols.
  /// Safe to call multiple times — duplicates are ignored.
  void subscribe(List<String> symbols) {
    final newSymbols = symbols.where((s) => !_subscribedSymbols.contains(s)).toList();
    if (newSymbols.isEmpty) return;
    _subscribedSymbols.addAll(newSymbols);
    debugPrint('[LivePrice] 📋 subscribe: $newSymbols | connected=$_isConnected');

    // Immediately emit cached prices for these symbols so widgets update
    // without waiting for the next tick from the server
    for (final symbol in newSymbols) {
      final cached = _priceCache[symbol];
      if (cached != null) {
        debugPrint('[LivePrice] 💾 Cache hit for $symbol: ₹${cached.ltp}');
        _priceController.add(cached);
      } else {
        debugPrint('[LivePrice] ⚠️ No cache for $symbol — waiting for tick');
      }
    }

    if (_isConnected) {
      // Emit each symbol individually — socket_io_client sends list items
      // as separate arguments, not as a JSON array, so we emit one at a time
      for (final symbol in newSymbols) {
        _socket?.emit('subscribe', symbol);
      }
    }
  }

  /// Unsubscribe from live prices for the given symbols.
  void unsubscribe(List<String> symbols) {
    _subscribedSymbols.removeAll(symbols);
    if (_isConnected) {
      for (final symbol in symbols) {
        _socket?.emit('unsubscribe', symbol);
      }
    }
  }

  // ── Price access ───────────────────────────────────────────────────────────

  /// Get the last known price for a symbol. Returns null if not yet received.
  PriceTick? getPrice(String symbol) => _priceCache[symbol];

  /// Get all cached prices.
  Map<String, PriceTick> getAllPrices() => Map.unmodifiable(_priceCache);

  /// Fetch a live price for [symbol] directly from the price server REST endpoint.
  /// The server stores most equities with an "-EQ" suffix (e.g. "VEDL-EQ"),
  /// while indices and a few large caps use the plain symbol (e.g. "NIFTY").
  /// This method tries the plain symbol first, then auto-retries with "-EQ".
  /// Falls back to the Socket.IO cache if the server is unreachable.
  Future<PriceTick?> fetchPrice(String symbol) async {
    // Return cached value immediately if fresh (within 10 seconds)
    final cached = _priceCache[symbol];
    if (cached != null &&
        DateTime.now().difference(cached.ts).inSeconds < 10) {
      return cached;
    }

    // Candidates to try: plain symbol first, then with -EQ suffix
    final candidates = [symbol];
    if (!symbol.endsWith('-EQ')) candidates.add('$symbol-EQ');

    try {
      for (final candidate in candidates) {
        final uri = Uri.parse('$_serverUrl/price/${Uri.encodeComponent(candidate)}');
        final res = await http.get(uri).timeout(const Duration(seconds: 5));
        if (res.statusCode != 200) continue;
        final data = jsonDecode(res.body) as Map<String, dynamic>;
        if (data['ltp'] == null) continue; // not in feed — try next candidate

        final tick = PriceTick(
          symbol:        symbol, // always store under the canonical name
          ltp:           (data['ltp']           as num).toDouble(),
          open:          (data['open']           as num? ?? 0).toDouble(),
          high:          (data['high']           as num? ?? 0).toDouble(),
          low:           (data['low']            as num? ?? 0).toDouble(),
          close:         (data['close']          as num? ?? 0).toDouble(),
          change:        (data['change']         as num? ?? 0).toDouble(),
          changePercent: (data['changePercent']  as num? ?? 0).toDouble(),
          ts:            DateTime.now(),
        );
        _priceCache[symbol] = tick; // update local cache
        debugPrint('[LivePrice] fetchPrice $symbol via $candidate: ₹${tick.ltp}');
        return tick;
      }
      return cached; // all candidates returned null — return stale cache
    } catch (_) {
      return cached; // network error — return whatever we have
    }
  }

  // ── Disconnect ─────────────────────────────────────────────────────────────

  void disconnect() {
    _log('disconnect_called');
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;
    _socket?.disconnect();
    _socket?.dispose();
    _socket = null;
    _isConnected = false;
    _isMarketClosed = false;
  }

  /// Full disconnect on logout — clears all state including subscriptions.
  void fullDisconnect() {
    disconnect();
    _subscribedSymbols.clear();
    _priceCache.clear();
  }

  void _startHeartbeat() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (_socket == null) return;
      // If socket thinks it's connected but hasn't received a tick in a while,
      // the connection may be stale (Android killed the TCP connection silently).
      // Force a reconnect to be safe.
      if (!_isConnected) {
        debugPrint('[LivePrice] Heartbeat: not connected — reconnecting...');
        connect();
      } else {
        // Send a ping to verify the connection is actually alive.
        // If the server doesn't respond, onDisconnect will fire and
        // the socket.io auto-reconnect will kick in.
        _socket?.emit('ping_check', {'ts': DateTime.now().millisecondsSinceEpoch});
      }
    });
  }

  void dispose() {
    disconnect();
    _priceController.close();
    _marketStatusController.close();
  }
}
