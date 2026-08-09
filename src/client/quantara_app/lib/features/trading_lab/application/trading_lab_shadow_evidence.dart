import 'dart:convert';

import '../../owner_alpha/domain/owner_alpha_models.dart';
import '../domain/trading_lab_models.dart';
import 'trading_lab_review_bundle.dart';

Map<String, Object?> buildTradingLabShadowEvidence(
  TradingLabRun run,
  Iterable<SignalJournalEntry> signalJournal,
) {
  final entries = signalJournal
      .where(
        (entry) =>
            !entry.createdAt.toUtc().isBefore(run.manifest.startedAtUtc) &&
            run.manifest.symbols.contains(entry.symbol.toUpperCase()) &&
            run.manifest.timeframes.contains(entry.timeframe),
      )
      .toList(growable: false)
    ..sort((left, right) => left.createdAt.compareTo(right.createdAt));

  final outcomeCounts = <String, int>{};
  final strategyBuckets = <String, _ShadowAccumulator>{};
  var terminalCount = 0;
  var activatedCount = 0;
  var totalSimulatedPnl = 0.0;
  var simulatedPnlSamples = 0;

  for (final entry in entries) {
    outcomeCounts[entry.outcome.name] =
        (outcomeCounts[entry.outcome.name] ?? 0) + 1;
    if (entry.hasTerminalOutcome || entry.closed) terminalCount += 1;
    if (entry.activatedAt != null) activatedCount += 1;
    final pnl = entry.simulatedPnl;
    if (pnl != null && pnl.isFinite) {
      totalSimulatedPnl += pnl;
      simulatedPnlSamples += 1;
    }
    final bucketKey = [
      '${entry.strategy.name}@${entry.strategyVersion}',
      entry.symbol,
      entry.timeframe,
      entry.marketRegime.name,
      entry.direction.name,
      _confidenceBucket(entry.confidencePercent),
    ].join('|');
    (strategyBuckets[bucketKey] ??= _ShadowAccumulator()).add(entry);
  }

  final scorecards = <Map<String, Object?>>[];
  for (final bucket in strategyBuckets.entries) {
    final parts = bucket.key.split('|');
    final value = bucket.value;
    scorecards.add({
      'strategyVersion': parts[0],
      'symbol': parts[1],
      'timeframe': parts[2],
      'marketRegime': parts[3],
      'direction': parts[4],
      'confidenceBucket': parts[5],
      'sampleSize': value.count,
      'terminalSamples': value.terminal,
      'activatedSamples': value.activated,
      'stopped': value.stopped,
      'tp1OrBetter': value.tp1OrBetter,
      'tp2OrBetter': value.tp2OrBetter,
      'tp3': value.tp3,
      'expiredUntriggered': value.expiredUntriggered,
      'simulatedPnlSamples': value.pnlSamples,
      'simulatedNetPnl': value.pnl,
      'simulatedExpectancyUsdt': value.pnlSamples == 0
          ? null
          : value.pnl / value.pnlSamples,
      'insufficientSample': value.terminal < 30,
    });
  }
  scorecards.sort((left, right) {
    final strategy = (left['strategyVersion'] as String).compareTo(
      right['strategyVersion'] as String,
    );
    if (strategy != 0) return strategy;
    final symbol = (left['symbol'] as String).compareTo(
      right['symbol'] as String,
    );
    if (symbol != 0) return symbol;
    return (left['timeframe'] as String).compareTo(
      right['timeframe'] as String,
    );
  });

  return {
    'summary': {
      'signalsTracked': entries.length,
      'activatedSignals': activatedCount,
      'terminalSignals': terminalCount,
      'outcomes': outcomeCounts,
      'simulatedPnlSamples': simulatedPnlSamples,
      'simulatedNetPnl': totalSimulatedPnl,
      'simulatedExpectancyUsdt': simulatedPnlSamples == 0
          ? null
          : totalSimulatedPnl / simulatedPnlSamples,
      'sampleWarning': terminalCount < 30
          ? 'Shadow sample is small; do not promote or reject a strategy from this evidence alone.'
          : null,
    },
    'scorecards': scorecards,
    'signals': entries.map(_shadowSignalJson).toList(growable: false),
  };
}

String buildTradingLabAiReviewJsonWithShadows(
  TradingLabRun run,
  Iterable<SignalJournalEntry> signalJournal,
) {
  final bundle = buildTradingLabAiReviewBundle(run);
  bundle['shadowEvidence'] = buildTradingLabShadowEvidence(run, signalJournal);
  return const JsonEncoder.withIndent('  ').convert(bundle);
}

Map<String, Object?> _shadowSignalJson(SignalJournalEntry entry) => {
  'setupId': entry.setupId,
  'symbol': entry.symbol,
  'timeframe': entry.timeframe,
  'direction': entry.direction.name,
  'strategy': entry.strategy.name,
  'strategyVersion': entry.strategyVersion,
  'marketRegime': entry.marketRegime.name,
  'confidencePercent': entry.confidencePercent,
  'riskReward': entry.riskReward,
  'createdAtUtc': entry.createdAt.toUtc().toIso8601String(),
  'validUntilUtc': entry.validUntil.toUtc().toIso8601String(),
  'entryLower': entry.entryLower,
  'entryUpper': entry.entryUpper,
  'stopLoss': entry.stopLoss,
  'targets': entry.targets,
  'maximumLoss': entry.maximumLoss,
  'positionSize': entry.positionSize,
  'notionalValue': entry.notionalValue,
  'estimatedRoundTripCosts': entry.estimatedRoundTripCosts,
  'recommendedLeverage': entry.recommendedLeverage,
  'maximumSafeLeverage': entry.maximumSafeLeverage,
  'selectedLeverage': entry.selectedLeverage,
  'outcome': entry.outcome.name,
  'highestTargetHit': entry.highestTargetHit,
  'activatedAtUtc': entry.activatedAt?.toUtc().toIso8601String(),
  'resolvedAtUtc': entry.resolvedAt?.toUtc().toIso8601String(),
  'priceChangePercent': entry.priceChangePercent,
  'simulatedPnl': entry.simulatedPnl,
  'marginReturnPercent': entry.marginReturnPercent,
  'closed': entry.closed,
};

String _confidenceBucket(int confidence) => switch (confidence) {
  < 60 => '<60',
  < 70 => '60-69',
  < 80 => '70-79',
  < 90 => '80-89',
  _ => '90-100',
};

final class _ShadowAccumulator {
  int count = 0;
  int terminal = 0;
  int activated = 0;
  int stopped = 0;
  int tp1OrBetter = 0;
  int tp2OrBetter = 0;
  int tp3 = 0;
  int expiredUntriggered = 0;
  int pnlSamples = 0;
  double pnl = 0;

  void add(SignalJournalEntry entry) {
    count += 1;
    if (entry.hasTerminalOutcome || entry.closed) terminal += 1;
    if (entry.activatedAt != null) activated += 1;
    switch (entry.outcome.name) {
      case 'stopped':
        stopped += 1;
      case 'tp1':
        tp1OrBetter += 1;
      case 'tp2':
        tp1OrBetter += 1;
        tp2OrBetter += 1;
      case 'tp3':
        tp1OrBetter += 1;
        tp2OrBetter += 1;
        tp3 += 1;
      case 'expiredUntriggered':
        expiredUntriggered += 1;
    }
    final simulated = entry.simulatedPnl;
    if (simulated != null && simulated.isFinite) {
      pnlSamples += 1;
      pnl += simulated;
    }
  }
}
