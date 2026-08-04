import '../../owner_alpha/domain/owner_alpha_models.dart';
import '../../portfolio_risk/domain/portfolio_risk_models.dart';
import 'auto_trade_models.dart';

abstract final class LocalLivePortfolioAdmission {
  static const int maximumSupportedConcurrentPositions = 3;
  static const Duration accountFreshnessWindow = Duration(seconds: 45);
  static const double marginSafetyBufferFraction = 0.15;

  static bool hasExecutionSlot({
    required int configuredMaximum,
    required int managedPositionCount,
    required int exchangePositionCount,
  }) {
    if (configuredMaximum < 1 ||
        configuredMaximum > maximumSupportedConcurrentPositions ||
        managedPositionCount < 0 ||
        exchangePositionCount < 0) {
      return false;
    }
    // A mismatch is reconciled elsewhere and must never create a phantom slot.
    if (managedPositionCount != exchangePositionCount) return false;
    return exchangePositionCount < configuredMaximum;
  }

  static PortfolioAccountTruth accountTruth({
    required AutoTradeAccountSnapshot account,
    required DateTime observedAt,
    required bool allOpenPositionsProtected,
    double pendingMarginReservations = 0,
  }) {
    final now = observedAt.toUtc();
    final fresh = !account.syncedAt.toUtc().isAfter(now) &&
        now.difference(account.syncedAt.toUtc()) <= accountFreshnessWindow;
    final isolated = account.positions.every(
      (position) => position.marginMode.toLowerCase() == 'isolated',
    );
    final feeReserve = account.estimatedEquity > 0
        ? account.estimatedEquity * 0.001
        : 0.0;
    final safetyBuffer = account.available > 0
        ? account.available * marginSafetyBufferFraction
        : 0.0;
    return PortfolioAccountTruth(
      asOf: account.syncedAt.toUtc(),
      fresh: fresh,
      allOpenPositionsProtected: allOpenPositionsProtected,
      marginMode: isolated ? 'isolated' : 'mixed',
      freeMargin: account.available,
      usedMargin: account.positionMargin,
      maintenanceMargin: 0,
      pendingMarginReservations: pendingMarginReservations,
      safetyBuffer: safetyBuffer,
      feeReserve: feeReserve,
    );
  }

  static PortfolioEntryCandidate candidate({
    required TradeIdea idea,
    required double plannedQuantity,
    required double entryPrice,
    required double stopPrice,
    required double requiredMargin,
    required int leverage,
    required double minimumQuantity,
    required double minimumNotional,
  }) {
    if (idea.direction == TradeDirection.wait) {
      throw const FormatException('A wait idea cannot reserve portfolio risk.');
    }
    final side = idea.direction == TradeDirection.long
        ? PortfolioSide.long
        : PortfolioSide.short;
    final reservationId = 'local-live:${idea.setupId}';
    return PortfolioEntryCandidate(
      reservationId: reservationId,
      journalTradeId: reservationId,
      candidateId: idea.setupId,
      symbol: idea.symbol,
      assetGroup: assetGroupForSymbol(idea.symbol),
      side: side,
      strategy: '${idea.strategy.name}:${idea.strategyVersion}',
      plannedQuantity: plannedQuantity,
      entryPrice: entryPrice,
      stopPrice: stopPrice,
      contractMultiplier: 1,
      entryFeeRate: 0.0006,
      exitFeeRate: 0.0006,
      slippageRate: 0.0008,
      fundingReserve: entryPrice * plannedQuantity * 0.0003,
      requiredMargin: requiredMargin,
      leverage: leverage,
      minimumQuantity: minimumQuantity,
      minimumNotional: minimumNotional,
    );
  }

  static String assetGroupForSymbol(String symbol) {
    final normalized = symbol.trim().toUpperCase();
    if (normalized.startsWith('XAU') || normalized.startsWith('XAG')) {
      return 'metals';
    }
    if (normalized.startsWith('BTC') || normalized.startsWith('ETH')) {
      return 'crypto-major';
    }
    return 'crypto-alt';
  }
}
