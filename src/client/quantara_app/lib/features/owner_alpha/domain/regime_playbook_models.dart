import 'dart:collection';

import '../../market_analysis/domain/contextual_price_action_models.dart';
import '../../market_analysis/domain/market_chart_models.dart';
import '../../market_analysis/domain/market_regime_models.dart';
import 'owner_alpha_models.dart';

enum RegimePlaybookId {
  trendPullbackContinuation,
  rangeEdgeSweepReclaim,
  breakoutAcceptanceRetest,
  failedBreakoutReversal,
  momentumExpansionScalp,
}

enum PlaybookCandidateState { inactive, forming, armed }

enum PlaybookManagementPolicy {
  trendRunner,
  rangeMeanThenOppositeEdge,
  breakoutRunner,
  failedBreakScaleOut,
  momentumQuickExit,
}

enum PlaybookConflictOutcome {
  none,
  selectedHighestQuality,
  ambiguousOpposingSignals,
}

final class RegimePlaybookFeatureFlags {
  const RegimePlaybookFeatureFlags({
    this.trendPullbackContinuation = true,
    this.rangeEdgeSweepReclaim = true,
    this.breakoutAcceptanceRetest = true,
    this.failedBreakoutReversal = true,
    this.momentumExpansionScalp = true,
  });

  factory RegimePlaybookFeatureFlags.fromEnvironment() =>
      const RegimePlaybookFeatureFlags(
        trendPullbackContinuation: bool.fromEnvironment(
          'QUANTARA_PLAYBOOK_TREND_PULLBACK',
          defaultValue: true,
        ),
        rangeEdgeSweepReclaim: bool.fromEnvironment(
          'QUANTARA_PLAYBOOK_RANGE_SWEEP',
          defaultValue: true,
        ),
        breakoutAcceptanceRetest: bool.fromEnvironment(
          'QUANTARA_PLAYBOOK_BREAKOUT_RETEST',
          defaultValue: true,
        ),
        failedBreakoutReversal: bool.fromEnvironment(
          'QUANTARA_PLAYBOOK_FAILED_BREAK',
          defaultValue: true,
        ),
        momentumExpansionScalp: bool.fromEnvironment(
          'QUANTARA_PLAYBOOK_MOMENTUM_SCALP',
          defaultValue: true,
        ),
      );

  final bool trendPullbackContinuation;
  final bool rangeEdgeSweepReclaim;
  final bool breakoutAcceptanceRetest;
  final bool failedBreakoutReversal;
  final bool momentumExpansionScalp;

  bool enabled(RegimePlaybookId id) => switch (id) {
    RegimePlaybookId.trendPullbackContinuation => trendPullbackContinuation,
    RegimePlaybookId.rangeEdgeSweepReclaim => rangeEdgeSweepReclaim,
    RegimePlaybookId.breakoutAcceptanceRetest => breakoutAcceptanceRetest,
    RegimePlaybookId.failedBreakoutReversal => failedBreakoutReversal,
    RegimePlaybookId.momentumExpansionScalp => momentumExpansionScalp,
  };
}

final class RegimePlaybookRuntimeContext {
  const RegimePlaybookRuntimeContext({
    required this.evaluatedAtUtc,
    this.higherTimeframeDirection,
    this.higherTimeframeFresh = false,
    this.liquidityVerified = false,
    this.processingLatency = Duration.zero,
    this.maximumMomentumLatency = const Duration(milliseconds: 750),
  });

  final DateTime evaluatedAtUtc;
  final ChartDirection? higherTimeframeDirection;
  final bool higherTimeframeFresh;
  final bool liquidityVerified;
  final Duration processingLatency;
  final Duration maximumMomentumLatency;

  bool get latencyHealthy =>
      !processingLatency.isNegative &&
      processingLatency <= maximumMomentumLatency;

  bool get valid =>
      evaluatedAtUtc.isUtc &&
      !processingLatency.isNegative &&
      maximumMomentumLatency > Duration.zero;
}

final class RegimePlaybookEvaluation {
  RegimePlaybookEvaluation({
    required this.playbook,
    required this.version,
    required this.enabled,
    required this.state,
    required this.direction,
    required this.regime,
    required this.qualityScore,
    required this.context,
    required this.trigger,
    required this.invalidation,
    required Iterable<double> targets,
    required this.managementPolicy,
    required Iterable<String> reasonCodes,
    this.idea,
  }) : targets = UnmodifiableListView(targets.toList(growable: false)),
       reasonCodes = UnmodifiableListView(reasonCodes.toList(growable: false)) {
    if (version.trim().isEmpty ||
        qualityScore < 0 ||
        qualityScore > 100 ||
        context.trim().isEmpty ||
        trigger.trim().isEmpty ||
        invalidation.trim().isEmpty) {
      throw ArgumentError('Playbook evaluation is incomplete.');
    }
    if (state == PlaybookCandidateState.armed &&
        (idea == null || !idea!.isActionable)) {
      throw ArgumentError('An armed playbook requires an actionable idea.');
    }
  }

