import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:quantara_app/features/decision_core/domain/economic_opportunity_models.dart';
import 'package:quantara_app/features/owner_alpha/domain/owner_alpha_models.dart';
import 'package:quantara_app/features/trading_lab/application/trading_lab_opportunity_ranking.dart';
import 'package:quantara_app/features/trading_lab/domain/trading_lab_models.dart';

void main() {
  final now = DateTime.utc(2026, 8, 15, 12);

  TradingLabRun run({
    double fee = 6,
    double spread = 1,
    double slippage = 2,
    double funding = 0.0001,
    double latency = 3,
    double partialFill = 0.8,
  }) => TradingLabRun(
    manifest: TradingLabRunManifest(
      runId: 'ranking-lab',
      startedAtUtc: now.subtract(const Duration(days: 1)),
      startingEquity: 500,
      riskPercent: 1,
      maximumConcurrentPositions: 3,
      leverage: 5,
      symbols: const ['BTCUSDT', 'ETHUSDT'],
      timeframes: const ['1h'],
      strategies: const ['trendPullback@v1'],
      feeRateBps: fee,
      spreadBps: spread,
      slippageBps: slippage,
      fundingRatePerEightHours: funding,
      latencyPenaltyBps: latency,
      partialFillRatio: partialFill,
    ),
  );

  TradingLabPendingCandidate pending({
    required String id,
    required String symbol,
    int quality = 80,
    double rr = 2,
  }) => TradingLabPendingCandidate(
    decisionKey: 'decision-$id',
    setupId: id,
    symbol: symbol,
    timeframe: '1h',
    direction: TradeDirection.long,
    strategy: 'trendPullback',
    strategyVersion: 'trendPullback/1.0',
    marketRegime: 'directionalTrend',
    confidencePercent: quality,
    riskReward: rr,
    entryLower: 99.5,
    entryUpper: 100.5,
    stopLoss: 97,
    targets: const [102, 104, 106],
    recommendedLeverage: 3,
    maximumSafeLeverage: 5,
    observedAtUtc: now.subtract(const Duration(minutes: 20)),
    validUntilUtc: now.add(const Duration(hours: 2)),
    signalCandleOpenTimeUtc: now.subtract(const Duration(hours: 1)),
    indicatorSnapshot: const {'relativeVolume20': 1.6},
  );

  test('same event set is comparable under all ranking policies', () {
    final policies = TradingLabOpportunityRanking.comparePolicies(
      run: run(),
      pendingCandidates: [
        pending(id: 'btc', symbol: 'BTCUSDT', quality: 85),
        pending(id: 'eth', symbol: 'ETHUSDT', quality: 82),
      ],
      marketPrices: const {'BTCUSDT': 100, 'ETHUSDT': 100},
      evaluatedAtUtc: now,
    );

    expect(policies.keys.toSet(), OpportunityRankingPolicy.values.toSet());
    for (final ranked in policies.values) {
      expect(ranked.length, 2);
      expect(ranked.map((item) => item.candidate.setupId).toSet(), {
        'btc',
        'eth',
      });
    }
  });

  test(
    'Trading Lab expands fee funding spread slippage and latency separately',
    () {
      final rankedCandidate = TradingLabOpportunityRanking.candidate(
        run: run(),
        pending: pending(id: 'btc', symbol: 'BTCUSDT'),
        marketPrice: 100,
      );

      expect(rankedCandidate.costs.feeR, greaterThan(0));
      expect(rankedCandidate.costs.fundingR, greaterThan(0));
      expect(rankedCandidate.costs.spreadR, greaterThan(0));
      expect(rankedCandidate.costs.slippageR, greaterThan(0));
      expect(rankedCandidate.costs.latencyR, greaterThan(0));
      expect(rankedCandidate.costs.unknownComponents, isEmpty);
      expect(rankedCandidate.fillProbability, 0.8);
    },
  );

  test(
    'worse execution assumptions reduce economic utility on identical setup',
    () {
      final setup = pending(id: 'btc', symbol: 'BTCUSDT');
      final cheap = TradingLabOpportunityRanking.comparePolicies(
        run: run(
          fee: 1,
          spread: 0.5,
          slippage: 0.5,
          funding: 0,
          latency: 0,
          partialFill: 1,
        ),
        pendingCandidates: [setup],
        marketPrices: const {'BTCUSDT': 100},
        evaluatedAtUtc: now,
      )[OpportunityRankingPolicy.economicUtility]!.single;
      final expensive = TradingLabOpportunityRanking.comparePolicies(
        run: run(
          fee: 20,
          spread: 10,
          slippage: 15,
          funding: 0.005,
          latency: 20,
          partialFill: 0.4,
        ),
        pendingCandidates: [setup],
        marketPrices: const {'BTCUSDT': 100},
        evaluatedAtUtc: now,
      )[OpportunityRankingPolicy.economicUtility]!.single;

      expect(
        expensive.utility.executionCostR,
        greaterThan(cheap.utility.executionCostR),
      );
      expect(expensive.utility.score, lessThan(cheap.utility.score));
    },
  );

  test('Trading Lab ranking adapter has no live or order authority', () {
    final source = File(
      'lib/features/trading_lab/application/trading_lab_opportunity_ranking.dart',
    ).readAsStringSync().toLowerCase();

    expect(source, isNot(contains('decisionenvironment.live')));
    expect(source, isNot(contains('placemarketentry')));
    expect(source, isNot(contains('withdraw')));
    expect(source, isNot(contains('transfer')));
  });
}
