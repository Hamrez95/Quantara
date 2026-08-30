import 'package:flutter_test/flutter_test.dart';
import 'package:quantara_app/features/windows_desktop/application/windows_service_management_client.dart';

void main() {
  WindowsServiceManagementCommandResult response({
    required int exitCode,
    required String payload,
  }) => WindowsServiceManagementCommandResult(
    exitCode: exitCode,
    stdout: payload,
    stderr: '',
  );

  String frame({
    required bool completed,
    required bool submissionAttempted,
    required bool exchangeTruthReconciled,
  }) =>
      '{"protocolVersion":1,"requestId":"client.42.99","kind":"managementResult","payload":{"completed":$completed,"submissionAttempted":$submissionAttempted,"exchangeTruthReconciled":$exchangeTruthReconciled}}';

  test('accepts only fully reconciled completed close', () async {
    String? invokedPositionId;
    final client = WindowsServiceManagementClient(
      closeCommand: (positionId) async {
        invokedPositionId = positionId;
        return response(
          exitCode: 0,
          payload: frame(
            completed: true,
            submissionAttempted: true,
            exchangeTruthReconciled: true,
          ),
        );
      },
    );

    final result = await client.closeExistingPosition('123456789');

    expect(invokedPositionId, '123456789');
    expect(result.completed, isTrue);
    expect(result.submissionAttempted, isTrue);
    expect(result.exchangeTruthReconciled, isTrue);
  });

  test('preserves canonical failed result without pretending success', () async {
    final client = WindowsServiceManagementClient(
      closeCommand: (positionId) async => response(
        exitCode: 8,
        payload: frame(
          completed: false,
          submissionAttempted: true,
          exchangeTruthReconciled: true,
        ),
      ),
    );

    final result = await client.closeExistingPosition('7');

    expect(result.completed, isFalse);
    expect(result.submissionAttempted, isTrue);
    expect(result.exchangeTruthReconciled, isTrue);
  });

  test('does not invoke helper for non-canonical position id', () async {
    var invoked = false;
    final client = WindowsServiceManagementClient(
      closeCommand: (positionId) async {
        invoked = true;
        return response(
          exitCode: 0,
          payload: frame(
            completed: true,
            submissionAttempted: true,
            exchangeTruthReconciled: true,
          ),
        );
      },
    );

    await expectLater(
      client.closeExistingPosition('12x'),
      throwsA(isA<WindowsServiceManagementException>()),
    );
    await expectLater(
      client.closeExistingPosition('0'),
      throwsA(isA<WindowsServiceManagementException>()),
    );
    expect(invoked, isFalse);
  });

  test('fails closed on contradictory success response', () async {
    final client = WindowsServiceManagementClient(
      closeCommand: (positionId) async => response(
        exitCode: 0,
        payload: frame(
          completed: true,
          submissionAttempted: false,
          exchangeTruthReconciled: false,
        ),
      ),
    );

    await expectLater(
      client.closeExistingPosition('22'),
      throwsA(isA<WindowsServiceManagementException>()),
    );
  });

  test('fails closed when helper exit code contradicts result', () async {
    final client = WindowsServiceManagementClient(
      closeCommand: (positionId) async => response(
        exitCode: 8,
        payload: frame(
          completed: true,
          submissionAttempted: true,
          exchangeTruthReconciled: true,
        ),
      ),
    );

    await expectLater(
      client.closeExistingPosition('22'),
      throwsA(isA<WindowsServiceManagementException>()),
    );
  });

  test('fails closed on malformed or expanded payload', () async {
    final malformed = WindowsServiceManagementClient(
      closeCommand: (positionId) async => response(
        exitCode: 8,
        payload:
            '{"protocolVersion":1,"requestId":"client.1","kind":"managementResult","payload":{"completed":false,"submissionAttempted":false,"exchangeTruthReconciled":false,"entryAuthority":true}}',
      ),
    );

    await expectLater(
      malformed.closeExistingPosition('9'),
      throwsA(isA<WindowsServiceManagementException>()),
    );
  });

  test('does not accept automatic retry semantics for unknown helper failure', () async {
    var calls = 0;
    final client = WindowsServiceManagementClient(
      closeCommand: (positionId) async {
        calls += 1;
        throw const WindowsServiceManagementException(
          'timed out; outcome unknown',
        );
      },
    );

    await expectLater(
      client.closeExistingPosition('44'),
      throwsA(isA<WindowsServiceManagementException>()),
    );
    expect(calls, 1);
  });
}
