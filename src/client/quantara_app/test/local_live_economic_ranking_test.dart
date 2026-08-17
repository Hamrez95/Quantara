import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:quantara_app/features/auto_trade/application/local_live_economic_ranking.dart';
import 'package:quantara_app/features/auto_trade/domain/execution_quality_models.dart';
import 'package:quantara_app/features/market_analysis/domain/market_regime_models.dart';
import 'package:quantara_app/features/owner_alpha/domain/owner_alpha_models.dart';

void main() {
  final now = DateTime.utc(2026, 8, 15, 12);

  TradeIdea idea({
    required String id,
    required String symbol,
    required String timeframe,
    TradeDirection direction = TradeDirection.long,
    int quality = 80,
    double rr = 2,
    double costs = 0.5,
  }) => TradeIdea(
    symbol: symbol,
    timeframe: timeframe,
    direction: direction,
    confidencePercent: quality,
    entryLower: 99.5,
    entryUpper: 100.5,
    stopLoss: direction == TradeDirection.long ? 97 : 103,
    targets: direction == TradeDirection.long
        ? const [102, 104, 106]
        : const [98, 96, 94],
    riskReward: rr,
    maximumLoss: 10,
    positionSize: 2,
    notionalValue: 200,
    recommendedLeverage: 2,
    maximumSafeLeverage: 5,
    requiredMargin: 100,
    estimatedRoundTripCosts: costs,
    setupId: id,
    candleClosedAt: now.subtract(const Duration(minutes: 20)),
    summary: 'test',
    invalidation: 'stop',
    reasons: const ['fixture'],
    strategy: AnalysisStrategy.structureZones,
    strategyVersion: 'structure/1.0',
    marketRegime: MarketRegime.directionalTrend,
    indicatorSnapshot: const {'relativeVolume20': 1.5},
    setupQualityScore: quality,
  );

  EstimatedExecutionCosts estimate({
    required double totalCost,
    DateTime? asOfUtc,
    ExecutionEvidenceQuality quality = ExecutionEvidenceQuality.observed,
    String version = 'execution-quality/test',
  }) => EstimatedExecutionCosts(
    modelVersion: version,
    asOfUtc: asOfUtc ?? now,
    evidenceQuality: quality,
    fees: totalCost,
    funding: 0,
    spread: 0,
    slippage: 0,
    latency: 0,
  );

  test(
    'preferred timeframe and conflict resolution happen before economics',
    () {
      final btc4h = idea(
        id: 'btc-4h',
        symbol: 'BTCUSDT',
        timeframe: '4h',
        quality: 95,
        costs: 0.1,
      );
      final btc1h = idea(
        id: 'btc-1h',
        symbol: 'BTCUSDT',
        timeframe: '1h',
        quality: 72,
        costs: 1.5,
      );
      final eth1h = idea(
        id: 'eth-1h',
        symbol: 'ETHUSDT',
        timeframe: '1h',
        quality: 82,
        costs: 0.1,
      );
      final solLong = idea(
        id: 'sol-long',
        symbol: 'SOLUSDT',
        timeframe: '1h',
        direction: TradeDirection.long,
      );
      final solShort = idea(
        id: 'sol-short',
        symbol: 'SOLUSDT',
        timeframe: '1h',
        direction: TradeDirection.short,
      );

      final ranked = LocalLiveEconomicRanking.rank(
        ideas: [btc4h, btc1h, eth1h, solLong, solShort],
        lastPrices: const {'BTCUSDT': 100, 'ETHUSDT': 100, 'SOLUSDT': 100},
        evaluatedAtUtc: now,
      );

      expect(ranked.map((item) => item.idea.setupId), contains('btc-1h'));
      expect(
        ranked.map((item) => item.idea.setupId),
        isNot(contains('btc-4h')),
      );
      expect(
        ranked.map((item) => item.idea.symbol),
        isNot(contains('SOLUSDT')),
      );
      expect(ranked.first.idea.setupId, 'eth-1h');
    },
  );

  test('concentration cost can reorder without changing the trade plan', () {
    final crowded = idea(
      id: 'crowded',
      symbol: 'BTCUSDT',
      timeframe: '1h',
      quality: 88,
    );
    final diverse = idea(
      id: 'diverse',
      symbol: 'ETHUSDT',
      timeframe: '1h',
      quality: 84,
    );

    final ranked = LocalLiveEconomicRanking.rank(
      ideas: [crowded, diverse],
      lastPrices: const {'BTCUSDT': 100, 'ETHUSDT': 100},
      evaluatedAtUtc: now,
      concentrationPenaltyBySymbol: const {'BTCUSDT': 1, 'ETHUSDT': 0},
    );

    expect(ranked.first.idea.setupId, 'diverse');
    expect(ranked.last.idea.stopLoss, crowded.stopLoss);
    expect(ranked.last.idea.maximumLoss, crowded.maximumLoss);
  });

  test('fresh observed execution cost evidence affects economic ranking', () {
    final expensive = idea(
      id: 'expensive',
      symbol: 'BTCUSDT',
      timeframe: '1h',
      quality: 85,
      costs: 0.1,
    );
    final cheap = idea(
      id: 'cheap',
      symbol: 'ETHUSDT',
      timeframe: '1h',
      quality: 85,
      costs: 0.1,
    );

    final ranked = LocalLiveEconomicRanking.rank(
      ideas: [expensive, cheap],
      lastPrices: const {'BTCUSDT': 100, 'ETHUSDT': 100},
      evaluatedAtUtc: now,
      executionCostsBySetupId: {
        'expensive': estimate(totalCost: 9),
        'cheap': estimate(totalCost: 0.5),
      },
    );

    expect(ranked.first.idea.setupId, 'cheap');
    final expensiveRanked = ranked.firstWhere(
      (item) => item.idea.setupId == 'expensive',
    );
    expect(expensiveRanked.ranked.utility.executionCostR, closeTo(0.9, 1e-9));
    expect(
      expensiveRanked.ranked.candidate.evidenceTags,
      contains('cost:execution-quality:execution-quality/test'),
    );
  });

  test('stale execution estimate falls back to TradeIdea aggregate cost', () {
    final fallback = idea(
      id: 'fallback',
      symbol: 'BTCUSDT',
      timeframe: '1h',
      costs: 0.5,
    );

    final ranked = LocalLiveEconomicRanking.rank(
      ideas: [fallback],
      lastPrices: const {'BTCUSDT': 100},
      evaluatedAtUtc: now,
      maximumExecutionEstimateAge: const Duration(seconds: 30),
      executionCostsBySetupId: {
        'fallback': estimate(
          totalCost: 9,
          asOfUtc: now.subtract(const Duration(seconds: 31)),
        ),
      },
    );

    expect(ranked.single.ranked.utility.executionCostR, closeTo(0.05, 1e-9));
    expect(
      ranked.single.ranked.candidate.evidenceTags,
      contains('cost:execution-quality-stale-fallback'),
    );
  });

  test('insufficient execution evidence cannot replace conservative fallback', () {
    final fallback = idea(
      id: 'insufficient',
      symbol: 'BTCUSDT',
      timeframe: '1h',
      costs: 0.5,
    );

    final ranked = LocalLiveEconomicRanking.rank(
      ideas: [fallback],
      lastPrices: const {'BTCUSDT': 100},
      evaluatedAtUtc: now,
      executionCostsBySetupId: {
        'insufficient': estimate(
          totalCost: 9,
          quality: ExecutionEvidenceQuality.insufficient,
        ),
      },
    );

    expect(ranked.single.ranked.utility.executionCostR, closeTo(0.05, 1e-9));
    expect(
      ranked.single.ranked.candidate.evidenceTags,
      contains('cost:execution-quality-insufficient-fallback'),
    );
  });

  test('ranker and adapter contain no live order or transfer authority', () {
    final adapter = File(
      'lib/features/auto_trade/application/local_live_economic_ranking.dart',
    ).readAsStringSync();
    final ranker = File(
      'lib/features/decision_core/application/economic_opportunity_ranker.dart',
    ).readAsStringSync();
    final combined = '$adapter\n$ranker'.toLowerCase();

    expect(combined, isNot(contains('placemarketentry')));
    expect(combined, isNot(contains('withdraw')));
    expect(combined, isNot(contains('transfer')));
    expect(combined, isNot(contains('privateapi')));
  });

  test(
    'Local Live source continues after deterministic candidate rejection',
    () {
      final source = File(
        'lib/features/auto_trade/application/local_live_trade_service.dart',
      ).readAsStringSync();
      final loop = source.indexOf('for (final rankedIdea in rankedIdeas)');
      final canonical = source.indexOf('if (!canonical.eligible)', loop);
      final reservation = source.indexOf(
        'if (!reservation.decision.allowed',
        canonical,
      );
      final canonicalContinue = source.indexOf('continue;', canonical);
      final reservationContinue = source.indexOf('continue;', reservation);

      expect(loop, greaterThanOrEqualTo(0));
      expect(canonical, greaterThan(loop));
      expect(
        canonicalContinue,
        allOf(greaterThan(canonical), lessThan(reservation)),
      );
      expect(reservationContinue, greaterThan(reservation));
    },
  );
}
