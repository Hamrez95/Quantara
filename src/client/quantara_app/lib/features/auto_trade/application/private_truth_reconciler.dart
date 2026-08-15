import '../domain/auto_trade_models.dart';
import '../domain/private_truth_models.dart';

abstract final class PrivateTruthReconciler {
  static PrivateTruthProjection reconcileRestSnapshot({
    required PrivateTruthProjection current,
    required AutoTradeAccountSnapshot snapshot,
  }) {
    final asOf = snapshot.syncedAt.toUtc();
    final balances = <String, PrivateBalanceUpdate>{
      snapshot.marginCoin.toUpperCase(): PrivateBalanceUpdate(
        coin: snapshot.marginCoin.toUpperCase(),
        available: snapshot.available,
        frozen: snapshot.frozen,
        margin: snapshot.positionMargin,
        isolationFrozen: 0,
        crossFrozen: 0,
        isolationMargin: snapshot.positionMargin,
        crossMargin: 0,
      ),
    };
    final positions = <String, PrivatePositionUpdate>{};
    final orders = <String, PrivateOrderUpdate>{};
    final protections = <String, PrivateProtectionUpdate>{};
    final resourceTimes = <String, DateTime>{};
    var ambiguous = false;

    for (final position in snapshot.positions) {
      final id = position.positionId.trim();
      final symbol = position.symbol.trim().toUpperCase();
      if (id.isEmpty || symbol.isEmpty || positions.containsKey(id)) {
        ambiguous = true;
        continue;
      }
      final verification = snapshot.protectionVerifications[id];
      if (verification == null || !verification.verified) ambiguous = true;
      final converted = PrivatePositionUpdate(
        event: 'REST_VERIFY',
        positionId: id,
        symbol: symbol,
        side: position.side,
        marginMode: position.marginMode,
        positionMode: position.positionMode,
        leverage: position.leverage,
        margin: position.margin,
        quantity: position.quantity,
        realizedPnl: position.realizedPnl ?? 0,
        unrealizedPnl: position.unrealizedPnl,
        funding: position.funding ?? 0,
        fee: position.fee ?? 0,
      );
      positions[id] = converted;
      resourceTimes[converted.resourceIdentity] = asOf;
    }

    for (final order in snapshot.orders) {
      final id = order.orderId.trim();
      final symbol = order.symbol.trim().toUpperCase();
      if (id.isEmpty || symbol.isEmpty || orders.containsKey(id)) {
        ambiguous = true;
        continue;
      }
      final converted = PrivateOrderUpdate(
        event: 'REST_VERIFY',
        orderId: id,
        clientId: order.clientId,
        symbol: symbol,
        side: order.side,
        orderType: order.orderType,
        orderStatus: 'PENDING',
        quantity: order.quantity,
        dealAmount: order.filledQuantity,
        averagePrice: 0,
        fee: 0,
        updatedAtUtc: asOf,
      );
      orders[id] = converted;
      resourceTimes[converted.resourceIdentity] = asOf;
    }

    for (final protection in snapshot.protectionOrders) {
      final id = protection.exchangeId.trim();
      final positionId = protection.positionId.trim();
      final symbol = protection.symbol.trim().toUpperCase();
      if (id.isEmpty || positionId.isEmpty || symbol.isEmpty) {
        ambiguous = true;
        continue;
      }
      final converted = PrivateProtectionUpdate(
        event: 'REST_VERIFY',
        orderId: id,
        positionId: positionId,
        symbol: symbol,
        status: 'ACTIVE',
        takeProfitQuantity: protection.takeProfitQuantity,
        takeProfitPrice: protection.takeProfitPrice,
        stopLossQuantity: protection.stopLossQuantity,
        stopLossPrice: protection.stopLossPrice,
      );
      final previous = protections[id];
      if (previous != null &&
          (previous.positionId != converted.positionId ||
              previous.stopLossPrice != converted.stopLossPrice ||
              previous.takeProfitPrice != converted.takeProfitPrice)) {
        ambiguous = true;
      }
      protections[id] = converted;
      resourceTimes[converted.resourceIdentity] = asOf;
    }

    final balance = balances.values.single;
    resourceTimes[balance.resourceIdentity] = asOf;

    return PrivateTruthProjection(
      cycleId: current.cycleId + 1,
      health: ambiguous
          ? PrivateTruthHealth.ambiguous
          : PrivateTruthHealth.fresh,
      lagReason: ambiguous
          ? PrivateTruthLagReason.activePositionAmbiguity
          : PrivateTruthLagReason.none,
      updatedAtUtc: asOf,
      restVerifiedAtUtc: asOf,
      balances: balances,
      orders: orders,
      positions: positions,
      protections: protections,
      resourceExchangeTimes: resourceTimes,
      recentEventIdentities: current.recentEventIdentities,
      metrics: current.metrics.copyWith(
        restVerificationCount: current.metrics.restVerificationCount + 1,
        entryBlocks: ambiguous
            ? current.metrics.entryBlocks + 1
            : current.metrics.entryBlocks,
      ),
      reconciliationGeneration: current.reconciliationGeneration + 1,
      activePositionAmbiguity: ambiguous,
    );
  }
}
