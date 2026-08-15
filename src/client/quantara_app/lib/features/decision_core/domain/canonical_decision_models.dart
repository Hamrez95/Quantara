import 'dart:collection';

import '../../owner_alpha/domain/owner_alpha_models.dart';

enum DecisionEnvironment { replay, shadow, paper, live }

enum CanonicalDecisionDisposition { rejected, eligible }

enum CanonicalDecisionRejection {
  none,
  nonActionable,
  evidenceNotClosed,
  expired,
  incompletePlan,
  alreadyExecuted,
  symbolOccupied,
  invalidMarketPrice,
  invalidInstrumentRules,
  marketClosed,
  apiUnsupported,
  markOutsideEntry,
  wrongSideStop,
  quantityBelowMinimum,
  quantityAboveMaximum,
  notionalBelowMinimum,
  insufficientMargin,
  executionCostToRiskTooHigh,
  portfolioRiskLimit,
  symbolHeatLimit,
}

final class CanonicalDecisionVersions {
  const CanonicalDecisionVersions({
    this.pipeline = 'canonical-decision/1.0',
    this.ranking = 'ranking-contract/1.0',
    this.risk = 'risk-contract/1.0',
    this.allocator = 'allocator-contract/1.0',
    this.executionModel = 'execution-economics/1.0',
  });

  final String pipeline;
  final String ranking;
  final String risk;
  final String allocator;
  final String executionModel;

  Map<String, Object?> toJson() => {
    'pipeline': pipeline,
    'ranking': ranking,
    'risk': risk,
    'allocator': allocator,
    'executionModel': executionModel,
  };
}

final class CanonicalDecisionProvenance {
  CanonicalDecisionProvenance({
    required this.environment,
    required this.eventTimeUtc,
    required this.marketDatasetSource,
    required this.marketDatasetVersion,
    required this.strategyConfigId,
    required this.sourceBuild,
    this.seed,
    this.versions = const CanonicalDecisionVersions(),
  }) {
    if (!eventTimeUtc.isUtc ||
        marketDatasetSource.trim().isEmpty ||
        marketDatasetVersion.trim().isEmpty ||
        strategyConfigId.trim().isEmpty ||
        sourceBuild.trim().isEmpty) {
      throw const FormatException('Canonical decision provenance is invalid.');
    }
  }

  final DecisionEnvironment environment;
  final DateTime eventTimeUtc;
  final String marketDatasetSource;
  final String marketDatasetVersion;
  final String strategyConfigId;
  final String sourceBuild;
  final int? seed;
  final CanonicalDecisionVersions versions;

  Map<String, Object?> toJson() => {
    'environment': environment.name,
    'eventTimeUtc': eventTimeUtc.toIso8601String(),
    'marketDatasetSource': marketDatasetSource,
    'marketDatasetVersion': marketDatasetVersion,
    'strategyConfigId': strategyConfigId,
    'sourceBuild': sourceBuild,
    'seed': seed,
    'versions': versions.toJson(),
  };
}

final class CanonicalOpportunityPlan {
  CanonicalOpportunityPlan({
    required this.setupId,
    required this.symbol,
    required this.timeframe,
    required this.direction,
    required this.strategy,
    required this.strategyVersion,
    required this.createdAtUtc,
    required this.validUntilUtc,
    required this.entryLower,
    required this.entryUpper,
    required this.stopLoss,
    required Iterable<double> targets,
    required this.maximumSafeLeverage,
    required this.riskReward,
    Iterable<String> reasonCodes = const [],
  }) : targets = UnmodifiableListView(targets.toList(growable: false)),
       reasonCodes = UnmodifiableListView(reasonCodes.toList(growable: false)) {
    if (setupId.trim().isEmpty ||
        symbol.trim().isEmpty ||
        timeframe.trim().isEmpty ||
        strategy.trim().isEmpty ||
        strategyVersion.trim().isEmpty ||
        !createdAtUtc.isUtc ||
        !validUntilUtc.isUtc) {
      throw const FormatException('Canonical opportunity identity is invalid.');
    }
  }

