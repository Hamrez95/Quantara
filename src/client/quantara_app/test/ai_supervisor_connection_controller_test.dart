import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:quantara_app/features/ai_supervisor/application/supervisor_connection_controller.dart';
import 'package:quantara_app/features/ai_supervisor/application/supervisor_connection_health_coordinator.dart';
import 'package:quantara_app/features/ai_supervisor/application/supervisor_health_client.dart';
import 'package:quantara_app/features/ai_supervisor/application/supervisor_secure_setup_store.dart';
import 'package:quantara_app/features/ai_supervisor/domain/supervisor_connection.dart';

void main() {
  const token = 'device-bound-control-token-123456789';
  const serverUrl = 'https://supervisor.example.com';

  test(
    'initialize stays not configured and does not probe without setup',
    () async {
      var calls = 0;
      final harness = _Harness((_) async {
        calls++;
        return _healthy();
      });

      await harness.controller.initialize();

      expect(
        harness.controller.snapshot.status,
        SupervisorConnectionStatus.notConfigured,
      );
      expect(calls, 0);
    },
  );

  test(
    'save emits connecting before connected and never exposes token',
    () async {
      final response = Completer<http.Response>();
      final harness = _Harness((_) => response.future);
      final statuses = <SupervisorConnectionStatus>[];
      harness.controller.addListener(
        () => statuses.add(harness.controller.snapshot.status),
      );

      final future = harness.controller.saveAndCheck(
        serverUrl: serverUrl,
        controlToken: token,
      );
      await Future<void>.delayed(Duration.zero);

      expect(
        harness.controller.snapshot.status,
        SupervisorConnectionStatus.connecting,
      );
      expect(harness.controller.snapshot.serverOrigin.toString(), serverUrl);
      expect(harness.controller.snapshot.toString(), isNot(contains(token)));

      response.complete(_healthy());
      final validation = await future;

      expect(validation.isValid, isTrue);
      expect(
        statuses,
        containsAllInOrder(<SupervisorConnectionStatus>[
          SupervisorConnectionStatus.connecting,
          SupervisorConnectionStatus.connected,
        ]),
      );
    },
  );

  test('invalid setup remains fail closed and never probes', () async {
    var calls = 0;
    final harness = _Harness((_) async {
      calls++;
      return _healthy();
    });

    final validation = await harness.controller.saveAndCheck(
      serverUrl: 'http://remote.example.com',
      controlToken: token,
    );

    expect(validation.isValid, isFalse);
    expect(
      validation.failures,
      contains(SupervisorSetupFailure.insecureServerUrl),
    );
    expect(
      harness.controller.snapshot.status,
      SupervisorConnectionStatus.notConfigured,
    );
    expect(calls, 0);
  });

  test('clear wins over an in-flight health response', () async {
    final response = Completer<http.Response>();
    final harness = _Harness((_) => response.future);

    final saveFuture = harness.controller.saveAndCheck(
      serverUrl: serverUrl,
      controlToken: token,
    );
    await Future<void>.delayed(Duration.zero);
    expect(
      harness.controller.snapshot.status,
      SupervisorConnectionStatus.connecting,
    );

    await harness.controller.clear();
    response.complete(_healthy());
    await saveFuture;

    expect(
      harness.controller.snapshot.status,
      SupervisorConnectionStatus.notConfigured,
    );
    expect(await harness.store.readControlToken(), isNull);
  });
}

http.Response _healthy() => http.Response(
  '{"enabled":true,"model":"gpt-5","readOnly":true,'
  '"liveTradingMutation":false,"credentialExposure":false}',
  200,
);

final class _Harness {
  _Harness(Future<http.Response> Function(http.Request) handler)
    : store = SupervisorSecureSetupStore(secureStore: _MemorySecureStore()) {
    controller = SupervisorConnectionController(
      setupStore: store,
      healthCoordinator: SupervisorConnectionHealthCoordinator(
        setupStore: store,
        healthClient: SupervisorHealthClient(client: MockClient(handler)),
        releaseBuild: true,
      ),
      releaseBuild: true,
    );
  }

  final SupervisorSecureSetupStore store;
  late final SupervisorConnectionController controller;
}

final class _MemorySecureStore implements SupervisorSecureKeyValueStore {
  final Map<String, String> _values = <String, String>{};

  @override
  Future<void> delete(String key) async => _values.remove(key);

  @override
  Future<String?> read(String key) async => _values[key];

  @override
  Future<void> write(String key, String value) async {
    _values[key] = value;
  }
}
