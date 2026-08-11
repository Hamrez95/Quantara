import 'trading_lab_metrics.dart';
import '../domain/trading_lab_models.dart';

const _minimumClosedTradesForRanking = 30;

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

  final strategyTimeframeGroups = <String, List<TradingLabPosition>>{};
  final strategyTimeframeRuns = <String, Set<String>>{};
  final configurationGroups = <String, _BenchmarkConfigurationBucket>{};
  final capitalGroups = <String, _BenchmarkCapitalBucket>{};

  for (final run in runs) {
    final manifest = run.manifest;
    final configKey = _configurationKey(manifest);
    final configBucket = configurationGroups.putIfAbsent(
      configKey,
      () => _BenchmarkConfigurationBucket(manifest),
    );
    configBucket.runIds.add(manifest.runId);
    configBucket.trades.addAll(run.closedPositions);
    configBucket.returns.add(run.returnPercent);
    configBucket.drawdowns.add(run.maximumDrawdownPercent);

    final capitalKey = manifest.startingEquity.toStringAsFixed(8);
    final capitalBucket = capitalGroups.putIfAbsent(
      capitalKey,
      () => _BenchmarkCapitalBucket(manifest.startingEquity),
    );
    capitalBucket.runIds.add(manifest.runId);
    capitalBucket.trades.addAll(run.closedPositions);
    capitalBucket.returns.add(run.returnPercent);
    capitalBucket.drawdowns.add(run.maximumDrawdownPercent);

    for (final position in run.closedPositions) {
      final key =
          '${position.strategy}@${position.strategyVersion}|${position.timeframe}';
      (strategyTimeframeGroups[key] ??= <TradingLabPosition>[]).add(position);
      (strategyTimeframeRuns[key] ??= <String>{}).add(manifest.runId);
    }
  }

  final strategyTimeframe = <Map<String, Object?>>[];
  for (final entry in strategyTimeframeGroups.entries) {
    final parts = entry.key.split('|');
    strategyTimeframe.add({
      'strategyVersion': parts[0],
      'timeframe': parts[1],
      ..._tradeStats(entry.value),
      'runCount': strategyTimeframeRuns[entry.key]?.length ?? 0,
      'evidenceTier': _evidenceTier(entry.value.length),
    });
  }
  _sortEvidenceRows(strategyTimeframe);

  final configurationMatrix = <Map<String, Object?>>[];
  for (final bucket in configurationGroups.values) {
    final manifest = bucket.manifest;
    configurationMatrix.add({
      'configurationId': _configurationKey(manifest),
      'startingEquity': manifest.startingEquity,
      'riskPercent': manifest.riskPercent,
      'maximumConcurrentPositions': manifest.maximumConcurrentPositions,
      'leverage': manifest.leverage,
      'minimumConfidencePercent': manifest.minimumConfidencePercent,
      'minimumRiskReward': manifest.minimumRiskReward,
      'maxEstimatedCostToRiskPercent': manifest.maxEstimatedCostToRiskPercent,
      'portfolioRiskPercent': manifest.portfolioRiskPercent,
      'symbolHeatPercent': manifest.symbolHeatPercent,
      'feeRateBps': manifest.feeRateBps,
      'slippageBps': manifest.slippageBps,
      'spreadBps': manifest.spreadBps,
      'timeframes': manifest.timeframes,
      'strategies': manifest.strategies,
      ..._tradeStats(bucket.trades),
      'runCount': bucket.runIds.length,
      'averageReturnPercent': _average(bucket.returns),
      'averageMaximumDrawdownPercent': _average(bucket.drawdowns),
      'evidenceTier': _evidenceTier(bucket.trades.length),
    });
  }
  _sortEvidenceRows(configurationMatrix);

  final capitalMatrix = <Map<String, Object?>>[];
  for (final bucket in capitalGroups.values) {
    capitalMatrix.add({
      'startingEquity': bucket.startingEquity,
      ..._tradeStats(bucket.trades),
      'runCount': bucket.runIds.length,
      'averageReturnPercent': _average(bucket.returns),
      'averageMaximumDrawdownPercent': _average(bucket.drawdowns),
      'evidenceTier': _evidenceTier(bucket.trades.length),
    });
  }
  _sortEvidenceRows(capitalMatrix);

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
        'portfolioRiskPercent': run.manifest.portfolioRiskPercent,
        'symbolHeatPercent': run.manifest.symbolHeatPercent,
        'feeRateBps': run.manifest.feeRateBps,
        'slippageBps': run.manifest.slippageBps,
        'spreadBps': run.manifest.spreadBps,
        'metrics': calculateTradingLabMetrics(run).toJson(),
      },
  ];

  final eligibleStrategyTimeframes = _eligible(strategyTimeframe);
  final eligibleConfigurations = _eligible(configurationMatrix);
  final eligibleCapital = _eligible(capitalMatrix);
  final anyEligible =
      eligibleStrategyTimeframes.isNotEmpty ||
      eligibleConfigurations.isNotEmpty ||
      eligibleCapital.isNotEmpty;

  return {
    'schema': 'quantara.trading_lab.benchmark.v2',
    'generatedAtUtc': (generatedAtUtc ?? DateTime.now())
        .toUtc()
        .toIso8601String(),
    'targetTimeframes': const ['5m', '15m', '30m', '1h'],
    'runCount': runs.length,
    'runConfigurations': runConfigurations,
    'strategyTimeframeMatrix': strategyTimeframe,
    'configurationMatrix': configurationMatrix,
    'capitalMatrix': capitalMatrix,
    'rankingStatus': anyEligible
        ? 'decision_eligible'
        : 'insufficient_evidence',
    'rankedEligibleStrategyTimeframes': eligibleStrategyTimeframes,
    'rankedEligibleConfigurations': eligibleConfigurations,
    'rankedEligibleCapital': eligibleCapital,
    'minimumClosedTradesForRanking': _minimumClosedTradesForRanking,
    'rankingNote':
        'Rows below the minimum sample remain visible as evidence but are never promoted as a best strategy, timeframe, configuration, or capital level.',
  };
}

