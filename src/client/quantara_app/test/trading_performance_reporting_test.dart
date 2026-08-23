import 'package:flutter_test/flutter_test.dart';
import 'package:quantara_app/features/trading_journal/domain/trading_journal_models.dart';
import 'package:quantara_app/features/trading_journal/domain/trading_journal_projection.dart';
import 'package:quantara_app/features/trading_journal/domain/trading_performance_analytics.dart';
import 'package:quantara_app/features/trading_journal/domain/trading_performance_reporting.dart';

void main() {
  test('weekly window is Monday UTC through the next Monday', () {
    final filter = TradingPerformanceReporting.periodFilter(
      period: TradingPerformancePeriod.weekly,
      anchorUtc: DateTime.utc(2026, 8, 15, 12),
    );

    expect(filter.startedAtUtc, DateTime.utc(2026, 8, 10));
    expect(filter.endedAtUtc, DateTime.utc(2026, 8, 17));
  });

  test('daily and monthly windows are deterministic UTC boundaries', () {
    final daily = TradingPerformanceReporting.periodFilter(
      period: TradingPerformancePeriod.daily,
      anchorUtc: DateTime.utc(2026, 8, 15, 23),
    );
    final monthly = TradingPerformanceReporting.periodFilter(
      period: TradingPerformancePeriod.monthly,
      anchorUtc: DateTime.utc(2026, 12, 15),
    );

    expect(daily.startedAtUtc, DateTime.utc(2026, 8, 15));
    expect(daily.endedAtUtc, DateTime.utc(2026, 8, 16));
    expect(monthly.startedAtUtc, DateTime.utc(2026, 12));
    expect(monthly.endedAtUtc, DateTime.utc(2027));
  });

  test('custom window requires explicit bounded UTC start and end', () {
    expect(
      () => TradingPerformanceReporting.periodFilter(
        period: TradingPerformancePeriod.custom,
        anchorUtc: DateTime.utc(2026, 8, 15),
        customStartedAtUtc: DateTime.utc(2026, 8, 1),
      ),
      throwsArgumentError,
    );

    final filter = TradingPerformanceReporting.periodFilter(
      period: TradingPerformancePeriod.custom,
      anchorUtc: DateTime.utc(2026, 8, 15),
      customStartedAtUtc: DateTime.utc(2026, 8, 1),
      customEndedAtUtc: DateTime.utc(2026, 8, 15),
    );

    expect(filter.startedAtUtc, DateTime.utc(2026, 8, 1));
    expect(filter.endedAtUtc, DateTime.utc(2026, 8, 15));
  });

  test('JSON and CSV exports use the same report truth', () {
    final report = TradingPerformanceAnalytics.build(
      projections: [
        _projection(id: 'a', strategy: 'trendPullback', net: 5, r: 0.8),
        _projection(id: 'b', strategy: 'rangeSweep', net: -2, r: -0.4),
      ],
      generatedAtUtc: DateTime.utc(2026, 8, 15),
      bootstrapIterations: 300,
    );

    final json = TradingPerformanceReporting.toJson(report);
    final csv = TradingPerformanceReporting.toCsv(report);

    expect(report.pricedTrades, 2);
    expect(json['schemaVersion'], 2);
    expect((json['summary']! as Map)['netPnl'], report.netPnl);
    expect((json['summary']! as Map)['riskHours'], report.riskHours);
    expect((json['uncertainty']! as Map)['sampleSize'], 2);
    expect(csv, contains('dimension,key,trades,netPnl'));
    expect(csv, contains('strategy,trendPullback'));
    expect(csv, contains('strategy,rangeSweep'));
    expect(csv, contains('strategyVersion,rules-v2'));
  });

  test('insights refuse segment conclusions on small samples', () {
    final report = TradingPerformanceAnalytics.build(
      projections: List.generate(
        8,
        (index) => _projection(
          id: 'small-$index',
          strategy: index.isEven ? 'trendPullback' : 'rangeSweep',
          net: index.isEven ? 2 : -1,
          r: index.isEven ? 0.5 : -0.2,
        ),
      ),
      generatedAtUtc: DateTime.utc(2026, 8, 15),
      bootstrapIterations: 300,
    );

    final insights = TradingPerformanceReporting.evidenceInsights(report);

    expect(insights, hasLength(1));
    expect(
      insights.single.kind,
      TradingPerformanceInsightKind.insufficientEvidence,
    );
    expect(insights.single.message, contains('do not change live parameters'));
  });

  test(
    'mature segment evidence reports strongest and weakest without auto tuning',
    () {
      final projections = <TradingJournalProjection>[
        ...List.generate(
          25,
          (index) => _projection(
            id: 'trend-$index',
            strategy: 'trendPullback',
            net: 3,
            r: 0.7,
          ),
        ),
        ...List.generate(
          25,
          (index) => _projection(
            id: 'range-$index',
            strategy: 'rangeSweep',
            net: -1,
            r: -0.25,
          ),
        ),
      ];
      final report = TradingPerformanceAnalytics.build(
        projections: projections,
        generatedAtUtc: DateTime.utc(2026, 8, 15),
        bootstrapIterations: 300,
      );

      final insights = TradingPerformanceReporting.evidenceInsights(report);

      expect(insights, hasLength(2));
      expect(insights.first.kind, TradingPerformanceInsightKind.worked);
      expect(insights.last.kind, TradingPerformanceInsightKind.didNotWork);
      expect(
        insights.first.message,
        contains('not an automatic parameter change'),
      );
    },
  );

  test('shareable summaries are available in English and Persian', () {
    final report = TradingPerformanceAnalytics.build(
      projections: [
        _projection(id: 'a', strategy: 'trendPullback', net: 5, r: 0.8),
      ],
      generatedAtUtc: DateTime.utc(2026, 8, 15),
      bootstrapIterations: 300,
    );

    final english = TradingPerformanceReporting.toShareableSummary(report);
    final persian = TradingPerformanceReporting.toShareableSummary(
      report,
      language: TradingPerformanceSummaryLanguage.persian,
    );

    expect(english, contains('Quantara performance'));
    expect(english, contains('not a profit guarantee'));
    expect(persian, contains('گزارش عملکرد Quantara'));
    expect(persian, contains('تضمین سود'));
  });
}

