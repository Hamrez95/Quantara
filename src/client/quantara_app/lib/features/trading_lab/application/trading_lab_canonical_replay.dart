import '../../decision_core/domain/canonical_decision_models.dart';
import '../../owner_alpha/domain/owner_alpha_models.dart';
import '../domain/trading_lab_models.dart';
import 'trading_lab_canonical_decision.dart';

/// Replays captured realtime/shadow signal evidence through the same
/// pre-execution decision contract used by Paper and Local Live.
///
/// This adapter deliberately has no live authority. It accepts only replay or
/// shadow provenance and returns deterministic canonical decision records.
List<CanonicalDecisionRecord> replayTradingLabEvidenceThroughCanonicalPipeline(
  TradingLabRun run,
  Iterable<SignalJournalEntry> signalJournal, {
  required DecisionEnvironment environment,
}) {
  if (environment != DecisionEnvironment.replay &&
      environment != DecisionEnvironment.shadow) {
    throw ArgumentError(
      'Captured Trading Lab evidence can only be replayed as replay or shadow.',
    );
  }

  final entries = signalJournal
      .where(
        (entry) =>
            !entry.createdAt.toUtc().isBefore(run.manifest.startedAtUtc) &&
            run.manifest.symbols.contains(entry.symbol.toUpperCase()) &&
            run.manifest.timeframes.contains(entry.timeframe),
      )
      .toList(growable: false)
    ..sort((left, right) => left.createdAt.compareTo(right.createdAt));

  return entries.map((entry) {
    final candidate = TradingLabPendingCandidate(
      decisionKey:
          'captured|${entry.setupId}|${entry.createdAt.toUtc().microsecondsSinceEpoch}',
      setupId: entry.setupId,
      symbol: entry.symbol,
      timeframe: entry.timeframe,
      direction: entry.direction,
      strategy: entry.strategy.name,
      strategyVersion: entry.strategyVersion,
      marketRegime: entry.marketRegime.name,
      confidencePercent: entry.confidencePercent,
      riskReward: entry.riskReward,
      entryLower: entry.entryLower,
      entryUpper: entry.entryUpper,
      stopLoss: entry.stopLoss,
      targets: entry.targets,
      recommendedLeverage: entry.recommendedLeverage,
      maximumSafeLeverage: entry.maximumSafeLeverage,
      observedAtUtc: entry.createdAt.toUtc(),
      validUntilUtc: entry.validUntil.toUtc(),
      signalCandleOpenTimeUtc: entry.createdAt.toUtc(),
      indicatorSnapshot: const {},
    );

    return evaluateTradingLabCanonicalDecision(
      environment: environment,
      run: run,
      candidate: candidate,
      eventTimeUtc: entry.createdAt.toUtc(),
      marketPrice: (entry.entryLower + entry.entryUpper) / 2,
      availableMargin: run.currentEquity,
      openRisk: 0,
      symbolRisk: 0,
    );
  }).toList(growable: false);
}
