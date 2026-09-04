import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quantara_app/features/owner_alpha/application/global_pause_runtime_policy.dart';
import 'package:quantara_app/features/owner_alpha/presentation/global_pause_control.dart';

void main() {
  Widget app({
    required GlobalPauseRuntimeMode mode,
    VoidCallback? onPause,
    VoidCallback? onResume,
    bool pauseFullyWhenFlat = false,
    ValueChanged<bool>? onPauseFullyWhenFlatChanged,
  }) {
    return MaterialApp(
      home: Scaffold(
        body: GlobalPauseControl(
          mode: mode,
          persian: false,
          onPauseRequested: onPause,
          onResumeRequested: onResume,
          pauseFullyWhenFlat: pauseFullyWhenFlat,
          onPauseFullyWhenFlatChanged: onPauseFullyWhenFlatChanged,
        ),
      ),
    );
  }

  testWidgets('running state exposes pause but never an arm action', (
    tester,
  ) async {
    var pauses = 0;
    await tester.pumpWidget(
      app(mode: GlobalPauseRuntimeMode.running, onPause: () => pauses += 1),
    );

    final primaryAction = find.byKey(
      const ValueKey('global-pause-primary-action'),
    );
    expect(find.text('Global Pause'), findsOneWidget);
    expect(find.textContaining('arm', findRichText: true), findsNothing);
    await tester.tap(primaryAction);
    expect(pauses, 1);
  });

  testWidgets(
    'safe pause explains minimum management and supports flat intent',
    (tester) async {
      bool? requested;
      await tester.pumpWidget(
        app(
          mode: GlobalPauseRuntimeMode.safePausedManagingExisting,
          onResume: () {},
          onPauseFullyWhenFlatChanged: (value) => requested = value,
        ),
      );

      final monitoringText = find.textContaining('minimum private monitoring');
      final flatSwitch = find.byKey(const ValueKey('pause-fully-when-flat'));
      expect(monitoringText, findsOneWidget);
      expect(find.text('Pause fully when flat'), findsOneWidget);
      await tester.tap(flatSwitch);
      expect(requested, isTrue);
    },
  );

  testWidgets('offline pause only delegates explicit resume request', (
    tester,
  ) async {
    var resumes = 0;
    await tester.pumpWidget(
      app(
        mode: GlobalPauseRuntimeMode.pausedOffline,
        onResume: () => resumes += 1,
      ),
    );

    final primaryAction = find.byKey(
      const ValueKey('global-pause-primary-action'),
    );
    final automaticResume = find.textContaining('Resume is never automatic');
    expect(find.text('Resume'), findsOneWidget);
    expect(automaticResume, findsOneWidget);
    await tester.tap(primaryAction);
    expect(resumes, 1);
  });

  testWidgets('resuming disables action until runtime validation completes', (
    tester,
  ) async {
    var resumes = 0;
    await tester.pumpWidget(
      app(mode: GlobalPauseRuntimeMode.resuming, onResume: () => resumes += 1),
    );

    final buttonFinder = find.byType(FilledButton);
    final button = tester.widget<FilledButton>(buttonFinder);
    expect(button.onPressed, isNull);
    expect(find.text('Validating…'), findsOneWidget);
    expect(resumes, 0);
  });
}
