import 'package:flutter_test/flutter_test.dart';
import 'package:quantara_app/features/windows_desktop/domain/windows_service_protocol.dart';

void main() {
  Map<String, Object?> frame({
    int version = WindowsServiceProtocol.currentVersion,
    String requestId = 'status-1',
    String kind = 'statusRequest',
    Map<String, Object?> payload = const {},
  }) => <String, Object?>{
    'protocolVersion': version,
    'requestId': requestId,
    'kind': kind,
    'payload': payload,
  };

  test('authenticated current-version status frame is accepted', () {
    final decoded = WindowsServiceProtocol.decodeAuthenticated(
      frame(),
      peerAuthenticated: true,
    );

    expect(decoded.protocolVersion, WindowsServiceProtocol.currentVersion);
    expect(decoded.requestId, 'status-1');
    expect(decoded.kind, WindowsServiceMessageKind.statusRequest);
    expect(decoded.payload, isEmpty);
  });

  test('unauthenticated peer is rejected before frame processing', () {
    expect(
      () => WindowsServiceProtocol.decodeAuthenticated(
        frame(version: 999),
        peerAuthenticated: false,
      ),
      throwsA(
        isA<WindowsServiceProtocolException>().having(
          (error) => error.message,
          'message',
          contains('Unauthenticated'),
        ),
      ),
    );
  });

  test('protocol version mismatch fails closed', () {
    expect(
      () => WindowsServiceProtocol.decodeAuthenticated(
        frame(version: WindowsServiceProtocol.currentVersion + 1),
        peerAuthenticated: true,
      ),
      throwsA(
        isA<WindowsServiceProtocolException>().having(
          (error) => error.message,
          'message',
          contains('Incompatible'),
        ),
      ),
    );
  });

  test('unknown message kind fails closed', () {
    expect(
      () => WindowsServiceProtocol.decodeAuthenticated(
        frame(kind: 'executeTrade'),
        peerAuthenticated: true,
      ),
      throwsA(isA<WindowsServiceProtocolException>()),
    );
  });

  test('malformed request ids are rejected', () {
    expect(
      () => WindowsServiceProtocol.decodeAuthenticated(
        frame(requestId: '../unsafe request'),
        peerAuthenticated: true,
      ),
      throwsA(isA<WindowsServiceProtocolException>()),
    );
  });

  test('oversized frames are rejected', () {
    final oversized = 'x' * WindowsServiceProtocol.maxFrameBytes;

    expect(
      () => WindowsServiceProtocol.decodeAuthenticated(
        frame(payload: {'value': oversized}),
        peerAuthenticated: true,
      ),
      throwsA(
        isA<WindowsServiceProtocolException>().having(
          (error) => error.message,
          'message',
          contains('size limit'),
        ),
      ),
    );
  });

  test('payload is immutable after construction', () {
    final original = <String, Object?>{'state': 'connected'};
    final decoded = WindowsServiceFrame(
      requestId: 'status-2',
      kind: WindowsServiceMessageKind.statusSnapshot,
      payload: original,
    );
    original['state'] = 'tampered';

    expect(decoded.payload['state'], 'connected');
    expect(
      () => decoded.payload['state'] = 'tampered',
      throwsUnsupportedError,
    );
  });
}
