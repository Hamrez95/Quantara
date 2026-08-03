import 'dart:math' as math;

enum AutoTradeConnectionState { disconnected, connecting, readOnly, error }

enum AutoTradeProtectionStatus {
  fullyProtected,
  missingStop,
  incompleteLadder,
  unverified,
  stale,
}

final class BitunixApiCredentials {
  const BitunixApiCredentials({required this.apiKey, required this.secretKey});

  final String apiKey;
  final String secretKey;

  String get maskedApiKey {
    if (apiKey.length <= 8) return '••••••••';
    return '${apiKey.substring(0, 4)}••••${apiKey.substring(apiKey.length - 4)}';
  }
}

final class AutoTradeAccountSnapshot {
  const AutoTradeAccountSnapshot({
    required this.marginCoin,
    required this.available,
    required this.frozen,
    required this.positionMargin,
    required this.crossUnrealizedPnl,
    required this.isolatedUnrealizedPnl,
    required this.positionMode,
    required this.positions,
    required this.orders,
    required this.syncedAt,
    this.protectionOrders = const [],
    this.protectionVerifications = const {},
  });

  final String marginCoin;
  final double available;
  final double frozen;
  final double positionMargin;
  final double crossUnrealizedPnl;
  final double isolatedUnrealizedPnl;
  final String positionMode;
  final List<AutoTradePosition> positions;

  /// Regular pending orders returned by the futures trade endpoint.
  final List<AutoTradeOrder> orders;

  /// Position TP/SL rows returned by the dedicated futures TP/SL endpoint.
  final List<AutoTradeProtectionOrder> protectionOrders;

  /// Per-position verification evidence for the dedicated TP/SL read.
  final Map<String, AutoTradeProtectionVerification> protectionVerifications;

  final DateTime syncedAt;

  double get totalUnrealizedPnl => crossUnrealizedPnl + isolatedUnrealizedPnl;

  double get estimatedEquity =>
      available + frozen + positionMargin + totalUnrealizedPnl;

  int get totalPendingOrderCount {
    final keys = <String>{};
    for (final order in orders) {
      keys.add(order.pendingOrderIdentity);
    }
    for (final order in protectionOrders) {
      keys.add(order.pendingOrderIdentity);
    }
    return keys.length;
  }

  List<AutoTradeOrder> get regularOrdersNotRepresentedByProtection {
    final protectionIds = protectionOrders
        .map((item) => item.exchangeId.trim())
        .where((item) => item.isNotEmpty)
        .toSet();
    return orders
        .where(
          (item) =>
              item.orderId.trim().isEmpty ||
              !protectionIds.contains(item.orderId.trim()),
        )
        .toList(growable: false);
  }

  AutoTradePositionProtection protectionForPosition(
    AutoTradePosition position,
  ) {
    final positionId = position.positionId.trim();
    final verification = protectionVerifications[positionId];
    if (positionId.isEmpty || verification == null || !verification.verified) {
      return AutoTradePositionProtection.unverified(
        position: position,
        asOf: verification?.asOf ?? syncedAt,
        reason:
            verification?.reason ??
            'Position TP/SL response could not be verified.',
      );
    }
    return AutoTradePositionProtection.reconcile(
      position: position,
      orders: protectionOrders,
      asOf: verification.asOf,
    );
  }

  bool get allOpenPositionsFullyProtected => positions.every(
    (position) =>
        protectionForPosition(position).status ==
        AutoTradeProtectionStatus.fullyProtected,
  );
}

final class AutoTradePosition {
  const AutoTradePosition({
    required this.positionId,
    required this.symbol,
    required this.quantity,
    required this.side,
    required this.marginMode,
    required this.positionMode,
    required this.leverage,
    required this.margin,
    required this.unrealizedPnl,
    required this.liquidationPrice,
    required this.averageOpenPrice,
  });

  final String positionId;
  final String symbol;
  final double quantity;
  final String side;
  final String marginMode;
  final String positionMode;
  final int leverage;
  final double margin;
  final double unrealizedPnl;
  final double liquidationPrice;
  final double averageOpenPrice;
}

final class AutoTradeOrder {
  const AutoTradeOrder({
    required this.orderId,
    required this.clientId,
    required this.symbol,
    required this.quantity,
    required this.filledQuantity,
    required this.side,
    required this.orderType,
    required this.marginMode,
    required this.leverage,
    required this.reduceOnly,
  });

  final String orderId;
  final String clientId;
  final String symbol;
  final double quantity;
  final double filledQuantity;
  final String side;
  final String orderType;
  final String marginMode;
  final int leverage;
  final bool reduceOnly;

