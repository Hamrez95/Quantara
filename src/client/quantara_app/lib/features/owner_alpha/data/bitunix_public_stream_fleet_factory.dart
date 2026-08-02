import 'dart:async';

import '../domain/bitunix_public_stream_models.dart';
import 'bitunix_public_stream_transport.dart';
import 'bitunix_subscription_planner.dart';
import 'bitunix_web_socket_adapter.dart';

typedef BitunixFleetStateHandler =
    FutureOr<void> Function(
      int shardIndex,
      BitunixPublicConnectionState state,
    );

abstract final class BitunixPublicStreamFleetFactory {
  static BitunixPublicStreamFleet build({
    required Iterable<BitunixPublicSubscription> subscriptions,
    required BitunixWebSocketConnector connector,
    required BitunixStreamEventHandler onEvent,
    required BitunixStreamFaultHandler onFault,
    required BitunixFleetStateHandler onState,
    BitunixPublicStreamConfig config = const BitunixPublicStreamConfig(),
    BitunixReconnectPolicy reconnectPolicy = const BitunixReconnectPolicy(),
    BitunixUtcClock? clock,
    BitunixAsyncDelay? delay,
  }) {
    final shards = BitunixSubscriptionPlanner.build(subscriptions);
    if (shards.isEmpty) {
      throw ArgumentError.value(
        subscriptions,
        'subscriptions',
        'At least one public subscription is required.',
      );
    }

    return BitunixPublicStreamFleet([
      for (final shard in shards)
        BitunixPublicStreamConnection(
          shard: shard,
          connector: connector,
          onEvent: onEvent,
          onFault: onFault,
          onState: (state) => onState(shard.index, state),
          config: config,
          reconnectPolicy: reconnectPolicy,
          clock: clock,
          delay: delay,
        ),
    ]);
  }
}
