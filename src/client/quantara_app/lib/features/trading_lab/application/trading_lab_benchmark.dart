import 'trading_lab_metrics.dart';
import '../domain/trading_lab_models.dart';

Map<String, Object?> buildTradingLabBenchmarkMatrix(
  Iterable<TradingLabRun> sourceRuns, {
  DateTime? generatedAtUtc,
}) {
  final byId = <String, TradingLabRun>{
    for (final run in sourceRuns) run.manifest.runId: run,
  };
  final runs = byId.values.toList(
    growable: false,
  )..sort((a, b) => a.manifest.startedAtUtc.compareTo(b.manifest.startedAtUtc));
  final groups = <String, List<TradingLabPosition>>{};
  final groupRuns = <String, Set<String>>{};
  for (final run in runs) {
    for (final position in run.closedPositions) {
      final key =
          '${position.strategy}@${position.strategyVersion}|${position.timeframe}';
      (groups[key] ??= <TradingLabPosition>[]).add(position);
      (groupRuns[key] ??= <String>{}).add(run.manifest.runId);
    }
  }

  final strategyTimeframe = <Map<String, Object?>>[];
  for (final entry in groups.entries) {
    final parts = entry.key.split('|');
    final trades = entry.value;
    final pnls = trades
        .map((item) => item.netRealizedPnl)
        .toList(growable: false);
    final rs = trades.map((item) => item.realizedR).toList(growable: false);
    final wins = pnls.where((value) => value > 1e-9).length;
    final losses = pnls.where((value) => value < -1e-9).length;
    final grossProfit = pnls
        .where((value) => value > 0)
        .fold<double>(0, (sum, value) => sum + value);
    final grossLoss = pnls
        .where((value) => value < 0)
        .fold<double>(0, (sum, value) => sum + value.abs());
    final averageR = rs.isEmpty
        ? 0.0
        : rs.fold<double>(0, (sum, value) => sum + value) / rs.length;
    strategyTimeframe.add({
      'strategyVersion': parts[0],
      'timeframe': parts[1],
      'sampleSize': trades.length,
      'wins': wins,
      'losses': losses,
      'breakevens': trades.length - wins - losses,
      'winRatePercent': trades.isEmpty ? 0 : wins / trades.length * 100,
      'netPnl': pnls.fold<double>(0, (sum, value) => sum + value),
      'averageR': averageR,
      'profitFactor': grossLoss <= 1e-9
          ? (grossProfit > 1e-9 ? null : null)
          : grossProfit / grossLoss,
      'runCount': groupRuns[entry.key]?.length ?? 0,
      'evidenceTier': trades.length >= 30
          ? 'decision_eligible'
          : 'insufficient_sample',
    });
  }
  strategyTimeframe.sort((a, b) {
    final sample = (b['sampleSize'] as int).compareTo(a['sampleSize'] as int);
    if (sample != 0) return sample;
    return (b['averageR'] as double).compareTo(a['averageR'] as double);
  });

  final runConfigurations = <Map<String, Object?>>[
    for (final run in runs)
      {
        'runId': run.manifest.runId,
        'experimentTag': run.manifest.experimentTag,
        'startedAtUtc': run.manifest.startedAtUtc.toIso8601String(),
        'startingEquity': run.manifest.startingEquity,
        'riskPercent': run.manifest.riskPercent,
        'maximumConcurrentPositions': run.manifest.maximumConcurrentPositions,
        'leverage': run.manifest.leverage,
        'timeframes': run.manifest.timeframes,
        'strategies': run.manifest.strategies,
        'minimumConfidencePercent': run.manifest.minimumConfidencePercent,
        'minimumRiskReward': run.manifest.minimumRiskReward,
        'maxEstimatedCostToRiskPercent':
            run.manifest.maxEstimatedCostToRiskPercent,
        'feeRateBps': run.manifest.feeRateBps,
        'slippageBps': run.manifest.slippageBps,
        'spreadBps': run.manifest.spreadBps,
        'metrics': calculateTradingLabMetrics(run).toJson(),
      },
  ];
  final eligible =
      strategyTimeframe
          .where((row) => row['evidenceTier'] == 'decision_eligible')
          .toList(growable: false)
        ..sort(
          (a, b) =>
              (b['averageR'] as double).compareTo(a['averageR'] as double),
        );

  return {
    'schema': 'quantara.trading_lab.benchmark.v1',
    'generatedAtUtc': (generatedAtUtc ?? DateTime.now())
        .toUtc()
        .toIso8601String(),
    'targetTimeframes': const ['5m', '15m', '30m', '1h'],
    'runCount': runs.length,
    'runConfigurations': runConfigurations,
    'strategyTimeframeMatrix': strategyTimeframe,
    'rankingStatus': eligible.isEmpty
        ? 'insufficient_evidence'
        : 'decision_eligible',
    'rankedEligibleStrategyTimeframes': eligible,
    'minimumClosedTradesForRanking': 30,
  };
}
