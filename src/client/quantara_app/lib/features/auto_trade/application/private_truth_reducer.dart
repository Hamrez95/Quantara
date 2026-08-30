import '../domain/private_truth_models.dart';

abstract final class PrivateTruthReducer {
  static const int maximumRecentEventIdentities = 4096;

  static PrivateTruthProjection markConnecting({
    required PrivateTruthProjection current,
    required DateTime nowUtc,
  }) => _copy(
    current,
    cycleId: current.cycleId + 1,
    health: PrivateTruthHealth.connecting,
    lagReason: PrivateTruthLagReason.disconnected,
    updatedAtUtc: nowUtc.toUtc(),
  );

  static PrivateTruthProjection markReconnect({
    required PrivateTruthProjection current,
    required DateTime nowUtc,
  }) => _copy(
    current,
    cycleId: current.cycleId + 1,
    health: PrivateTruthHealth.reconciling,
    lagReason: PrivateTruthLagReason.reconnectPendingReconciliation,
    updatedAtUtc: nowUtc.toUtc(),
    clearRestVerification: true,
    metrics: current.metrics.copyWith(
      reconnectCount: current.metrics.reconnectCount + 1,
    ),
  );

  static PrivateTruthProjection markRestVerified({
    required PrivateTruthProjection current,
    required DateTime verifiedAtUtc,
    bool activePositionAmbiguity = false,
  }) => _copy(
    current,
    cycleId: current.cycleId + 1,
    health: activePositionAmbiguity
        ? PrivateTruthHealth.ambiguous
        : PrivateTruthHealth.fresh,
    lagReason: activePositionAmbiguity
        ? PrivateTruthLagReason.activePositionAmbiguity
        : PrivateTruthLagReason.none,
    updatedAtUtc: verifiedAtUtc.toUtc(),
    restVerifiedAtUtc: verifiedAtUtc.toUtc(),
    reconciliationGeneration: current.reconciliationGeneration + 1,
    activePositionAmbiguity: activePositionAmbiguity,
    metrics: current.metrics.copyWith(
      restVerificationCount: current.metrics.restVerificationCount + 1,
      entryBlocks: activePositionAmbiguity
          ? current.metrics.entryBlocks + 1
          : current.metrics.entryBlocks,
    ),
  );

  static PrivateTruthProjection markStale({
    required PrivateTruthProjection current,
    required DateTime nowUtc,
    required PrivateTruthLagReason reason,
  }) => _copy(
    current,
    cycleId: current.cycleId + 1,
    health: PrivateTruthHealth.stale,
    lagReason: reason,
    updatedAtUtc: nowUtc.toUtc(),
    metrics: current.metrics.copyWith(
      entryBlocks: current.metrics.entryBlocks + 1,
    ),
  );

