import 'package:flutter_test/flutter_test.dart';
import 'package:quantara_app/features/auto_trade/application/private_truth_account_snapshot.dart';
import 'package:quantara_app/features/auto_trade/domain/auto_trade_models.dart';
import 'package:quantara_app/features/auto_trade/domain/private_truth_models.dart';

void main() {
  final now = DateTime.utc(2026, 8, 16, 1);

  AutoTradeAccountSnapshot baseline({bool includePosition = true}) =>
      AutoTradeAccountSnapshot(
        marginCoin: 'USDT',
        available: 900,
        frozen: 0,
        positionMargin: includePosition ? 100 : 0,
        crossUnrealizedPnl: 0,
        isolatedUnrealizedPnl: 5,
        positionMode: 'ONE_WAY',
        positions: includePosition
            ? const [
                AutoTradePosition(
                  positionId: 'p-1',
                  symbol: 'BTCUSDT',
                  quantity: 0.01,
                  side: 'LONG',
                  marginMode: 'ISOLATION',
                  positionMode: 'ONE_WAY',
                  leverage: 3,
                  margin: 100,
                  unrealizedPnl: 5,
                  liquidationPrice: 70000,
                  averageOpenPrice: 100000,
                ),
              ]
            : const [],
        orders: const [],
        protectionOrders: includePosition
            ? const [
                AutoTradeProtectionOrder.stopLoss(
                  exchangeId: 'sl-1',
                  positionId: 'p-1',
                  symbol: 'BTCUSDT',
                  price: 95000,
                  quantity: 0.01,
                ),
              ]
            : const [],
        protectionVerifications: includePosition
            ? {'p-1': AutoTradeProtectionVerification.verified(asOf: now)}
            : const {},
        syncedAt: now,
      );

  PrivateTruthProjection projection({String positionId = 'p-1'}) =>
      PrivateTruthProjection(
        cycleId: 2,
        health: PrivateTruthHealth.fresh,
        lagReason: PrivateTruthLagReason.none,
        updatedAtUtc: now.add(const Duration(seconds: 1)),
        restVerifiedAtUtc: now,
        balances: const {
          'USDT': PrivateBalanceUpdate(
            coin: 'USDT',
            available: 895,
            frozen: 0,
            margin: 100,
            isolationFrozen: 0,
            crossFrozen: 0,
            isolationMargin: 100,
            crossMargin: 0,
          ),
        },
        orders: const {},
        positions: {
          positionId: PrivatePositionUpdate(
            event: 'UPDATE',
            positionId: positionId,
            symbol: 'BTCUSDT',
            side: 'LONG',
            marginMode: 'ISOLATION',
            positionMode: 'ONE_WAY',
            leverage: 3,
            margin: 100,
            quantity: 0.01,
            realizedPnl: 0,
            unrealizedPnl: 7,
            funding: -0.02,
            fee: 0.3,
          ),
        },
        protections: const {
          'sl-1': PrivateProtectionUpdate(
            event: 'UPDATE',
            orderId: 'sl-1',
            positionId: 'p-1',
            symbol: 'BTCUSDT',
            status: 'ACTIVE',
            takeProfitQuantity: null,
            takeProfitPrice: null,
            stopLossQuantity: 0.01,
            stopLossPrice: 95000,
          ),
        },
        resourceExchangeTimes: const {},
        recentEventIdentities: const [],
        metrics: const PrivateTruthMetrics(),
      );

  test(
    'hot deltas replace current values while REST keeps immutable fields',
    () {
      final view = PrivateTruthAccountSnapshotBuilder.build(
        projection: projection(),
        restBaseline: baseline(),
      );

      expect(view.completeForNewEntry, isTrue);
      expect(view.snapshot.available, 895);
      expect(view.snapshot.positions.single.unrealizedPnl, 7);
      expect(view.snapshot.positions.single.averageOpenPrice, 100000);
      expect(view.snapshot.positions.single.liquidationPrice, 70000);
      expect(view.snapshot.positions.single.funding, -0.02);
      expect(view.snapshot.syncedAt, now.add(const Duration(seconds: 1)));
    },
  );

  test(
    'new WS position stays visible but blocks another entry until REST sees it',
    () {
      final view = PrivateTruthAccountSnapshotBuilder.build(
        projection: projection(positionId: 'p-new'),
        restBaseline: baseline(includePosition: false),
      );

      expect(view.snapshot.positions.single.positionId, 'p-new');
      expect(view.completeForNewEntry, isFalse);
      expect(view.missingBaselinePositionIds, ['p-new']);
    },
  );

  test('terminal fill truth is not misrepresented as a pending order', () {
    final baseProjection = projection();
    final withFill = PrivateTruthProjection(
      cycleId: baseProjection.cycleId,
      health: baseProjection.health,
      lagReason: baseProjection.lagReason,
      updatedAtUtc: baseProjection.updatedAtUtc,
      restVerifiedAtUtc: baseProjection.restVerifiedAtUtc,
      balances: baseProjection.balances,
      orders: {
        'o-1': PrivateOrderUpdate(
          event: 'UPDATE',
          orderId: 'o-1',
          clientId: 'q-1',
          symbol: 'BTCUSDT',
          side: 'BUY',
          orderType: 'MARKET',
          orderStatus: 'FILLED',
          quantity: 0.01,
          dealAmount: 0.01,
          averagePrice: 100100,
          fee: 0.2,
          updatedAtUtc: now,
        ),
      },
      positions: baseProjection.positions,
      protections: baseProjection.protections,
      resourceExchangeTimes: baseProjection.resourceExchangeTimes,
      recentEventIdentities: baseProjection.recentEventIdentities,
      metrics: baseProjection.metrics,
    );

    final view = PrivateTruthAccountSnapshotBuilder.build(
      projection: withFill,
      restBaseline: baseline(),
    );

    expect(view.snapshot.orders, isEmpty);
  });
}
