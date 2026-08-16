import 'dart:collection';

enum PrivateTruthChannel { balance, order, position, tpsl }

enum PrivateTruthHealth {
  disconnected,
  connecting,
  authenticating,
  reconciling,
  fresh,
  stale,
  ambiguous,
}

enum PrivateTruthLagReason {
  none,
  disconnected,
  reconnectPendingReconciliation,
  websocketStale,
  restVerificationStale,
  malformedCurrentEvent,
  activePositionAmbiguity,
}

sealed class PrivateTruthPayload {
  const PrivateTruthPayload();

  String get resourceIdentity;
}

final class PrivateBalanceUpdate extends PrivateTruthPayload {
  const PrivateBalanceUpdate({
    required this.coin,
    required this.available,
    required this.frozen,
    required this.margin,
    required this.isolationFrozen,
    required this.crossFrozen,
    required this.isolationMargin,
    required this.crossMargin,
  });

  final String coin;
  final double available;
  final double frozen;
  final double margin;
  final double isolationFrozen;
  final double crossFrozen;
  final double isolationMargin;
  final double crossMargin;

  @override
  String get resourceIdentity => 'balance:${coin.toUpperCase()}';
}

final class PrivateOrderUpdate extends PrivateTruthPayload {
  const PrivateOrderUpdate({
    required this.event,
    required this.orderId,
    required this.clientId,
    required this.symbol,
    required this.side,
    required this.orderType,
    required this.orderStatus,
    required this.quantity,
    required this.dealAmount,
    required this.averagePrice,
    required this.fee,
    required this.updatedAtUtc,
  });

  final String event;
  final String orderId;
  final String clientId;
  final String symbol;
  final String side;
  final String orderType;
  final String orderStatus;
  final double quantity;
  final double dealAmount;
  final double averagePrice;
  final double fee;
  final DateTime? updatedAtUtc;

  bool get isTerminal => const {
    'CANCELED',
    'FILLED',
    'PART_FILLED_CANCELED',
  }.contains(orderStatus.toUpperCase());

  @override
  String get resourceIdentity => 'order:$orderId';
}

final class PrivatePositionUpdate extends PrivateTruthPayload {
  const PrivatePositionUpdate({
    required this.event,
    required this.positionId,
    required this.symbol,
    required this.side,
    required this.marginMode,
    required this.positionMode,
    required this.leverage,
    required this.margin,
    required this.quantity,
    required this.realizedPnl,
    required this.unrealizedPnl,
    required this.funding,
    required this.fee,
  });

  final String event;
  final String positionId;
  final String symbol;
  final String side;
  final String marginMode;
  final String positionMode;
  final int leverage;
  final double margin;
  final double quantity;
  final double realizedPnl;
  final double unrealizedPnl;
  final double funding;
  final double fee;

  bool get closed => event.toUpperCase() == 'CLOSE' || quantity <= 0;

  @override
  String get resourceIdentity => 'position:$positionId';
}

final class PrivateProtectionUpdate extends PrivateTruthPayload {
  const PrivateProtectionUpdate({
    required this.event,
    required this.orderId,
    required this.positionId,
    required this.symbol,
    required this.status,
    required this.takeProfitQuantity,
    required this.takeProfitPrice,
    required this.stopLossQuantity,
    required this.stopLossPrice,
  });

  final String event;
  final String orderId;
  final String positionId;
  final String symbol;
  final String status;
  final double? takeProfitQuantity;
  final double? takeProfitPrice;
  final double? stopLossQuantity;
  final double? stopLossPrice;

  bool get isTerminal =>
      const {'CANCELED', 'FILLED'}.contains(status.toUpperCase());

  @override
  String get resourceIdentity => 'tpsl:$orderId';
}

final class PrivateTruthEvent {
  const PrivateTruthEvent({
    required this.eventIdentity,
    required this.channel,
    required this.exchangeTimestampUtc,
    required this.receivedAtUtc,
    required this.processedAtUtc,
    required this.payload,
  });

  final String eventIdentity;
  final PrivateTruthChannel channel;
  final DateTime exchangeTimestampUtc;
  final DateTime receivedAtUtc;
  final DateTime processedAtUtc;
  final PrivateTruthPayload payload;

  Duration get exchangeToLocalLatency =>
      processedAtUtc.difference(exchangeTimestampUtc);
}