  factory CanonicalOpportunityPlan.fromTradeIdea(TradeIdea idea) =>
      CanonicalOpportunityPlan(
        setupId: idea.setupId,
        symbol: idea.symbol.trim().toUpperCase(),
        timeframe: idea.timeframe,
        direction: idea.direction,
        strategy: idea.strategy.name,
        strategyVersion: idea.strategyVersion,
        createdAtUtc: idea.createdAt.toUtc(),
        validUntilUtc: idea.validUntil.toUtc(),
        entryLower: idea.entryLower,
        entryUpper: idea.entryUpper,
        stopLoss: idea.stopLoss,
        targets: idea.targets,
        maximumSafeLeverage: idea.maximumSafeLeverage ?? 1,
        riskReward: idea.riskReward,
        reasonCodes: [
          'strategy:${idea.strategy.name}',
          'regime:${idea.marketRegime.name}',
          'rejection:${idea.rejectionReason.name}',
        ],
      );

  final String setupId;
  final String symbol;
  final String timeframe;
  final TradeDirection direction;
  final String strategy;
  final String strategyVersion;
  final DateTime createdAtUtc;
  final DateTime validUntilUtc;
  final double? entryLower;
  final double? entryUpper;
  final double? stopLoss;
  final UnmodifiableListView<double> targets;
  final int maximumSafeLeverage;
  final double? riskReward;
  final UnmodifiableListView<String> reasonCodes;

  bool get isActionable => direction != TradeDirection.wait;

  Map<String, Object?> toJson() => {
    'setupId': setupId,
    'symbol': symbol,
    'timeframe': timeframe,
    'direction': direction.name,
    'strategy': strategy,
    'strategyVersion': strategyVersion,
    'createdAtUtc': createdAtUtc.toIso8601String(),
    'validUntilUtc': validUntilUtc.toIso8601String(),
    'entryLower': entryLower,
    'entryUpper': entryUpper,
    'stopLoss': stopLoss,
    'targets': targets,
    'maximumSafeLeverage': maximumSafeLeverage,
    'riskReward': riskReward,
    'reasonCodes': reasonCodes,
  };
}

final class CanonicalInstrumentRules {
  const CanonicalInstrumentRules({
    required this.open,
    required this.apiSupported,
    required this.pricePrecision,
    required this.quantityPrecision,
    required this.minimumQuantity,
    required this.maximumMarketQuantity,
    required this.minimumNotional,
    required this.minimumLeverage,
    required this.maximumLeverage,
    this.exchangeRulesKnown = true,
  });

  factory CanonicalInstrumentRules.synthetic({
    int pricePrecision = 8,
    int quantityPrecision = 6,
  }) => CanonicalInstrumentRules(
    open: true,
    apiSupported: true,
    pricePrecision: pricePrecision,
    quantityPrecision: quantityPrecision,
    minimumQuantity: 0.000001,
    maximumMarketQuantity: 1000000000,
    minimumNotional: 0.01,
    minimumLeverage: 1,
    maximumLeverage: TradeIdea.maximumManualLeverage,
    exchangeRulesKnown: false,
  );

  final bool open;
  final bool apiSupported;
  final int pricePrecision;
  final int quantityPrecision;
  final double minimumQuantity;
  final double maximumMarketQuantity;
  final double minimumNotional;
  final int minimumLeverage;
  final int maximumLeverage;
  final bool exchangeRulesKnown;

  bool get isValid =>
      pricePrecision >= 0 &&
      pricePrecision <= 12 &&
      quantityPrecision >= 0 &&
      quantityPrecision <= 12 &&
      minimumQuantity.isFinite &&
      minimumQuantity > 0 &&
      maximumMarketQuantity.isFinite &&
      maximumMarketQuantity >= minimumQuantity &&
      minimumNotional.isFinite &&
      minimumNotional >= 0 &&
      minimumLeverage >= 1 &&
      maximumLeverage >= minimumLeverage;
}

