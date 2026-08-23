import 'package:flutter_test/flutter_test.dart';
import 'package:quantara_app/features/trading_journal/domain/trading_journal_models.dart';
import 'package:quantara_app/features/trading_journal/domain/trading_journal_projection.dart';
import 'package:quantara_app/features/trading_journal/domain/trading_performance_analytics.dart';
import 'package:quantara_app/features/trading_journal/domain/trading_performance_models.dart';

void main() {
  test(
    'report aggregates journal net truth and capital-time without double cost subtraction',
    () {
      final report = TradingPerformanceAnalytics.build(
        projections: [
          _projection(
            id: 'a',
            symbol: 'BTCUSDT',
            strategy: 'trendPullback',
            version: 'trend-v2',
            net: 8,
            gross: 10,
            fees: 1,
            funding: -1,
            r: 1.2,
            riskBudget: 10,
            expectedMargin: 40,
          ),
          _projection(
            id: 'b',
            symbol: 'BTCUSDT',
            strategy: 'trendPullback',
            version: 'trend-v2',
            net: -5,
            gross: -4,
            fees: 1,
            funding: 0,
            r: -0.8,
            riskBudget: 10,
            expectedMargin: 40,
          ),
        ],
        generatedAtUtc: DateTime.utc(2026, 8, 15),
        bootstrapIterations: 300,
      );

      expect(report.closedTrades, 2);
      expect(report.pricedTrades, 2);
      expect(report.economicsPendingTrades, 0);
      expect(report.grossPnl, 6);
      expect(report.fees, 2);
      expect(report.funding, -1);
      expect(report.netPnl, 3);
      expect(report.wins, 1);
      expect(report.losses, 1);
      expect(report.expectancyR, closeTo(0.2, 0.000001));
      expect(report.riskHours, 40);
      expect(report.capitalHours, 160);
      expect(report.netPnlPerRiskHour, closeTo(3 / 40, 0.000001));
      expect(report.netPnlPerCapitalHour, closeTo(3 / 160, 0.000001));
      expect(report.byStrategyVersion['trend-v2']?.trades, 2);
      expect(report.byLeverageBand['4-10x']?.trades, 2);
      expect(report.byConfidenceBand['75-89']?.trades, 2);
      expect(
        report.warnings.any((item) => item.contains('not subtracted')),
        isTrue,
      );
    },
  );

  test('pending economics are explicit and never treated as zero-PnL', () {
    final priced = _projection(
      id: 'priced',
      symbol: 'BTCUSDT',
      strategy: 'trendPullback',
      version: 'trend-v2',
      net: 4,
      gross: 5,
      fees: 1,
      funding: 0,
      r: 0.8,
    );
    final pending = TradingJournalProjection(
      journalTradeId: 'pending',
      symbol: 'ETHUSDT',
      timeframe: '1h',
      strategy: 'rangeSweep',
      direction: TradingJournalDirection.long,
      source: TradingJournalSource.localLive,
      state: TradingJournalTradeState.closed,
      timeline: const [],
      decidedAt: DateTime.utc(2026, 8, 10, 10),
      integrity: TradingJournalIntegrity.verified,
      closedAt: DateTime.utc(2026, 8, 10, 12),
    );

    final report = TradingPerformanceAnalytics.build(
      projections: [priced, pending],
      generatedAtUtc: DateTime.utc(2026, 8, 15),
      bootstrapIterations: 300,
    );

    expect(report.closedTrades, 2);
    expect(report.pricedTrades, 1);
    expect(report.economicsPendingTrades, 1);
    expect(report.netPnl, 4);
    expect(report.wins, 1);
    expect(report.losses, 0);
    expect(report.byStrategy.keys, ['trendPullback']);
    expect(report.warnings.any((item) => item.contains('excluded')), isTrue);
  });

  test('the same filter applies to headline and all attribution groups', () {
    final filter = TradingPerformanceFilter(
      startedAtUtc: DateTime.utc(2026, 8, 2),
      endedAtUtc: DateTime.utc(2026, 8, 20),
      symbols: const ['BTCUSDT'],
      timeframes: const ['1h'],
      strategies: const ['trendPullback'],
      strategyVersions: const ['trend-v2'],
      regimes: const ['trend'],
      sources: const [TradingJournalSource.localLive],
      directions: const [TradingJournalDirection.long],
    );
    final report = TradingPerformanceAnalytics.build(
      projections: [
        _projection(
          id: 'included',
          symbol: 'BTCUSDT',
          strategy: 'trendPullback',
          version: 'trend-v2',
          net: 4,
          gross: 5,
          fees: 1,
          funding: 0,
          r: 0.8,
        ),
        _projection(
          id: 'wrong-symbol',
          symbol: 'ETHUSDT',
          strategy: 'trendPullback',
          version: 'trend-v2',
          net: 20,
          gross: 21,
          fees: 1,
          funding: 0,
          r: 3,
        ),
        _projection(
          id: 'wrong-version',
          symbol: 'BTCUSDT',
          strategy: 'trendPullback',
          version: 'trend-v1',
          net: 30,
          gross: 31,
          fees: 1,
          funding: 0,
          r: 4,
        ),
      ],
      filter: filter,
      generatedAtUtc: DateTime.utc(2026, 8, 15),
      bootstrapIterations: 300,
    );

    expect(report.closedTrades, 1);
    expect(report.netPnl, 4);
    expect(report.bySymbol.keys, ['BTCUSDT']);
    expect(report.byTimeframe.keys, ['1h']);
    expect(report.byStrategy.keys, ['trendPullback']);
    expect(report.byStrategyVersion.keys, ['trend-v2']);
    expect(report.byRegime.keys, ['trend']);
    expect(report.byMode.keys, [TradingJournalSource.localLive.name]);
  });

  test('risk-adjusted ratios remain hidden on small R samples', () {
    final report = TradingPerformanceAnalytics.build(
      projections: List.generate(
        10,
        (index) => _projection(
          id: 'small-$index',
          symbol: 'BTCUSDT',
          strategy: 'trendPullback',
          version: 'trend-v2',
          net: index.isEven ? 2 : -1,
          gross: index.isEven ? 2.5 : -0.5,
          fees: 0.5,
          funding: 0,
          r: index.isEven ? 0.5 : -0.25,
        ),
      ),
      generatedAtUtc: DateTime.utc(2026, 8, 15),
      bootstrapIterations: 300,
    );

    expect(report.sharpeLike, isNull);
    expect(report.sortinoLike, isNull);
    expect(report.sampleSupportsRiskAdjustedRatios, isFalse);
  });

  test('bootstrap uncertainty is deterministic for a fixed seed', () {
    final items = List.generate(
      35,
      (index) => _projection(
        id: 'trade-$index',
        symbol: index.isEven ? 'BTCUSDT' : 'ETHUSDT',
        strategy: 'trendPullback',
        version: 'trend-v2',
        net: index % 4 == 0 ? -2 : 3,
        gross: index % 4 == 0 ? -1.5 : 3.5,
        fees: 0.5,
        funding: 0,
        r: index % 4 == 0 ? -0.7 : 0.9,
      ),
    );

    final first = TradingPerformanceAnalytics.build(
      projections: items,
      generatedAtUtc: DateTime.utc(2026, 8, 15),
      bootstrapSeed: 42,
      bootstrapIterations: 400,
    );
    final second = TradingPerformanceAnalytics.build(
      projections: items,
      generatedAtUtc: DateTime.utc(2026, 8, 15),
      bootstrapSeed: 42,
      bootstrapIterations: 400,
    );

    expect(first.uncertainty.expectancyRP05, second.uncertainty.expectancyRP05);
    expect(
      first.uncertainty.expectancyRMedian,
      second.uncertainty.expectancyRMedian,
    );
    expect(first.uncertainty.expectancyRP95, second.uncertainty.expectancyRP95);
    expect(first.sharpeLike, isNotNull);
  });

  test(
    'analytics fails closed when the bounded closed-trade budget is exceeded',
    () {
      final items = List.generate(
        3,
        (index) => _projection(
          id: 'trade-$index',
          symbol: 'BTCUSDT',
          strategy: 'trendPullback',
          version: 'trend-v2',
          net: 1,
          gross: 1.5,
          fees: 0.5,
          funding: 0,
          r: 0.1,
        ),
      );

      expect(
        () => TradingPerformanceAnalytics.build(
          projections: items,
          generatedAtUtc: DateTime.utc(2026, 8, 15),
          bootstrapIterations: 300,
          maximumClosedTrades: 2,
        ),
        throwsStateError,
      );
    },
  );
}

