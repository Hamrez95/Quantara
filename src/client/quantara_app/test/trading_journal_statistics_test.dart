import 'package:flutter_test/flutter_test.dart';
import 'package:quantara_app/features/trading_journal/domain/trading_journal_models.dart';
import 'package:quantara_app/features/trading_journal/domain/trading_journal_projection.dart';
import 'package:quantara_app/features/trading_journal/domain/trading_journal_statistics.dart';

void main() {
  TradingJournalProjection closed({
    required String id,
    required String symbol,
    required String timeframe,
    required String strategy,
    required double net,
    required double realizedR,
    required TradingJournalCloseReason closeReason,
  }) => TradingJournalProjection.fixture(
    journalTradeId: id,
    symbol: symbol,
    timeframe: timeframe,
    strategy: strategy,
    direction: TradingJournalDirection.long,
    source: TradingJournalSource.paper,
    state: TradingJournalTradeState.closed,
    netPnl: net,
    realizedR: realizedR,
    closeReason: closeReason,
    decidedAt: DateTime.utc(2026, 8, 1),
    closedAt: DateTime.utc(2026, 8, 1, 2),
  );

  TradingJournalProjection pending({
    required String id,
    required String symbol,
    required String timeframe,
    required String strategy,
  }) => TradingJournalProjection.fixture(
    journalTradeId: id,
    symbol: symbol,
    timeframe: timeframe,
    strategy: strategy,
    direction: TradingJournalDirection.long,
    source: TradingJournalSource.localLive,
    state: TradingJournalTradeState.closed,
    decidedAt: DateTime.utc(2026, 8, 1),
    closedAt: DateTime.utc(2026, 8, 1, 3),
  );

  test('statistics include expectancy, profit factor and average R', () {
    final statistics = TradingJournalStatistics.calculate([
      closed(
        id: 'a',
        symbol: 'XRPUSDT',
        timeframe: '15m',
        strategy: 'structure',
        net: 4,
        realizedR: 2,
        closeReason: TradingJournalCloseReason.takeProfit2,
      ),
      closed(
        id: 'b',
        symbol: 'BTCUSDT',
        timeframe: '1h',
        strategy: 'structure',
        net: -2,
        realizedR: -1,
        closeReason: TradingJournalCloseReason.stop,
      ),
      closed(
        id: 'c',
        symbol: 'XRPUSDT',
        timeframe: '15m',
        strategy: 'breakout',
        net: 1,
        realizedR: 0.5,
        closeReason: TradingJournalCloseReason.manual,
      ),
    ]);

    expect(statistics.closedCount, 3);
    expect(statistics.pricedClosedCount, 3);
    expect(statistics.economicsPendingCount, 0);
    expect(statistics.winCount, 2);
    expect(statistics.lossCount, 1);
    expect(statistics.winRatePercent, closeTo(66.6667, 0.001));
    expect(statistics.expectancy, closeTo(1, 0.000001));
    expect(statistics.profitFactor, closeTo(2.5, 0.000001));
    expect(statistics.averageR, closeTo(0.5, 0.000001));
    expect(statistics.stopCount, 1);
    expect(statistics.takeProfitCount, 1);
    expect(statistics.bySymbol['XRPUSDT']!.netPnl, 5);
    expect(statistics.byTimeframe['15m']!.trades, 2);
    expect(statistics.byStrategy['structure']!.trades, 2);
  });

  test('pending economics are never scored as zero-PnL trades', () {
    final statistics = TradingJournalStatistics.calculate([
      closed(
        id: 'win',
        symbol: 'BTCUSDT',
        timeframe: '1h',
        strategy: 'trend',
        net: 4,
        realizedR: 1,
        closeReason: TradingJournalCloseReason.takeProfit1,
      ),
      closed(
        id: 'loss',
        symbol: 'BTCUSDT',
        timeframe: '1h',
        strategy: 'trend',
        net: -2,
        realizedR: -0.5,
        closeReason: TradingJournalCloseReason.stop,
      ),
      pending(
        id: 'pending',
        symbol: 'BTCUSDT',
        timeframe: '1h',
        strategy: 'trend',
      ),
    ]);

    expect(statistics.closedCount, 3);
    expect(statistics.pricedClosedCount, 2);
    expect(statistics.economicsPendingCount, 1);
    expect(statistics.winRatePercent, 50);
    expect(statistics.expectancy, 1);
    expect(statistics.averageR, 0.25);
    expect(statistics.profitFactor, 2);
    expect(statistics.byStrategy['trend']!.trades, 2);
    expect(statistics.byStrategy['trend']!.netPnl, 2);
  });

  test('equity curve drawdown uses closed trade order', () {
    final statistics = TradingJournalStatistics.calculate([
      closed(
        id: 'a',
        symbol: 'XRPUSDT',
        timeframe: '15m',
        strategy: 's',
        net: 5,
        realizedR: 1,
        closeReason: TradingJournalCloseReason.takeProfit1,
      ),
      closed(
        id: 'b',
        symbol: 'XRPUSDT',
        timeframe: '15m',
        strategy: 's',
        net: -3,
        realizedR: -0.6,
        closeReason: TradingJournalCloseReason.stop,
      ),
      pending(
        id: 'pending-middle',
        symbol: 'XRPUSDT',
        timeframe: '15m',
        strategy: 's',
      ),
      closed(
        id: 'c',
        symbol: 'XRPUSDT',
        timeframe: '15m',
        strategy: 's',
        net: -4,
        realizedR: -0.8,
        closeReason: TradingJournalCloseReason.stop,
      ),
    ]);

    expect(statistics.maximumDrawdown, closeTo(7, 0.000001));
  });

  test('missed idea preserves counterfactual result separately', () {
    final projection = TradingJournalProjection.fixture(
      journalTradeId: 'missed-1',
      symbol: 'SOLUSDT',
      timeframe: '1h',
      strategy: 'structure',
      direction: TradingJournalDirection.long,
      source: TradingJournalSource.signalOnly,
      state: TradingJournalTradeState.missed,
      decidedAt: DateTime.utc(2026, 8, 1),
      counterfactualOutcome: const TradingJournalCounterfactualOutcome(
        classification: TradingJournalCounterfactualClassification.wouldWin,
        highestTargetReached: 2,
        priceMovePercent: 3.4,
        realizedR: 2.1,
      ),
    );

    expect(projection.netPnl, isNull);
    expect(
      projection.counterfactualOutcome!.classification,
      TradingJournalCounterfactualClassification.wouldWin,
    );
    expect(projection.counterfactualOutcome!.highestTargetReached, 2);
  });
}
