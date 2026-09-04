import 'strategy_evaluation_run.dart';

enum StrategyEvaluationTradeSide { long, short }

/// Manual evaluation baseline. Exchange wallet history is intentionally not a
/// supported source because an evaluation baseline must be user-configured.
final class StrategyEvaluationCapitalBaseline {
  const StrategyEvaluationCapitalBaseline.manualSetting(this.amount);

  final double amount;
  String get source => 'manualSetting';

  void validate() {
    if (!amount.isFinite || amount <= 0) {
      throw ArgumentError.value(amount, 'amount');
    }
  }
}

/// Immutable per-trade accounting facts that are not inferred from exchange
/// account history. `fees + funding` may be lower than `trade.cost` because the
/// deterministic evaluation cost can also contain slippage.
final class StrategyEvaluationTradeAccounting {
  const StrategyEvaluationTradeAccounting({
    required this.tradeId,
    required this.side,
    required this.fees,
    required this.funding,
  });

  final String tradeId;
  final StrategyEvaluationTradeSide side;
  final double fees;
  final double funding;

  void validate() {
    if (tradeId.trim().isEmpty) throw ArgumentError.value(tradeId, 'tradeId');
    if (!fees.isFinite || fees < 0) throw ArgumentError.value(fees, 'fees');
    if (!funding.isFinite) throw ArgumentError.value(funding, 'funding');
  }
}

/// Compact setup scorecard projection scoped to exactly one immutable run.
/// It derives only from run-owned trade facts plus explicitly supplied manual
/// accounting metadata and never grants execution authority.
final class StrategyEvaluationAccountScorecard {
  const StrategyEvaluationAccountScorecard({
    required this.runId,
    required this.strategyId,
    required this.strategyVersion,
    required this.snapshotHash,
    required this.duration,
    required this.openedTrades,
    required this.longCount,
    required this.shortCount,
    required this.wins,
    required this.losses,
    required this.breakeven,
    required this.grossProfit,
    required this.grossLoss,
    required this.fees,
    required this.funding,
    required this.netPnl,
    required this.startingEvaluationCapital,
    required this.currentEvaluationEquity,
    required this.roi,
    required this.maximumDrawdown,
  });

  final String runId;
  final String strategyId;
  final String strategyVersion;
  final String snapshotHash;
  final Duration duration;
  final int openedTrades;
  final int longCount;
  final int shortCount;
  final int wins;
  final int losses;
  final int breakeven;
  final double grossProfit;
  final double grossLoss;
  final double fees;
  final double funding;
  final double netPnl;
  final double startingEvaluationCapital;
  final double currentEvaluationEquity;
  final double roi;
  final double maximumDrawdown;

  bool get grantsLocalLiveAuthority => false;

  factory StrategyEvaluationAccountScorecard.fromRun({
    required StrategyEvaluationRun run,
    required StrategyEvaluationCapitalBaseline baseline,
    required Iterable<StrategyEvaluationTradeAccounting> accounting,
  }) {
    baseline.validate();
    final byTradeId = <String, StrategyEvaluationTradeAccounting>{};
    for (final fact in accounting) {
      fact.validate();
      if (byTradeId.putIfAbsent(fact.tradeId, () => fact) != fact) {
        throw ArgumentError('duplicate accounting for ${fact.tradeId}');
      }
    }

    final runTradeIds = run.trades.map((trade) => trade.tradeId).toSet();
    if (byTradeId.keys.any((tradeId) => !runTradeIds.contains(tradeId))) {
      throw ArgumentError('accounting contains a trade outside this run');
    }
    if (byTradeId.length != run.trades.length ||
        run.trades.any((trade) => !byTradeId.containsKey(trade.tradeId))) {
      throw ArgumentError('accounting must cover every trade in this run');
    }

    var longCount = 0;
    var shortCount = 0;
    var wins = 0;
    var losses = 0;
    var breakeven = 0;
    var grossProfit = 0.0;
    var grossLoss = 0.0;
    var fees = 0.0;
    var funding = 0.0;

    for (final trade in run.trades) {
      trade.validate();
      final fact = byTradeId[trade.tradeId]!;
      switch (fact.side) {
        case StrategyEvaluationTradeSide.long:
          longCount += 1;
        case StrategyEvaluationTradeSide.short:
          shortCount += 1;
      }
      if (trade.netPnl > 0) {
        wins += 1;
      } else if (trade.netPnl < 0) {
        losses += 1;
      } else {
        breakeven += 1;
      }
      if (trade.grossPnl > 0) {
        grossProfit += trade.grossPnl;
      } else if (trade.grossPnl < 0) {
        grossLoss += trade.grossPnl.abs();
      }
      fees += fact.fees;
      funding += fact.funding;
    }

    final netPnl = run.scorecard.totalNetPnl;
    return StrategyEvaluationAccountScorecard(
      runId: run.runId,
      strategyId: run.identity.strategyId,
      strategyVersion: run.identity.strategyVersion,
      snapshotHash: run.identity.snapshotHash,
      duration: run.rangeEndUtc.difference(run.rangeStartUtc),
      openedTrades: run.trades.length,
      longCount: longCount,
      shortCount: shortCount,
      wins: wins,
      losses: losses,
      breakeven: breakeven,
      grossProfit: grossProfit,
      grossLoss: grossLoss,
      fees: fees,
      funding: funding,
      netPnl: netPnl,
      startingEvaluationCapital: baseline.amount,
      currentEvaluationEquity: baseline.amount + netPnl,
      roi: netPnl / baseline.amount,
      maximumDrawdown: run.scorecard.maximumDrawdown,
    );
  }

  Map<String, Object?> toJson() => <String, Object?>{
    'schemaVersion': 1,
    'runId': runId,
    'strategyId': strategyId,
    'strategyVersion': strategyVersion,
    'snapshotHash': snapshotHash,
    'durationMicros': duration.inMicroseconds,
    'openedTrades': openedTrades,
    'longCount': longCount,
    'shortCount': shortCount,
    'wins': wins,
    'losses': losses,
    'breakeven': breakeven,
    'grossProfit': grossProfit,
    'grossLoss': grossLoss,
    'fees': fees,
    'funding': funding,
    'netPnl': netPnl,
    'startingEvaluationCapital': startingEvaluationCapital,
    'startingCapitalSource': 'manualSetting',
    'currentEvaluationEquity': currentEvaluationEquity,
    'roi': roi,
    'maximumDrawdown': maximumDrawdown,
    'grantsLocalLiveAuthority': false,
  };
}