final class PrivateTruthFillConfirmation {
  const PrivateTruthFillConfirmation({
    required this.order,
    required this.position,
  });

  final PrivateOrderUpdate order;
  final PrivatePositionUpdate position;
}

final class PrivateTruthMetrics {
  const PrivateTruthMetrics({
    this.acceptedEvents = 0,
    this.duplicateEvents = 0,
    this.outOfOrderEvents = 0,
    this.malformedEvents = 0,
    this.reconnectCount = 0,
    this.restVerificationCount = 0,
    this.entryBlocks = 0,
  });

  final int acceptedEvents;
  final int duplicateEvents;
  final int outOfOrderEvents;
  final int malformedEvents;
  final int reconnectCount;
  final int restVerificationCount;
  final int entryBlocks;

  PrivateTruthMetrics copyWith({
    int? acceptedEvents,
    int? duplicateEvents,
    int? outOfOrderEvents,
    int? malformedEvents,
    int? reconnectCount,
    int? restVerificationCount,
    int? entryBlocks,
  }) => PrivateTruthMetrics(
    acceptedEvents: acceptedEvents ?? this.acceptedEvents,
    duplicateEvents: duplicateEvents ?? this.duplicateEvents,
    outOfOrderEvents: outOfOrderEvents ?? this.outOfOrderEvents,
    malformedEvents: malformedEvents ?? this.malformedEvents,
    reconnectCount: reconnectCount ?? this.reconnectCount,
    restVerificationCount: restVerificationCount ?? this.restVerificationCount,
    entryBlocks: entryBlocks ?? this.entryBlocks,
  );
}

final class PrivateTruthProjection {
  PrivateTruthProjection({
    required this.cycleId,
    required this.health,
    required this.lagReason,
    required this.updatedAtUtc,
    required this.restVerifiedAtUtc,
    required Map<String, PrivateBalanceUpdate> balances,
    required Map<String, PrivateOrderUpdate> orders,
    required Map<String, PrivatePositionUpdate> positions,
    required Map<String, PrivateProtectionUpdate> protections,
    required Map<String, DateTime> resourceExchangeTimes,
    required Iterable<String> recentEventIdentities,
    required this.metrics,
    this.reconciliationGeneration = 0,
    this.activePositionAmbiguity = false,
  }) : balances = Map.unmodifiable(balances),
       orders = Map.unmodifiable(orders),
       positions = Map.unmodifiable(positions),
       protections = Map.unmodifiable(protections),
       resourceExchangeTimes = Map.unmodifiable(resourceExchangeTimes),
       recentEventIdentities = UnmodifiableListView(
         recentEventIdentities.toList(growable: false),
       );

  factory PrivateTruthProjection.empty(DateTime nowUtc) =>
      PrivateTruthProjection(
        cycleId: 0,
        health: PrivateTruthHealth.disconnected,
        lagReason: PrivateTruthLagReason.disconnected,
        updatedAtUtc: nowUtc.toUtc(),
        restVerifiedAtUtc: null,
        balances: const {},
        orders: const {},
        positions: const {},
        protections: const {},
        resourceExchangeTimes: const {},
        recentEventIdentities: const [],
        metrics: const PrivateTruthMetrics(),
      );

  final int cycleId;
  final PrivateTruthHealth health;
  final PrivateTruthLagReason lagReason;
  final DateTime updatedAtUtc;
  final DateTime? restVerifiedAtUtc;
  final Map<String, PrivateBalanceUpdate> balances;
  final Map<String, PrivateOrderUpdate> orders;
  final Map<String, PrivatePositionUpdate> positions;
  final Map<String, PrivateProtectionUpdate> protections;
  final Map<String, DateTime> resourceExchangeTimes;
  final UnmodifiableListView<String> recentEventIdentities;
  final PrivateTruthMetrics metrics;
  final int reconciliationGeneration;
  final bool activePositionAmbiguity;

  bool get canAdmitNewEntries =>
      health == PrivateTruthHealth.fresh &&
      lagReason == PrivateTruthLagReason.none &&
      restVerifiedAtUtc != null &&
      !activePositionAmbiguity;

  bool get reduceOnlyManagementAvailable =>
      positions.values.any((position) => !position.closed);

  Duration ageAt(DateTime nowUtc) => nowUtc.toUtc().difference(updatedAtUtc);
}
