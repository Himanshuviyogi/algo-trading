import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:equatable/equatable.dart';

// ── BrokerType ────────────────────────────────────────────────────────────────

/// Supported brokers. Add a new value here when expanding to more brokers.
enum BrokerType {
  angelOne;

  /// Human-readable display name.
  String get displayName => switch (this) {
        BrokerType.angelOne => 'Angel One',
      };

  /// Firestore document ID for this broker.
  String get id => switch (this) {
        BrokerType.angelOne => 'angel_one',
      };

  /// Icon asset path for this broker.
  String get iconAsset => switch (this) {
        BrokerType.angelOne => 'assets/images/angel_one_logo.png',
      };

  static BrokerType? fromId(String id) => switch (id) {
        'angel_one' => BrokerType.angelOne,
        _ => null,
      };
}

// ── BrokerConnection ──────────────────────────────────────────────────────────

/// Represents a saved broker connection for a user.
///
/// Stored at: `users/{uid}/broker_connections/{broker_id}`
///
/// Sensitive fields (apiKey, totpSecret) are write-only — they are never
/// read back into this model. The model only tracks connection status and
/// the non-sensitive client ID so the UI can show who is connected.
class BrokerConnection extends Equatable {
  const BrokerConnection({
    required this.brokerId,
    required this.broker,
    required this.clientId,
    required this.isConnected,
    this.lastVerifiedAt,
    required this.createdAt,
  });

  /// Firestore document ID — same as [broker.id] (e.g. "angel_one").
  final String brokerId;

  final BrokerType broker;

  /// The broker's client/user ID (e.g. Angel One client code like "A123456").
  /// Not sensitive — safe to display in the UI.
  final String clientId;

  /// True when the price server has successfully verified the credentials.
  final bool isConnected;

  /// Timestamp of last successful credential verification by the price server.
  final DateTime? lastVerifiedAt;

  final DateTime createdAt;

  // ── Derived ────────────────────────────────────────────────────────────────

  String get displayName => broker.displayName;

  String get statusLabel => isConnected ? 'Connected' : 'Not connected';

  // ── fromFirestore ──────────────────────────────────────────────────────────

  factory BrokerConnection.fromFirestore(DocumentSnapshot doc) {
    final d = doc.data() as Map<String, dynamic>;
    final brokerType = BrokerType.fromId(d['broker_id'] as String? ?? '');
    return BrokerConnection(
      brokerId:       d['broker_id']  as String? ?? doc.id,
      broker:         brokerType      ?? BrokerType.angelOne,
      clientId:       d['client_id']  as String? ?? '',
      isConnected:    d['is_connected'] as bool? ?? false,
      lastVerifiedAt: d['last_verified_at'] is Timestamp
          ? (d['last_verified_at'] as Timestamp).toDate()
          : null,
      createdAt: d['created_at'] is Timestamp
          ? (d['created_at'] as Timestamp).toDate()
          : DateTime.now(),
    );
  }

  // ── toFirestore ────────────────────────────────────────────────────────────

  /// Safe fields only — never includes apiKey or totpSecret.
  Map<String, dynamic> toFirestore() => {
        'broker_id':        brokerId,
        'client_id':        clientId,
        'is_connected':     isConnected,
        'last_verified_at': lastVerifiedAt != null
            ? Timestamp.fromDate(lastVerifiedAt!)
            : null,
        'created_at': Timestamp.fromDate(createdAt),
      };

  // ── copyWith ───────────────────────────────────────────────────────────────

  BrokerConnection copyWith({
    bool? isConnected,
    DateTime? lastVerifiedAt,
  }) =>
      BrokerConnection(
        brokerId:       brokerId,
        broker:         broker,
        clientId:       clientId,
        isConnected:    isConnected     ?? this.isConnected,
        lastVerifiedAt: lastVerifiedAt  ?? this.lastVerifiedAt,
        createdAt:      createdAt,
      );

  @override
  List<Object?> get props => [
        brokerId,
        broker,
        clientId,
        isConnected,
        lastVerifiedAt,
        createdAt,
      ];
}

// ── BrokerConnectionInput ─────────────────────────────────────────────────────

/// Input DTO used when saving a new or updated broker connection.
/// Contains the sensitive fields (apiKey, totpSecret, pin) that are passed to
/// Firestore once and never read back into the Flutter app.
class BrokerConnectionInput {
  const BrokerConnectionInput({
    required this.broker,
    required this.clientId,
    required this.apiKey,
    required this.totpSecret,
    required this.pin,
  });

  final BrokerType broker;
  final String clientId;
  final String apiKey;

  /// TOTP secret key (base-32 encoded) used by the price server to generate
  /// time-based OTPs for Angel One programmatic login.
  final String totpSecret;

  /// Angel One 4-digit MPIN (login password).
  final String pin;

  Map<String, dynamic> toFirestore() => {
        'broker_id':    broker.id,
        'client_id':    clientId,
        'api_key':      apiKey,
        'totp_secret':  totpSecret,
        'pin':          pin,
        'is_connected': false, // set to true by price server after verification
        'created_at':   Timestamp.fromDate(DateTime.now()),
        'updated_at':   FieldValue.serverTimestamp(),
      };
}
