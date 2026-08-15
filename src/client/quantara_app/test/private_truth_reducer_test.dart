import 'package:flutter_test/flutter_test.dart';
import 'package:quantara_app/features/auto_trade/application/private_truth_reducer.dart';
import 'package:quantara_app/features/auto_trade/domain/private_truth_models.dart';

void main() {
  final now = DateTime.utc(2026, 8, 15, 12);

  PrivateTruthEvent positionEvent({
    required String identity,
    required DateTime exchangeTime,
    double quantity = 1,
    String event = 'UPDATE',
  }) => PrivateTruthEvent(
    eventIdentity: identity,
    channel: PrivateTruthChannel.position,
    exchangeTimestampUtc: exchangeTime,
    receivedAtUtc: exchangeTime.add(const Duration(milliseconds: 20)),
    processedAtUtc: exchangeTime.add(const Duration(milliseconds: 25)),
    payload: PrivatePositionUpdate(
      event: event,
      positionId: 'pos-1',
      symbol: 'BTCUSDT',
      side: 'LONG',
      marginMode: 'ISOLATION',
      positionMode: 'ONE_WAY',
      leverage: 3,
      margin: 50,
      quantity: quantity,
      realizedPnl: 0,
      unrealizedPnl: 0,
      funding: 0,
      fee: 0,
    ),
  );

  test('new entries require REST reconciliation after connect/reconnect', () {
    var projection = PrivateTruthProjection.empty(now);
    projection = PrivateTruthReducer.markConnecting(
      current: projection,
      nowUtc: now,
    );
    projection = PrivateTruthReducer.apply(
      current: projection,
      event: positionEvent(identity: 'e1', exchangeTime: now),
    );

    expect(projection.canAdmitNewEntries, isFalse);
    expect(projection.health, PrivateTruthHealth.reconciling);

    projection = PrivateTruthReducer.markRestVerified(
      current: projection,
      verifiedAtUtc: now.add(const Duration(seconds: 1)),
    );
    expect(projection.canAdmitNewEntries, isTrue);

    projection = PrivateTruthReducer.markReconnect(
      current: projection,
      nowUtc: now.add(const Duration(seconds: 2)),
    );
    expect(projection.canAdmitNewEntries, isFalse);
    expect(projection.restVerifiedAtUtc, isNull);
    expect(
      projection.lagReason,
      PrivateTruthLagReason.reconnectPendingReconciliation,
    );
  });

  test('duplicate event is idempotent and increments duplicate metric', () {
    var projection = PrivateTruthProjection.empty(now);
    final event = positionEvent(identity: 'same', exchangeTime: now);
    projection = PrivateTruthReducer.apply(current: projection, event: event);
    final once = projection.positions['pos-1'];
    projection = PrivateTruthReducer.apply(current: projection, event: event);

    expect(projection.positions['pos-1']!.quantity, once!.quantity);
    expect(projection.metrics.acceptedEvents, 1);
    expect(projection.metrics.duplicateEvents, 1);
  });

  test('out-of-order resource event cannot roll state backward', () {
    var projection = PrivateTruthProjection.empty(now);
    projection = PrivateTruthReducer.apply(
      current: projection,
      event: positionEvent(
        identity: 'newer',
        exchangeTime: now.add(const Duration(seconds: 2)),
        quantity: 2,
      ),
    );
    projection = PrivateTruthReducer.apply(
      current: projection,
      event: positionEvent(
        identity: 'older',
        exchangeTime: now.add(const Duration(seconds: 1)),
        quantity: 1,
      ),
    );

    expect(projection.positions['pos-1']!.quantity, 2);
    expect(projection.metrics.outOfOrderEvents, 1);
  });

  test(
    'exchange-confirmed terminal order fact survives until REST rebuild',
    () {
      final event = PrivateTruthEvent(
        eventIdentity: 'filled-order',
        channel: PrivateTruthChannel.order,
        exchangeTimestampUtc: now,
        receivedAtUtc: now.add(const Duration(milliseconds: 10)),
        processedAtUtc: now.add(const Duration(milliseconds: 12)),
        payload: PrivateOrderUpdate(
          event: 'UPDATE',
          orderId: 'order-1',
          clientId: 'q-local-1',
          symbol: 'BTCUSDT',
          side: 'BUY',
          orderType: 'MARKET',
          orderStatus: 'FILLED',
          quantity: 0.01,
          dealAmount: 0.01,
          averagePrice: 100000,
          fee: 0.6,
          updatedAtUtc: now,
        ),
      );

      final projection = PrivateTruthReducer.apply(
        current: PrivateTruthProjection.empty(now),
        event: event,
      );

      expect(projection.orders['order-1'], isNotNull);
      expect(projection.orders['order-1']!.isTerminal, isTrue);
      expect(projection.orders['order-1']!.dealAmount, 0.01);
      expect(projection.orders['order-1']!.averagePrice, 100000);
    },
  );

  test(
    'closed position is removed from hot projection without optimistic fill',
    () {
      var projection = PrivateTruthProjection.empty(now);
      projection = PrivateTruthReducer.apply(
        current: projection,
        event: positionEvent(identity: 'open', exchangeTime: now, quantity: 1),
      );
      expect(projection.reduceOnlyManagementAvailable, isTrue);

      projection = PrivateTruthReducer.apply(
        current: projection,
        event: positionEvent(
          identity: 'closed',
          exchangeTime: now.add(const Duration(seconds: 1)),
          quantity: 0,
          event: 'CLOSE',
        ),
      );
      expect(projection.positions, isEmpty);
    },
  );

  test(
    'stale private truth blocks entries while retaining active position state',
    () {
      var projection = PrivateTruthProjection.empty(now);
      projection = PrivateTruthReducer.apply(
        current: projection,
        event: positionEvent(identity: 'open', exchangeTime: now, quantity: 1),
      );
      projection = PrivateTruthReducer.markRestVerified(
        current: projection,
        verifiedAtUtc: now.add(const Duration(seconds: 1)),
      );
      projection = PrivateTruthReducer.markStale(
        current: projection,
        nowUtc: now.add(const Duration(seconds: 20)),
        reason: PrivateTruthLagReason.websocketStale,
      );

      expect(projection.canAdmitNewEntries, isFalse);
      expect(projection.reduceOnlyManagementAvailable, isTrue);
      expect(projection.positions['pos-1']!.quantity, 1);
      expect(projection.metrics.entryBlocks, 1);
    },
  );

  test('REST ambiguity remains fail closed', () {
    final projection = PrivateTruthReducer.markRestVerified(
      current: PrivateTruthProjection.empty(now),
      verifiedAtUtc: now,
      activePositionAmbiguity: true,
    );

    expect(projection.health, PrivateTruthHealth.ambiguous);
    expect(projection.canAdmitNewEntries, isFalse);
    expect(projection.metrics.entryBlocks, 1);
  });
}