Map<String, Object?> _tradeStats(Iterable<TradingLabPosition> source) {
  final trades = source.toList(growable: false);
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
  return {
    'sampleSize': trades.length,
    'wins': wins,
    'losses': losses,
    'breakevens': trades.length - wins - losses,
    'winRatePercent': trades.isEmpty ? 0.0 : wins / trades.length * 100,
    'netPnl': pnls.fold<double>(0, (sum, value) => sum + value),
    'averageR': _average(rs),
    'profitFactor': grossLoss <= 1e-9 ? null : grossProfit / grossLoss,
  };
}

String _configurationKey(TradingLabRunManifest manifest) => [
  'capital=${manifest.startingEquity.toStringAsFixed(4)}',
  'risk=${manifest.riskPercent.toStringAsFixed(4)}',
  'slots=${manifest.maximumConcurrentPositions}',
  'lev=${manifest.leverage}',
  'conf=${manifest.minimumConfidencePercent}',
  'rr=${manifest.minimumRiskReward.toStringAsFixed(4)}',
  'costRisk=${manifest.maxEstimatedCostToRiskPercent.toStringAsFixed(4)}',
  'portfolioRisk=${manifest.portfolioRiskPercent.toStringAsFixed(4)}',
  'heat=${manifest.symbolHeatPercent.toStringAsFixed(4)}',
  'fee=${manifest.feeRateBps.toStringAsFixed(4)}',
  'slip=${manifest.slippageBps.toStringAsFixed(4)}',
  'spread=${manifest.spreadBps.toStringAsFixed(4)}',
  'tf=${manifest.timeframes.join(",")}',
  'strategy=${manifest.strategies.join(",")}',
].join('|');

String _evidenceTier(int sampleSize) =>
    sampleSize >= _minimumClosedTradesForRanking
    ? 'decision_eligible'
    : 'insufficient_sample';

List<Map<String, Object?>> _eligible(List<Map<String, Object?>> rows) {
  final eligible = rows
      .where((row) => row['evidenceTier'] == 'decision_eligible')
      .toList(growable: false);
  _sortEvidenceRows(eligible);
  return eligible;
}

void _sortEvidenceRows(List<Map<String, Object?>> rows) {
  rows.sort((a, b) {
    final aEligible = a['evidenceTier'] == 'decision_eligible';
    final bEligible = b['evidenceTier'] == 'decision_eligible';
    if (aEligible != bEligible) return bEligible ? 1 : -1;
    final averageR = (b['averageR'] as double).compareTo(
      a['averageR'] as double,
    );
    if (averageR != 0) return averageR;
    final sample = (b['sampleSize'] as int).compareTo(a['sampleSize'] as int);
    if (sample != 0) return sample;
    return (b['netPnl'] as double).compareTo(a['netPnl'] as double);
  });
}

double _average(Iterable<double> values) {
  final items = values.toList(growable: false);
  if (items.isEmpty) return 0;
  return items.fold<double>(0, (sum, value) => sum + value) / items.length;
}

final class _BenchmarkConfigurationBucket {
  _BenchmarkConfigurationBucket(this.manifest);

  final TradingLabRunManifest manifest;
  final Set<String> runIds = <String>{};
  final List<TradingLabPosition> trades = <TradingLabPosition>[];
  final List<double> returns = <double>[];
  final List<double> drawdowns = <double>[];
}

final class _BenchmarkCapitalBucket {
  _BenchmarkCapitalBucket(this.startingEquity);

  final double startingEquity;
  final Set<String> runIds = <String>{};
  final List<TradingLabPosition> trades = <TradingLabPosition>[];
  final List<double> returns = <double>[];
  final List<double> drawdowns = <double>[];
}
