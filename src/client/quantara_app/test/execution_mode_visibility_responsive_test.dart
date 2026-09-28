import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quantara_app/app/quantara_app.dart';

import 'support/owner_alpha_test_fakes.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  for (final locale in <Locale>[const Locale('fa'), const Locale('en')]) {
    testWidgets(
      'manual-only boundary remains usable at 320px and large text in ${locale.languageCode}',
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
            initialLocale: locale,
          ),
        );
        await tester.pumpAndSettle();

        // The Supervisor connection surface also uses an AI glyph. The
        // execution-mode affordance lives in the owner-alpha content and is
        // the last matching navigation/action icon in this composed shell.
        await tester.tap(find.byIcon(Icons.smart_toy_outlined).last);
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull);
      },
    );
  }
}
