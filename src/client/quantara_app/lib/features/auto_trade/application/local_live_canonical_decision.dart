import '../../decision_core/application/canonical_decision_pipeline.dart';
import '../../decision_core/domain/canonical_decision_models.dart';
import '../../owner_alpha/domain/owner_alpha_models.dart';
import '../data/bitunix_local_live_api_client.dart';
import '../domain/auto_trade_models.dart';
import '../domain/local_live_trade_models.dart';

CanonicalDecisionRecord evaluateLocalLiveCanonicalDecision({
  required TradeIdea idea,
  required LocalLiveTradeConfiguration configuration,
  required AutoTradeAccountSnapshot account,
  required BitunixInstrumentRules rules,
  required double markPrice,
  required DateTime eventTimeUtc,
  required bool alreadyExecuted,
  required bool symbolOccupied,
  LocalLivePortfolioBudgetStatus? portfolioBudget,
}) {
  final minimumNotional = rules.minimumQuantity * markPrice;
  final economics = const CanonicalExecutionEconomics(
    feeRateBpsPerSide: 6,
    spreadBpsRoundTrip: 1,
    slippageBpsPerSide: 2,
    fundingReserveBps: 0,
    marginSafetyBufferMultiplier: 1.15,
    maximumCostToRiskPercent: 25,
    version: 'bitunix-live-conservative/1.0',
  );
  final portfolioOpenRisk = portfolioBudget == null
      ? 0.0
      : portfolioBudget.openRisk +
            portfolioBudget.pendingRisk +
            portfolioBudget.ambiguousRisk;
  final portfolioRiskLimit = portfolioBudget?.riskLimit ?? double.infinity;
  final configId = [
    configuration.enabledStrategies.map((item) => item.name).join(','),
    configuration.timeframes.join(','),
    configuration.cadence.name,
    configuration.riskPercent,
    configuration.leverage,
    configuration.maximumConcurrentPositions,
  ].join('|');
  return CanonicalDecisionPipeline.evaluate(
    CanonicalDecisionInput(
      plan: CanonicalOpportunityPlan.fromTradeIdea(idea),
      provenance: CanonicalDecisionProvenance(
        environment: DecisionEnvironment.live,
        eventTimeUtc: eventTimeUtc.toUtc(),
        marketDatasetSource: 'bitunix-futures-public',
        marketDatasetVersion: 'realtime-v1',
        strategyConfigId: configId,
        sourceBuild: const String.fromEnvironment(
          'QUANTARA_BUILD_SHA',
          defaultValue: 'unknown',
        ),
        versions: CanonicalDecisionVersions(executionModel: economics.version),
      ),
      marketPrice: markPrice,
      equity: account.estimatedEquity,
      availableMargin: account.available,
      riskPercent: configuration.riskPercent,
      requestedLeverage: configuration.leverage,
      instrumentRules: CanonicalInstrumentRules(
        open: rules.open,
        apiSupported: rules.apiSupported,
        pricePrecision: rules.pricePrecision,
        quantityPrecision: rules.quantityPrecision,
        minimumQuantity: rules.minimumQuantity,
        maximumMarketQuantity: rules.maximumMarketQuantity,
        minimumNotional: minimumNotional,
        minimumLeverage: rules.minimumLeverage,
        maximumLeverage: rules.maximumLeverage,
      ),
      economics: economics,
      portfolio: CanonicalPortfolioContext(
        openRisk: portfolioOpenRisk,
        portfolioRiskLimit: portfolioRiskLimit,
      ),
      alreadyExecuted: alreadyExecuted,
      symbolOccupied: symbolOccupied,
    ),
  );
}
