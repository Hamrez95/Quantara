import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';

final class ReadOnlySupportSessionGrant {
  const ReadOnlySupportSessionGrant({
    required this.token,
    required this.expiresAt,
    required this.scope,
  });

  final String token;
  final DateTime expiresAt;
  final String scope;
}

final class ReadOnlySupportSessionSnapshot {
  const ReadOnlySupportSessionSnapshot({
    required this.createdAt,
    required this.expiresAt,
    required this.scope,
    required this.tokenFingerprint,
  });

  final DateTime createdAt;
  final DateTime expiresAt;
  final String scope;
  final String tokenFingerprint;

  Map<String, Object?> toDiagnosticJson(DateTime now) => {
    'active': now.toUtc().isBefore(expiresAt),
    'scope': scope,
    'createdAt': createdAt.toUtc().toIso8601String(),
    'expiresAt': expiresAt.toUtc().toIso8601String(),
    'tokenFingerprint': tokenFingerprint,
    'transportImplemented': true,
    'exchangeCredentialsExposed': false,
    'tradingPermission': false,
  };
}

final class ReadOnlySupportSessionManager {
  ReadOnlySupportSessionManager({DateTime Function()? clock, Random? random})
    : _clock = clock ?? (() => DateTime.now().toUtc()),
      _random = random ?? Random.secure();

  static const scope = 'diagnostics.read';
  final DateTime Function() _clock;
  final Random _random;
  ReadOnlySupportSessionSnapshot? _snapshot;

  ReadOnlySupportSessionSnapshot? get current {
    final snapshot = _snapshot;
    if (snapshot == null) return null;
    if (!_clock().toUtc().isBefore(snapshot.expiresAt)) {
      _snapshot = null;
      return null;
    }
    return snapshot;
  }

  bool get isActive => current != null;

  ReadOnlySupportSessionGrant enable({
    Duration ttl = const Duration(minutes: 45),
  }) {
    if (ttl < const Duration(minutes: 30) ||
        ttl > const Duration(minutes: 60)) {
      throw ArgumentError.value(
        ttl,
        'ttl',
        'must be between 30 and 60 minutes',
      );
    }
    final now = _clock().toUtc();
    final bytes = List<int>.generate(32, (_) => _random.nextInt(256));
    final token = base64UrlEncode(bytes).replaceAll('=', '');
    final fingerprint = sha256
        .convert(utf8.encode(token))
        .toString()
        .substring(0, 16);
    final expiresAt = now.add(ttl);
    _snapshot = ReadOnlySupportSessionSnapshot(
      createdAt: now,
      expiresAt: expiresAt,
      scope: scope,
      tokenFingerprint: fingerprint,
    );
    return ReadOnlySupportSessionGrant(
      token: token,
      expiresAt: expiresAt,
      scope: scope,
    );
  }

  void revoke() => _snapshot = null;

  static Map<String, Object?> architectureDescriptor() => const {
    'defaultEnabled': false,
    'scope': scope,
    'readOnly': true,
    'sanitizedDiagnosticsOnly': true,
    'revocable': true,
    'ttlMinutes': {'minimum': 30, 'default': 45, 'maximum': 60},
    'backendTransportImplemented': true,
    'mcpTransport': 'remote-http',
    'exchangeCredentialsAllowed': false,
    'tradingWritesAllowed': false,
  };
}
