import 'trading_journal_models.dart';
import 'trading_journal_projection.dart';

final class TradingJournalPerformanceGroup {
  const TradingJournalPerformanceGroup({
    required this.trades,
    required this.netPnl,
    required this.averageR,
  });

  final int trades;
  final double netPnl;
  final double averageR;
}

final class TradingJournalPerformanceSummary {
  const TradingJournalPerformanceSummary({
    required this.closedTrades,
    required this.pricedTrades,
    required this.economicsPendingTrades,
    required this.grossPnl,
    required this.fees,
    required this.funding,
    required this.netPnl,
    required this.averageNetPnl,
    required this.averageR,
    required this.averageHoldingDuration,
    required this.riskHours,
    required this.capitalHours,
    required this.netPnlPerRiskHour,
    required this.netPnlPerCapitalHour,
    required this.byStrategy,
  });

  final int closedTrades;
  final int pricedTrades;
  final int economicsPendingTrades;
  final double grossPnl;
  final double fees;
  final double funding;
  final double netPnl;
  final double averageNetPnl;
  final double averageR;
  final Duration averageHoldingDuration;
  final double riskHours;
  final double capitalHours;
  final double netPnlPerRiskHour;
  final double netPnlPerCapitalHour;
  final Map<String, TradingJournalPerformanceGroup> byStrategy;

  factory TradingJournalPerformanceSummary.calculate(
    Iterable<TradingJournalProjection> projections, {
    int maximumClosedTrades = 2000,
  }) {
    if (maximumClosedTrades <= 0) {
      throw ArgumentError.value(
        maximumClosedTrades,
        'maximumClosedTrades',
        'must be positive',
      );
    }

    var closedTrades = 0;
    var pricedTrades = 0;
    var economicsPendingTrades = 0;
    var grossPnl = 0.0;
    var fees = 0.0;
    var funding = 0.0;
    var netPnl = 0.0;
    var realizedRSum = 0.0;
    var realizedRCount = 0;
    var holdingMicroseconds = 0;
    var holdingCount = 0;
    var riskHours = 0.0;
    var capitalHours = 0.0;
    final byStrategy = <String, _MutablePerformanceGroup>{};

    for (final projection in projections) {
      if (projection.state != TradingJournalTradeState.closed) continue;
      closedTrades += 1;
      if (closedTrades > maximumClosedTrades) {
        throw StateError(
          'Trading journal analytics window exceeded $maximumClosedTrades closed trades.',
        );
      }

      if (projection.economicsPending || projection.netPnl == null) {
        economicsPendingTrades += 1;
        continue;
      }

      final net = projection.netPnl!;
      if (!net.isFinite) continue;
      pricedTrades += 1;
      netPnl += net;

      final gross = projection.grossPnl;
      if (gross != null && gross.isFinite) grossPnl += gross;
      final fee = projection.fees;
      if (fee != null && fee.isFinite) fees += fee.abs();
      final fundingValue = projection.funding;
      if (fundingValue != null && fundingValue.isFinite) {
        funding += fundingValue;
      }
      final realizedR = projection.realizedR;
      if (realizedR != null && realizedR.isFinite) {
        realizedRSum += realizedR;
        realizedRCount += 1;
      }

      final duration = projection.holdingDuration;
      if (duration != null && !duration.isNegative) {
        holdingMicroseconds += duration.inMicroseconds;
        holdingCount += 1;
        final hours = duration.inMicroseconds / Duration.microsecondsPerHour;
        final plan = projection.plan;
        if (plan != null) {
          if (plan.riskBudget.isFinite && plan.riskBudget > 0) {
            riskHours += plan.riskBudget * hours;
          }
          if (plan.expectedMargin.isFinite && plan.expectedMargin > 0) {
            capitalHours += plan.expectedMargin * hours;
          }
        }
      }

      final group = byStrategy.putIfAbsent(
        projection.strategy,
        _MutablePerformanceGroup.new,
      );
      group.trades += 1;
      group.netPnl += net;
      if (realizedR != null && realizedR.isFinite) {
        group.realizedRSum += realizedR;
        group.realizedRCount += 1;
      }
    }

    return TradingJournalPerformanceSummary(
      closedTrades: closedTrades,
      pricedTrades: pricedTrades,
      economicsPendingTrades: economicsPendingTrades,
      grossPnl: grossPnl,
      fees: fees,
      funding: funding,
      netPnl: netPnl,
      averageNetPnl: pricedTrades == 0 ? 0 : netPnl / pricedTrades,
      averageR: realizedRCount == 0 ? 0 : realizedRSum / realizedRCount,
      averageHoldingDuration: holdingCount == 0
          ? Duration.zero
          : Duration(microseconds: holdingMicroseconds ~/ holdingCount),
      riskHours: riskHours,
      capitalHours: capitalHours,
      netPnlPerRiskHour: riskHours <= 0 ? 0 : netPnl / riskHours,
      netPnlPerCapitalHour: capitalHours <= 0 ? 0 : netPnl / capitalHours,
      byStrategy: Map.unmodifiable({
        for (final entry in byStrategy.entries)
          entry.key: TradingJournalPerformanceGroup(
            trades: entry.value.trades,
            netPnl: entry.value.netPnl,
            averageR: entry.value.realizedRCount == 0
                ? 0
                : entry.value.realizedRSum / entry.value.realizedRCount,
          ),
      }),
    );
  }
}

final class _MutablePerformanceGroup {
  int trades = 0;
  double netPnl = 0;
  double realizedRSum = 0;
  int realizedRCount = 0;
}
