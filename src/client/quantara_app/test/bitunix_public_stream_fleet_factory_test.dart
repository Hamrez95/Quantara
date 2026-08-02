import 'package:flutter_test/flutter_test.dart';
import 'package:quantara_app/features/owner_alpha/data/bitunix_public_stream_fleet_factory.dart';
import 'package:quantara_app/features/owner_alpha/data/bitunix_web_socket_adapter.dart';
import 'package:quantara_app/features/owner_alpha/domain/bitunix_public_stream_models.dart';

void main() {
  group('BitunixPublicStreamFleetFactory', () {
    test('creates independent connections at the 300-channel boundary', () {
      final connector = _UnusedConnector();
      final fleet = BitunixPublicStreamFleetFactory.build(
        subscriptions: [
          for (var index = 0; index < 301; index++)
            BitunixPublicSubscription.ticker(
              'S${index.toString().padLeft(4, '0')}USDT',
            ),
        ],
        connector: connector,
        onEvent: (_) {},
        onFault: (_) {},
        onState: (_, _) {},
      );

      expect(fleet.connections, hasLength(2));
      expect(fleet.connections.first.shard.subscriptions, hasLength(300));
      expect(fleet.connections.last.shard.subscriptions, hasLength(1));
      expect(fleet.connections.first.shard.index, 0);
      expect(fleet.connections.last.shard.index, 1);
    });

    test('deduplicates before creating fleet connections', () {
      final subscription = BitunixPublicSubscription.ticker('BTCUSDT');
      final fleet = BitunixPublicStreamFleetFactory.build(
        subscriptions: [subscription, subscription],
        connector: _UnusedConnector(),
        onEvent: (_) {},
        onFault: (_) {},
        onState: (_, _) {},
      );

      expect(fleet.connections, hasLength(1));
      expect(fleet.connections.single.shard.subscriptions, hasLength(1));
    });

    test('rejects an empty market universe', () {
      expect(
        () => BitunixPublicStreamFleetFactory.build(
          subscriptions: const [],
          connector: _UnusedConnector(),
          onEvent: (_) {},
          onFault: (_) {},
          onState: (_, _) {},
        ),
        throwsArgumentError,
      );
    });
  });
}

final class _UnusedConnector implements BitunixWebSocketConnector {
  @override
  BitunixWebSocket connect(Uri uri) {
    throw StateError('The fleet factory test must not open a socket.');
  }
}