  final RegimePlaybookId playbook;
  final String version;
  final bool enabled;
  final PlaybookCandidateState state;
  final TradeDirection direction;
  final MarketRegime regime;
  final int qualityScore;
  final String context;
  final String trigger;
  final String invalidation;
  final UnmodifiableListView<double> targets;
  final PlaybookManagementPolicy managementPolicy;
  final UnmodifiableListView<String> reasonCodes;
  final TradeIdea? idea;

  bool get isArmed => state == PlaybookCandidateState.armed;
  bool get isForming => state == PlaybookCandidateState.forming;
}

final class RegimePlaybookPortfolioSnapshot {
  RegimePlaybookPortfolioSnapshot({
    required Iterable<RegimePlaybookEvaluation> evaluations,
    required this.contextual,
    required this.conflictOutcome,
    required Iterable<String> coverageGaps,
    this.selected,
  }) : evaluations = UnmodifiableListView(evaluations.toList(growable: false)),
       coverageGaps = UnmodifiableListView(
         coverageGaps.toList(growable: false),
       );

  final UnmodifiableListView<RegimePlaybookEvaluation> evaluations;
  final ContextualPriceActionAssessment contextual;
  final PlaybookConflictOutcome conflictOutcome;
  final UnmodifiableListView<String> coverageGaps;
  final RegimePlaybookEvaluation? selected;

  Iterable<RegimePlaybookEvaluation> get forming =>
      evaluations.where((item) => item.isForming);

  Iterable<RegimePlaybookEvaluation> get armed =>
      evaluations.where((item) => item.isArmed);
}

final class PlaybookOutcomeSample {
  const PlaybookOutcomeSample({
    required this.playbook,
    required this.resolvedAtUtc,
    required this.pnlR,
    this.missed = false,
  });

  final RegimePlaybookId playbook;
  final DateTime resolvedAtUtc;
  final double pnlR;
  final bool missed;

  bool get valid => resolvedAtUtc.isUtc && pnlR.isFinite;
}

final class PlaybookPerformanceMetrics {
  const PlaybookPerformanceMetrics({
    required this.playbook,
    required this.sampleCount,
    required this.signalsPerWeek,
    required this.expectancyR,
    required this.maximumDrawdownR,
    required this.missedRate,
  });

  final RegimePlaybookId playbook;
  final int sampleCount;
  final double signalsPerWeek;
  final double expectancyR;
  final double maximumDrawdownR;
  final double missedRate;
}

abstract final class PlaybookPerformanceReporter {
  static Map<RegimePlaybookId, PlaybookPerformanceMetrics> summarize(
    Iterable<PlaybookOutcomeSample> samples,
  ) {
    final grouped = <RegimePlaybookId, List<PlaybookOutcomeSample>>{
      for (final id in RegimePlaybookId.values) id: [],
    };
    for (final sample in samples) {
      if (!sample.valid) continue;
      grouped[sample.playbook]!.add(sample);
    }
    return Map.unmodifiable({
      for (final entry in grouped.entries)
        entry.key: _summarize(entry.key, entry.value),
    });
  }

  static PlaybookPerformanceMetrics _summarize(
    RegimePlaybookId id,
    List<PlaybookOutcomeSample> values,
  ) {
    if (values.isEmpty) {
      return PlaybookPerformanceMetrics(
        playbook: id,
        sampleCount: 0,
        signalsPerWeek: 0,
        expectancyR: 0,
        maximumDrawdownR: 0,
        missedRate: 0,
      );
    }
    values.sort(
      (left, right) => left.resolvedAtUtc.compareTo(right.resolvedAtUtc),
    );
    final expectancy =
        values.fold<double>(0, (sum, item) => sum + item.pnlR) / values.length;
    var cumulative = 0.0;
    var peak = 0.0;
    var maximumDrawdown = 0.0;
    for (final sample in values) {
      cumulative += sample.pnlR;
      if (cumulative > peak) peak = cumulative;
      final drawdown = peak - cumulative;
      if (drawdown > maximumDrawdown) maximumDrawdown = drawdown;
    }
    final elapsed = values.last.resolvedAtUtc.difference(
      values.first.resolvedAtUtc,
    );
    final normalizedDays = elapsed.inSeconds / Duration.secondsPerDay;
    final denominatorDays = normalizedDays < 7 ? 7.0 : normalizedDays;
    final signalsPerWeek = values.length * 7 / denominatorDays;
    final missed = values.where((item) => item.missed).length;
    return PlaybookPerformanceMetrics(
      playbook: id,
      sampleCount: values.length,
      signalsPerWeek: signalsPerWeek,
      expectancyR: expectancy,
      maximumDrawdownR: maximumDrawdown,
      missedRate: missed / values.length,
    );
  }
}
