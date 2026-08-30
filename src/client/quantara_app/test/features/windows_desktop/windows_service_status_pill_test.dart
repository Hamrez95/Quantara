import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quantara_app/features/windows_desktop/application/windows_service_management_client.dart';
import 'package:quantara_app/features/windows_desktop/application/windows_service_status_reader.dart';
import 'package:quantara_app/features/windows_desktop/presentation/windows_service_status_pill.dart';

void main() {
  WindowsServiceStatusReader readerFor(String stdout) {
    return WindowsServiceStatusReader(
      command: () async => WindowsServiceStatusCommandResult(
        exitCode: 0,
        stdout: stdout,
        stderr: '',
      ),
    );
  }

  WindowsServiceManagementClient managementClientFor({
    required Future<WindowsServiceManagementCommandResult> Function(
      String positionId,
    )
    closeCommand,
  }) {
    return WindowsServiceManagementClient(closeCommand: closeCommand);
  }

  Widget host(
    WindowsServiceStatusReader reader, {
    WindowsServiceManagementClient? managementClient,
  }) {
    return MaterialApp(
      locale: const Locale('en'),
      home: Scaffold(
        body: WindowsServiceStatusPill(
          reader: reader,
          managementClient: managementClient,
          forceVisible: true,
        ),
      ),
    );
  }

  testWidgets('shows authenticated disarmed service without entry authority', (
    tester,
  ) async {
    await tester.pumpWidget(
      host(
        readerFor(
          '{"protocolVersion":1,"requestId":"ui.1","kind":"statusSnapshot","payload":{"serviceState":"disarmed","entryAuthority":false}}',
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Windows service: disarmed'), findsOneWidget);
    expect(find.textContaining('running'), findsNothing);
  });

  testWidgets('surfaces reconciliation-required state distinctly', (
    tester,
  ) async {
    await tester.pumpWidget(
      host(
        readerFor(
          '{"protocolVersion":1,"requestId":"ui.2","kind":"statusSnapshot","payload":{"serviceState":"reconciliationRequired","entryAuthority":false}}',
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Windows service: reconcile'), findsOneWidget);
  });

  testWidgets('surfaces management-only state without entry authority', (
    tester,
  ) async {
    await tester.pumpWidget(
      host(
        readerFor(
          '{"protocolVersion":1,"requestId":"ui.management","kind":"statusSnapshot","payload":{"serviceState":"manageExistingOnly","entryAuthority":false}}',
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Windows service: manage existing only'), findsOneWidget);
    expect(find.textContaining('unverified'), findsNothing);
  });

  testWidgets('management-only state requires explicit close confirmation', (
    tester,
  ) async {
    var calls = 0;
    String? closedPositionId;
    final managementClient = managementClientFor(
      closeCommand: (positionId) async {
        calls += 1;
        closedPositionId = positionId;
        return const WindowsServiceManagementCommandResult(
          exitCode: 0,
          stdout:
              '{"protocolVersion":1,"requestId":"ui.close.1","kind":"managementResult","payload":{"completed":true,"submissionAttempted":true,"exchangeTruthReconciled":true}}',
          stderr: '',
        );
      },
    );

    await tester.pumpWidget(
      host(
        readerFor(
          '{"protocolVersion":1,"requestId":"ui.management.action","kind":"statusSnapshot","payload":{"serviceState":"manageExistingOnly","entryAuthority":false}}',
        ),
        managementClient: managementClient,
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Windows service: manage existing only'));
    await tester.pumpAndSettle();

    expect(find.text('Close existing position'), findsOneWidget);
    expect(find.text('Close position'), findsOneWidget);
    expect(tester.widget<FilledButton>(find.byType(FilledButton)).onPressed, isNull);

    await tester.enterText(find.byType(TextField), '123456');
    await tester.tap(
      find.text(
        'I confirm that only this existing position should be closed.',
      ),
    );
    await tester.pump();

    expect(
      tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
      isNotNull,
    );
    await tester.tap(find.text('Close position'));
    await tester.pumpAndSettle();

    expect(calls, 1);
    expect(closedPositionId, '123456');
    expect(
      find.text('Position close was confirmed by fresh exchange state.'),
      findsOneWidget,
    );
  });

  testWidgets('management UI does not call helper for invalid position id', (
    tester,
  ) async {
    var calls = 0;
    final managementClient = managementClientFor(
      closeCommand: (positionId) async {
        calls += 1;
        throw StateError('must not run');
      },
    );

    await tester.pumpWidget(
      host(
        readerFor(
          '{"protocolVersion":1,"requestId":"ui.management.invalid","kind":"statusSnapshot","payload":{"serviceState":"manageExistingOnly","entryAuthority":false}}',
        ),
        managementClient: managementClient,
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Windows service: manage existing only'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '12x');
    await tester.tap(
      find.text(
        'I confirm that only this existing position should be closed.',
      ),
    );
    await tester.pump();

    expect(
      find.text('ID must be 1-64 decimal digits and non-zero.'),
      findsOneWidget,
    );
    expect(tester.widget<FilledButton>(find.byType(FilledButton)).onPressed, isNull);
    expect(calls, 0);
  });

  testWidgets('canonical failed close is not retried or presented as success', (
    tester,
  ) async {
    var calls = 0;
    final managementClient = managementClientFor(
      closeCommand: (positionId) async {
        calls += 1;
        return const WindowsServiceManagementCommandResult(
          exitCode: 8,
          stdout:
              '{"protocolVersion":1,"requestId":"ui.close.failed","kind":"managementResult","payload":{"completed":false,"submissionAttempted":true,"exchangeTruthReconciled":true}}',
          stderr: '',
        );
      },
    );

    await tester.pumpWidget(
      host(
        readerFor(
          '{"protocolVersion":1,"requestId":"ui.management.failed","kind":"statusSnapshot","payload":{"serviceState":"manageExistingOnly","entryAuthority":false}}',
        ),
        managementClient: managementClient,
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Windows service: manage existing only'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '55');
    await tester.tap(
      find.text(
        'I confirm that only this existing position should be closed.',
      ),
    );
    await tester.pump();
    await tester.tap(find.text('Close position'));
    await tester.pumpAndSettle();

    expect(calls, 1);
    expect(
      find.text(
        'Position close was not confirmed. Reconcile exchange state before retrying.',
      ),
      findsOneWidget,
    );
    expect(find.text('Close existing position'), findsOneWidget);
  });

  testWidgets('non-management state cannot open mutation control', (
    tester,
  ) async {
    await tester.pumpWidget(
      host(
        readerFor(
          '{"protocolVersion":1,"requestId":"ui.disarmed.action","kind":"statusSnapshot","payload":{"serviceState":"disarmed","entryAuthority":false}}',
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Windows service: disarmed'));
    await tester.pumpAndSettle();

    expect(find.text('Close existing position'), findsNothing);
  });

  testWidgets('fails closed when the service response cannot be verified', (
    tester,
  ) async {
    final reader = WindowsServiceStatusReader(
      command: () async => const WindowsServiceStatusCommandResult(
        exitCode: 5,
        stdout: '',
        stderr: 'ignored diagnostic',
      ),
    );

    await tester.pumpWidget(host(reader));
    await tester.pumpAndSettle();

    expect(find.text('Windows service: unverified'), findsOneWidget);
    expect(find.byIcon(Icons.shield_outlined), findsOneWidget);
  });

  testWidgets('does not render on unsupported platforms by default', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    try {
      final reader = readerFor(
        '{"protocolVersion":1,"requestId":"ui.3","kind":"statusSnapshot","payload":{"serviceState":"disarmed","entryAuthority":false}}',
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: WindowsServiceStatusPill(reader: reader)),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.textContaining('Windows service:'), findsNothing);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });
}
