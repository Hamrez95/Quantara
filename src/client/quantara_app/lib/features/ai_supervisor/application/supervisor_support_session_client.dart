import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:http/http.dart' as http;

import '../domain/supervisor_connection.dart';
import 'supervisor_secure_setup_store.dart';

final class SupervisorSupportSessionClient {
  factory SupervisorSupportSessionClient({
    required SupervisorSecureSetupStore setupStore,
    http.Client? client,
    Duration timeout = const Duration(seconds: 5),
    DateTime Function()? now,
    String Function()? sessionTokenFactory,
  }) {
    return SupervisorSupportSessionClient._(
      setupStore,
      client ?? http.Client(),
      timeout,
      now ?? DateTime.now,
      sessionTokenFactory ?? _createSessionToken,
    );
  }

  SupervisorSupportSessionClient._(
    this._setupStore,
    this._client,
    this._timeout,
    this._now,
    this._sessionTokenFactory,
  );

  static const registerPath = '/api/v1/supervisor/support-session/register';
  static const sessionPath = '/api/v1/supervisor/support-session';
  static const controlTokenHeader = 'X-Quantara-Control-Token';

  final SupervisorSecureSetupStore _setupStore;
  final http.Client _client;
  final Duration _timeout;
  final DateTime Function() _now;
  final String Function() _sessionTokenFactory;

  String? _activeSessionToken;

  Future<bool> start({
    required SupervisorConnectionSnapshot connection,
    required Duration duration,
    required bool releaseBuild,
  }) async {
    if (!connection.isHealthy ||
        duration <= Duration.zero ||
        duration > const Duration(hours: 1)) {
      return false;
    }

    final setup = await _setupStore.load(releaseBuild: releaseBuild);
    final controlToken = await _setupStore.readControlToken();
    if (setup == null || controlToken == null) return false;

    final sessionToken = _sessionTokenFactory();
    final observedAt = _now().toUtc();
    final expiresAt = observedAt.add(duration);
    final attributes = <String, String>{
      'connectionStatus': connection.status.name,
      if (connection.lastSuccessfulHealthCheckAt != null)
        'lastSuccessfulHealthCheckAt': connection.lastSuccessfulHealthCheckAt!
            .toUtc()
            .toIso8601String(),
      if (connection.diagnosticCode != null)
        'diagnosticCode': connection.diagnosticCode!,
    };
    final uri = setup.serverOrigin.replace(
      path: registerPath,
      query: null,
      fragment: null,
    );

    try {
      final response = await _client
          .post(
            uri,
            headers: {
              controlTokenHeader: controlToken,
              'Content-Type': 'application/json',
            },
            body: jsonEncode({
              'token': sessionToken,
              'expiresAtUtc': expiresAt.toIso8601String(),
              'scope': 'diagnostics.read',
              'evidence': [
                {
                  'evidenceId':
                      'client-connection-${observedAt.microsecondsSinceEpoch}',
                  'domain': 'app',
                  'kind': 'supervisor_connection',
                  'observedAtUtc': observedAt.toIso8601String(),
                  'summary': 'Sanitized Quantara Supervisor connection state',
                  'severity': 'info',
                  'component': 'quantara_app',
                  'version': null,
                  'correlationId': null,
                  'attributes': attributes,
                },
              ],
            }),
          )
          .timeout(_timeout);
      if (response.statusCode != 201) return false;

      final decoded = jsonDecode(response.body);
      if (decoded is! Map<String, dynamic> ||
          decoded['scope'] != 'diagnostics.read' ||
          decoded['expiresAtUtc'] is! String) {
        return false;
      }
      final remoteExpiry = DateTime.tryParse(decoded['expiresAtUtc'] as String);
      if (remoteExpiry == null || !remoteExpiry.isAfter(observedAt)) {
        return false;
      }

      _activeSessionToken = sessionToken;
      return true;
    } on TimeoutException {
      return false;
    } on FormatException {
      return false;
    } on http.ClientException {
      return false;
    }
  }

  Future<void> stop({required SupervisorConnectionSnapshot connection}) async {
    final token = _activeSessionToken;
    _activeSessionToken = null;
    final origin = connection.serverOrigin;
    if (token == null || origin == null) return;

    final uri = origin.replace(path: sessionPath, query: null, fragment: null);
    try {
      await _client
          .delete(uri, headers: {'Authorization': 'Bearer $token'})
          .timeout(_timeout);
    } on TimeoutException {
      // Local revocation is immediate. Remote sessions remain bounded by expiry.
    } on http.ClientException {
      // Do not resurrect a locally stopped session after transport failure.
    }
  }

  static String _createSessionToken() {
    final random = Random.secure();
    final bytes = List<int>.generate(32, (_) => random.nextInt(256));
    return base64UrlEncode(bytes).replaceAll('=', '');
  }
}
