import 'package:flutter_test/flutter_test.dart';
import 'package:quantara_app/features/trading_journal/domain/trading_journal_models.dart';
import 'package:quantara_app/features/trading_journal/domain/trading_journal_performance_summary.dart';
import 'package:quantara_app/features/trading_journal/domain/trading_journal_projection.dart';

void main() {
  test(
    'aggregates cost-aware performance and capital-time in one bounded pass',
    () {
      final base = DateTime.utc(2026, 8, 17, 12);
      final summary = TradingJournalPerformanceSummary.calculate([
        _closed(
          id: 'win',
          strategy: 'trend',
          decidedAt: base,
          grossPnl: 12,
          fees: 1,
          funding: -0.5,
          netPnl: 10.5,
          realizedR: 1.05,
          holdingDuration: const Duration(hours: 2),
          riskBudget: 10,
          expectedMargin: 50,
        ),
        _closed(
          id: 'loss',
          strategy: 'trend',
          decidedAt: base.add(const Duration(hours: 3)),
          grossPnl: -4,
          fees: 1,
          funding: 0,
          netPnl: -5,
          realizedR: -0.5,
          holdingDuration: const Duration(hours: 1),
          riskBudget: 10,
          expectedMargin: 50,
        ),
      ]);

      expect(summary.closedTrades, 2);
      expect(summary.pricedTrades, 2);
      expect(summary.economicsPendingTrades, 0);
      expect(summary.grossPnl, closeTo(8, 1e-9));
      expect(summary.fees, closeTo(2, 1e-9));
      expect(summary.funding, closeTo(-0.5, 1e-9));
      expect(summary.netPnl, closeTo(5.5, 1e-9));
      expect(summary.averageNetPnl, closeTo(2.75, 1e-9));
      expect(summary.averageR, closeTo(0.275, 1e-9));
      expect(summary.averageHoldingDuration, const Duration(minutes: 90));
      expect(summary.riskHours, closeTo(30, 1e-9));
      expect(summary.capitalHours, closeTo(150, 1e-9));
      expect(summary.netPnlPerRiskHour, closeTo(5.5 / 30, 1e-9));
      expect(summary.netPnlPerCapitalHour, closeTo(5.5 / 150, 1e-9));
      expect(summary.byStrategy['trend']?.trades, 2);
      expect(summary.byStrategy['trend']?.netPnl, closeTo(5.5, 1e-9));
      expect(summary.byStrategy['trend']?.averageR, closeTo(0.275, 1e-9));
    },
  );

  test(
    'pending economics are counted but never treated as zero-PnL trades',
    () {
      final base = DateTime.utc(2026, 8, 17, 12);
      final summary = TradingJournalPerformanceSummary.calculate([
        _closed(
          id: 'priced',
          strategy: 'range',
          decidedAt: base,
          grossPnl: 4,
          fees: 1,
          funding: 0,
          netPnl: 3,
          realizedR: 0.3,
          holdingDuration: const Duration(hours: 1),
          riskBudget: 10,
          expectedMargin: 20,
        ),
        TradingJournalProjection(
          journalTradeId: 'pending',
          symbol: 'ETHUSDT',
          timeframe: '15m',
          strategy: 'range',
          direction: TradingJournalDirection.long,
          source: TradingJournalSource.localLive,
          state: TradingJournalTradeState.closed,
          timeline: const [],
          decidedAt: base.add(const Duration(hours: 2)),
          integrity: TradingJournalIntegrity.verified,
        ),
      ]);

      expect(summary.closedTrades, 2);
      expect(summary.pricedTrades, 1);
      expect(summary.economicsPendingTrades, 1);
      expect(summary.netPnl, 3);
      expect(summary.averageNetPnl, 3);
      expect(summary.byStrategy['range']?.trades, 1);
    },
  );

  test(
    'analytics window fails closed when the bounded trade budget is exceeded',
    () {
      final base = DateTime.utc(2026, 8, 17, 12);
      final trades = [
        _closed(
          id: 'one',
          strategy: 'trend',
          decidedAt: base,
          grossPnl: 1,
          fees: 0,
          funding: 0,
          netPnl: 1,
          realizedR: 0.1,
          holdingDuration: const Duration(minutes: 30),
          riskBudget: 10,
          expectedMargin: 20,
        ),
        _closed(
          id: 'two',
          strategy: 'trend',
          decidedAt: base.add(const Duration(hours: 1)),
          grossPnl: 1,
          fees: 0,
          funding: 0,
          netPnl: 1,
          realizedR: 0.1,
          holdingDuration: const Duration(minutes: 30),
          riskBudget: 10,
          expectedMargin: 20,
        ),
      ];

      expect(
        () => TradingJournalPerformanceSummary.calculate(
          trades,
          maximumClosedTrades: 1,
        ),
        throwsStateError,
      );
    },
  );
}

TradingJournalProjection _closed({
  required String id,
  required String strategy,
  required DateTime decidedAt,
  required double grossPnl,
  required double fees,
  required double funding,
  required double netPnl,
  required double realizedR,
  required Duration holdingDuration,
  required double riskBudget,
  required double expectedMargin,
}) {
  final plan = TradingJournalPlan(
    journalTradeId: id,
    setupId: 'setup-$id',
    analysisVersion: 'test',
    symbol: 'BTCUSDT',
    market: 'futures',
    timeframe: '15m',
    direction: TradingJournalDirection.long,
    strategy: strategy,
    cadence: '15m',
    source: TradingJournalSource.localLive,
    decidedAt: decidedAt,
    decisionPrice: 100,
    entryLower: 99,
    entryUpper: 101,
    plannedEntry: 100,
    originalStopLoss: 98,
    targets: const [102, 104],
    expectedRMultiples: const [1, 2],
    confidencePercent: 75,
    confluence: const ['test'],
    regime: 'trend',
    rationale: 'test',
    invalidation: 'test',
    accountEquity: 1000,
    riskPercent: 1,
    riskBudget: riskBudget,
    leverage: 3,
    expectedMargin: expectedMargin,
    passedGates: const ['test'],
    blockedGates: const [],
    appVersion: 'test',
    strategyRulesVersion: 'test',
  );
  return TradingJournalProjection(
    journalTradeId: id,
    symbol: 'BTCUSDT',
    timeframe: '15m',
    strategy: strategy,
    direction: TradingJournalDirection.long,
    source: TradingJournalSource.localLive,
    state: TradingJournalTradeState.closed,
    timeline: const [],
    decidedAt: decidedAt,
    integrity: TradingJournalIntegrity.verified,
    plan: plan,
    grossPnl: grossPnl,
    fees: fees,
    funding: funding,
    netPnl: netPnl,
    realizedR: realizedR,
    holdingDuration: holdingDuration,
    closeReason: netPnl >= 0
        ? TradingJournalCloseReason.takeProfit1
        : TradingJournalCloseReason.stop,
    closedAt: decidedAt.add(holdingDuration),
  );
}
