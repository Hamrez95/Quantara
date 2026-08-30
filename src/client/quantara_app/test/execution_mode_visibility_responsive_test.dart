import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quantara_app/app/quantara_app.dart';

import 'support/owner_alpha_test_fakes.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  for (final testCase in <({Locale locale, String modeLabel})>[
    (locale: const Locale('fa'), modeLabel: 'فقط مشاهده · Read Only'),
    (locale: const Locale('en'), modeLabel: 'Read Only'),
  ]) {
    testWidgets(
      'execution mode remains readable at 320px and large text in ${testCase.locale.languageCode}',
      (tester) async {
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = const Size(320, 760);
        tester.platformDispatcher.textScaleFactorTestValue = 2;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

        await tester.pumpWidget(
          QuantaraApp(
            repository: const FakeOwnerAlphaRepository(),
            settingsStore: MemoryOwnerAlphaSettingsStore(),
            preferencesStore: MemoryAppPreferencesStore(),
            opportunityStateStore: MemoryOpportunityStateStore(),
            notificationGateway: RecordingSetupNotificationGateway(),
            initialLocale: testCase.locale,
          ),
        );
        await tester.pumpAndSettle();

        await tester.tap(find.byIcon(Icons.smart_toy_outlined).first);
        await tester.pumpAndSettle();

        expect(find.text(testCase.modeLabel), findsOneWidget);
        expect(find.textContaining('Approval Required'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  }
}
