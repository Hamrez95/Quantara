import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:quantara_app/features/ai_supervisor/application/supervisor_connection_controller.dart';
import 'package:quantara_app/features/ai_supervisor/application/supervisor_connection_health_coordinator.dart';
import 'package:quantara_app/features/ai_supervisor/application/supervisor_health_client.dart';
import 'package:quantara_app/features/ai_supervisor/application/supervisor_secure_setup_store.dart';
import 'package:quantara_app/features/ai_supervisor/presentation/supervisor_connection_launcher.dart';

void main() {
  testWidgets('Supervisor launcher stays compact and explains provisioning', (
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
          client: MockClient((_) async => http.Response('', 500)),
        ),
        releaseBuild: true,
      ),
      releaseBuild: true,
    );
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('fa'),
        supportedLocales: const [Locale('fa'), Locale('en')],
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        home: Scaffold(
          body: Align(
            alignment: Alignment.bottomLeft,
            child: SupervisorConnectionLauncher(controller: controller),
          ),
        ),
      ),
    );

    expect(find.textContaining('فقط خواندنی'), findsNothing);
    expect(find.text('تنظیم اتصال'), findsNothing);

    final launcher = find.byKey(
      const ValueKey('supervisor-compact-launcher'),
    );
    expect(launcher, findsOneWidget);
    expect(tester.getSize(launcher), const Size(48, 48));

    await tester.tap(launcher);
    await tester.pumpAndSettle();

    expect(find.text('این اطلاعات حساب ChatGPT نیستند'), findsOneWidget);
    expect(find.textContaining('QUANTARA_CONTROL_TOKEN'), findsOneWidget);
    expect(find.textContaining('OPENAI_API_KEY'), findsOneWidget);
    expect(find.textContaining('فقط خواندنی'), findsOneWidget);
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
