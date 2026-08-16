import '../domain/auto_trade_models.dart';
import '../domain/private_truth_models.dart';
import '../domain/trading_pnl_projection.dart';

final class PrivateTruthAccountView {
  const PrivateTruthAccountView({
    required this.snapshot,
    required this.completeForNewEntry,
    required this.missingBaselinePositionIds,
  });

  final AutoTradeAccountSnapshot snapshot;
  final bool completeForNewEntry;
  final List<String> missingBaselinePositionIds;
}

/// Builds the latency-critical current account view from the private WebSocket
/// projection while retaining immutable/forensic fields from the latest REST
/// verification. A hot position that has not yet appeared in REST remains
/// visible for management but blocks further entry until reconciliation.
abstract final class PrivateTruthAccountSnapshotBuilder {
  static PrivateTruthAccountView build({
    required PrivateTruthProjection projection,
    required AutoTradeAccountSnapshot restBaseline,
    TradingPnlProjection? coldPnlProjection,
  }) {
    final baselinePositions = {
      for (final position in restBaseline.positions)
        position.positionId.trim(): position,
    };
    final baselineOrdersById = {
      for (final order in restBaseline.orders)
        if (order.orderId.trim().isNotEmpty) order.orderId.trim(): order,
    };
    final baselineOrdersByClient = {
      for (final order in restBaseline.orders)
        if (order.clientId.trim().isNotEmpty) order.clientId.trim(): order,
    };
    final missingBaselinePositionIds = <String>[];
    final positions = <AutoTradePosition>[];

    for (final hot in projection.positions.values) {
      if (hot.closed) continue;
      final id = hot.positionId.trim();
      final baseline = baselinePositions[id];
      if (baseline == null) missingBaselinePositionIds.add(id);
      final fillPrice = projection.orders.values
          .where(
            (order) =>
                order.symbol.toUpperCase() == hot.symbol.toUpperCase() &&
                order.orderStatus.toUpperCase() == 'FILLED' &&
                order.averagePrice > 0,
          )
          .fold<double>(0, (value, order) => order.averagePrice);
      positions.add(
        AutoTradePosition(
          positionId: id,
          symbol: hot.symbol.toUpperCase(),
          quantity: hot.quantity,
          side: hot.side,
          marginMode: hot.marginMode,
          positionMode: hot.positionMode,
          leverage: hot.leverage,
          margin: hot.margin,
          unrealizedPnl: hot.unrealizedPnl,
          liquidationPrice: baseline?.liquidationPrice ?? 0,
          averageOpenPrice:
              baseline?.averageOpenPrice ?? (fillPrice > 0 ? fillPrice : 0),
          realizedPnl: hot.realizedPnl,
          fee: hot.fee,
          funding: hot.funding,
          openedAt: baseline?.openedAt,
        ),
      );
    }

    final orders = <AutoTradeOrder>[];
    for (final hot in projection.orders.values) {
      if (hot.isTerminal) continue;
      final baseline =
          baselineOrdersById[hot.orderId.trim()] ??
          baselineOrdersByClient[hot.clientId.trim()];
      orders.add(
        AutoTradeOrder(
          orderId: hot.orderId,
          clientId: hot.clientId,
          symbol: hot.symbol.toUpperCase(),
          quantity: hot.quantity,
          filledQuantity: hot.dealAmount,
          side: hot.side,
          orderType: hot.orderType,
          marginMode: baseline?.marginMode ?? 'UNKNOWN',
          leverage: baseline?.leverage ?? 0,
          reduceOnly: baseline?.reduceOnly ?? false,
        ),
      );
    }

    final protectionOrders = projection.protections.values
        .where((item) => !item.isTerminal)
        .map(
          (item) => AutoTradeProtectionOrder(
            exchangeId: item.orderId,
            positionId: item.positionId,
            symbol: item.symbol.toUpperCase(),
            takeProfitPrice: item.takeProfitPrice,
            takeProfitQuantity: item.takeProfitQuantity,
            stopLossPrice: item.stopLossPrice,
            stopLossQuantity: item.stopLossQuantity,
          ),
        )
        .toList(growable: false);

    final verificationAt =
        projection.restVerifiedAtUtc ?? projection.updatedAtUtc;
    final protectionVerifications = <String, AutoTradeProtectionVerification>{};
    for (final position in positions) {
      final baseline =
          restBaseline.protectionVerifications[position.positionId];
      protectionVerifications[position.positionId] =
          baseline ??
          AutoTradeProtectionVerification.unverified(
            asOf: verificationAt,
            reason:
                'Position has not completed a bounded REST protection verification.',
          );
    }

    final marginCoin = restBaseline.marginCoin.toUpperCase();
    final balance = projection.balances[marginCoin];
    var crossUnrealizedPnl = 0.0;
    var isolatedUnrealizedPnl = 0.0;
    var positionMargin = 0.0;
    for (final position in positions) {
      positionMargin += position.margin;
      if (position.marginMode.toUpperCase().contains('CROSS')) {
        crossUnrealizedPnl += position.unrealizedPnl;
      } else {
        isolatedUnrealizedPnl += position.unrealizedPnl;
      }
    }
    if (positionMargin <= 0) {
      positionMargin = balance?.margin ?? restBaseline.positionMargin;
    }

    final snapshot = AutoTradeAccountSnapshot(
      marginCoin: marginCoin,
      available: balance?.available ?? restBaseline.available,
      frozen: balance?.frozen ?? restBaseline.frozen,
      positionMargin: positionMargin,
      crossUnrealizedPnl: crossUnrealizedPnl,
      isolatedUnrealizedPnl: isolatedUnrealizedPnl,
      positionMode: restBaseline.positionMode,
      positions: List.unmodifiable(positions),
      orders: List.unmodifiable(orders),
      protectionOrders: List.unmodifiable(protectionOrders),
      protectionVerifications: Map.unmodifiable(protectionVerifications),
      pnlProjection: coldPnlProjection ?? restBaseline.pnlProjection,
      syncedAt: projection.updatedAtUtc.toUtc(),
    );

    return PrivateTruthAccountView(
      snapshot: snapshot,
      completeForNewEntry:
          projection.canAdmitNewEntries && missingBaselinePositionIds.isEmpty,
      missingBaselinePositionIds: List.unmodifiable(missingBaselinePositionIds),
    );
  }
}