  String get pendingOrderIdentity {
    final id = orderId.trim();
    if (id.isNotEmpty) return 'exchange:$id';
    final client = clientId.trim();
    if (client.isNotEmpty) return 'client:$client';
    return 'regular:$symbol:$side:$orderType:$quantity:$filledQuantity';
  }
}

final class AutoTradeProtectionVerification {
  const AutoTradeProtectionVerification.verified({required this.asOf})
    : verified = true,
      reason = null;

  const AutoTradeProtectionVerification.unverified({
    required this.asOf,
    required this.reason,
  }) : verified = false;

  final bool verified;
  final DateTime asOf;
  final String? reason;
}

final class AutoTradeProtectionOrder {
  const AutoTradeProtectionOrder({
    required this.exchangeId,
    required this.positionId,
    required this.symbol,
    this.takeProfitPrice,
    this.takeProfitQuantity,
    this.takeProfitStopType,
    this.takeProfitOrderType,
    this.stopLossPrice,
    this.stopLossQuantity,
    this.stopLossStopType,
    this.stopLossOrderType,
  });

  const AutoTradeProtectionOrder.takeProfit({
    required this.exchangeId,
    required this.positionId,
    required this.symbol,
    required double price,
    required double quantity,
    this.takeProfitStopType,
    this.takeProfitOrderType,
  }) : takeProfitPrice = price,
       takeProfitQuantity = quantity,
       stopLossPrice = null,
       stopLossQuantity = null,
       stopLossStopType = null,
       stopLossOrderType = null;

  const AutoTradeProtectionOrder.stopLoss({
    required this.exchangeId,
    required this.positionId,
    required this.symbol,
    required double price,
    required double quantity,
    this.stopLossStopType,
    this.stopLossOrderType,
  }) : stopLossPrice = price,
       stopLossQuantity = quantity,
       takeProfitPrice = null,
       takeProfitQuantity = null,
       takeProfitStopType = null,
       takeProfitOrderType = null;

  final String exchangeId;
  final String positionId;
  final String symbol;
  final double? takeProfitPrice;
  final double? takeProfitQuantity;
  final String? takeProfitStopType;
  final String? takeProfitOrderType;
  final double? stopLossPrice;
  final double? stopLossQuantity;
  final String? stopLossStopType;
  final String? stopLossOrderType;

  bool get hasTakeProfit => takeProfitPrice != null && takeProfitPrice! > 0;
  bool get hasStopLoss => stopLossPrice != null && stopLossPrice! > 0;

  String get pendingOrderIdentity {
    final id = exchangeId.trim();
    if (id.isNotEmpty) return 'exchange:$id';
    return 'protection:$positionId:$symbol:$takeProfitPrice:'
        '$takeProfitQuantity:$stopLossPrice:$stopLossQuantity';
  }

  AutoTradeProtectionLeg? get takeProfitLeg {
    final price = takeProfitPrice;
    if (price == null || price <= 0) return null;
    return AutoTradeProtectionLeg(
      exchangeId: exchangeId,
      price: price,
      quantity: takeProfitQuantity,
      stopType: takeProfitStopType,
      orderType: takeProfitOrderType,
    );
  }

  AutoTradeProtectionLeg? get stopLossLeg {
    final price = stopLossPrice;
    if (price == null || price <= 0) return null;
    return AutoTradeProtectionLeg(
      exchangeId: exchangeId,
      price: price,
      quantity: stopLossQuantity,
      stopType: stopLossStopType,
      orderType: stopLossOrderType,
    );
  }
}

final class AutoTradeProtectionLeg {
  const AutoTradeProtectionLeg({
    required this.exchangeId,
    required this.price,
    required this.quantity,
    required this.stopType,
    required this.orderType,
  });

  final String exchangeId;
  final double price;
  final double? quantity;
  final String? stopType;
  final String? orderType;
}

final class AutoTradePositionProtection {
  const AutoTradePositionProtection._({
    required this.position,
    required this.status,
    required this.stopLoss,
    required this.takeProfits,
    required this.totalTakeProfitQuantity,
    required this.residualQuantity,
    required this.hasResidualDust,
    required this.asOf,
    required this.reason,
  });

