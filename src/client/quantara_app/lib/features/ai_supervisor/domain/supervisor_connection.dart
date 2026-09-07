enum SupervisorConnectionStatus {
  notConfigured,
  connecting,
  connected,
  expired,
  revoked,
  serverUnreachable,
  incompatibleServer,
}

enum SupervisorSetupFailure {
  missingServerUrl,
  invalidServerUrl,
  insecureServerUrl,
  missingControlToken,
  invalidControlToken,
}

final class SupervisorSetupValidation {
  const SupervisorSetupValidation._({
    required this.serverOrigin,
    required this.failures,
  });

  final Uri? serverOrigin;
  final Set<SupervisorSetupFailure> failures;

  bool get isValid => failures.isEmpty && serverOrigin != null;

  static SupervisorSetupValidation validate({
    required String serverUrl,
    required String controlToken,
    required bool releaseBuild,
  }) {
    final failures = <SupervisorSetupFailure>{};
    final rawUrl = serverUrl.trim();
    Uri? origin;

    if (rawUrl.isEmpty) {
      failures.add(SupervisorSetupFailure.missingServerUrl);
    } else {
      final parsed = Uri.tryParse(rawUrl);
      if (!_hasSafeUrlShape(parsed)) {
        failures.add(SupervisorSetupFailure.invalidServerUrl);
      } else if (!_isAllowedScheme(parsed!, releaseBuild: releaseBuild)) {
        failures.add(SupervisorSetupFailure.insecureServerUrl);
      } else {
        origin = Uri(
          scheme: parsed.scheme.toLowerCase(),
          host: parsed.host,
          port: parsed.hasPort ? parsed.port : null,
        );
      }
    }

    final token = controlToken.trim();
    if (token.isEmpty) {
      failures.add(SupervisorSetupFailure.missingControlToken);
    } else if (!_isSafeTokenShape(token)) {
      failures.add(SupervisorSetupFailure.invalidControlToken);
    }

    return SupervisorSetupValidation._(
      serverOrigin: origin,
      failures: Set.unmodifiable(failures),
    );
  }

  static bool _hasSafeUrlShape(Uri? uri) {
    if (uri == null || !uri.hasScheme || uri.host.isEmpty) {
      return false;
    }
    if (uri.userInfo.isNotEmpty || uri.query.isNotEmpty) {
      return false;
    }
    return uri.fragment.isEmpty;
  }

  static bool _isAllowedScheme(Uri uri, {required bool releaseBuild}) {
    final scheme = uri.scheme.toLowerCase();
    if (scheme == 'https') {
      return true;
    }
    if (releaseBuild || scheme != 'http') {
      return false;
    }

    final host = uri.host.toLowerCase();
    return host == 'localhost' || host == '127.0.0.1' || host == '::1';
  }

  static bool _isSafeTokenShape(String token) {
    if (token.length < 24 || token.length > 512) {
      return false;
    }

    for (final codeUnit in token.codeUnits) {
      if (codeUnit <= 0x20 || codeUnit == 0x7f) {
        return false;
      }
    }
    return true;
  }
}

final class SupervisorConnectionSnapshot {
  const SupervisorConnectionSnapshot({
    required this.status,
    this.serverOrigin,
    this.lastSuccessfulHealthCheckAt,
    this.diagnosticCode,
  });

  factory SupervisorConnectionSnapshot.notConfigured() {
    return const SupervisorConnectionSnapshot(
      status: SupervisorConnectionStatus.notConfigured,
    );
  }

  final SupervisorConnectionStatus status;
  final Uri? serverOrigin;
  final DateTime? lastSuccessfulHealthCheckAt;

  /// Sanitized machine-readable reason only. Never store raw response bodies,
  /// authorization headers, exchange credentials, or the control-token value.
  final String? diagnosticCode;

  bool get isHealthy => status == SupervisorConnectionStatus.connected;

  SupervisorConnectionSnapshot connectedAt(DateTime at) {
    if (serverOrigin == null) {
      throw StateError('A configured server origin is required.');
    }

    return SupervisorConnectionSnapshot(
      status: SupervisorConnectionStatus.connected,
      serverOrigin: serverOrigin,
      lastSuccessfulHealthCheckAt: at.toUtc(),
    );
  }
}
