import 'package:flutter_test/flutter_test.dart';
import 'package:quantara_app/features/trading_journal/domain/trading_journal_models.dart';
import 'package:quantara_app/features/trading_journal/domain/trading_journal_projection.dart';
import 'package:quantara_app/features/trading_journal/domain/trading_performance_analytics.dart';
import 'package:quantara_app/features/trading_journal/domain/trading_performance_models.dart';

void main() {
  test(
    'report aggregates ledger net truth without subtracting attribution twice',
    () {
      final report = TradingPerformanceAnalytics.build(
        projections: [
          _projection(
            id: 'a',
            symbol: 'BTCUSDT',
            net: 8,
            gross: 10,
            fees: 1,
            funding: -1,
            r: 1.2,
          ),
          _projection(
            id: 'b',
            symbol: 'BTCUSDT',
            net: -5,
            gross: -4,
            fees: 1,
            funding: 0,
            r: -0.8,
          ),
        ],
        generatedAtUtc: DateTime.utc(2026, 8, 15),
        bootstrapIterations: 300,
      );

      expect(report.closedTrades, 2);
      expect(report.grossPnl, 6);
      expect(report.fees, 2);
      expect(report.funding, -1);
      expect(report.netPnl, 3);
      expect(report.wins, 1);
      expect(report.losses, 1);
      expect(report.expectancyR, closeTo(0.2, 0.000001));
      expect(
        report.warnings.any((item) => item.contains('not subtracted')),
        isTrue,
      );
    },
  );

  test('the same filter is applied to headline and attribution groups', () {
    final filter = TradingPerformanceFilter(
      startedAtUtc: DateTime.utc(2026, 8, 2),
      endedAtUtc: DateTime.utc(2026, 8, 20),
      symbols: const ['BTCUSDT'],
      timeframes: const ['1h'],
      sources: const [TradingJournalSource.localLive],
    );
    final report = TradingPerformanceAnalytics.build(
      projections: [
        _projection(
          id: 'included',
          symbol: 'BTCUSDT',
          net: 4,
          gross: 5,
          fees: 1,
          funding: 0,
          r: 0.8,
        ),
        _projection(
          id: 'wrong-symbol',
          symbol: 'ETHUSDT',
          net: 20,
          gross: 21,
          fees: 1,
          funding: 0,
          r: 3,
        ),
        _projection(
          id: 'too-early',
          symbol: 'BTCUSDT',
          net: 30,
          gross: 31,
          fees: 1,
          funding: 0,
          r: 4,
          closedAt: DateTime.utc(2026, 8, 1),
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
    expect(report.byMode.keys, [TradingJournalSource.localLive.name]);
  });

  test('risk-adjusted ratios remain hidden on small samples', () {
    final report = TradingPerformanceAnalytics.build(
      projections: List.generate(
        10,
        (index) => _projection(
          id: 'small-$index',
          symbol: 'BTCUSDT',
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
}

TradingJournalProjection _projection({
  required String id,
  required String symbol,
  required double net,
  required double gross,
  required double fees,
  required double funding,
  required double r,
  DateTime? closedAt,
}) {
  final resolvedAt = closedAt ?? DateTime.utc(2026, 8, 10, 12);
  return TradingJournalProjection(
    journalTradeId: id,
    symbol: symbol,
    timeframe: '1h',
    strategy: 'trendPullback',
    direction: TradingJournalDirection.long,
    source: TradingJournalSource.localLive,
    state: TradingJournalTradeState.closed,
    timeline: const [],
    decidedAt: resolvedAt.subtract(const Duration(hours: 2)),
    integrity: TradingJournalIntegrity.verified,
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
    closedAt: resolvedAt,
  );
}
