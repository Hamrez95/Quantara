import 'package:flutter_test/flutter_test.dart';
import 'package:quantara_app/features/windows_desktop/domain/windows_service_protocol.dart';

void main() {
  WindowsServiceFrame frameWithPayload(Map<String, Object?> payload) {
    return WindowsServiceFrame(
      requestId: 'status-1',
      kind: WindowsServiceMessageKind.statusSnapshot,
      payload: payload,
    );
  }

  test('accepts known read-only service safety states', () {
    for (final state in WindowsServiceSafetyState.values) {
      final snapshot = WindowsServiceStatusSnapshot.fromFrame(
        frameWithPayload(<String, Object?>{
          'serviceState': state.name,
          'entryAuthority': false,
        }),
      );

      expect(snapshot.requestId, 'status-1');
      expect(snapshot.safetyState, state);
      expect(snapshot.entryAuthority, isFalse);
    }
  });

  test('rejects any entry authority grant', () {
    expect(
      () => WindowsServiceStatusSnapshot.fromFrame(
        frameWithPayload(<String, Object?>{
          'serviceState': 'disarmed',
          'entryAuthority': true,
        }),
      ),
      throwsA(isA<WindowsServiceProtocolException>()),
    );
  });

  test('rejects unknown or malformed safety state', () {
    for (final state in <Object?>['running', '', null, 1]) {
      expect(
        () => WindowsServiceStatusSnapshot.fromFrame(
          frameWithPayload(<String, Object?>{
            'serviceState': state,
            'entryAuthority': false,
          }),
        ),
        throwsA(isA<WindowsServiceProtocolException>()),
      );
    }
  });

  test('rejects missing, extra, or non-boolean authority fields', () {
    final payloads = <Map<String, Object?>>[
      <String, Object?>{'serviceState': 'disarmed'},
      <String, Object?>{
        'serviceState': 'disarmed',
        'entryAuthority': 'false',
      },
      <String, Object?>{
        'serviceState': 'disarmed',
        'entryAuthority': false,
        'unexpected': true,
      },
    ];

    for (final payload in payloads) {
      expect(
        () => WindowsServiceStatusSnapshot.fromFrame(
          frameWithPayload(payload),
        ),
        throwsA(isA<WindowsServiceProtocolException>()),
      );
    }
  });

  test('rejects non-status frames', () {
    final frame = WindowsServiceFrame(
      requestId: 'status-1',
      kind: WindowsServiceMessageKind.statusRequest,
      payload: const <String, Object?>{},
    );

    expect(
      () => WindowsServiceStatusSnapshot.fromFrame(frame),
      throwsA(isA<WindowsServiceProtocolException>()),
    );
  });
}
