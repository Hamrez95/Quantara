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

  test('accepts only fully reconciled completed stop tightening', () async {
    String? invokedPositionId;
    String? invokedPrice;
    final client = WindowsServiceManagementClient(
      closeCommand: (positionId) async => throw StateError('not used'),
      tightenStopCommand: (positionId, newStopPrice) async {
        invokedPositionId = positionId;
        invokedPrice = newStopPrice;
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

    final result = await client.tightenExistingStop(
      positionId: '123456789',
      newStopPrice: '65000.5',
    );

    expect(invokedPositionId, '123456789');
    expect(invokedPrice, '65000.5');
    expect(result.completed, isTrue);
    expect(result.exchangeTruthReconciled, isTrue);
  });

  test('rejects invalid tighten-stop price before helper invocation', () async {
    var calls = 0;
    final client = WindowsServiceManagementClient(
      closeCommand: (positionId) async => throw StateError('not used'),
      tightenStopCommand: (positionId, newStopPrice) async {
        calls += 1;
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

    for (final price in ['', '0', '-1', 'NaN', 'Infinity', '1e8', '12x']) {
      await expectLater(
        client.tightenExistingStop(positionId: '9', newStopPrice: price),
        throwsA(isA<WindowsServiceManagementException>()),
      );
    }
    expect(calls, 0);
  });

  test('fails closed when tighten-stop command is unavailable', () async {
    final client = WindowsServiceManagementClient(
      closeCommand: (positionId) async => throw StateError('not used'),
    );

    await expectLater(
      client.tightenExistingStop(positionId: '9', newStopPrice: '10.5'),
      throwsA(isA<WindowsServiceManagementException>()),
    );
  });

  test(
    'preserves canonical failed result without pretending success',
    () async {
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
    },
  );

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

  test(
    'does not accept automatic retry semantics for unknown helper failure',
    () async {
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
    },
  );
}
