import 'package:flutter_test/flutter_test.dart';
import 'package:quantara_app/features/trading_journal/domain/trading_counterfactual_performance.dart';
import 'package:quantara_app/features/trading_journal/domain/trading_journal_models.dart';
import 'package:quantara_app/features/trading_journal/domain/trading_journal_projection.dart';
import 'package:quantara_app/features/trading_journal/domain/trading_performance_models.dart';

void main() {
  TradingJournalProjection missed({
    required String id,
    required String symbol,
    required String strategy,
    TradingJournalCounterfactualOutcome? outcome,
  }) => TradingJournalProjection.fixture(
    journalTradeId: id,
    symbol: symbol,
    timeframe: '1h',
    strategy: strategy,
    direction: TradingJournalDirection.long,
    source: TradingJournalSource.signalOnly,
    state: TradingJournalTradeState.missed,
    decidedAt: DateTime.utc(2026, 8, 10, 12),
    counterfactualOutcome: outcome,
  );

  test('explicit missed outcomes remain separate from actual trade truth', () {
    final projections = [
      missed(
        id: 'win',
        symbol: 'BTCUSDT',
        strategy: 'trend',
        outcome: const TradingJournalCounterfactualOutcome(
          classification: TradingJournalCounterfactualClassification.wouldWin,
          highestTargetReached: 2,
          priceMovePercent: 3,
          realizedR: 1.5,
        ),
      ),
      missed(
        id: 'loss',
        symbol: 'BTCUSDT',
        strategy: 'trend',
        outcome: const TradingJournalCounterfactualOutcome(
          classification: TradingJournalCounterfactualClassification.wouldLose,
          highestTargetReached: 0,
          priceMovePercent: -2,
          realizedR: -1,
        ),
      ),
      missed(
        id: 'flat',
        symbol: 'ETHUSDT',
        strategy: 'range',
        outcome: const TradingJournalCounterfactualOutcome(
          classification: TradingJournalCounterfactualClassification.breakEven,
          highestTargetReached: 0,
          priceMovePercent: 0,
          realizedR: 0,
        ),
      ),
      missed(
        id: 'unknown',
        symbol: 'ETHUSDT',
        strategy: 'range',
      ),
      TradingJournalProjection.fixture(
        journalTradeId: 'actual',
        symbol: 'BTCUSDT',
        timeframe: '1h',
        strategy: 'trend',
        direction: TradingJournalDirection.long,
        source: TradingJournalSource.paper,
        state: TradingJournalTradeState.closed,
        decidedAt: DateTime.utc(2026, 8, 10, 12),
        closedAt: DateTime.utc(2026, 8, 10, 14),
        netPnl: 12,
        realizedR: 1.2,
      ),
    ];

    final summary = TradingCounterfactualPerformance.calculate(
      projections: projections,
    );

    expect(summary.missedSignals, 4);
    expect(summary.resolvedSignals, 3);
    expect(summary.wouldWin, 1);
    expect(summary.wouldLose, 1);
    expect(summary.breakEven, 1);
    expect(summary.unresolved, 1);
    expect(summary.totalResolvedR, 0.5);
    expect(summary.averageResolvedR, closeTo(1 / 6, 1e-12));
    expect(summary.resolutionRatePercent, 75);
    expect(summary.byStrategy['trend']!.missedSignals, 2);
    expect(summary.bySymbol['ETHUSDT']!.unresolved, 1);
  });

  test('inconsistent hindsight classification fails closed as unresolved', () {
    final summary = TradingCounterfactualPerformance.calculate(
      projections: [
        missed(
          id: 'impossible-win',
          symbol: 'BTCUSDT',
          strategy: 'trend',
          outcome: const TradingJournalCounterfactualOutcome(
            classification:
                TradingJournalCounterfactualClassification.wouldWin,
            highestTargetReached: 0,
            priceMovePercent: -1,
            realizedR: -0.5,
          ),
        ),
      ],
    );

    expect(summary.missedSignals, 1);
    expect(summary.resolvedSignals, 0);
    expect(summary.unresolved, 1);
    expect(summary.totalResolvedR, 0);
  });

  test('counterfactual report honors the same basic performance filters', () {
    final summary = TradingCounterfactualPerformance.calculate(
      projections: [
        missed(
          id: 'btc',
          symbol: 'BTCUSDT',
          strategy: 'trend',
          outcome: const TradingJournalCounterfactualOutcome(
            classification:
                TradingJournalCounterfactualClassification.wouldWin,
            highestTargetReached: 1,
            priceMovePercent: 2,
            realizedR: 1,
          ),
        ),
        missed(
          id: 'eth',
          symbol: 'ETHUSDT',
          strategy: 'range',
          outcome: const TradingJournalCounterfactualOutcome(
            classification:
                TradingJournalCounterfactualClassification.wouldLose,
            highestTargetReached: 0,
            priceMovePercent: -2,
            realizedR: -1,
          ),
        ),
      ],
      filter: TradingPerformanceFilter(
        symbols: const ['btcusdt'],
        strategies: const ['trend'],
        sources: const [TradingJournalSource.signalOnly],
        directions: const [TradingJournalDirection.long],
        startedAtUtc: DateTime.utc(2026, 8, 10),
        endedAtUtc: DateTime.utc(2026, 8, 11),
      ),
    );

    expect(summary.missedSignals, 1);
    expect(summary.wouldWin, 1);
    expect(summary.bySymbol.keys, ['BTCUSDT']);
    expect(summary.byStrategy.keys, ['trend']);
  });

  test('counterfactual report is bounded and JSON remains explicit', () {
    expect(
      () => TradingCounterfactualPerformance.calculate(
        projections: [
          missed(id: 'a', symbol: 'BTCUSDT', strategy: 'trend'),
          missed(id: 'b', symbol: 'ETHUSDT', strategy: 'range'),
        ],
        maximumMissedSignals: 1,
      ),
      throwsStateError,
    );

    final summary = TradingCounterfactualPerformance.calculate(
      projections: [missed(id: 'a', symbol: 'BTCUSDT', strategy: 'trend')],
    );
    final json = summary.toJson();
    expect(json['missedSignals'], 1);
    expect(json['resolvedSignals'], 0);
    expect(json['unresolved'], 1);
    expect((json['byStrategy']! as Map).containsKey('trend'), isTrue);
  });
}
