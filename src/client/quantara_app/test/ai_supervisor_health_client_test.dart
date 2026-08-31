import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:quantara_app/features/ai_supervisor/application/supervisor_health_client.dart';

void main() {
  const token = 'device-bound-control-token-123456789';
  final origin = Uri.parse('https://supervisor.example.com');
  final checkedAt = DateTime.utc(2026, 9, 1, 0, 30);

  test('health probe uses only the read-only status GET contract', () async {
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

  test('reachable server can truthfully report Supervisor disabled', () async {
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

  test('rejected control token is sanitized unauthorized state', () async {
    final client = MockClient(
      (_) async => http.Response('secret details', 401),
    );
    final probe = SupervisorHealthClient(client: client, now: () => checkedAt);

    final result = await probe.check(serverOrigin: origin, controlToken: token);

    expect(result.status, SupervisorHealthTransportStatus.unauthorized);
    expect(result.diagnosticCode, 'control_token_rejected');
    expect(result.toString(), isNot(contains('secret details')));
  });

  test(
    'mutation-capable status contract fails closed as incompatible',
    () async {
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
    },
  );

  test('malformed status response never retains raw body', () async {
    final client = MockClient((_) async => http.Response('token=$token', 200));
    final probe = SupervisorHealthClient(client: client, now: () => checkedAt);

    final result = await probe.check(serverOrigin: origin, controlToken: token);

    expect(result.status, SupervisorHealthTransportStatus.incompatibleServer);
    expect(result.diagnosticCode, 'invalid_status_json');
    expect(result.toString(), isNot(contains(token)));
  });

  test('timeout fails closed without blind retry', () async {
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

  test('missing status endpoint is incompatible server', () async {
    final client = MockClient((_) async => http.Response('', 404));
    final probe = SupervisorHealthClient(client: client, now: () => checkedAt);

    final result = await probe.check(serverOrigin: origin, controlToken: token);

    expect(result.status, SupervisorHealthTransportStatus.incompatibleServer);
    expect(result.diagnosticCode, 'status_endpoint_missing');
  });
}