final class CanonicalExecutionEconomics {
  const CanonicalExecutionEconomics({
    this.feeRateBpsPerSide = 6,
    this.spreadBpsRoundTrip = 1,
    this.slippageBpsPerSide = 2,
    this.fundingReserveBps = 0,
    this.orderLatencyMilliseconds = 0,
    this.marginSafetyBufferMultiplier = 1.15,
    this.maximumCostToRiskPercent = 25,
    this.version = 'execution-economics/1.0',
  });

  final double feeRateBpsPerSide;
  final double spreadBpsRoundTrip;
  final double slippageBpsPerSide;
  final double fundingReserveBps;
  final int orderLatencyMilliseconds;
  final double marginSafetyBufferMultiplier;
  final double maximumCostToRiskPercent;
  final String version;

  double get estimatedRoundTripRate =>
      (feeRateBpsPerSide * 2 +
          spreadBpsRoundTrip +
          slippageBpsPerSide * 2 +
          fundingReserveBps) /
      10000;

  bool get isValid =>
      [
        feeRateBpsPerSide,
        spreadBpsRoundTrip,
        slippageBpsPerSide,
        fundingReserveBps,
      ].every((value) => value.isFinite && value >= 0 && value <= 500) &&
      orderLatencyMilliseconds >= 0 &&
      marginSafetyBufferMultiplier.isFinite &&
      marginSafetyBufferMultiplier >= 1 &&
      marginSafetyBufferMultiplier <= 3 &&
      maximumCostToRiskPercent.isFinite &&
      maximumCostToRiskPercent >= 0 &&
      maximumCostToRiskPercent <= 200 &&
      version.trim().isNotEmpty;

  Map<String, Object?> toJson() => {
    'feeRateBpsPerSide': feeRateBpsPerSide,
    'spreadBpsRoundTrip': spreadBpsRoundTrip,
    'slippageBpsPerSide': slippageBpsPerSide,
    'fundingReserveBps': fundingReserveBps,
    'orderLatencyMilliseconds': orderLatencyMilliseconds,
    'marginSafetyBufferMultiplier': marginSafetyBufferMultiplier,
    'maximumCostToRiskPercent': maximumCostToRiskPercent,
    'version': version,
  };
}

final class CanonicalPortfolioContext {
  const CanonicalPortfolioContext({
    this.openRisk = 0,
    this.portfolioRiskLimit = double.infinity,
    this.symbolRisk = 0,
    this.symbolHeatLimit = double.infinity,
  });

  final double openRisk;
  final double portfolioRiskLimit;
  final double symbolRisk;
  final double symbolHeatLimit;

  bool get isValid =>
      openRisk.isFinite &&
      openRisk >= 0 &&
      !portfolioRiskLimit.isNaN &&
      portfolioRiskLimit >= 0 &&
      symbolRisk.isFinite &&
      symbolRisk >= 0 &&
      !symbolHeatLimit.isNaN &&
      symbolHeatLimit >= 0;
}

final class CanonicalDecisionInput {
  const CanonicalDecisionInput({
    required this.plan,
    required this.provenance,
    required this.marketPrice,
    required this.equity,
    required this.availableMargin,
    required this.riskPercent,
    required this.requestedLeverage,
    required this.instrumentRules,
    required this.economics,
    this.portfolio = const CanonicalPortfolioContext(),
    this.alreadyExecuted = false,
    this.symbolOccupied = false,
  });

  final CanonicalOpportunityPlan plan;
  final CanonicalDecisionProvenance provenance;
  final double marketPrice;
  final double equity;
  final double availableMargin;
  final double riskPercent;
  final int requestedLeverage;
  final CanonicalInstrumentRules instrumentRules;
  final CanonicalExecutionEconomics economics;
  final CanonicalPortfolioContext portfolio;
  final bool alreadyExecuted;
  final bool symbolOccupied;
}

