import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:quantara_app/features/windows_desktop/application/windows_service_status_reader.dart';
import 'package:quantara_app/features/windows_desktop/domain/windows_service_protocol.dart';

void main() {
  WindowsServiceStatusReader readerFor({
    int exitCode = 0,
    String stdout =
        '{"protocolVersion":1,"requestId":"client.1","kind":"statusSnapshot","payload":{"serviceState":"disarmed","entryAuthority":false}}',
    String stderr = '',
  }) {
    return WindowsServiceStatusReader(
      command: () async => WindowsServiceStatusCommandResult(
        exitCode: exitCode,
        stdout: stdout,
        stderr: stderr,
      ),
    );
  }

  test('accepts canonical authenticated read-only snapshot', () async {
    final snapshot = await readerFor().read();

    expect(snapshot.requestId, 'client.1');
    expect(snapshot.safetyState, WindowsServiceSafetyState.disarmed);
    expect(snapshot.entryAuthority, isFalse);
  });

  test('rejects helper failures without trusting stdout', () async {
    final reader = readerFor(exitCode: 5);

    await expectLater(
      reader.read(),
      throwsA(
        isA<WindowsServiceStatusReadException>().having(
          (error) => error.message,
          'message',
          contains('exit code 5'),
        ),
      ),
    );
  });

  test('rejects malformed JSON', () async {
    await expectLater(
      readerFor(stdout: '{invalid').read(),
      throwsA(isA<WindowsServiceStatusReadException>()),
    );
  });

  test('rejects non-object JSON', () async {
    await expectLater(
      readerFor(stdout: '[]').read(),
      throwsA(isA<WindowsServiceStatusReadException>()),
    );
  });

  test('rejects any service entry authority grant', () async {
    const unsafe =
        '{"protocolVersion":1,"requestId":"client.1","kind":"statusSnapshot","payload":{"serviceState":"disarmed","entryAuthority":true}}';

    await expectLater(
      readerFor(stdout: unsafe).read(),
      throwsA(isA<WindowsServiceStatusReadException>()),
    );
  });

  test('rejects unknown service state', () async {
    const unsafe =
        '{"protocolVersion":1,"requestId":"client.1","kind":"statusSnapshot","payload":{"serviceState":"running","entryAuthority":false}}';

    await expectLater(
      readerFor(stdout: unsafe).read(),
      throwsA(isA<WindowsServiceStatusReadException>()),
    );
  });

  test('rejects response above the protocol frame ceiling', () async {
    final oversized = utf8.decode(
      List<int>.filled(WindowsServiceProtocol.maxFrameBytes + 1, 97),
    );

    await expectLater(
      readerFor(stdout: oversized).read(),
      throwsA(isA<WindowsServiceStatusReadException>()),
    );
  });

  test('normalizes unexpected command exceptions safely', () async {
    final reader = WindowsServiceStatusReader(
      command: () => Future<WindowsServiceStatusCommandResult>.error(
        StateError('sensitive implementation detail'),
      ),
    );

    await expectLater(
      reader.read(),
      throwsA(
        isA<WindowsServiceStatusReadException>()
            .having((error) => error.message, 'message', contains('StateError'))
            .having(
              (error) => error.message,
              'message',
              isNot(contains('sensitive implementation detail')),
            ),
      ),
    );
  });
}
