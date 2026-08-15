import '../../decision_core/application/economic_opportunity_ranker.dart';
import '../../decision_core/domain/economic_opportunity_models.dart';
import '../../market_analysis/domain/market_regime_models.dart';
import '../domain/trading_lab_models.dart';

abstract final class TradingLabOpportunityRanking {
  static OpportunityRankingCandidate candidate({
    required TradingLabRun run,
    required TradingLabPendingCandidate pending,
    required double marketPrice,
    OpportunityCalibrationEvidence? calibration,
    OpportunityRankingConfiguration config = const OpportunityRankingConfiguration(),
  }) {
    final referenceEntry = (pending.entryLower + pending.entryUpper) / 2;
    final riskPerUnit = (referenceEntry - pending.stopLoss).abs();
    if (!riskPerUnit.isFinite || riskPerUnit <= 0) {
      throw const FormatException('Trading Lab candidate risk distance is invalid.');
    }
    double rateToR(double rate) => referenceEntry * rate / riskPerUnit;
    final feeR = rateToR(run.manifest.feeRateBps * 2 / 10000);
    final spreadR = rateToR(run.manifest.spreadBps / 10000);
    final slippageR = rateToR(run.manifest.slippageBps * 2 / 10000);
    final latencyR = rateToR(run.manifest.latencyPenaltyBps * 2 / 10000);
    final holdingHours = config.holdingHoursFor(pending.timeframe);
    final fundingWindows = holdingHours / 8;
    final fundingR = rateToR(
      run.manifest.fundingRatePerEightHours.abs() * fundingWindows,
    );
    final riskBudget = run.currentEquity * run.manifest.riskPercent / 100;
    final regime = MarketRegime.values.firstWhere(
      (value) => value.name == pending.marketRegime,
      orElse: () => MarketRegime.transition,
    );
    final relativeVolume = pending.indicatorSnapshot['relativeVolume20'];
    final liquidity = relativeVolume == null || !relativeVolume.isFinite
        ? null
        : (relativeVolume / 2).clamp(0.0, 1.0);
    return OpportunityRankingCandidate(
      setupId: pending.setupId,
      symbol: pending.symbol.trim().toUpperCase(),
      timeframe: pending.timeframe,
      direction: pending.direction,
      strategy: pending.strategy,
      strategyVersion: pending.strategyVersion,
      marketRegime: regime,
      createdAtUtc: pending.observedAtUtc,
      validUntilUtc: pending.validUntilUtc,
      setupQualityScore: pending.confidencePercent,
      riskReward: pending.riskReward,
      riskBudget: riskBudget,
      requiredMargin: null,
      currentPrice: marketPrice,
      entryLower: pending.entryLower,
      entryUpper: pending.entryUpper,
      stopLoss: pending.stopLoss,
      costs: OpportunityExecutionCostEvidence(
        feeR: feeR,
        fundingR: fundingR,
        spreadR: spreadR,
        slippageR: slippageR,
        latencyR: latencyR,
      ),
      expectedHoldingHours: holdingHours,
      liquidityScore: liquidity,
      fillProbability: run.manifest.partialFillRatio,
      tailRiskPenalty: _tailRiskPenalty(regime),
      calibration: calibration,
      evidenceTags: const [
        'execution:trading-lab-manifest',
        'holding:timeframe-prior-v1',
      ],
    );
  }

  static Map<OpportunityRankingPolicy, List<RankedOpportunity>> comparePolicies({
    required TradingLabRun run,
    required Iterable<TradingLabPendingCandidate> pendingCandidates,
    required Map<String, double> marketPrices,
    required DateTime evaluatedAtUtc,
    Map<String, OpportunityCalibrationEvidence> calibrationBySetupId = const {},
    OpportunityRankingConfiguration config = const OpportunityRankingConfiguration(),
  }) {
    final candidates = <OpportunityRankingCandidate>[];
    for (final pending in pendingCandidates) {
      final marketPrice = marketPrices[pending.symbol.trim().toUpperCase()];
      if (marketPrice == null || !marketPrice.isFinite || marketPrice <= 0) {
        continue;
      }
      candidates.add(
        candidate(
          run: run,
          pending: pending,
          marketPrice: marketPrice,
          calibration: calibrationBySetupId[pending.setupId],
          config: config,
        ),
      );
    }
    return Map.unmodifiable({
      for (final policy in OpportunityRankingPolicy.values)
        policy: EconomicOpportunityRanker.rank(
          candidates: candidates,
          evaluatedAtUtc: evaluatedAtUtc,
          policy: policy,
          config: config,
        ),
    });
  }

  static double _tailRiskPenalty(MarketRegime regime) => switch (regime) {
    MarketRegime.directionalTrend => 0.05,
    MarketRegime.range => 0.1,
    MarketRegime.breakoutExpansion => 0.15,
    MarketRegime.transition => 0.35,
    MarketRegime.disorder => 0.7,
  };
}
