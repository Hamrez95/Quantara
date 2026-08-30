import 'package:flutter_test/flutter_test.dart';
import 'package:quantara_app/features/auto_trade/domain/auto_trade_models.dart';
import 'package:quantara_app/features/auto_trade/domain/private_account_reconciliation.dart';

void main() {
  final syncedAt = DateTime.utc(2026, 8, 3, 11, 27);
  final snapshot = AutoTradeAccountSnapshot(
    marginCoin: 'USDT',
    available: 27.85,
    frozen: 0,
    positionMargin: 2.30,
    crossUnrealizedPnl: 0,
    isolatedUnrealizedPnl: 0.0021,
    positionMode: 'HEDGE',
    positions: const [
      AutoTradePosition(
        positionId: 'xrp-position-1',
        symbol: 'XRPUSDT',
        quantity: 21.4,
        side: 'SHORT',
        marginMode: 'ISOLATION',
        positionMode: 'HEDGE',
        leverage: 10,
        margin: 2.30,
        unrealizedPnl: 0.0021,
        liquidationPrice: 1.12,
        averageOpenPrice: 1.0665,
      ),
    ],
    orders: const [],
    syncedAt: syncedAt,
  );

  test(
    'stale private truth blocks entries but preserves position management',
    () {
      final fresh = PrivateAccountReconciliationState.fresh(
        snapshot: snapshot,
        cycleId: 'cycle-1',
        completedAt: syncedAt,
      );

      expect(fresh.health, PrivateAccountReconciliationHealth.fresh);
      expect(fresh.blocksNewEntries, isFalse);
      expect(fresh.allowsExistingPositionManagement, isTrue);

      final stale = fresh.evaluateFreshness(
        now: syncedAt.add(const Duration(minutes: 2)),
        staleAfter: const Duration(seconds: 45),
      );

      expect(stale.health, PrivateAccountReconciliationHealth.stale);
      expect(stale.blocksNewEntries, isTrue);
      expect(stale.allowsExistingPositionManagement, isTrue);
      expect(stale.snapshot, same(snapshot));
    },
  );

  test('newer Local Live count divergence fails closed until reconciled', () {
    final fresh = PrivateAccountReconciliationState.fresh(
      snapshot: snapshot,
      cycleId: 'cycle-physical-xrp',
      completedAt: syncedAt,
    );

    final divergent = fresh.observeLocalLiveOpenPositions(
      openPositionCount: 0,
      observedAt: syncedAt.add(const Duration(seconds: 5)),
    );

    expect(divergent.health, PrivateAccountReconciliationHealth.divergent);
    expect(divergent.blocksNewEntries, isTrue);
    expect(divergent.allowsExistingPositionManagement, isTrue);
    expect(divergent.cycleId, 'cycle-physical-xrp');

    final recovered = divergent.observeLocalLiveOpenPositions(
      openPositionCount: 1,
      observedAt: syncedAt.add(const Duration(seconds: 10)),
    );

    expect(recovered.health, PrivateAccountReconciliationHealth.fresh);
    expect(recovered.blocksNewEntries, isFalse);
  });

  test(
    'failed refresh never replaces a last-known position with fake zeroes',
    () {
      final fresh = PrivateAccountReconciliationState.fresh(
        snapshot: snapshot,
        cycleId: 'cycle-1',
        completedAt: syncedAt,
      );

      final failed = fresh.markRefreshFailure(
        attemptedAt: syncedAt.add(const Duration(seconds: 20)),
        warning: 'Private account refresh failed.',
      );

      expect(failed.health, PrivateAccountReconciliationHealth.stale);
      expect(failed.snapshot?.positions, hasLength(1));
      expect(failed.snapshot?.available, 27.85);
      expect(failed.blocksNewEntries, isTrue);
    },
  );
}
