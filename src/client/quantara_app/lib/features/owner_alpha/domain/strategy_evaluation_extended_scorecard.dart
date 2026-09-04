import 'strategy_evaluation_run.dart';

/// Additional deterministic scorecard metrics derived only from immutable
/// evaluation trade facts. No exchange history is queried or inferred here.
final class StrategyEvaluationExtendedScorecard {
  const StrategyEvaluationExtendedScorecard({
    required this.wins,
    required this.losses,
    required this.breakeven,
    required this.grossProfit,
    required this.grossLoss,
    required this.totalCosts,
    required this.averageHoldingTime,
    required this.maximumLosingStreak,
  });

  final int wins;
  final int losses;
  final int breakeven;
  final double grossProfit;
  final double grossLoss;
  final double totalCosts;
  final Duration averageHoldingTime;
  final int maximumLosingStreak;

  factory StrategyEvaluationExtendedScorecard.fromTrades(
    Iterable<StrategyEvaluationTrade> source,
  ) {
    final trades = source.toList(growable: false);
    var wins = 0;
    var losses = 0;
    var breakeven = 0;
    var grossProfit = 0.0;
    var grossLoss = 0.0;
    var totalCosts = 0.0;
    var holdingMicros = 0;
    var losingStreak = 0;
    var maximumLosingStreak = 0;

    for (final trade in trades) {
      trade.validate();
      final net = trade.netPnl;
      holdingMicros += trade.duration.inMicroseconds;
      totalCosts += trade.cost;
      if (trade.grossPnl > 0) {
        grossProfit += trade.grossPnl;
      } else if (trade.grossPnl < 0) {
        grossLoss += trade.grossPnl.abs();
      }
      if (net > 0) {
        wins += 1;
        losingStreak = 0;
      } else if (net < 0) {
        losses += 1;
        losingStreak += 1;
        if (losingStreak > maximumLosingStreak) {
          maximumLosingStreak = losingStreak;
        }
      } else {
        breakeven += 1;
        losingStreak = 0;
      }
    }

    return StrategyEvaluationExtendedScorecard(
      wins: wins,
      losses: losses,
      breakeven: breakeven,
      grossProfit: grossProfit,
      grossLoss: grossLoss,
      totalCosts: totalCosts,
      averageHoldingTime: trades.isEmpty
          ? Duration.zero
          : Duration(microseconds: holdingMicros ~/ trades.length),
      maximumLosingStreak: maximumLosingStreak,
    );
  }

  Map<String, Object?> toJson() => <String, Object?>{
    'wins': wins,
    'losses': losses,
    'breakeven': breakeven,
    'grossProfit': grossProfit,
    'grossLoss': grossLoss,
    'totalCosts': totalCosts,
    'averageHoldingMicros': averageHoldingTime.inMicroseconds,
    'maximumLosingStreak': maximumLosingStreak,
  };
}
