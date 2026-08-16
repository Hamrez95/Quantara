import 'package:flutter_test/flutter_test.dart';
import 'package:quantara_app/features/auto_trade/application/private_truth_reconciler.dart';
import 'package:quantara_app/features/auto_trade/domain/auto_trade_models.dart';
import 'package:quantara_app/features/auto_trade/domain/private_truth_models.dart';

void main() {
  final now = DateTime.utc(2026, 8, 15, 12);

  AutoTradeAccountSnapshot snapshot({
    bool verified = true,
    List<AutoTradePosition>? positions,
    List<AutoTradeOrder>? orders,
    List<AutoTradeProtectionOrder>? protections,
  }) {
    final values =
        positions ??
        const [
          AutoTradePosition(
            positionId: 'p-1',
            symbol: 'BTCUSDT',
            quantity: 0.01,
            side: 'LONG',
            marginMode: 'ISOLATION',
            positionMode: 'ONE_WAY',
            leverage: 3,
            margin: 50,
            unrealizedPnl: 2,
            liquidationPrice: 70000,
            averageOpenPrice: 100000,
            realizedPnl: 0,
            fee: 0.2,
            funding: -0.01,
          ),
        ];
    return AutoTradeAccountSnapshot(
      marginCoin: 'USDT',
      available: 450,
      frozen: 0,
      positionMargin: 50,
      crossUnrealizedPnl: 0,
      isolatedUnrealizedPnl: 2,
      positionMode: 'ONE_WAY',
      positions: values,
      orders: orders ?? const [],
      protectionOrders:
          protections ??
          const [
            AutoTradeProtectionOrder.stopLoss(
              exchangeId: 'sl-1',
              positionId: 'p-1',
              symbol: 'BTCUSDT',
              price: 95000,
              quantity: 0.01,
            ),
          ],
      protectionVerifications: {
        for (final position in values)
          position.positionId: verified
              ? AutoTradeProtectionVerification.verified(asOf: now)
              : AutoTradeProtectionVerification.unverified(
                  asOf: now,
                  reason: 'unverified',
                ),
      },
      syncedAt: now,
    );
  }

  test('verified REST snapshot rebuilds the authoritative hot projection', () {
    final projection = PrivateTruthReconciler.reconcileRestSnapshot(
      current: PrivateTruthProjection.empty(
        now.subtract(const Duration(seconds: 5)),
      ),
      snapshot: snapshot(),
    );

    expect(projection.health, PrivateTruthHealth.fresh);
    expect(projection.canAdmitNewEntries, isTrue);
    expect(projection.positions['p-1']!.quantity, 0.01);
    expect(projection.protections['sl-1']!.stopLossPrice, 95000);
    expect(projection.balances['USDT']!.available, 450);
    expect(projection.restVerifiedAtUtc, now);
    expect(projection.metrics.restVerificationCount, 1);
  });

  test(
    'unverified active position protection makes reconciliation ambiguous',
    () {
      final projection = PrivateTruthReconciler.reconcileRestSnapshot(
        current: PrivateTruthProjection.empty(now),
        snapshot: snapshot(verified: false),
      );

      expect(projection.health, PrivateTruthHealth.ambiguous);
      expect(projection.activePositionAmbiguity, isTrue);
      expect(projection.canAdmitNewEntries, isFalse);
      expect(projection.positions, contains('p-1'));
    },
  );

  test(
    'REST verification removes stale hot resources absent from snapshot',
    () {
      final hot = PrivateTruthProjection(
        cycleId: 1,
        health: PrivateTruthHealth.fresh,
        lagReason: PrivateTruthLagReason.none,
        updatedAtUtc: now.subtract(const Duration(seconds: 1)),
        restVerifiedAtUtc: now.subtract(const Duration(seconds: 1)),
        balances: const {},
        orders: const {},
        positions: const {
          'ghost': PrivatePositionUpdate(
            event: 'UPDATE',
            positionId: 'ghost',
            symbol: 'ETHUSDT',
            side: 'LONG',
            marginMode: 'ISOLATION',
            positionMode: 'ONE_WAY',
            leverage: 2,
            margin: 10,
            quantity: 1,
            realizedPnl: 0,
            unrealizedPnl: 0,
            funding: 0,
            fee: 0,
          ),
        },
        protections: const {},
        resourceExchangeTimes: const {},
        recentEventIdentities: const ['old-event'],
        metrics: const PrivateTruthMetrics(),
      );

      final projection = PrivateTruthReconciler.reconcileRestSnapshot(
        current: hot,
        snapshot: snapshot(positions: const [], protections: const []),
      );

      expect(projection.positions, isEmpty);
      expect(projection.recentEventIdentities, contains('old-event'));
    },
  );

  test('duplicate or missing REST position identities fail closed', () {
    const malformed = AutoTradePosition(
      positionId: '',
      symbol: 'BTCUSDT',
      quantity: 0.01,
      side: 'LONG',
      marginMode: 'ISOLATION',
      positionMode: 'ONE_WAY',
      leverage: 3,
      margin: 50,
      unrealizedPnl: 0,
      liquidationPrice: 70000,
      averageOpenPrice: 100000,
    );
    final projection = PrivateTruthReconciler.reconcileRestSnapshot(
      current: PrivateTruthProjection.empty(now),
      snapshot: snapshot(positions: const [malformed], protections: const []),
    );

    expect(projection.health, PrivateTruthHealth.ambiguous);
    expect(projection.canAdmitNewEntries, isFalse);
  });
}
