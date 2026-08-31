import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

enum SupervisorHealthTransportStatus {
  reachable,
  unauthorized,
  serverUnreachable,
  incompatibleServer,
}

final class SupervisorHealthProbeResult {
  const SupervisorHealthProbeResult({
    required this.status,
    required this.checkedAt,
    this.supervisorEnabled,
    this.model,
    this.diagnosticCode,
  });

  final SupervisorHealthTransportStatus status;
  final DateTime checkedAt;
  final bool? supervisorEnabled;
  final String? model;

  /// Sanitized machine-readable reason only. Never populate this with a raw
  /// response body, authorization header, exchange credential, or token.
  final String? diagnosticCode;

  bool get isReachable => status == SupervisorHealthTransportStatus.reachable;
}

final class SupervisorHealthClient {
  SupervisorHealthClient({
    http.Client? client,
    Duration timeout = const Duration(seconds: 5),
    DateTime Function()? now,
  }) : _client = client ?? http.Client(),
       _timeout = timeout,
       _now = now ?? DateTime.now;

  static const statusPath = '/api/v1/supervisor/status';
  static const controlTokenHeader = 'X-Quantara-Supervisor-Token';

  final http.Client _client;
  final Duration _timeout;
  final DateTime Function() _now;

  Future<SupervisorHealthProbeResult> check({
    required Uri serverOrigin,
    required String controlToken,
  }) async {
    final checkedAt = _now().toUtc();
    final uri = serverOrigin.replace(
      path: statusPath,
      query: null,
      fragment: null,
    );

    try {
      final response = await _client
          .get(uri, headers: {controlTokenHeader: controlToken})
          .timeout(_timeout);

      if (response.statusCode == 401 || response.statusCode == 403) {
        return SupervisorHealthProbeResult(
          status: SupervisorHealthTransportStatus.unauthorized,
          checkedAt: checkedAt,
          diagnosticCode: 'control_token_rejected',
        );
      }
      if (response.statusCode == 404) {
        return SupervisorHealthProbeResult(
          status: SupervisorHealthTransportStatus.incompatibleServer,
          checkedAt: checkedAt,
          diagnosticCode: 'status_endpoint_missing',
        );
      }
      if (response.statusCode != 200) {
        return SupervisorHealthProbeResult(
          status: SupervisorHealthTransportStatus.serverUnreachable,
          checkedAt: checkedAt,
          diagnosticCode: 'status_http_error',
        );
      }

      final decoded = jsonDecode(response.body);
      if (decoded is! Map<String, dynamic>) {
        return _incompatible(checkedAt, 'invalid_status_payload');
      }

      final enabled = decoded['enabled'];
      final model = decoded['model'];
      final readOnly = decoded['readOnly'];
      final liveTradingMutation = decoded['liveTradingMutation'];
      final credentialExposure = decoded['credentialExposure'];
      if (enabled is! bool ||
          model is! String ||
          model.trim().isEmpty ||
          readOnly != true ||
          liveTradingMutation != false ||
          credentialExposure != false) {
        return _incompatible(checkedAt, 'incompatible_status_contract');
      }

      return SupervisorHealthProbeResult(
        status: SupervisorHealthTransportStatus.reachable,
        checkedAt: checkedAt,
        supervisorEnabled: enabled,
        model: model.trim(),
        diagnosticCode: enabled ? null : 'supervisor_not_enabled',
      );
    } on TimeoutException {
      return SupervisorHealthProbeResult(
        status: SupervisorHealthTransportStatus.serverUnreachable,
        checkedAt: checkedAt,
        diagnosticCode: 'health_timeout',
      );
    } on FormatException {
      return _incompatible(checkedAt, 'invalid_status_json');
    } on http.ClientException {
      return SupervisorHealthProbeResult(
        status: SupervisorHealthTransportStatus.serverUnreachable,
        checkedAt: checkedAt,
        diagnosticCode: 'health_transport_error',
      );
    }
  }

  SupervisorHealthProbeResult _incompatible(DateTime at, String code) {
    return SupervisorHealthProbeResult(
      status: SupervisorHealthTransportStatus.incompatibleServer,
      checkedAt: at,
      diagnosticCode: code,
    );
  }
}