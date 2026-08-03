import 'dart:math' as math;

import 'portfolio_risk_models.dart';

abstract final class PortfolioRiskTransitions {
  static PortfolioRiskLedger applyExchangeConfirmedReduction({
    required PortfolioRiskLedger ledger,
    required String positionId,
    required String eventId,
    required double remainingQuantity,
  }) {
    if (ledger.processedEventIds.contains(eventId)) return ledger;
    if (!remainingQuantity.isFinite || remainingQuantity < 0) {
      throw const FormatException('Confirmed remaining quantity is invalid.');
    }
    var changed = false;
    final next = ledger.reservations.map((item) {
      if (!item.open || item.positionId != positionId) return item;
      if (remainingQuantity > item.filledQuantity + 1e-9) {
        throw const FormatException(
          'Confirmed remaining quantity exceeds the open quantity.',
        );
      }
      changed = true;
      if (remainingQuantity <= 1e-9) {
        return item.copyWith(
          plannedQuantity: 0,
          filledQuantity: 0,
          estimatedEntryFee: 0,
          estimatedExitFee: 0,
          slippageReserve: 0,
          fundingReserve: 0,
          maximumLoss: 0,
          reservedMargin: 0,
          lifecycle: PortfolioReservationLifecycle.closed,
          verification: PortfolioVerificationState.exchangeConfirmed,
          revision: item.revision + 1,
        );
      }
      final fraction = remainingQuantity / item.filledQuantity;
      final entryFee = item.estimatedEntryFee * fraction;
      final exitFee = item.estimatedExitFee * fraction;
      final slippage = item.slippageReserve * fraction;
      final funding = item.fundingReserve * fraction;
      final maximumLoss = PortfolioRiskMath.confirmedOpenRisk(
        side: item.side,
        entryPrice: item.entryPrice,
        confirmedStop: item.currentExchangeConfirmedStop,
        remainingQuantity: remainingQuantity,
        contractMultiplier: item.contractMultiplier,
        entryFee: entryFee,
        exitFee: exitFee,
        slippageReserve: slippage,
        fundingReserve: funding,
      );
      return item.copyWith(
        plannedQuantity: remainingQuantity,
        filledQuantity: remainingQuantity,
        estimatedEntryFee: entryFee,
        estimatedExitFee: exitFee,
        slippageReserve: slippage,
        fundingReserve: funding,
        maximumLoss: maximumLoss,
        reservedMargin: item.reservedMargin * fraction,
        verification: PortfolioVerificationState.exchangeConfirmed,
        revision: item.revision + 1,
      );
    }).toList(growable: false);
    return PortfolioRiskLedger(
      schemaVersion: ledger.schemaVersion,
      revision: changed ? ledger.revision + 1 : ledger.revision,
      tradingDay: ledger.tradingDay,
      dailyRiskLimit: ledger.dailyRiskLimit,
      realizedLoss: ledger.realizedLoss,
      realizedProfit: ledger.realizedProfit,
      reservations: next,
      processedEventIds: {...ledger.processedEventIds, eventId},
    );
  }

  static PortfolioRiskLedger observeExternalUnmanaged({
    required PortfolioRiskLedger ledger,
    required String positionId,
    required String symbol,
    required PortfolioSide side,
    required double quantity,
    required double entryPrice,
    required double observedStop,
    required double conservativeMaximumLoss,
    required double observedMargin,
    required DateTime observedAt,
  }) {
    if ([
          quantity,
          entryPrice,
          observedStop,
          conservativeMaximumLoss,
          observedMargin,
        ].any((value) => !value.isFinite || value < 0) ||
        quantity <= 0 ||
        entryPrice <= 0 ||
        observedStop <= 0 ||
        positionId.trim().isEmpty ||
        symbol.trim().isEmpty) {
      throw const FormatException('External position truth is invalid.');
    }
    if (ledger.reservations.any(
      (item) => item.active && item.positionId == positionId,
    )) {
      return ledger;
    }
    final external = PositionRiskReservation(
      reservationId: 'external-unmanaged:$positionId',
      journalTradeId: 'external-unmanaged:$positionId',
      candidateId: 'external-unmanaged:$positionId',
      symbol: symbol.toUpperCase(),
      assetGroup: 'crypto',
      side: side,
      strategy: 'external-unmanaged-observation',
      entryOrderId: null,
      positionId: positionId,
      plannedQuantity: quantity,
      filledQuantity: quantity,
      entryPrice: entryPrice,
      currentExchangeConfirmedStop: observedStop,
      contractMultiplier: 1,
      estimatedEntryFee: 0,
      estimatedExitFee: 0,
      slippageReserve: 0,
      fundingReserve: 0,
      maximumLoss: math.max(0, conservativeMaximumLoss),
      reservedMargin: observedMargin,
      createdAt: observedAt.toUtc(),
      tradingDayId: ledger.tradingDay.value,
      lifecycle: PortfolioReservationLifecycle.ambiguous,
      verification: PortfolioVerificationState.unverified,
      revision: 1,
    );
    return PortfolioRiskLedger(
      schemaVersion: ledger.schemaVersion,
      revision: ledger.revision + 1,
      tradingDay: ledger.tradingDay,
      dailyRiskLimit: ledger.dailyRiskLimit,
      realizedLoss: ledger.realizedLoss,
      realizedProfit: ledger.realizedProfit,
      reservations: [...ledger.reservations, external],
      processedEventIds: ledger.processedEventIds,
    );
  }
}