TradingJournalProjection _projection({
  required String id,
  required String strategy,
  required double net,
  required double r,
}) {
  final decidedAt = DateTime.utc(2026, 8, 10, 10);
  final plan = TradingJournalPlan(
    journalTradeId: id,
    setupId: 'setup-$id',
    analysisVersion: 'analysis-v2',
    symbol: strategy == 'trendPullback' ? 'BTCUSDT' : 'ETHUSDT',
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
    regime: strategy == 'trendPullback' ? 'trend' : 'range',
    rationale: 'test',
    invalidation: 'test',
    accountEquity: 1000,
    riskPercent: 1,
    riskBudget: 10,
    leverage: 5,
    expectedMargin: 40,
    passedGates: const ['test'],
    blockedGates: const [],
    appVersion: 'test',
    strategyRulesVersion: 'rules-v2',
  );
  return TradingJournalProjection(
    journalTradeId: id,
    symbol: plan.symbol,
    timeframe: '1h',
    strategy: strategy,
    direction: TradingJournalDirection.long,
    source: TradingJournalSource.localLive,
    state: TradingJournalTradeState.closed,
    timeline: const [],
    decidedAt: decidedAt,
    integrity: TradingJournalIntegrity.verified,
    plan: plan,
    grossPnl: net + 0.5,
    fees: 0.5,
    funding: 0,
    netPnl: net,
    realizedR: r,
    priceMovePercent: r,
    mfe: r > 0 ? r + 0.3 : 0.2,
    mae: r < 0 ? r.abs() + 0.2 : 0.1,
    holdingDuration: const Duration(hours: 2),
    closeReason: net > 0
        ? TradingJournalCloseReason.takeProfit1
        : TradingJournalCloseReason.stop,
    closedAt: DateTime.utc(2026, 8, 10, 12),
  );
}
