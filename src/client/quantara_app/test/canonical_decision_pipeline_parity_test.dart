import 'package:flutter_test/flutter_test.dart';
import 'package:quantara_app/features/decision_core/application/canonical_decision_pipeline.dart';
import 'package:quantara_app/features/decision_core/domain/canonical_decision_models.dart';
import 'package:quantara_app/features/market_analysis/domain/market_regime_models.dart';
import 'package:quantara_app/features/owner_alpha/domain/owner_alpha_models.dart';

void main() {
  final eventTime = DateTime.utc(2026, 8, 15, 8);
  final idea = TradeIdea(
    symbol: 'BTCUSDT',
    timeframe: '1h',
    direction: TradeDirection.long,
    confidencePercent: 78,
    entryLower: 99,
    entryUpper: 101,
    stopLoss: 95,
    targets: const [108, 112, 116],
    riskReward: 1.8,
    maximumLoss: 10,
    positionSize: 2,
    notionalValue: 200,
    recommendedLeverage: 10,
    maximumSafeLeverage: 12,
    requiredMargin: 20,
    estimatedRoundTripCosts: 0.34,
    setupId: 'btc-1h-pullback-001',
    candleClosedAt: eventTime.subtract(const Duration(minutes: 30)),
    summary: 'fixture',
    invalidation: 'fixture stop',
    reasons: const ['closed-candle-fixture'],
    strategy: AnalysisStrategy.trendPullback,
    strategyVersion: 'trend-pullback/2.0',
    marketRegime: MarketRegime.directionalTrend,
  );
  const rules = CanonicalInstrumentRules(
    open: true,
    apiSupported: true,
    pricePrecision: 2,
    quantityPrecision: 3,
    minimumQuantity: 0.001,
    maximumMarketQuantity: 1000,
    minimumNotional: 5,
    minimumLeverage: 1,
    maximumLeverage: 20,
  );
  const economics = CanonicalExecutionEconomics(
    feeRateBpsPerSide: 6,
    spreadBpsRoundTrip: 1,
    slippageBpsPerSide: 2,
    fundingReserveBps: 0,
    marginSafetyBufferMultiplier: 1.15,
    maximumCostToRiskPercent: 25,
  );
  const portfolio = CanonicalPortfolioContext(
    openRisk: 8,
    portfolioRiskLimit: 50,
    symbolRisk: 2,
    symbolHeatLimit: 25,
  );

  CanonicalDecisionRecord evaluate(DecisionEnvironment environment) {
    return CanonicalDecisionPipeline.evaluate(
      CanonicalDecisionInput(
        plan: CanonicalOpportunityPlan.fromTradeIdea(idea),
        provenance: CanonicalDecisionProvenance(
          environment: environment,
          eventTimeUtc: eventTime,
          marketDatasetSource: 'captured-bitunix-public',
          marketDatasetVersion: 'fixture-2026-08-15-a',
          strategyConfigId: 'golden-config-001',
          sourceBuild: 'fixture-build-sha',
        ),
        marketPrice: 100,
        equity: 1000,
        availableMargin: 500,
        riskPercent: 1,
        requestedLeverage: 10,
        instrumentRules: rules,
        economics: economics,
        portfolio: portfolio,
      ),
    );
  }

  test('replay shadow paper and live share identical pre-execution decision', () {
    final records = DecisionEnvironment.values.map(evaluate).toList();

    expect(records.every((record) => record.eligible), isTrue);
    final expected = records.first.parityJson();
    final fingerprint = records.first.preExecutionFingerprint;
    for (final record in records.skip(1)) {
      expect(record.parityJson(), equals(expected));
      expect(record.preExecutionFingerprint, fingerprint);
    }
    expect(
      records.map((record) => record.provenance.environment).toSet(),
      DecisionEnvironment.values.toSet(),
    );
  });

  test('closed-candle event time is a hard parity gate', () {
    final plan = CanonicalOpportunityPlan.fromTradeIdea(idea);
    final record = CanonicalDecisionPipeline.evaluate(
      CanonicalDecisionInput(
        plan: plan,
        provenance: CanonicalDecisionProvenance(
          environment: DecisionEnvironment.replay,
          eventTimeUtc: plan.createdAtUtc.subtract(const Duration(seconds: 1)),
          marketDatasetSource: 'fixture',
          marketDatasetVersion: 'v1',
          strategyConfigId: 'cfg',
          sourceBuild: 'sha',
        ),
        marketPrice: 100,
        equity: 1000,
        availableMargin: 500,
        riskPercent: 1,
        requestedLeverage: 10,
        instrumentRules: rules,
        economics: economics,
      ),
    );

    expect(record.eligible, isFalse);
    expect(record.rejection, CanonicalDecisionRejection.evidenceNotClosed);
  });

  test('wrong-side stop after exchange normalization fails closed', () {
    final badIdea = TradeIdea(
      symbol: 'BTCUSDT',
      timeframe: '1h',
      direction: TradeDirection.long,
      confidencePercent: 80,
      entryLower: 99.99,
      entryUpper: 100.01,
      stopLoss: 100.001,
      targets: const [101, 102, 103],
      riskReward: 1.8,
      maximumLoss: 10,
      positionSize: 1,
      notionalValue: 100,
      recommendedLeverage: 5,
      maximumSafeLeverage: 10,
      requiredMargin: 20,
      estimatedRoundTripCosts: 0.2,
      setupId: 'wrong-stop',
      candleClosedAt: eventTime.subtract(const Duration(minutes: 10)),
      summary: 'fixture',
      invalidation: 'fixture',
      reasons: const [],
      marketRegime: MarketRegime.directionalTrend,
    );
    final record = CanonicalDecisionPipeline.evaluate(
      CanonicalDecisionInput(
        plan: CanonicalOpportunityPlan.fromTradeIdea(badIdea),
        provenance: CanonicalDecisionProvenance(
          environment: DecisionEnvironment.live,
          eventTimeUtc: eventTime,
          marketDatasetSource: 'fixture',
          marketDatasetVersion: 'v1',
          strategyConfigId: 'cfg',
          sourceBuild: 'sha',
        ),
        marketPrice: 100,
        equity: 1000,
        availableMargin: 500,
        riskPercent: 1,
        requestedLeverage: 5,
        instrumentRules: rules,
        economics: economics,
      ),
    );

    expect(record.eligible, isFalse);
    expect(record.rejection, CanonicalDecisionRejection.wrongSideStop);
  });

  test('confirmed live economics stay separate from simulated estimates', () {
    final record = evaluate(DecisionEnvironment.live);
    final estimated = record.estimatedRoundTripCosts;
    final confirmed = ConfirmedExecutionEconomics(
      orderId: 'order-1',
      positionId: 'position-1',
      confirmedAtUtc: eventTime.add(const Duration(seconds: 2)),
      averageFillPrice: 100.07,
      filledQuantity: record.quantity,
      fees: 0.19,
      funding: 0.01,
      realizedSlippage: 0.07,
    );

    expect(confirmed.toJson()['fees'], 0.19);
    expect(record.estimatedRoundTripCosts, estimated);
    expect(record.toJson().containsKey('confirmedEconomics'), isFalse);
  });
}
