import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:quantara_app/features/ai_supervisor/application/supervisor_connection_health_coordinator.dart';
import 'package:quantara_app/features/ai_supervisor/application/supervisor_health_client.dart';
import 'package:quantara_app/features/ai_supervisor/application/supervisor_secure_setup_store.dart';
import 'package:quantara_app/features/ai_supervisor/domain/supervisor_connection.dart';

void main() {
  const token = 'device-bound-control-token-123456789';
  final origin = Uri.parse('https://supervisor.example.com');
  final firstCheck = DateTime.utc(2026, 9, 1, 1);
  final secondCheck = DateTime.utc(2026, 9, 1, 1, 5);

  test('reports not configured without probing the network', () async {
    var calls = 0;
    final coordinator = SupervisorConnectionHealthCoordinator(
      setupStore: SupervisorSecureSetupStore(secureStore: _MemorySecureStore()),
      healthClient: SupervisorHealthClient(
        client: MockClient((_) async {
          calls++;
          return http.Response('{}', 200);
        }),
      ),
      releaseBuild: true,
    );

    final snapshot = await coordinator.checkNow();

    expect(snapshot.status, SupervisorConnectionStatus.notConfigured);
    expect(snapshot.serverOrigin, isNull);
    expect(calls, 0);
  });

  test('reports connected and records the last successful check', () async {
    final store = await _configuredStore(origin: origin, token: token);
    final coordinator = SupervisorConnectionHealthCoordinator(
      setupStore: store,
      healthClient: SupervisorHealthClient(
        client: MockClient(
          (_) async => http.Response(
            '{"enabled":true,"model":"gpt-5","readOnly":true,'
            '"liveTradingMutation":false,"credentialExposure":false}',
            200,
          ),
        ),
        now: () => firstCheck,
      ),
      releaseBuild: true,
    );

    final snapshot = await coordinator.checkNow();

    expect(snapshot.status, SupervisorConnectionStatus.connected);
    expect(snapshot.serverOrigin, origin);
    expect(snapshot.lastSuccessfulHealthCheckAt, firstCheck);
    expect(snapshot.diagnosticCode, isNull);
  });

  test('maps expired tokens without exposing the token', () async {
    final store = await _configuredStore(origin: origin, token: token);
    final coordinator = SupervisorConnectionHealthCoordinator(
      setupStore: store,
      healthClient: SupervisorHealthClient(
        client: MockClient((_) async => http.Response('token=$token', 401)),
        now: () => firstCheck,
      ),
      releaseBuild: true,
    );

    final snapshot = await coordinator.checkNow();

    expect(snapshot.status, SupervisorConnectionStatus.expired);
    expect(snapshot.diagnosticCode, 'control_token_expired');
    expect(snapshot.toString(), isNot(contains(token)));
  });

  test('maps revoked tokens without exposing the token', () async {
    final store = await _configuredStore(origin: origin, token: token);
    final coordinator = SupervisorConnectionHealthCoordinator(
      setupStore: store,
      healthClient: SupervisorHealthClient(
        client: MockClient((_) async => http.Response('token=$token', 403)),
        now: () => firstCheck,
      ),
      releaseBuild: true,
    );

    final snapshot = await coordinator.checkNow();

    expect(snapshot.status, SupervisorConnectionStatus.revoked);
    expect(snapshot.diagnosticCode, 'control_token_revoked');
    expect(snapshot.toString(), isNot(contains(token)));
  });

  test('preserves last success when a later probe is unreachable', () async {
    var calls = 0;
    final store = await _configuredStore(origin: origin, token: token);
    final coordinator = SupervisorConnectionHealthCoordinator(
      setupStore: store,
      healthClient: SupervisorHealthClient(
        client: MockClient((_) async {
          calls++;
          if (calls == 1) {
            return http.Response(
              '{"enabled":true,"model":"gpt-5","readOnly":true,'
              '"liveTradingMutation":false,"credentialExposure":false}',
              200,
            );
          }
          throw http.ClientException('offline');
        }),
        now: () => calls == 0 ? firstCheck : secondCheck,
      ),
      releaseBuild: true,
    );

    final healthy = await coordinator.checkNow();
    final unreachable = await coordinator.checkNow();

    expect(healthy.status, SupervisorConnectionStatus.connected);
    expect(unreachable.status, SupervisorConnectionStatus.serverUnreachable);
    expect(unreachable.lastSuccessfulHealthCheckAt, firstCheck);
    expect(unreachable.diagnosticCode, 'health_transport_error');
  });

  test('fails closed for a disabled or incompatible Supervisor', () async {
    final store = await _configuredStore(origin: origin, token: token);
    final disabled = SupervisorConnectionHealthCoordinator(
      setupStore: store,
      healthClient: SupervisorHealthClient(
        client: MockClient(
          (_) async => http.Response(
            '{"enabled":false,"model":"gpt-5","readOnly":true,'
            '"liveTradingMutation":false,"credentialExposure":false}',
            200,
          ),
        ),
        now: () => firstCheck,
      ),
      releaseBuild: true,
    );

    final disabledSnapshot = await disabled.checkNow();

    expect(
      disabledSnapshot.status,
      SupervisorConnectionStatus.incompatibleServer,
    );
    expect(disabledSnapshot.diagnosticCode, 'supervisor_not_enabled');
  });
}

Future<SupervisorSecureSetupStore> _configuredStore({
  required Uri origin,
  required String token,
}) async {
  final store = SupervisorSecureSetupStore(secureStore: _MemorySecureStore());
  final result = await store.save(
    serverUrl: origin.toString(),
    controlToken: token,
    releaseBuild: true,
  );
  expect(result.isValid, isTrue);
  return store;
}

final class _MemorySecureStore implements SupervisorSecureKeyValueStore {
  final Map<String, String> _values = <String, String>{};

  @override
  Future<void> delete(String key) async {
    _values.remove(key);
  }

  @override
  Future<String?> read(String key) async => _values[key];

  @override
  Future<void> write(String key, String value) async {
    _values[key] = value;
  }
}
