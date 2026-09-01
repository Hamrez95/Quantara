import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:quantara_app/features/ai_supervisor/application/supervisor_connection_controller.dart';
import 'package:quantara_app/features/ai_supervisor/application/supervisor_connection_health_coordinator.dart';
import 'package:quantara_app/features/ai_supervisor/application/supervisor_health_client.dart';
import 'package:quantara_app/features/ai_supervisor/application/supervisor_secure_setup_store.dart';
import 'package:quantara_app/features/ai_supervisor/presentation/supervisor_connection_panel.dart';

void main() {
  testWidgets('Supervisor setup stays truthful and never renders token', (
    tester,
  ) async {
    final secureStore = _MemorySecureStore();
    final setupStore = SupervisorSecureSetupStore(secureStore: secureStore);
    final healthClient = SupervisorHealthClient(
      client: MockClient((request) async {
        expect(
          request.url.toString(),
          'https://supervisor.example.com/api/v1/supervisor/status',
        );
        expect(
          request.headers[SupervisorHealthClient.controlTokenHeader],
          'test-control-token-1234567890',
        );
        return http.Response(
          '{"enabled":true,"model":"gpt","readOnly":true,'
          '"liveTradingMutation":false,"credentialExposure":false}',
          200,
        );
      }),
    );
    final controller = SupervisorConnectionController(
      setupStore: setupStore,
      healthCoordinator: SupervisorConnectionHealthCoordinator(
        setupStore: setupStore,
        healthClient: healthClient,
        releaseBuild: true,
      ),
      releaseBuild: true,
    );
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('en'),
        home: Scaffold(
          body: SingleChildScrollView(
            child: SupervisorConnectionPanel(controller: controller),
          ),
        ),
      ),
    );

    expect(find.text('Not configured'), findsOneWidget);
    expect(
      find.text('ChatGPT analysis is not configured on this device.'),
      findsOneWidget,
    );

    await tester.tap(find.text('Configure'));
    await tester.pumpAndSettle();

    final tokenField = tester.widget<TextField>(
      find.byKey(const ValueKey('supervisor-control-token-field')),
    );
    expect(tokenField.obscureText, isTrue);

    await tester.enterText(
      find.byKey(const ValueKey('supervisor-server-url-field')),
      'https://supervisor.example.com',
    );
    await tester.enterText(
      find.byKey(const ValueKey('supervisor-control-token-field')),
      'test-control-token-1234567890',
    );
    await tester.tap(find.text('Save & test'));
    await tester.pumpAndSettle();

    expect(find.text('Connected'), findsOneWidget);
    expect(find.text('supervisor.example.com'), findsOneWidget);
    expect(find.text('test-control-token-1234567890'), findsNothing);
  });

  testWidgets('release setup rejects HTTP before any health request', (
    tester,
  ) async {
    var requests = 0;
    final setupStore = SupervisorSecureSetupStore(
      secureStore: _MemorySecureStore(),
    );
    final controller = SupervisorConnectionController(
      setupStore: setupStore,
      healthCoordinator: SupervisorConnectionHealthCoordinator(
        setupStore: setupStore,
        healthClient: SupervisorHealthClient(
          client: MockClient((request) async {
            requests++;
            return http.Response('', 500);
          }),
        ),
        releaseBuild: true,
      ),
      releaseBuild: true,
    );
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('en'),
        home: Scaffold(
          body: SingleChildScrollView(
            child: SupervisorConnectionPanel(controller: controller),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Configure'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('supervisor-server-url-field')),
      'http://supervisor.example.com',
    );
    await tester.enterText(
      find.byKey(const ValueKey('supervisor-control-token-field')),
      'test-control-token-1234567890',
    );
    await tester.tap(find.text('Save & test'));
    await tester.pump();

    expect(find.text('Release builds require HTTPS.'), findsOneWidget);
    expect(requests, 0);
    expect(find.text('Not configured'), findsOneWidget);
  });

  testWidgets('read-only session requires health and supports explicit stop', (
    tester,
  ) async {
    final setupStore = SupervisorSecureSetupStore(
      secureStore: _MemorySecureStore(),
    );
    final controller = SupervisorConnectionController(
      setupStore: setupStore,
      healthCoordinator: SupervisorConnectionHealthCoordinator(
        setupStore: setupStore,
        healthClient: SupervisorHealthClient(
          client: MockClient(
            (request) async => http.Response(
              '{"enabled":true,"model":"gpt","readOnly":true,'
              '"liveTradingMutation":false,"credentialExposure":false}',
              200,
            ),
          ),
        ),
        releaseBuild: true,
      ),
      releaseBuild: true,
    );
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('en'),
        home: Scaffold(
          body: SingleChildScrollView(
            child: SupervisorConnectionPanel(controller: controller),
          ),
        ),
      ),
    );

    final startFinder = find.byKey(const ValueKey('supervisor-session-start'));
    expect(tester.widget<OutlinedButton>(startFinder).onPressed, isNull);

    await tester.tap(find.text('Configure'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('supervisor-server-url-field')),
      'https://supervisor.example.com',
    );
    await tester.enterText(
      find.byKey(const ValueKey('supervisor-control-token-field')),
      'test-control-token-1234567890',
    );
    await tester.tap(find.text('Save & test'));
    await tester.pumpAndSettle();

    expect(tester.widget<OutlinedButton>(startFinder).onPressed, isNotNull);
    await tester.tap(startFinder);
    await tester.pump();

    expect(
      find.byKey(const ValueKey('supervisor-session-active')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('supervisor-session-remaining')),
      findsOneWidget,
    );
    expect(find.text('Stop / Disconnect'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('supervisor-session-stop')));
    await tester.pump();
    expect(
      find.byKey(const ValueKey('supervisor-session-active')),
      findsNothing,
    );
    expect(find.text('Start another 15 min session'), findsOneWidget);
  });
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