  static PrivateTruthProjection apply({
    required PrivateTruthProjection current,
    required PrivateTruthEvent event,
  }) {
    if (current.recentEventIdentities.contains(event.eventIdentity)) {
      return _copy(
        current,
        metrics: current.metrics.copyWith(
          duplicateEvents: current.metrics.duplicateEvents + 1,
        ),
      );
    }
    final resource = event.payload.resourceIdentity;
    final priorTimestamp = current.resourceExchangeTimes[resource];
    if (priorTimestamp != null &&
        event.exchangeTimestampUtc.isBefore(priorTimestamp)) {
      return _copy(
        current,
        recentEventIdentities: _remember(
          current.recentEventIdentities,
          event.eventIdentity,
        ),
        metrics: current.metrics.copyWith(
          outOfOrderEvents: current.metrics.outOfOrderEvents + 1,
        ),
      );
    }

    final balances = Map<String, PrivateBalanceUpdate>.of(current.balances);
    final orders = Map<String, PrivateOrderUpdate>.of(current.orders);
    final positions = Map<String, PrivatePositionUpdate>.of(current.positions);
    final protections = Map<String, PrivateProtectionUpdate>.of(
      current.protections,
    );
    switch (event.payload) {
      case final PrivateBalanceUpdate balance:
        balances[balance.coin.toUpperCase()] = balance;
      case final PrivateOrderUpdate order:
        // Keep the latest exchange-confirmed terminal order fact long enough for
        // the post-submit hot path to observe FILLED/CANCELED truth. The next
        // authoritative REST reconciliation rebuilds the active-order set.
        orders[order.orderId] = order;
      case final PrivatePositionUpdate position:
        if (position.closed) {
          positions.remove(position.positionId);
        } else {
          positions[position.positionId] = position;
        }
      case final PrivateProtectionUpdate protection:
        if (protection.isTerminal) {
          protections.remove(protection.orderId);
        } else {
          protections[protection.orderId] = protection;
        }
    }
    final resourceTimes = Map<String, DateTime>.of(
      current.resourceExchangeTimes,
    )..[resource] = event.exchangeTimestampUtc;
    return PrivateTruthProjection(
      cycleId: current.cycleId + 1,
      health: current.restVerifiedAtUtc == null
          ? PrivateTruthHealth.reconciling
          : PrivateTruthHealth.fresh,
      lagReason: current.restVerifiedAtUtc == null
          ? PrivateTruthLagReason.reconnectPendingReconciliation
          : PrivateTruthLagReason.none,
      updatedAtUtc: event.processedAtUtc,
      restVerifiedAtUtc: current.restVerifiedAtUtc,
      balances: balances,
      orders: orders,
      positions: positions,
      protections: protections,
      resourceExchangeTimes: resourceTimes,
      recentEventIdentities: _remember(
        current.recentEventIdentities,
        event.eventIdentity,
      ),
      metrics: current.metrics.copyWith(
        acceptedEvents: current.metrics.acceptedEvents + 1,
      ),
      reconciliationGeneration: current.reconciliationGeneration,
      activePositionAmbiguity: current.activePositionAmbiguity,
    );
  }

  static List<String> _remember(Iterable<String> existing, String identity) {
    final values = [...existing, identity];
    if (values.length <= maximumRecentEventIdentities) return values;
    return values.sublist(values.length - maximumRecentEventIdentities);
  }

  static PrivateTruthProjection _copy(
    PrivateTruthProjection current, {
    int? cycleId,
    PrivateTruthHealth? health,
    PrivateTruthLagReason? lagReason,
    DateTime? updatedAtUtc,
    DateTime? restVerifiedAtUtc,
    bool clearRestVerification = false,
    Map<String, PrivateBalanceUpdate>? balances,
    Map<String, PrivateOrderUpdate>? orders,
    Map<String, PrivatePositionUpdate>? positions,
    Map<String, PrivateProtectionUpdate>? protections,
    Map<String, DateTime>? resourceExchangeTimes,
    Iterable<String>? recentEventIdentities,
    PrivateTruthMetrics? metrics,
    int? reconciliationGeneration,
    bool? activePositionAmbiguity,
  }) => PrivateTruthProjection(
    cycleId: cycleId ?? current.cycleId,
    health: health ?? current.health,
    lagReason: lagReason ?? current.lagReason,
    updatedAtUtc: updatedAtUtc ?? current.updatedAtUtc,
    restVerifiedAtUtc: clearRestVerification
        ? null
        : restVerifiedAtUtc ?? current.restVerifiedAtUtc,
    balances: balances ?? current.balances,
    orders: orders ?? current.orders,
    positions: positions ?? current.positions,
    protections: protections ?? current.protections,
    resourceExchangeTimes:
        resourceExchangeTimes ?? current.resourceExchangeTimes,
    recentEventIdentities:
        recentEventIdentities ?? current.recentEventIdentities,
    metrics: metrics ?? current.metrics,
    reconciliationGeneration:
        reconciliationGeneration ?? current.reconciliationGeneration,
    activePositionAmbiguity:
        activePositionAmbiguity ?? current.activePositionAmbiguity,
  );
}
