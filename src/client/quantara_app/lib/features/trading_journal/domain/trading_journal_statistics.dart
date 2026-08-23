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
    required this.pricedClosedCount,
    required this.economicsPendingCount,
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

  /// All closed records, including closures whose final economics are pending.
  final int closedCount;

  /// Closed records with authoritative net PnL available.
  final int pricedClosedCount;

  /// Closed records that must not be treated as zero-PnL while reconciliation
  /// is still incomplete or economic truth is otherwise unavailable.
  final int economicsPendingCount;
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
    final priced = closed
        .where((item) => item.netPnl != null)
        .toList(growable: false);
    final netValues = priced.map((item) => item.netPnl!).toList(growable: false);
    final rValues = priced
        .map((item) => item.realizedR)
        .whereType<double>()
        .toList(growable: false);
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
      pricedClosedCount: priced.length,
      economicsPendingCount: closed.length - priced.length,
      winCount: wins,
      lossCount: losses,
      winRatePercent: priced.isEmpty ? 0 : wins / priced.length * 100,
      expectancy: priced.isEmpty
          ? 0
          : netValues.fold<double>(0, (sum, item) => sum + item) /
                priced.length,
      profitFactor: grossLoss == 0
          ? (grossProfit > 0 ? double.infinity : 0)
          : grossProfit / grossLoss,
      averageR: rValues.isEmpty
          ? 0
          : rValues.fold<double>(0, (sum, item) => sum + item) / rValues.length,
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
      bySymbol: _groups(priced, (item) => item.symbol),
      byTimeframe: _groups(priced, (item) => item.timeframe),
      byStrategy: _groups(priced, (item) => item.strategy),
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
            (sum, item) => sum + item.netPnl!,
          ),
          averageR: _averageKnownR(entry.value),
        ),
    });
  }

  static double _averageKnownR(Iterable<TradingJournalProjection> values) {
    final known = values
        .map((item) => item.realizedR)
        .whereType<double>()
        .toList(growable: false);
    if (known.isEmpty) return 0;
    return known.fold<double>(0, (sum, item) => sum + item) / known.length;
  }
}
