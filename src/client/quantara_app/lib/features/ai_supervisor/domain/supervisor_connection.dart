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
      final hasSafeShape = parsed != null &&
          parsed.hasScheme &&
          parsed.host.isNotEmpty &&
          parsed.userInfo.isEmpty &&
          parsed.query.isEmpty &&
          parsed.fragment.isEmpty;

      if (!hasSafeShape) {
        failures.add(SupervisorSetupFailure.invalidServerUrl);
      } else if (releaseBuild && parsed.scheme.toLowerCase() != 'https') {
        failures.add(SupervisorSetupFailure.insecureServerUrl);
      } else if (!releaseBuild && !_isAllowedDevelopmentScheme(parsed)) {
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

  static bool _isAllowedDevelopmentScheme(Uri uri) {
    final scheme = uri.scheme.toLowerCase();
    if (scheme == 'https') {
      return true;
    }
    if (scheme != 'http') {
      return false;
    }

    final host = uri.host.toLowerCase();
    return host == 'localhost' ||
        host == '127.0.0.1' ||
        host == '::1';
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

  const SupervisorConnectionSnapshot.notConfigured()
      : status = SupervisorConnectionStatus.notConfigured,
        serverOrigin = null,
        lastSuccessfulHealthCheckAt = null,
        diagnosticCode = null;

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
