import 'package:flutter_test/flutter_test.dart';
import 'package:quantara_app/features/market_analysis/domain/market_chart_models.dart';
import 'package:quantara_app/features/trading_journal/domain/trading_journal_chart_snapshot.dart';
import 'package:quantara_app/features/trading_journal/domain/trading_journal_models.dart';
import 'package:quantara_app/features/trading_journal/domain/trading_journal_replay.dart';

void main() {
  TradingJournalPlan planWith(Map<String, double> snapshot) =>
      TradingJournalPlan(
        journalTradeId: 'journal-1',
        setupId: 'setup-1',
        analysisVersion: 'test',
        symbol: 'ETHUSDT',
        market: 'USDT_PERPETUAL',
        timeframe: '15m',
        direction: TradingJournalDirection.long,
        strategy: 'structureZones',
        cadence: 'balanced',
        source: TradingJournalSource.localLive,
        decidedAt: DateTime.utc(2026, 8, 24),
        decisionPrice: 100,
        entryLower: 99,
        entryUpper: 101,
        plannedEntry: 100,
        originalStopLoss: 95,
        targets: const [105, 110, 115],
        expectedRMultiples: const [1, 2, 3],
        confidencePercent: 80,
        confluence: const [],
        regime: 'trend',
        rationale: 'fixture',
        invalidation: 'fixture',
        accountEquity: 1000,
        riskPercent: 1,
        riskBudget: 10,
        leverage: 2,
        expectedMargin: 50,
        passedGates: const [],
        blockedGates: const [],
        appVersion: 'test',
        strategyRulesVersion: 'test',
        indicatorSnapshot: snapshot,
      );

  test('replay uses only persisted decision-time chart evidence', () {
    final start = DateTime.utc(2026, 8, 20);
    final analysis = TimeframeChartAnalysis(
      symbol: 'ETHUSDT',
      timeframe: '15m',
      candles: List.generate(24, (index) {
        final open = 100.0 + index;
        return ChartCandle(
          openTime: start.add(Duration(minutes: 15 * index)),
          open: open,
          high: open + 2,
          low: open - 1,
          close: open + 1,
          volume: 10,
        );
      }),
      zones: const [],
      direction: ChartDirection.bullish,
      directionStrength: 0.8,
      volatilityPercent: 1.5,
      summary: 'decision',
      generatedAt: start.add(const Duration(hours: 6)),
      fingerprint: 'decision-fingerprint',
    );
    final plan = planWith(
      TradingJournalChartSnapshot.encodeIntoIndicatorSnapshot(analysis),
    );

    final replay = TradingJournalReplay.decisionChart(plan);
    expect(replay, isNotNull);
    expect(replay!.latestCandle.close, analysis.latestCandle.close);
    expect(replay.generatedAt, analysis.generatedAt);
  });

  test(
    'legacy plan without snapshot fails closed instead of using live data',
    () {
      expect(TradingJournalReplay.decisionChart(planWith(const {})), isNull);
    },
  );
}
