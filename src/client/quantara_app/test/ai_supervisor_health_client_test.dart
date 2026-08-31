import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:quantara_app/features/ai_supervisor/application/supervisor_health_client.dart';

void main() {
  const token = 'device-bound-control-token-123456789';
  final origin = Uri.parse('https://supervisor.example.com');
  final checkedAt = DateTime.utc(2026, 9, 1, 0, 30);

  test('probes only the read-only status contract', () async {
    late http.Request captured;
    final client = MockClient((request) async {
      captured = request;
      return http.Response(
        '{"enabled":true,"model":"gpt-5","readOnly":true,'
        '"liveTradingMutation":false,"credentialExposure":false}',
        200,
      );
    });
    final probe = SupervisorHealthClient(client: client, now: () => checkedAt);

    final result = await probe.check(serverOrigin: origin, controlToken: token);

    expect(captured.method, 'GET');
    expect(
      captured.url,
      Uri.parse('https://supervisor.example.com/api/v1/supervisor/status'),
    );
    expect(captured.headers[SupervisorHealthClient.controlTokenHeader], token);
    expect(captured.headers.containsKey('authorization'), isFalse);
    expect(result.status, SupervisorHealthTransportStatus.reachable);
    expect(result.supervisorEnabled, isTrue);
    expect(result.model, 'gpt-5');
    expect(result.checkedAt, checkedAt);
    expect(result.diagnosticCode, isNull);
    expect(result.toString(), isNot(contains(token)));
  });

  test('reports a disabled Supervisor truthfully', () async {
    final client = MockClient(
      (_) async => http.Response(
        '{"enabled":false,"model":"gpt-5","readOnly":true,'
        '"liveTradingMutation":false,"credentialExposure":false}',
        200,
      ),
    );
    final probe = SupervisorHealthClient(client: client, now: () => checkedAt);

    final result = await probe.check(serverOrigin: origin, controlToken: token);

    expect(result.status, SupervisorHealthTransportStatus.reachable);
    expect(result.supervisorEnabled, isFalse);
    expect(result.diagnosticCode, 'supervisor_not_enabled');
  });

  test('maps 401 to expired token', () async {
    final client = MockClient((_) async => http.Response('token=$token', 401));
    final probe = SupervisorHealthClient(client: client, now: () => checkedAt);

    final result = await probe.check(serverOrigin: origin, controlToken: token);

    expect(result.status, SupervisorHealthTransportStatus.tokenExpired);
    expect(result.diagnosticCode, 'control_token_expired');
    expect(result.toString(), isNot(contains(token)));
  });

  test('maps 403 to revoked token', () async {
    final client = MockClient((_) async => http.Response('token=$token', 403));
    final probe = SupervisorHealthClient(client: client, now: () => checkedAt);

    final result = await probe.check(serverOrigin: origin, controlToken: token);

    expect(result.status, SupervisorHealthTransportStatus.tokenRevoked);
    expect(result.diagnosticCode, 'control_token_revoked');
    expect(result.toString(), isNot(contains(token)));
  });

  test('rejects mutation-capable status contract', () async {
    final client = MockClient(
      (_) async => http.Response(
        '{"enabled":true,"model":"gpt-5","readOnly":true,'
        '"liveTradingMutation":true,"credentialExposure":false}',
        200,
      ),
    );
    final probe = SupervisorHealthClient(client: client, now: () => checkedAt);

    final result = await probe.check(serverOrigin: origin, controlToken: token);

    expect(result.status, SupervisorHealthTransportStatus.incompatibleServer);
    expect(result.diagnosticCode, 'incompatible_status_contract');
  });

  test('does not retain malformed status body', () async {
    final client = MockClient((_) async => http.Response('token=$token', 200));
    final probe = SupervisorHealthClient(client: client, now: () => checkedAt);

    final result = await probe.check(serverOrigin: origin, controlToken: token);

    expect(result.status, SupervisorHealthTransportStatus.incompatibleServer);
    expect(result.diagnosticCode, 'invalid_status_json');
    expect(result.toString(), isNot(contains(token)));
  });

  test('times out without blind retry', () async {
    var calls = 0;
    final client = MockClient((_) async {
      calls++;
      await Completer<void>().future;
      return http.Response('{}', 200);
    });
    final probe = SupervisorHealthClient(
      client: client,
      timeout: const Duration(milliseconds: 1),
      now: () => checkedAt,
    );

    final result = await probe.check(serverOrigin: origin, controlToken: token);

    expect(result.status, SupervisorHealthTransportStatus.serverUnreachable);
    expect(result.diagnosticCode, 'health_timeout');
    expect(calls, 1);
  });

  test('marks missing status endpoint incompatible', () async {
    final client = MockClient((_) async => http.Response('', 404));
    final probe = SupervisorHealthClient(client: client, now: () => checkedAt);

    final result = await probe.check(serverOrigin: origin, controlToken: token);

    expect(result.status, SupervisorHealthTransportStatus.incompatibleServer);
    expect(result.diagnosticCode, 'status_endpoint_missing');
  });
}