final class CanonicalDecisionRecord {
  CanonicalDecisionRecord({
    required this.disposition,
    required this.rejection,
    required this.decisionKey,
    required this.preExecutionFingerprint,
    required this.plan,
    required this.provenance,
    required this.instrumentRulesKnown,
    required this.referenceEntry,
    required this.normalizedEntry,
    required this.normalizedStop,
    required this.quantity,
    required this.notional,
    required this.leverage,
    required this.requiredMargin,
    required this.bufferedMarginRequirement,
    required this.riskBudget,
    required this.plannedRisk,
    required this.riskPerUnit,
    required this.estimatedRoundTripCosts,
    required this.executionCostToRiskPercent,
    required this.portfolioRiskAfter,
    required this.symbolRiskAfter,
    required this.economics,
    Iterable<String> reasonCodes = const [],
  }) : reasonCodes = UnmodifiableListView(reasonCodes.toList(growable: false));

  final CanonicalDecisionDisposition disposition;
  final CanonicalDecisionRejection rejection;
  final String decisionKey;
  final String preExecutionFingerprint;
  final CanonicalOpportunityPlan plan;
  final CanonicalDecisionProvenance provenance;
  final bool instrumentRulesKnown;
  final double referenceEntry;
  final double normalizedEntry;
  final double normalizedStop;
  final double quantity;
  final double notional;
  final int leverage;
  final double requiredMargin;
  final double bufferedMarginRequirement;
  final double riskBudget;
  final double plannedRisk;
  final double riskPerUnit;
  final double estimatedRoundTripCosts;
  final double executionCostToRiskPercent;
  final double portfolioRiskAfter;
  final double symbolRiskAfter;
  final CanonicalExecutionEconomics economics;
  final UnmodifiableListView<String> reasonCodes;

  bool get eligible => disposition == CanonicalDecisionDisposition.eligible;

  Map<String, Object?> parityJson() => {
    'disposition': disposition.name,
    'rejection': rejection.name,
    'decisionKey': decisionKey,
    'preExecutionFingerprint': preExecutionFingerprint,
    'plan': plan.toJson(),
    'instrumentRulesKnown': instrumentRulesKnown,
    'referenceEntry': referenceEntry,
    'normalizedEntry': normalizedEntry,
    'normalizedStop': normalizedStop,
    'quantity': quantity,
    'notional': notional,
    'leverage': leverage,
    'requiredMargin': requiredMargin,
    'bufferedMarginRequirement': bufferedMarginRequirement,
    'riskBudget': riskBudget,
    'plannedRisk': plannedRisk,
    'riskPerUnit': riskPerUnit,
    'estimatedRoundTripCosts': estimatedRoundTripCosts,
    'executionCostToRiskPercent': executionCostToRiskPercent,
    'portfolioRiskAfter': portfolioRiskAfter,
    'symbolRiskAfter': symbolRiskAfter,
    'economics': economics.toJson(),
    'reasonCodes': reasonCodes,
  };

  Map<String, Object?> toJson() => {
    ...parityJson(),
    'provenance': provenance.toJson(),
  };
}

final class ConfirmedExecutionEconomics {
  ConfirmedExecutionEconomics({
    required this.orderId,
    required this.positionId,
    required this.confirmedAtUtc,
    required this.averageFillPrice,
    required this.filledQuantity,
    required this.fees,
    required this.funding,
    required this.realizedSlippage,
  }) {
    if (orderId.trim().isEmpty ||
        positionId.trim().isEmpty ||
        !confirmedAtUtc.isUtc ||
        averageFillPrice <= 0 ||
        filledQuantity <= 0) {
      throw const FormatException('Confirmed execution economics are invalid.');
    }
  }

  final String orderId;
  final String positionId;
  final DateTime confirmedAtUtc;
  final double averageFillPrice;
  final double filledQuantity;
  final double fees;
  final double funding;
  final double realizedSlippage;

  Map<String, Object?> toJson() => {
    'orderId': orderId,
    'positionId': positionId,
    'confirmedAtUtc': confirmedAtUtc.toIso8601String(),
    'averageFillPrice': averageFillPrice,
    'filledQuantity': filledQuantity,
    'fees': fees,
    'funding': funding,
    'realizedSlippage': realizedSlippage,
  };
}
