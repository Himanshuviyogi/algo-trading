part of 'broker_cubit.dart';

// ── Base ──────────────────────────────────────────────────────────────────────

sealed class BrokerState extends Equatable {
  const BrokerState();

  /// The current connection list, if known. Used to preserve the list in
  /// transient states (saving, error) so the UI doesn't flicker to empty.
  List<BrokerConnection> get connections => const [];
}

// ── Idle ──────────────────────────────────────────────────────────────────────

/// Initial state before [BrokerCubit.load] is called (or on idle/logged-out instance).
final class BrokerInitial extends BrokerState {
  const BrokerInitial();
  @override
  List<Object?> get props => [];
}

// ── Loading ───────────────────────────────────────────────────────────────────

/// Waiting for the first Firestore snapshot.
final class BrokerLoading extends BrokerState {
  const BrokerLoading();
  @override
  List<Object?> get props => [];
}

// ── Loaded ────────────────────────────────────────────────────────────────────

/// Live snapshot from Firestore — emitted on every stream update.
final class BrokerLoaded extends BrokerState {
  const BrokerLoaded({required List<BrokerConnection> connections})
      : _connections = connections;

  final List<BrokerConnection> _connections;

  @override
  List<BrokerConnection> get connections => _connections;

  /// True if at least one broker connection is verified and active.
  bool get hasConnectedBroker => _connections.any((c) => c.isConnected);

  /// Returns the connection for [broker], or null if not configured.
  BrokerConnection? connectionFor(BrokerType broker) =>
      _connections.cast<BrokerConnection?>().firstWhere(
            (c) => c?.broker == broker,
            orElse: () => null,
          );

  @override
  List<Object?> get props => [_connections];
}

// ── Saving ────────────────────────────────────────────────────────────────────

/// A save/verify or re-verify operation is in progress.
final class BrokerSaving extends BrokerState {
  const BrokerSaving({List<BrokerConnection> connections = const []})
      : _connections = connections;

  final List<BrokerConnection> _connections;

  @override
  List<BrokerConnection> get connections => _connections;

  @override
  List<Object?> get props => [_connections];
}

// ── SaveSuccess ───────────────────────────────────────────────────────────────

/// Save + verify completed successfully. The Firestore stream will
/// immediately push a [BrokerLoaded] to reflect the change.
final class BrokerSaveSuccess extends BrokerState {
  const BrokerSaveSuccess();
  @override
  List<Object?> get props => [];
}

// ── SaveFailed ────────────────────────────────────────────────────────────────

/// Save or verification failed. [message] is shown in the UI.
final class BrokerSaveFailed extends BrokerState {
  const BrokerSaveFailed({
    required this.message,
    List<BrokerConnection> connections = const [],
  }) : _connections = connections;

  final String message;
  final List<BrokerConnection> _connections;

  @override
  List<BrokerConnection> get connections => _connections;

  @override
  List<Object?> get props => [message, _connections];
}

// ── Error ─────────────────────────────────────────────────────────────────────

/// Firestore stream emitted an error.
final class BrokerError extends BrokerState {
  const BrokerError(this.message);
  final String message;
  @override
  List<Object?> get props => [message];
}