TradingJournalProjection _projection({
  required String id,
  required String symbol,
  required String strategy,
  required String version,
  required double net,
  required double gross,
  required double fees,
  required double funding,
  required double r,
  double riskBudget = 10,
  double expectedMargin = 40,
}) {
  final decidedAt = DateTime.utc(2026, 8, 10, 10);
  final closedAt = DateTime.utc(2026, 8, 10, 12);
  final plan = TradingJournalPlan(
    journalTradeId: id,
    setupId: 'setup-$id',
    analysisVersion: 'analysis-v2',
    symbol: symbol,
    market: 'futures',
    timeframe: '1h',
    direction: TradingJournalDirection.long,
    strategy: strategy,
    cadence: '1h',
    source: TradingJournalSource.localLive,
    decidedAt: decidedAt,
    decisionPrice: 100,
    entryLower: 99,
    entryUpper: 101,
    plannedEntry: 100,
    originalStopLoss: 98,
    targets: const [102, 104],
    expectedRMultiples: const [1, 2],
    confidencePercent: 80,
    confluence: const ['test'],
    regime: 'trend',
    rationale: 'test',
    invalidation: 'test',
    accountEquity: 1000,
    riskPercent: 1,
    riskBudget: riskBudget,
    leverage: 5,
    expectedMargin: expectedMargin,
    passedGates: const ['test'],
    blockedGates: const [],
    appVersion: 'test',
    strategyRulesVersion: version,
  );
  return TradingJournalProjection(
    journalTradeId: id,
    symbol: symbol,
    timeframe: '1h',
    strategy: strategy,
    direction: TradingJournalDirection.long,
    source: TradingJournalSource.localLive,
    state: TradingJournalTradeState.closed,
    timeline: const [],
    decidedAt: decidedAt,
    integrity: TradingJournalIntegrity.verified,
    plan: plan,
    entryPrice: 100.2,
    initialQuantity: 2,
    grossPnl: gross,
    fees: fees,
    funding: funding,
    netPnl: net,
    realizedR: r,
    priceMovePercent: r,
    mfe: r > 0 ? r + 0.5 : 0.2,
    mae: r < 0 ? r.abs() + 0.2 : 0.1,
    holdingDuration: const Duration(hours: 2),
    closeReason: net > 0
        ? TradingJournalCloseReason.takeProfit1
        : TradingJournalCloseReason.stop,
    closedAt: closedAt,
  );
}
