import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
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

  Widget host(WindowsServiceStatusReader reader) {
    return MaterialApp(
      locale: const Locale('en'),
      home: Scaffold(
        body: WindowsServiceStatusPill(reader: reader, forceVisible: true),
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
  });
}
