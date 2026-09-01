import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quantara_app/features/windows_desktop/application/windows_service_management_client.dart';
import 'package:quantara_app/features/windows_desktop/application/windows_service_status_reader.dart';
import 'package:quantara_app/features/windows_desktop/presentation/windows_service_status_pill.dart';

void main() {
  WindowsServiceStatusReader managementReader() {
    return WindowsServiceStatusReader(
      command: () async => const WindowsServiceStatusCommandResult(
        exitCode: 0,
        stdout:
            '{"protocolVersion":1,"requestId":"ui.tighten","kind":"statusSnapshot","payload":{"serviceState":"manageExistingOnly","entryAuthority":false}}',
        stderr: '',
      ),
    );
  }

  testWidgets('tighten-stop UI requires explicit bounded confirmation', (
    tester,
  ) async {
    var calls = 0;
    String? positionId;
    String? stopPrice;
    final client = WindowsServiceManagementClient(
      closeCommand: (id) async => throw StateError('close must not run'),
      tightenStopCommand: (id, price) async {
        calls += 1;
        positionId = id;
        stopPrice = price;
        return const WindowsServiceManagementCommandResult(
          exitCode: 0,
          stdout:
              '{"protocolVersion":1,"requestId":"ui.tighten.1","kind":"managementResult","payload":{"completed":true,"submissionAttempted":true,"exchangeTruthReconciled":true}}',
          stderr: '',
        );
      },
    );

    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('en'),
        home: Scaffold(
          body: WindowsServiceStatusPill(
            reader: managementReader(),
            managementClient: client,
            forceVisible: true,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Windows service: manage existing only'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Tighten stop instead'));
    await tester.pumpAndSettle();

    expect(find.text('Tighten existing stop'), findsOneWidget);
    expect(find.text('Tighten stop'), findsOneWidget);
    expect(
      tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
      isNull,
    );

    final fields = find.byType(TextField);
    expect(fields, findsNWidgets(2));
    await tester.enterText(fields.at(0), '123456');
    await tester.enterText(fields.at(1), '65000.5');
    await tester.tap(
      find.text(
        'I confirm that only this existing position stop may be tightened.',
      ),
    );
    await tester.pump();

    expect(
      tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
      isNotNull,
    );
    await tester.tap(find.text('Tighten stop'));
    await tester.pumpAndSettle();

    expect(calls, 1);
    expect(positionId, '123456');
    expect(stopPrice, '65000.5');
    expect(
      find.text('The tighter stop was confirmed by fresh exchange state.'),
      findsOneWidget,
    );
  });

  testWidgets('invalid stop price never reaches management helper', (
    tester,
  ) async {
    var calls = 0;
    final client = WindowsServiceManagementClient(
      closeCommand: (id) async => throw StateError('close must not run'),
      tightenStopCommand: (id, price) async {
        calls += 1;
        throw StateError('tighten must not run');
      },
    );

    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('en'),
        home: Scaffold(
          body: WindowsServiceStatusPill(
            reader: managementReader(),
            managementClient: client,
            forceVisible: true,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Windows service: manage existing only'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Tighten stop instead'));
    await tester.pumpAndSettle();

    final fields = find.byType(TextField);
    await tester.enterText(fields.at(0), '123456');
    await tester.enterText(fields.at(1), '1e8');
    await tester.tap(
      find.text(
        'I confirm that only this existing position stop may be tightened.',
      ),
    );
    await tester.pump();

    expect(find.text('Price must be a positive decimal value.'), findsOneWidget);
    expect(
      tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
      isNull,
    );
    expect(calls, 0);
  });
}
