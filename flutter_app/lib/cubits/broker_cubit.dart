import 'dart:async';

import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../models/broker_connection.dart';
import '../repositories/broker_repository.dart';

part 'broker_state.dart';

/// Cubit that manages the user's broker connections.
///
/// Lifecycle:
///   - Created in [_SessionManager] when the user logs in (with a real uid).
///   - Replaced with an idle instance (uid = '') on logout.
///   - The [watchConnections] Firestore stream drives the loaded state.
///
/// Usage:
/// ```dart
/// context.read<BrokerCubit>().save(uid, input);
/// context.read<BrokerCubit>().delete(uid, brokerId);
/// ```
class BrokerCubit extends Cubit<BrokerState> {
  BrokerCubit({
    required BrokerRepository brokerRepository,
    required String userId,
  })  : _repository = brokerRepository,
        _userId = userId,
        super(const BrokerInitial());

  final BrokerRepository _repository;
  final String _userId;

  StreamSubscription<List<BrokerConnection>>? _sub;

  // ── load ───────────────────────────────────────────────────────────────────

  /// Start streaming broker connections from Firestore.
  /// Safe to call multiple times — cancels any existing subscription first.
  void load() {
    if (_userId.isEmpty) return; // idle instance — nothing to stream

    emit(const BrokerLoading());
    _sub?.cancel();

    _sub = _repository.watchConnections(_userId).listen(
      (connections) {
        if (isClosed) return;
        emit(BrokerLoaded(connections: connections));
      },
      onError: (Object error) {
        if (isClosed) return;
        emit(BrokerError(error.toString()));
      },
    );
  }

  // ── save ───────────────────────────────────────────────────────────────────

  /// Save new credentials and verify with the price server.
  ///
  /// Emits [BrokerSaving] during the operation, then either:
  /// - [BrokerSaveSuccess] on success (stream will auto-update loaded state)
  /// - [BrokerSaveFailed] on error (includes the error message)
  Future<void> save(BrokerConnectionInput input) async {
    if (_userId.isEmpty) return;

    // Preserve the current connection list so the UI doesn't flicker.
    final previous = state is BrokerLoaded
        ? (state as BrokerLoaded).connections
        : <BrokerConnection>[];

    emit(BrokerSaving(connections: previous));

    try {
      await _repository.saveAndVerify(_userId, input);
      if (isClosed) return;
      emit(const BrokerSaveSuccess());
      // The Firestore stream will fire and push a new BrokerLoaded immediately.
    } on BrokerVerificationException catch (e) {
      if (isClosed) return;
      emit(BrokerSaveFailed(
        message: e.message,
        connections: previous,
      ));
    } catch (e) {
      if (isClosed) return;
      emit(BrokerSaveFailed(
        message: e.toString(),
        connections: previous,
      ));
    }
  }

  // ── delete ─────────────────────────────────────────────────────────────────

  /// Remove a broker connection. The Firestore stream update drives the UI.
  Future<void> delete(String brokerId) async {
    if (_userId.isEmpty) return;
    try {
      await _repository.deleteConnection(_userId, brokerId);
    } catch (_) {
      // Silently ignore — the stream will stay consistent.
    }
  }

  // ── reverify ───────────────────────────────────────────────────────────────

  /// Re-run the price server verification for an existing connection.
  Future<void> reverify(String brokerId) async {
    if (_userId.isEmpty) return;

    final previous = state is BrokerLoaded
        ? (state as BrokerLoaded).connections
        : <BrokerConnection>[];

    emit(BrokerSaving(connections: previous));

    try {
      await _repository.reverify(_userId, brokerId);
      if (isClosed) return;
      emit(const BrokerSaveSuccess());
    } on BrokerVerificationException catch (e) {
      if (isClosed) return;
      emit(BrokerSaveFailed(message: e.message, connections: previous));
    } catch (e) {
      if (isClosed) return;
      emit(BrokerSaveFailed(message: e.toString(), connections: previous));
    }
  }

  // ── hasConnectedBroker ─────────────────────────────────────────────────────

  /// Convenience getter — true if at least one broker is currently connected.
  bool get hasConnectedBroker {
    if (state is BrokerLoaded) {
      return (state as BrokerLoaded).connections.any((c) => c.isConnected);
    }
    return false;
  }

  // ── close ──────────────────────────────────────────────────────────────────

  @override
  Future<void> close() {
    _sub?.cancel();
    return super.close();
  }
}
