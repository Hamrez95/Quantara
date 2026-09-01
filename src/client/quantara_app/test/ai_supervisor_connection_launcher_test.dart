import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:quantara_app/features/ai_supervisor/application/supervisor_connection_controller.dart';
import 'package:quantara_app/features/ai_supervisor/application/supervisor_connection_health_coordinator.dart';
import 'package:quantara_app/features/ai_supervisor/application/supervisor_health_client.dart';
import 'package:quantara_app/features/ai_supervisor/application/supervisor_secure_setup_store.dart';
import 'package:quantara_app/features/ai_supervisor/presentation/supervisor_connection_launcher.dart';

void main() {
  testWidgets('unconfigured Supervisor stays compact and explains setup', (
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
          client: MockClient((request) async => http.Response('', 500)),
        ),
        releaseBuild: true,
      ),
      releaseBuild: true,
    );
    addTearDown(controller.dispose);
    await controller.initialize();

    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('en'),
        home: Scaffold(
          body: Column(
            children: [
              SupervisorConnectionLauncher(controller: controller),
              const Expanded(child: ColoredBox(color: Colors.black)),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final launcher = find.byKey(
      const ValueKey('supervisor-connection-launcher'),
    );
    expect(launcher, findsOneWidget);
    expect(tester.getSize(launcher).height, lessThanOrEqualTo(72));
    expect(find.text('Not configured · optional'), findsOneWidget);
    expect(
      find.textContaining('Analysis and diagnostics only:'),
      findsNothing,
    );

    await tester.tap(find.byKey(const ValueKey('supervisor-open-details')));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('supervisor-setup-explanation')),
      findsOneWidget,
    );
    expect(
      find.textContaining('QUANTARA_CONTROL_TOKEN'),
      findsOneWidget,
    );
    expect(find.textContaining('not an OpenAI API key'), findsOneWidget);
    expect(find.text('Configure'), findsOneWidget);
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
