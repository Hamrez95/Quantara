enum SupervisorSessionStatus {
  inactive,
  active,
  expired,
  stopped,
}

/// The only diagnostic fields allowed to cross the Supervisor gateway.
///
/// Keep this list deliberately small and additive changes security-reviewed.
const Set<String> supervisorDiagnosticAllowList = <String>{
  'connectionStatus',
  'lastSuccessfulHealthCheckAt',
  'diagnosticCode',
  'appVersion',
  'platform',
};

/// Defense-in-depth names which must never cross the Supervisor gateway even
/// if a caller accidentally includes them in an evidence map.
const Set<String> supervisorDiagnosticDenyList = <String>{
  'apiKey',
  'apiSecret',
  'secret',
  'signature',
  'authorization',
  'controlToken',
  'exchangeCredentials',
  'order',
  'cancelOrder',
  'stopLoss',
  'takeProfit',
  'leverage',
  'riskLimit',
  'transferFunds',
  'autoTrade',
};

Map<String, Object?> sanitizeSupervisorEvidence(
  Map<String, Object?> evidence,
) {
  final sanitized = <String, Object?>{};
  for (final entry in evidence.entries) {
    if (!supervisorDiagnosticAllowList.contains(entry.key) ||
        supervisorDiagnosticDenyList.contains(entry.key)) {
      continue;
    }

    final value = entry.value;
    if (value == null || value is String || value is num || value is bool) {
      sanitized[entry.key] = value;
    }
  }
  return Map<String, Object?>.unmodifiable(sanitized);
}

final class SupervisorReadOnlySession {
  factory SupervisorReadOnlySession({
    required DateTime startedAt,
    required Duration duration,
  }) {
    if (duration <= Duration.zero || duration > const Duration(hours: 1)) {
      throw ArgumentError.value(
        duration,
        'duration',
        'Supervisor sessions must be greater than zero and at most one hour.',
      );
    }

    return SupervisorReadOnlySession._(startedAt.toUtc(), duration);
  }

  SupervisorReadOnlySession._(this._startedAt, this._duration);

  final DateTime _startedAt;
  final Duration _duration;
  bool _stopped = false;

  DateTime get startedAt => _startedAt;
  DateTime get expiresAt => _startedAt.add(_duration);

  SupervisorSessionStatus statusAt(DateTime now) {
    if (_stopped) return SupervisorSessionStatus.stopped;
    if (!now.toUtc().isBefore(expiresAt)) {
      return SupervisorSessionStatus.expired;
    }
    return SupervisorSessionStatus.active;
  }

  Duration remainingAt(DateTime now) {
    if (statusAt(now) != SupervisorSessionStatus.active) {
      return Duration.zero;
    }
    return expiresAt.difference(now.toUtc());
  }

  bool get isStopped => _stopped;

  void stop() {
    _stopped = true;
  }

  Map<String, Object?> evidenceForGateway({
    required DateTime now,
    required Map<String, Object?> evidence,
  }) {
    if (statusAt(now) != SupervisorSessionStatus.active) {
      throw StateError('Supervisor session is not active.');
    }
    return sanitizeSupervisorEvidence(evidence);
  }
}
