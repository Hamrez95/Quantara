import '../domain/trading_lab_models.dart';

final class TradingLabStrategyScorecard {
  const TradingLabStrategyScorecard({
    required this.strategyVersion,
    required this.symbol,
    required this.timeframe,
    required this.marketRegime,
    required this.direction,
    required this.confidenceBucket,
    required this.riskRewardBucket,
    required this.sampleSize,
    required this.wins,
    required this.losses,
    required this.breakevens,
    required this.winRatePercent,
    required this.netPnl,
    required this.expectancyUsdt,
    required this.averageR,
    required this.medianR,
    required this.profitFactor,
    required this.averageMfeR,
    required this.averageMaeR,
    required this.insufficientSample,
  });

  final String strategyVersion;
  final String symbol;
  final String timeframe;
  final String marketRegime;
  final String direction;
  final String confidenceBucket;
  final String riskRewardBucket;
  final int sampleSize;
  final int wins;
  final int losses;
  final int breakevens;
  final double winRatePercent;
  final double netPnl;
  final double expectancyUsdt;
  final double averageR;
  final double medianR;
  final double? profitFactor;
  final double averageMfeR;
  final double averageMaeR;
  final bool insufficientSample;

  Map<String, Object?> toJson() => {
    'strategyVersion': strategyVersion,
    'symbol': symbol,
    'timeframe': timeframe,
    'marketRegime': marketRegime,
    'direction': direction,
    'confidenceBucket': confidenceBucket,
    'riskRewardBucket': riskRewardBucket,
    'sampleSize': sampleSize,
    'wins': wins,
    'losses': losses,
    'breakevens': breakevens,
    'winRatePercent': winRatePercent,
    'netPnl': netPnl,
    'expectancyUsdt': expectancyUsdt,
    'averageR': averageR,
    'medianR': medianR,
    'profitFactor': profitFactor?.isFinite == true ? profitFactor : null,
    'averageMfeR': averageMfeR,
    'averageMaeR': averageMaeR,
    'insufficientSample': insufficientSample,
  };
}

List<TradingLabStrategyScorecard> buildTradingLabStrategyScorecards(
  TradingLabRun run,
) {
  final groups = <String, List<TradingLabPosition>>{};
  for (final position in run.closedPositions) {
    final key = [
      '${position.strategy}@${position.strategyVersion}',
      position.symbol,
      position.timeframe,
      position.marketRegime,
      position.direction.name,
      _confidenceBucket(position.confidencePercent),
      _riskRewardBucket(position.riskReward),
    ].join('|');
    (groups[key] ??= <TradingLabPosition>[]).add(position);
  }

  final result = <TradingLabStrategyScorecard>[];
  for (final entry in groups.entries) {
    final parts = entry.key.split('|');
    final trades = entry.value;
    final pnls = trades.map((item) => item.netRealizedPnl).toList(growable: false);
    final rs = trades.map((item) => item.realizedR).toList(growable: false);
    final mfe = trades.map(_mfeR).toList(growable: false);
    final mae = trades.map(_maeR).toList(growable: false);
    final wins = pnls.where((value) => value > 1e-9).length;
    final losses = pnls.where((value) => value < -1e-9).length;
    final breakevens = trades.length - wins - losses;
    final grossProfit = pnls
        .where((value) => value > 0)
        .fold<double>(0, (sum, value) => sum + value);
    final grossLoss = pnls
        .where((value) => value < 0)
        .fold<double>(0, (sum, value) => sum + value.abs());
    final netPnl = pnls.fold<double>(0, (sum, value) => sum + value);
    result.add(
      TradingLabStrategyScorecard(
        strategyVersion: parts[0],
        symbol: parts[1],
        timeframe: parts[2],
        marketRegime: parts[3],
        direction: parts[4],
        confidenceBucket: parts[5],
        riskRewardBucket: parts[6],
        sampleSize: trades.length,
        wins: wins,
        losses: losses,
        breakevens: breakevens,
        winRatePercent: trades.isEmpty ? 0 : wins / trades.length * 100,
        netPnl: netPnl,
        expectancyUsdt: trades.isEmpty ? 0 : netPnl / trades.length,
        averageR: _average(rs),
        medianR: _median(rs),
        profitFactor: grossLoss <= 1e-9
            ? (grossProfit > 1e-9 ? double.infinity : null)
            : grossProfit / grossLoss,
        averageMfeR: _average(mfe),
        averageMaeR: _average(mae),
        insufficientSample: trades.length < 30,
      ),
    );
  }
  result.sort((left, right) {
    var value = left.strategyVersion.compareTo(right.strategyVersion);
    if (value != 0) return value;
    value = left.symbol.compareTo(right.symbol);
    if (value != 0) return value;
    value = left.timeframe.compareTo(right.timeframe);
    if (value != 0) return value;
    value = left.marketRegime.compareTo(right.marketRegime);
    if (value != 0) return value;
    value = left.direction.compareTo(right.direction);
    if (value != 0) return value;
    return left.confidenceBucket.compareTo(right.confidenceBucket);
  });
  return List.unmodifiable(result);
}

String _confidenceBucket(int confidence) => switch (confidence) {
  < 60 => '<60',
  < 70 => '60-69',
  < 80 => '70-79',
  < 90 => '80-89',
  _ => '90-100',
};

String _riskRewardBucket(double riskReward) => switch (riskReward) {
  < 1 => '<1',
  < 1.5 => '1.0-1.49',
  < 2 => '1.5-1.99',
  < 3 => '2.0-2.99',
  _ => '3+',
};

double _mfeR(TradingLabPosition position) {
  final riskPerUnit = (position.entryPrice - position.originalStopLoss).abs();
  if (riskPerUnit <= 1e-12) return 0;
  final move = switch (position.direction.name) {
    'long' =>
      (position.maximumFavorablePrice ?? position.entryPrice) - position.entryPrice,
    'short' =>
      position.entryPrice - (position.maximumFavorablePrice ?? position.entryPrice),
    _ => 0.0,
  };
  return move / riskPerUnit;
}

double _maeR(TradingLabPosition position) {
  final riskPerUnit = (position.entryPrice - position.originalStopLoss).abs();
  if (riskPerUnit <= 1e-12) return 0;
  final move = switch (position.direction.name) {
    'long' =>
      position.entryPrice - (position.maximumAdversePrice ?? position.entryPrice),
    'short' =>
      (position.maximumAdversePrice ?? position.entryPrice) - position.entryPrice,
    _ => 0.0,
  };
  return move / riskPerUnit;
}

double _average(List<double> values) => values.isEmpty
    ? 0
    : values.fold<double>(0, (sum, value) => sum + value) / values.length;

double _median(List<double> values) {
  if (values.isEmpty) return 0;
  final sorted = [...values]..sort();
  final middle = sorted.length ~/ 2;
  return sorted.length.isOdd
      ? sorted[middle]
      : (sorted[middle - 1] + sorted[middle]) / 2;
}
