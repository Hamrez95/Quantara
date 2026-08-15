import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:quantara_app/features/auto_trade/data/bitunix_private_websocket_client.dart';
import 'package:quantara_app/features/auto_trade/domain/auto_trade_models.dart';

final class _MalformedTransport implements PrivateWsTransport {
  final controller = StreamController<Object?>();

  @override
  Future<void> get ready async {}

  @override
  Stream<Object?> get stream => controller.stream;

  @override
  void add(Object data) {}

  @override
  Future<void> close() async {
    if (!controller.isClosed) await controller.close();
  }

  void emit(Object? value) => controller.add(value);
}

Future<void> _flush([int count = 1]) async {
  for (var i = 0; i < count; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

void main() {
  test('malformed or unsupported private frames are counted, never promoted', () async {
    final transport = _MalformedTransport();
    final now = DateTime.utc(2026, 8, 16, 1);
    final client = BitunixPrivateWebSocketClient(
      connector: (_) async => transport,
      delay: (_) async {},
      clock: () => now,
      nonceFactory: () => 'nonce',
      heartbeatInterval: const Duration(hours: 1),
      staleAfter: const Duration(hours: 2),
    );
    final events = <Object>[];
    final subscription = client.events.listen(events.add);
    await client.start(
      const BitunixApiCredentials(apiKey: 'api', secretKey: 'secret'),
    );
    transport.emit(jsonEncode(<String, Object?>{'op': 'login', 'code': 0}));
    await _flush(2);
    transport.emit(jsonEncode(<String, Object?>{'op': 'subscribe', 'code': 0}));
    await _flush(2);

    transport.emit('not-json');
    transport.emit(jsonEncode(<String, Object?>{
      'ch': 'unsupported',
      'ts': 1,
      'data': <String, Object?>{},
    }));
    await _flush(3);

    expect(client.droppedOrMalformedEvents, 2);
    expect(events, isEmpty);
    await subscription.cancel();
    await client.dispose();
  });
}
