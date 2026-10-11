import 'dart:async';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';

/// Singleton that watches network connectivity.
/// Emits `true` when online, `false` when offline.
///
/// Usage:
///   ConnectivityService.instance.isOnline        // current state
///   ConnectivityService.instance.onlineStream    // stream of bool
class ConnectivityService {
  ConnectivityService._();
  static final instance = ConnectivityService._();

  final _connectivity = Connectivity();
  final _controller = StreamController<bool>.broadcast();
  StreamSubscription<List<ConnectivityResult>>? _sub;

  bool _isOnline = true;
  bool get isOnline => _isOnline;

  Stream<bool> get onlineStream => _controller.stream;

  Future<void> init() async {
    // Check current state immediately
    final results = await _connectivity.checkConnectivity();
    _isOnline = _isConnected(results);

    // Watch for changes
    _sub = _connectivity.onConnectivityChanged.listen((results) {
      final online = _isConnected(results);
      if (online != _isOnline) {
        _isOnline = online;
        _controller.add(online);
        debugPrint('[Connectivity] ${online ? '✅ Online' : '❌ Offline'}');
      }
    });
  }

  bool _isConnected(List<ConnectivityResult> results) =>
      results.any((r) =>
          r == ConnectivityResult.mobile ||
          r == ConnectivityResult.wifi ||
          r == ConnectivityResult.ethernet);

  void dispose() {
    _sub?.cancel();
    _controller.close();
  }
}
