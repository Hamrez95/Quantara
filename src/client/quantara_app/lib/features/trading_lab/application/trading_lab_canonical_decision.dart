import '../../decision_core/application/canonical_decision_pipeline.dart';
import '../../decision_core/domain/canonical_decision_models.dart';
import '../domain/trading_lab_models.dart';

CanonicalDecisionRecord evaluateTradingLabCanonicalDecision({
  required DecisionEnvironment environment,
  required TradingLabRun run,
  required TradingLabPendingCandidate candidate,
  required DateTime eventTimeUtc,
  required double marketPrice,
  required double availableMargin,
  required double openRisk,
  required double symbolRisk,
}) {
  if (environment == DecisionEnvironment.live) {
    throw ArgumentError(
      'Trading Lab adapters cannot request live execution authority.',
    );
  }
  final manifest = run.manifest;
  final plan = CanonicalOpportunityPlan(
    setupId: candidate.setupId,
    symbol: candidate.symbol,
    timeframe: candidate.timeframe,
    direction: candidate.direction,
    strategy: candidate.strategy,
    strategyVersion: candidate.strategyVersion,
    createdAtUtc: candidate.observedAtUtc,
    validUntilUtc: candidate.validUntilUtc,
    entryLower: candidate.entryLower,
    entryUpper: candidate.entryUpper,
    stopLoss: candidate.stopLoss,
    targets: candidate.targets,
    maximumSafeLeverage: candidate.maximumSafeLeverage,
    riskReward: candidate.riskReward,
    reasonCodes: [
      'marketRegime:${candidate.marketRegime}',
      'source:trading-lab-pending-candidate',
    ],
  );
  final economics = CanonicalExecutionEconomics(
    feeRateBpsPerSide: manifest.feeRateBps,
    spreadBpsRoundTrip: manifest.spreadBps,
    slippageBpsPerSide:
        manifest.slippageBps + manifest.latencyPenaltyBps,
    fundingReserveBps: 0,
    marginSafetyBufferMultiplier: 1,
    maximumCostToRiskPercent: manifest.maxEstimatedCostToRiskPercent,
    version: 'trading-lab-${manifest.executionModel.name}/1.1',
  );
  return CanonicalDecisionPipeline.evaluate(
    CanonicalDecisionInput(
      plan: plan,
      provenance: CanonicalDecisionProvenance(
        environment: environment,
        eventTimeUtc: eventTimeUtc.toUtc(),
        marketDatasetSource: 'trading-lab-owner-alpha-snapshot',
        marketDatasetVersion: manifest.engineVersion,
        strategyConfigId: [
          manifest.engineVersion,
          candidate.strategy,
          candidate.strategyVersion,
          manifest.riskPercent,
          manifest.leverage,
          manifest.executionModel.name,
          manifest.feeRateBps,
          manifest.spreadBps,
          manifest.slippageBps,
          manifest.latencyPenaltyBps,
          manifest.partialFillRatio,
        ].join('|'),
        sourceBuild: const String.fromEnvironment(
          'QUANTARA_BUILD_SHA',
          defaultValue: 'unknown',
        ),
        versions: CanonicalDecisionVersions(executionModel: economics.version),
      ),
      marketPrice: marketPrice,
      equity: run.currentEquity,
      availableMargin: availableMargin,
      riskPercent: manifest.riskPercent,
      requestedLeverage: manifest.leverage,
      instrumentRules: CanonicalInstrumentRules.synthetic(),
      economics: economics,
      portfolio: CanonicalPortfolioContext(
        openRisk: openRisk,
        portfolioRiskLimit:
            run.currentEquity * manifest.portfolioRiskPercent / 100,
        symbolRisk: symbolRisk,
        symbolHeatLimit: run.currentEquity * manifest.symbolHeatPercent / 100,
      ),
    ),
  );
}
