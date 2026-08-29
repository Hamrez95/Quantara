import 'package:flutter_test/flutter_test.dart';
import 'package:quantara_app/features/auto_trade/application/private_truth_coordinator.dart';
import 'package:quantara_app/features/auto_trade/domain/private_truth_models.dart';

void main() {
  final now = DateTime.utc(2026, 8, 29);

  PrivateOrderUpdate order({String side = 'BUY'}) => PrivateOrderUpdate(
    event: 'UPDATE',
    orderId: 'order-1',
    clientId: 'client-1',
    symbol: 'BTCUSDT',
    side: side,
    orderType: 'MARKET',
    orderStatus: 'FILLED',
    quantity: 0.01,
    dealAmount: 0.01,
    averagePrice: 100000,
    fee: 0.1,
    updatedAtUtc: now,
  );

  PrivatePositionUpdate position({
    String positionId = 'position-1',
    String side = 'LONG',
  }) => PrivatePositionUpdate(
    event: 'UPDATE',
    positionId: positionId,
    symbol: 'BTCUSDT',
    side: side,
    marginMode: 'ISOLATION',
    positionMode: 'ONE_WAY',
    leverage: 3,
    margin: 50,
    quantity: 0.01,
    realizedPnl: 0,
    unrealizedPnl: 1,
    funding: 0,
    fee: 0.1,
  );

  PrivateTruthProjection projection({
    required PrivateOrderUpdate orderUpdate,
    required Iterable<PrivatePositionUpdate> positions,
  }) => PrivateTruthProjection(
    cycleId: 1,
    health: PrivateTruthHealth.fresh,
    lagReason: PrivateTruthLagReason.none,
    updatedAtUtc: now,
    restVerifiedAtUtc: now,
    balances: const {},
    orders: {orderUpdate.orderId: orderUpdate},
    positions: {for (final item in positions) item.positionId: item},
    protections: const {},
    resourceExchangeTimes: const {},
    recentEventIdentities: const [],
    metrics: const PrivateTruthMetrics(),
  );

  PrivateTruthFillConfirmation? match({
    String orderSide = 'BUY',
    required Iterable<PrivatePositionUpdate> positions,
  }) {
    final orderUpdate = order(side: orderSide);
    return PrivateTruthFillMatchPolicy.match(
      projection: projection(orderUpdate: orderUpdate, positions: positions),
      orderId: orderUpdate.orderId,
      clientId: orderUpdate.clientId,
      symbol: orderUpdate.symbol,
    );
  }

  test('BUY fill binds only to LONG position truth', () {
    final result = match(positions: [position(side: 'LONG')]);

    expect(result, isNotNull);
    expect(result!.position.side, 'LONG');
  });

  test('SELL fill binds only to SHORT position truth', () {
    final result = match(
      orderSide: 'SELL',
      positions: [position(side: 'SHORT')],
    );

    expect(result, isNotNull);
    expect(result!.position.side, 'SHORT');
  });

  test('opposite-side position cannot confirm a private fill', () {
    expect(match(positions: [position(side: 'SHORT')]), isNull);
  });

  test('same-symbol opposite-side position is ignored, not ambiguous', () {
    final result = match(
      positions: [
        position(side: 'LONG'),
        position(positionId: 'position-2', side: 'SHORT'),
      ],
    );

    expect(result, isNotNull);
    expect(result!.position.positionId, 'position-1');
  });

  test('unknown order side fails closed', () {
    expect(
      match(
        orderSide: 'UNKNOWN',
        positions: [position(side: 'LONG')],
      ),
      isNull,
    );
  });
}
