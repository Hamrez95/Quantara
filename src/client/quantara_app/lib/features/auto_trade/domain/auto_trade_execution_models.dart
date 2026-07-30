import 'auto_trade_models.dart';

enum AutoTradeOperatingMode {
  readOnly,
  shadow,
  manualApproval,
  liveCanary,
  restrictedAuto,
  paused,
  circuitBreaker,
}

enum AutoTradeDirection { long, short }

enum AutoTradePlanStatus { shadow, awaitingApproval }

enum AutoTradeRejectionCode {
  unsupportedMode,
  circuitBreaker,
  staleSignal,
  expiredSignal,
  staleAccount,
  unhealthyPrivateStream,
  symbolDisabled,
  timeframeDisabled,
  strategyDisabled,
  notPrimarySetup,
  timeframeConflict,
  existingExposure,
  tooManyPositions,
  dailyLossLimit,
  symbolClosed,
  apiTradingUnsupported,
  excessiveSlippage,
  invalidPrices,
  invalidRisk,
  quantityBelowMinimum,
  quantityAboveMaximum,
  insufficientAvailableMargin,
  totalMarginLimit,
}

final class AutoTradeExecutionLimits {
  const AutoTradeExecutionLimits({
    required this.riskPercent,
    required this.defaultLeverage,
    required this.maximumConcurrentPositions,
    required this.maximumMarginUsagePercent,
    required this.maximumDailyLossPercent,
    required this.maximumSlippageBps,
    required this.maximumSignalAge,
    required this.allowedSymbols,
    required this.allowedTimeframes,
    required this.allowedStrategies,
    this.marginBufferPercent = 5,
  });

  final double riskPercent;
  final int defaultLeverage;
  final int maximumConcurrentPositions;
  final double maximumMarginUsagePercent;
  final double maximumDailyLossPercent;
  final double maximumSlippageBps;
  final Duration maximumSignalAge;
  final Set<String> allowedSymbols;
  final Set<String> allowedTimeframes;
  final Set<String> allowedStrategies;
  final double marginBufferPercent;
}

final class AutoTradeSignalCandidate {
  const AutoTradeSignalCandidate({
    required this.setupId,
    required this.symbol,
    required this.timeframe,
    required this.strategyVersion,
    required this.direction,
    required this.entryPrice,
    required this.stopLoss,
    required this.targets,
    required this.createdAt,
    required this.validUntil,
    required this.marketDataAt,
    required this.primarySetup,
    required this.timeframeConflict,
    required this.estimatedRoundTripFeeRate,
    required this.estimatedSlippageBps,
  });

  final String setupId;
  final String symbol;
  final String timeframe;
  final String strategyVersion;
  final AutoTradeDirection direction;
  final double entryPrice;
  final double stopLoss;
  final List<double> targets;
  final DateTime createdAt;
  final DateTime validUntil;
  final DateTime marketDataAt;
  final bool primarySetup;
  final bool timeframeConflict;
  final double estimatedRoundTripFeeRate;
  final double estimatedSlippageBps;
}

final class AutoTradeInstrumentRules {
  const AutoTradeInstrumentRules({
    required this.symbol,
    required this.tickSize,
    required this.stepSize,
    required this.minimumQuantity,
    required this.maximumQuantity,
    required this.maximumLeverage,
    required this.tradable,
    required this.apiTradingSupported,
  });

  final String symbol;
  final double tickSize;
  final double stepSize;
  final double minimumQuantity;
  final double maximumQuantity;
  final int maximumLeverage;
  final bool tradable;
  final bool apiTradingSupported;
}

final class AutoTradePlanningContext {
  const AutoTradePlanningContext({
    required this.mode,
    required this.account,
    required this.instrument,
    required this.limits,
    required this.now,
    required this.currentDailyLossPercent,
    required this.privateStreamHealthy,
  });

  final AutoTradeOperatingMode mode;
  final AutoTradeAccountSnapshot account;
  final AutoTradeInstrumentRules instrument;
  final AutoTradeExecutionLimits limits;
  final DateTime now;
  final double currentDailyLossPercent;
  final bool privateStreamHealthy;
}

final class AutoTradeOrderPlan {
  const AutoTradeOrderPlan({
    required this.clientId,
    required this.setupId,
    required this.status,
    required this.symbol,
    required this.direction,
    required this.leverage,
    required this.quantity,
    required this.entryPrice,
    required this.stopLoss,
    required this.targets,
    required this.riskBudget,
    required this.riskPerUnit,
    required this.notional,
    required this.requiredMargin,
    required this.maximumLoss,
    required this.estimatedFees,
    required this.estimatedSlippage,
    required this.createdAt,
    required this.expiresAt,
  });

  final String clientId;
  final String setupId;
  final AutoTradePlanStatus status;
  final String symbol;
  final AutoTradeDirection direction;
  final int leverage;
  final double quantity;
  final double entryPrice;
  final double stopLoss;
  final List<double> targets;
  final double riskBudget;
  final double riskPerUnit;
  final double notional;
  final double requiredMargin;
  final double maximumLoss;
  final double estimatedFees;
  final double estimatedSlippage;
  final DateTime createdAt;
  final DateTime expiresAt;

  bool get requiresManualApproval =>
      status == AutoTradePlanStatus.awaitingApproval;

  bool get isolatedMargin => true;
}

final class AutoTradePlanningResult {
  const AutoTradePlanningResult._({required this.plan, required this.rejections});

  factory AutoTradePlanningResult.accepted(AutoTradeOrderPlan plan) =>
      AutoTradePlanningResult._(
        plan: plan,
        rejections: const <AutoTradeRejectionCode>[],
      );

  factory AutoTradePlanningResult.rejected(
    Iterable<AutoTradeRejectionCode> rejections,
  ) => AutoTradePlanningResult._(
    plan: null,
    rejections: List.unmodifiable(rejections.toSet()),
  );

  final AutoTradeOrderPlan? plan;
  final List<AutoTradeRejectionCode> rejections;

  bool get accepted => plan != null && rejections.isEmpty;
}