  factory AutoTradePositionProtection.reconcile({
    required AutoTradePosition position,
    required List<AutoTradeProtectionOrder> orders,
    required DateTime asOf,
    int expectedTakeProfitCount = 3,
  }) {
    final matched = <String, AutoTradeProtectionOrder>{};
    var malformed = false;
    for (final order in orders) {
      if (order.positionId.trim() != position.positionId.trim()) continue;
      final key = order.pendingOrderIdentity;
      final previous = matched[key];
      if (previous != null &&
          (previous.takeProfitPrice != order.takeProfitPrice ||
              previous.takeProfitQuantity != order.takeProfitQuantity ||
              previous.stopLossPrice != order.stopLossPrice ||
              previous.stopLossQuantity != order.stopLossQuantity)) {
        malformed = true;
      }
      matched[key] = order;
    }

    final stops = matched.values
        .map((item) => item.stopLossLeg)
        .whereType<AutoTradeProtectionLeg>()
        .toList(growable: false);
    final takeProfits = matched.values
        .map((item) => item.takeProfitLeg)
        .whereType<AutoTradeProtectionLeg>()
        .toList(growable: true);
    final short = position.side.toUpperCase().contains('SHORT');
    takeProfits.sort(
      (left, right) => short
          ? right.price.compareTo(left.price)
          : left.price.compareTo(right.price),
    );

    final totalTakeProfitQuantity = takeProfits.fold<double>(
      0,
      (sum, item) => sum + (item.quantity ?? 0),
    );
    final residualQuantity = math
        .max(0, position.quantity - totalTakeProfitQuantity)
        .toDouble();
    final tolerance = math.max(0.00000001, position.quantity.abs() * 0.000001);
    final dustThreshold = math.max(tolerance, position.quantity.abs() * 0.001);
    final stop = stops.length == 1 ? stops.single : null;
    final stopQuantity = stop?.quantity;
    final stopCoversPosition =
        stop != null &&
        stopQuantity != null &&
        stopQuantity + tolerance >= position.quantity;
    final validTargetQuantities = takeProfits.every(
      (item) => item.quantity != null && item.quantity! > 0,
    );
    final targetQuantityCovered =
        totalTakeProfitQuantity + tolerance >= position.quantity &&
        totalTakeProfitQuantity <= position.quantity + tolerance;

    late final AutoTradeProtectionStatus status;
    String? reason;
    if (malformed || stops.length > 1) {
      status = AutoTradeProtectionStatus.unverified;
      reason = malformed
          ? 'Conflicting duplicate protection identifiers were returned.'
          : 'More than one stop-loss order was returned for the position.';
    } else if (!stopCoversPosition) {
      status = AutoTradeProtectionStatus.missingStop;
      reason = stop == null
          ? 'No exchange-confirmed stop loss was found.'
          : 'The exchange-confirmed stop does not cover the full position.';
    } else if (takeProfits.length < expectedTakeProfitCount ||
        !validTargetQuantities ||
        !targetQuantityCovered) {
      status = AutoTradeProtectionStatus.incompleteLadder;
      reason = 'The take-profit ladder is incomplete or quantity-mismatched.';
    } else {
      status = AutoTradeProtectionStatus.fullyProtected;
    }

    return AutoTradePositionProtection._(
      position: position,
      status: status,
      stopLoss: stop,
      takeProfits: List.unmodifiable(takeProfits),
      totalTakeProfitQuantity: totalTakeProfitQuantity,
      residualQuantity: residualQuantity,
      hasResidualDust:
          residualQuantity > tolerance && residualQuantity <= dustThreshold,
      asOf: asOf.toUtc(),
      reason: reason,
    );
  }

  factory AutoTradePositionProtection.unverified({
    required AutoTradePosition position,
    required DateTime asOf,
    required String reason,
  }) => AutoTradePositionProtection._(
    position: position,
    status: AutoTradeProtectionStatus.unverified,
    stopLoss: null,
    takeProfits: const [],
    totalTakeProfitQuantity: 0,
    residualQuantity: position.quantity,
    hasResidualDust: false,
    asOf: asOf.toUtc(),
    reason: reason,
  );

  final AutoTradePosition position;
  final AutoTradeProtectionStatus status;
  final AutoTradeProtectionLeg? stopLoss;
  final List<AutoTradeProtectionLeg> takeProfits;
  final double totalTakeProfitQuantity;
  final double residualQuantity;
  final bool hasResidualDust;
  final DateTime asOf;
  final String? reason;

  AutoTradeProtectionStatus effectiveStatus({required bool stale}) =>
      stale ? AutoTradeProtectionStatus.stale : status;
}

final class AutoTradeSafeException implements Exception {
  const AutoTradeSafeException(this.message, {this.code});

  final String message;
  final Object? code;

  @override
  String toString() => message;
}
