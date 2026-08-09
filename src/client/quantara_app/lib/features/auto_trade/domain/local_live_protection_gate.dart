import 'auto_trade_models.dart';
import 'local_live_trade_models.dart';

/// Evaluates only exchange-confirmed stop/target coverage for existing
/// Quantara-managed positions. PnL/history warnings are intentionally not part
/// of this gate: they have their own fail-closed readiness policy.
abstract final class LocalLiveProtectionGate {
  static bool allManagedPositionsFullyProtected({
    required AutoTradeAccountSnapshot account,
    required List<LocalLiveManagedPosition> managed,
  }) {
    final openExchangePositions = account.positions
        .where((position) => position.quantity > 0)
        .toList(growable: false);
    if (managed.length != openExchangePositions.length) return false;

    for (final managedPosition in managed) {
      final position = openExchangePositions
          .where(
            (item) =>
                item.positionId.trim() == managedPosition.positionId.trim(),
          )
          .firstOrNull;
      if (position == null) return false;

      final verification =
          account.protectionVerifications[position.positionId.trim()];
      if (verification == null || !verification.verified) return false;

      final protection = AutoTradePositionProtection.reconcile(
        position: position,
        orders: account.protectionOrders,
        asOf: verification.asOf,
        expectedTakeProfitCount:
            managedPosition.targetAllocation.activeTargetCount,
      );
      if (protection.status != AutoTradeProtectionStatus.fullyProtected) {
        return false;
      }
    }
    return true;
  }
}
