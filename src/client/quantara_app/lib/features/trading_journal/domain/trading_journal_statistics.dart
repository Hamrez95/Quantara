import 'dart:math' as math;

import 'trading_journal_models.dart';
import 'trading_journal_projection.dart';

final class TradingJournalGroupStatistics {
  const TradingJournalGroupStatistics({
    required this.trades,
    required this.netPnl,
    required this.averageR,
  });

  final int trades;
  final double netPnl;
  final double averageR;
}

final class TradingJournalStatistics {
  const TradingJournalStatistics({
    required this.closedCount,
    required this.winCount,
    required this.lossCount,
    required this.winRatePercent,
    required this.expectancy,
    required this.profitFactor,
    required this.averageR,
    required this.maximumDrawdown,
    required this.stopCount,
    required this.takeProfitCount,
    required this.bySymbol,
    required this.byTimeframe,
    required this.byStrategy,
  });

  final int closedCount;
  final int winCount;
  final int lossCount;
  final double winRatePercent;
  final double expectancy;
  final double profitFactor;
  final double averageR;
  final double maximumDrawdown;
  final int stopCount;
  final int takeProfitCount;
  final Map<String, TradingJournalGroupStatistics> bySymbol;
  final Map<String, TradingJournalGroupStatistics> byTimeframe;
  final Map<String, TradingJournalGroupStatistics> byStrategy;

  factory TradingJournalStatistics.calculate(
    Iterable<TradingJournalProjection> projections,
  ) {
    final closed =
        projections
            .where((item) => item.state == TradingJournalTradeState.closed)
            .toList(growable: false)
          ..sort(
            (left, right) => (left.closedAt ?? left.decidedAt).compareTo(
              right.closedAt ?? right.decidedAt,
            ),
          );
    final netValues = closed.map((item) => item.netPnl ?? 0).toList();
    final rValues = closed.map((item) => item.realizedR ?? 0).toList();
    final wins = netValues.where((item) => item > 0).length;
    final losses = netValues.where((item) => item < 0).length;
    final grossProfit = netValues
        .where((item) => item > 0)
        .fold<double>(0, (sum, item) => sum + item);
    final grossLoss = netValues
        .where((item) => item < 0)
        .fold<double>(0, (sum, item) => sum + item.abs());

    var equity = 0.0;
    var peak = 0.0;
    var maximumDrawdown = 0.0;
    for (final value in netValues) {
      equity += value;
      peak = math.max(peak, equity);
      maximumDrawdown = math.max(maximumDrawdown, peak - equity);
    }

    return TradingJournalStatistics(
      closedCount: closed.length,
      winCount: wins,
      lossCount: losses,
      winRatePercent: closed.isEmpty ? 0 : wins / closed.length * 100,
      expectancy: closed.isEmpty
          ? 0
          : netValues.fold<double>(0, (sum, item) => sum + item) /
                closed.length,
      profitFactor: grossLoss == 0
          ? (grossProfit > 0 ? double.infinity : 0)
          : grossProfit / grossLoss,
      averageR: closed.isEmpty
          ? 0
          : rValues.fold<double>(0, (sum, item) => sum + item) / closed.length,
      maximumDrawdown: maximumDrawdown,
      stopCount: closed
          .where((item) => item.closeReason == TradingJournalCloseReason.stop)
          .length,
      takeProfitCount: closed
          .where(
            (item) => const {
              TradingJournalCloseReason.takeProfit1,
              TradingJournalCloseReason.takeProfit2,
              TradingJournalCloseReason.takeProfit3,
            }.contains(item.closeReason),
          )
          .length,
      bySymbol: _groups(closed, (item) => item.symbol),
      byTimeframe: _groups(closed, (item) => item.timeframe),
      byStrategy: _groups(closed, (item) => item.strategy),
    );
  }

  static Map<String, TradingJournalGroupStatistics> _groups(
    Iterable<TradingJournalProjection> values,
    String Function(TradingJournalProjection value) keyOf,
  ) {
    final grouped = <String, List<TradingJournalProjection>>{};
    for (final value in values) {
      grouped.putIfAbsent(keyOf(value), () => []).add(value);
    }
    return Map.unmodifiable({
      for (final entry in grouped.entries)
        entry.key: TradingJournalGroupStatistics(
          trades: entry.value.length,
          netPnl: entry.value.fold<double>(
            0,
            (sum, item) => sum + (item.netPnl ?? 0),
          ),
          averageR: entry.value.isEmpty
              ? 0
              : entry.value.fold<double>(
                      0,
                      (sum, item) => sum + (item.realizedR ?? 0),
                    ) /
                    entry.value.length,
        ),
    });
  }
}
