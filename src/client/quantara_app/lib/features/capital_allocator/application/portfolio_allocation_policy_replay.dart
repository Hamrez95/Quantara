import 'dart:collection';
import 'dart:convert';
import 'dart:math' as math;

import 'package:crypto/crypto.dart';

import '../../portfolio_risk/domain/portfolio_correlation_policy.dart';
import '../domain/portfolio_capital_allocator.dart';

enum PortfolioAllocationReplayPolicy {
  conservativeEqualRisk,
  utilityWeightedFixedRisk,
  correlationAwareMarginalUtility,
  reserveCapacity,
}

final class PortfolioAllocationReplayOutcome {
  const PortfolioAllocationReplayOutcome({
    required this.proposalId,
    required this.realizedNetR,
    required this.riskHours,
    required this.capitalHours,
    required this.executionCostR,
    this.holdingFrames = 1,
  });

  final String proposalId;
  final double realizedNetR;
  final double riskHours;
  final double capitalHours;
  final double executionCostR;
  final int holdingFrames;

  bool get valid =>
      proposalId.trim().isNotEmpty &&
      realizedNetR.isFinite &&
      riskHours.isFinite &&
      riskHours >= 0 &&
      capitalHours.isFinite &&
      capitalHours >= 0 &&
      executionCostR.isFinite &&
      executionCostR >= 0 &&
      holdingFrames >= 1;
}

final class PortfolioAllocationReplayFrame {
  PortfolioAllocationReplayFrame({
    required this.frameId,
    required this.occurredAtUtc,
    required Iterable<PortfolioAllocationProposal> proposals,
    required Iterable<PortfolioAllocationReplayOutcome> outcomes,
  }) : proposals = UnmodifiableListView(proposals.toList(growable: false)),
       outcomes = UnmodifiableMapView({
         for (final outcome in outcomes) outcome.proposalId.trim(): outcome,
       }) {
    final proposalIds = <String>{};
    if (frameId.trim().isEmpty || !occurredAtUtc.isUtc) {
      throw const FormatException(
        'Allocation replay frame identity is invalid.',
      );
    }
    for (final proposal in this.proposals) {
      final id = proposal.id.trim();
      if (id.isEmpty || !proposalIds.add(id)) {
        throw const FormatException(
          'Allocation replay proposal identities must be unique and non-empty.',
        );
      }
    }
    if (this.outcomes.length != outcomes.length ||
        this.outcomes.values.any((outcome) => !outcome.valid) ||
        this.outcomes.keys.toSet().difference(proposalIds).isNotEmpty ||
        proposalIds.difference(this.outcomes.keys.toSet()).isNotEmpty) {
      throw const FormatException(
        'Allocation replay outcomes must cover every proposal exactly once.',
      );
    }
  }

  final String frameId;
  final DateTime occurredAtUtc;
  final UnmodifiableListView<PortfolioAllocationProposal> proposals;
  final UnmodifiableMapView<String, PortfolioAllocationReplayOutcome> outcomes;
}

final class PortfolioAllocationReplayConfiguration {
  const PortfolioAllocationReplayConfiguration({
    this.version = 'portfolio-allocation-replay/1.0',
    this.totalRiskBudget = 10,
    this.totalMarginBudget = 100,
    this.maximumSelections = 3,
    this.minimumUtilityScore = 0,
    this.reserveRiskFraction = 0.2,
    this.reserveMarginFraction = 0.2,
    this.correlationPolicy = const PortfolioCorrelationPolicy(),
  });

  final String version;
  final double totalRiskBudget;
  final double totalMarginBudget;
  final int maximumSelections;
  final double minimumUtilityScore;
  final double reserveRiskFraction;
  final double reserveMarginFraction;
  final PortfolioCorrelationPolicy correlationPolicy;

  bool get valid =>
      version.trim().isNotEmpty &&
      totalRiskBudget.isFinite &&
      totalRiskBudget > 0 &&
      totalMarginBudget.isFinite &&
      totalMarginBudget > 0 &&
      maximumSelections > 0 &&
      minimumUtilityScore.isFinite &&
      reserveRiskFraction.isFinite &&
      reserveRiskFraction >= 0 &&
      reserveRiskFraction < 1 &&
      reserveMarginFraction.isFinite &&
      reserveMarginFraction >= 0 &&
      reserveMarginFraction < 1 &&
      correlationPolicy.maximumBucketRiskFraction.isFinite &&
      correlationPolicy.maximumBucketRiskFraction > 0 &&
      correlationPolicy.maximumBucketRiskFraction <= 1;
}

final class PortfolioAllocationReplaySelection {
  const PortfolioAllocationReplaySelection({
    required this.proposalId,
    required this.symbol,
    required this.utilityScore,
    required this.allocatedRisk,
    required this.allocatedMargin,
    required this.allocatedQuantity,
    required this.correlationBucket,
    required this.releaseFrameIndex,
  });

  final String proposalId;
  final String symbol;
  final double utilityScore;
  final double allocatedRisk;
  final double allocatedMargin;
  final double allocatedQuantity;
  final String correlationBucket;
  final int releaseFrameIndex;

  Map<String, Object?> toJson() => {
    'proposalId': proposalId,
    'symbol': symbol,
    'utilityScore': utilityScore,
    'allocatedRisk': allocatedRisk,
    'allocatedMargin': allocatedMargin,
    'allocatedQuantity': allocatedQuantity,
    'correlationBucket': correlationBucket,
    'releaseFrameIndex': releaseFrameIndex,
  };
}

final class PortfolioAllocationReplayFrameResult {
  PortfolioAllocationReplayFrameResult({
    required this.frameId,
    required this.occurredAtUtc,
    required Iterable<PortfolioAllocationReplaySelection> selected,
    required this.lockedRiskAfterSelection,
    required this.lockedMarginAfterSelection,
    required this.opportunityRegret,
  }) : selected = UnmodifiableListView(selected.toList(growable: false));

  final String frameId;
  final DateTime occurredAtUtc;
  final UnmodifiableListView<PortfolioAllocationReplaySelection> selected;
  final double lockedRiskAfterSelection;
  final double lockedMarginAfterSelection;
  final double opportunityRegret;

  Map<String, Object?> toJson() => {
    'frameId': frameId,
    'occurredAtUtc': occurredAtUtc.toIso8601String(),
    'selected': selected.map((value) => value.toJson()).toList(growable: false),
    'lockedRiskAfterSelection': lockedRiskAfterSelection,
    'lockedMarginAfterSelection': lockedMarginAfterSelection,
    'opportunityRegret': opportunityRegret,
  };
}

final class PortfolioAllocationReplayMetrics {
  const PortfolioAllocationReplayMetrics({
    required this.frameCount,
    required this.opportunityCount,
    required this.selectionCount,
    required this.netPnl,
    required this.netExpectancyPerSelection,
    required this.pnlPerRiskHour,
    required this.pnlPerCapitalHour,
    required this.maximumDrawdown,
    required this.worstSingleLoss,
    required this.averageRiskUtilization,
    required this.averageCapitalUtilization,
    required this.averageIdleRisk,
    required this.averageIdleMargin,
    required this.riskTurnover,
    required this.tradingCosts,
    required this.maximumConcentrationFraction,
    required this.opportunityRegret,
  });

  final int frameCount;
  final int opportunityCount;
  final int selectionCount;
  final double netPnl;
  final double netExpectancyPerSelection;
  final double pnlPerRiskHour;
  final double pnlPerCapitalHour;
  final double maximumDrawdown;
  final double worstSingleLoss;
  final double averageRiskUtilization;
  final double averageCapitalUtilization;
  final double averageIdleRisk;
  final double averageIdleMargin;
  final double riskTurnover;
  final double tradingCosts;
  final double maximumConcentrationFraction;
  final double opportunityRegret;

  Map<String, Object?> toJson() => {
    'frameCount': frameCount,
    'opportunityCount': opportunityCount,
    'selectionCount': selectionCount,
    'netPnl': netPnl,
    'netExpectancyPerSelection': netExpectancyPerSelection,
    'pnlPerRiskHour': pnlPerRiskHour,
    'pnlPerCapitalHour': pnlPerCapitalHour,
    'maximumDrawdown': maximumDrawdown,
    'worstSingleLoss': worstSingleLoss,
    'averageRiskUtilization': averageRiskUtilization,
    'averageCapitalUtilization': averageCapitalUtilization,
    'averageIdleRisk': averageIdleRisk,
    'averageIdleMargin': averageIdleMargin,
    'riskTurnover': riskTurnover,
    'tradingCosts': tradingCosts,
    'maximumConcentrationFraction': maximumConcentrationFraction,
    'opportunityRegret': opportunityRegret,
  };
}

final class PortfolioAllocationReplayResult {
  PortfolioAllocationReplayResult({
    required this.policy,
    required this.configurationVersion,
    required Iterable<PortfolioAllocationReplayFrameResult> frames,
    required this.metrics,
    required this.fingerprint,
  }) : frames = UnmodifiableListView(frames.toList(growable: false));

  final PortfolioAllocationReplayPolicy policy;
  final String configurationVersion;
  final UnmodifiableListView<PortfolioAllocationReplayFrameResult> frames;
  final PortfolioAllocationReplayMetrics metrics;
  final String fingerprint;

  Map<String, Object?> toJson() => {
    'policy': policy.name,
    'configurationVersion': configurationVersion,
    'frames': frames.map((value) => value.toJson()).toList(growable: false),
    'metrics': metrics.toJson(),
    'fingerprint': fingerprint,
  };
}

abstract final class PortfolioAllocationPolicyReplay {
  static List<PortfolioAllocationReplayResult> compare({
    required Iterable<PortfolioAllocationReplayFrame> frames,
    PortfolioAllocationReplayConfiguration configuration =
        const PortfolioAllocationReplayConfiguration(),
  }) {
    final values = frames.toList(growable: false);
    _validateFrames(values, configuration);
    return PortfolioAllocationReplayPolicy.values
        .map(
          (policy) => _run(
            policy: policy,
            frames: values,
            configuration: configuration,
          ),
        )
        .toList(growable: false);
  }

  static PortfolioAllocationReplayResult run({
    required PortfolioAllocationReplayPolicy policy,
    required Iterable<PortfolioAllocationReplayFrame> frames,
    PortfolioAllocationReplayConfiguration configuration =
        const PortfolioAllocationReplayConfiguration(),
  }) {
    final values = frames.toList(growable: false);
    _validateFrames(values, configuration);
    return _run(policy: policy, frames: values, configuration: configuration);
  }

  static void _validateFrames(
    List<PortfolioAllocationReplayFrame> frames,
    PortfolioAllocationReplayConfiguration configuration,
  ) {
    if (!configuration.valid) {
      throw const FormatException(
        'Allocation replay configuration is invalid.',
      );
    }
    DateTime? previous;
    final frameIds = <String>{};
    for (final frame in frames) {
      if (!frameIds.add(frame.frameId.trim()) ||
          (previous != null && frame.occurredAtUtc.isBefore(previous))) {
        throw const FormatException(
          'Allocation replay frames must have unique IDs and ordered UTC time.',
        );
      }
      previous = frame.occurredAtUtc;
    }
  }

  static PortfolioAllocationReplayResult _run({
    required PortfolioAllocationReplayPolicy policy,
    required List<PortfolioAllocationReplayFrame> frames,
    required PortfolioAllocationReplayConfiguration configuration,
  }) {
    final active = <_ActiveReplayAllocation>[];
    final frameResults = <PortfolioAllocationReplayFrameResult>[];
    final realizedPath = <double>[];
    var cumulativePnl = 0.0;
    var peakPnl = 0.0;
    var maximumDrawdown = 0.0;
    var worstSingleLoss = 0.0;
    var riskHours = 0.0;
    var capitalHours = 0.0;
    var riskTurnover = 0.0;
    var tradingCosts = 0.0;
    var riskUtilizationSum = 0.0;
    var capitalUtilizationSum = 0.0;
    var idleRiskSum = 0.0;
    var idleMarginSum = 0.0;
    var maximumConcentrationFraction = 0.0;
    var opportunityRegret = 0.0;
    var opportunityCount = 0;
    var selectionCount = 0;

    void realize(_ActiveReplayAllocation allocation) {
      final pnl =
          allocation.selection.allocatedRisk * allocation.outcome.realizedNetR;
      cumulativePnl += pnl;
      peakPnl = math.max(peakPnl, cumulativePnl);
      maximumDrawdown = math.max(maximumDrawdown, peakPnl - cumulativePnl);
      worstSingleLoss = math.max(worstSingleLoss, math.max(0.0, -pnl));
      riskHours +=
          allocation.selection.allocatedRisk * allocation.outcome.riskHours;
      capitalHours +=
          allocation.selection.allocatedMargin *
          allocation.outcome.capitalHours;
      tradingCosts +=
          allocation.selection.allocatedRisk *
          allocation.outcome.executionCostR;
      realizedPath.add(cumulativePnl);
    }

    for (var frameIndex = 0; frameIndex < frames.length; frameIndex++) {
      final frame = frames[frameIndex];
      final released =
          active
              .where(
                (allocation) =>
                    allocation.selection.releaseFrameIndex <= frameIndex,
              )
              .toList(growable: false)
            ..sort(
              (left, right) => left.selection.proposalId.compareTo(
                right.selection.proposalId,
              ),
            );
      for (final allocation in released) {
        realize(allocation);
      }
      active.removeWhere(
        (allocation) => allocation.selection.releaseFrameIndex <= frameIndex,
      );

      opportunityCount += frame.proposals.length;
      final beforeRisk = active.fold<double>(
        0,
        (sum, allocation) => sum + allocation.selection.allocatedRisk,
      );
      final beforeMargin = active.fold<double>(
        0,
        (sum, allocation) => sum + allocation.selection.allocatedMargin,
      );
      final availableRisk = math.max(
        0.0,
        configuration.totalRiskBudget - beforeRisk,
      );
      final availableMargin = math.max(
        0.0,
        configuration.totalMarginBudget - beforeMargin,
      );
      final availableSlots = math.max(
        0,
        configuration.maximumSelections - active.length,
      );
      final ranked = frame.proposals.toList(growable: false)
        ..sort(_compareProposals);
      final activeSymbols = active
          .map((allocation) => allocation.selection.symbol.toUpperCase())
          .toSet();
      final bucketRisk = <String, double>{};
      for (final allocation in active) {
        bucketRisk.update(
          allocation.selection.correlationBucket,
          (value) => value + allocation.selection.allocatedRisk,
          ifAbsent: () => allocation.selection.allocatedRisk,
        );
      }

      final selected = _select(
        policy: policy,
        frameIndex: frameIndex,
        ranked: ranked,
        outcomes: frame.outcomes,
        availableRisk: availableRisk,
        availableMargin: availableMargin,
        availableSlots: availableSlots,
        activeSymbols: activeSymbols,
        bucketRisk: bucketRisk,
        configuration: configuration,
      );
      final selectedIds = selected.map((value) => value.proposalId).toSet();
      final minimumActiveUtility = active.isEmpty
          ? null
          : active
                .map((allocation) => allocation.selection.utilityScore)
                .reduce(math.min);
      var frameRegret = 0.0;
      if (minimumActiveUtility != null) {
        final bucketLimit =
            configuration.totalRiskBudget *
            configuration.correlationPolicy.maximumBucketRiskFraction;
        for (final proposal in ranked) {
          if (selectedIds.contains(proposal.id) ||
              !proposal.valid ||
              !proposal.riskDecision.allowed ||
              proposal.utility.score < configuration.minimumUtilityScore) {
            continue;
          }
          final bucket = configuration.correlationPolicy.bucketFor(
            symbol: proposal.candidate.symbol,
            assetGroup: proposal.candidate.assetGroup,
          );
          final blockedByEarlierCapital =
              availableSlots == 0 ||
              proposal.requestedRisk > availableRisk + 1e-9 ||
              proposal.requestedMargin > availableMargin + 1e-9 ||
              activeSymbols.contains(proposal.symbol) ||
              (bucketRisk[bucket] ?? 0) + proposal.requestedRisk >
                  bucketLimit + 1e-9;
          if (!blockedByEarlierCapital) continue;
          frameRegret += math.max(
            0.0,
            proposal.utility.score - minimumActiveUtility,
          );
        }
      }
      opportunityRegret += frameRegret;

      for (final selection in selected) {
        final outcome = frame.outcomes[selection.proposalId]!;
        active.add(
          _ActiveReplayAllocation(selection: selection, outcome: outcome),
        );
        riskTurnover += selection.allocatedRisk;
        selectionCount += 1;
      }

      final lockedRisk = active.fold<double>(
        0,
        (sum, allocation) => sum + allocation.selection.allocatedRisk,
      );
      final lockedMargin = active.fold<double>(
        0,
        (sum, allocation) => sum + allocation.selection.allocatedMargin,
      );
      riskUtilizationSum += lockedRisk / configuration.totalRiskBudget;
      capitalUtilizationSum += lockedMargin / configuration.totalMarginBudget;
      idleRiskSum += math.max(0.0, configuration.totalRiskBudget - lockedRisk);
      idleMarginSum += math.max(
        0.0,
        configuration.totalMarginBudget - lockedMargin,
      );
      final riskByBucket = <String, double>{};
      for (final allocation in active) {
        riskByBucket.update(
          allocation.selection.correlationBucket,
          (value) => value + allocation.selection.allocatedRisk,
          ifAbsent: () => allocation.selection.allocatedRisk,
        );
      }
      for (final value in riskByBucket.values) {
        maximumConcentrationFraction = math.max(
          maximumConcentrationFraction,
          value / configuration.totalRiskBudget,
        );
      }

      frameResults.add(
        PortfolioAllocationReplayFrameResult(
          frameId: frame.frameId,
          occurredAtUtc: frame.occurredAtUtc,
          selected: selected,
          lockedRiskAfterSelection: lockedRisk,
          lockedMarginAfterSelection: lockedMargin,
          opportunityRegret: frameRegret,
        ),
      );
    }

    active.sort((left, right) {
      final releaseOrder = left.selection.releaseFrameIndex.compareTo(
        right.selection.releaseFrameIndex,
      );
      if (releaseOrder != 0) return releaseOrder;
      return left.selection.proposalId.compareTo(right.selection.proposalId);
    });
    for (final allocation in active) {
      realize(allocation);
    }

    final frameCount = frames.length;
    final metrics = PortfolioAllocationReplayMetrics(
      frameCount: frameCount,
      opportunityCount: opportunityCount,
      selectionCount: selectionCount,
      netPnl: cumulativePnl,
      netExpectancyPerSelection: selectionCount == 0
          ? 0
          : cumulativePnl / selectionCount,
      pnlPerRiskHour: riskHours == 0 ? 0 : cumulativePnl / riskHours,
      pnlPerCapitalHour: capitalHours == 0 ? 0 : cumulativePnl / capitalHours,
      maximumDrawdown: maximumDrawdown,
      worstSingleLoss: worstSingleLoss,
      averageRiskUtilization: frameCount == 0
          ? 0
          : riskUtilizationSum / frameCount,
      averageCapitalUtilization: frameCount == 0
          ? 0
          : capitalUtilizationSum / frameCount,
      averageIdleRisk: frameCount == 0 ? 0 : idleRiskSum / frameCount,
      averageIdleMargin: frameCount == 0 ? 0 : idleMarginSum / frameCount,
      riskTurnover: riskTurnover,
      tradingCosts: tradingCosts,
      maximumConcentrationFraction: maximumConcentrationFraction,
      opportunityRegret: opportunityRegret,
    );
    final fingerprint = _fingerprint(
      policy: policy,
      configuration: configuration,
      frames: frameResults,
      metrics: metrics,
      realizedPath: realizedPath,
    );
    return PortfolioAllocationReplayResult(
      policy: policy,
      configurationVersion: configuration.version,
      frames: frameResults,
      metrics: metrics,
      fingerprint: fingerprint,
    );
  }

  static List<PortfolioAllocationReplaySelection> _select({
    required PortfolioAllocationReplayPolicy policy,
    required int frameIndex,
    required List<PortfolioAllocationProposal> ranked,
    required Map<String, PortfolioAllocationReplayOutcome> outcomes,
    required double availableRisk,
    required double availableMargin,
    required int availableSlots,
    required Set<String> activeSymbols,
    required Map<String, double> bucketRisk,
    required PortfolioAllocationReplayConfiguration configuration,
  }) {
    if (availableSlots <= 0 || availableRisk <= 0 || availableMargin <= 0) {
      return const [];
    }
    final candidates = ranked
        .where(
          (proposal) =>
              proposal.valid &&
              proposal.riskDecision.allowed &&
              proposal.requestedRisk > 0 &&
              proposal.utility.score >= configuration.minimumUtilityScore &&
              !activeSymbols.contains(proposal.symbol),
        )
        .toList(growable: false);
    if (candidates.isEmpty) return const [];

    final riskLimit = policy == PortfolioAllocationReplayPolicy.reserveCapacity
        ? availableRisk * (1 - configuration.reserveRiskFraction)
        : availableRisk;
    final marginLimit =
        policy == PortfolioAllocationReplayPolicy.reserveCapacity
        ? availableMargin * (1 - configuration.reserveMarginFraction)
        : availableMargin;
    final selected = <PortfolioAllocationReplaySelection>[];
    final selectedSymbols = <String>{...activeSymbols};
    final workingBucketRisk = <String, double>{...bucketRisk};
    var riskUsed = 0.0;
    var marginUsed = 0.0;

    double requestedRiskFor(PortfolioAllocationProposal proposal) {
      if (policy == PortfolioAllocationReplayPolicy.conservativeEqualRisk) {
        final slice = riskLimit / availableSlots;
        return math.min(proposal.requestedRisk, slice);
      }
      if (policy == PortfolioAllocationReplayPolicy.utilityWeightedFixedRisk) {
        final pool = candidates.take(availableSlots).toList(growable: false);
        final positiveScores = pool
            .map((value) => math.max(0.000001, value.utility.score))
            .toList(growable: false);
        final totalScore = positiveScores.fold<double>(
          0,
          (sum, value) => sum + value,
        );
        final index = pool.indexWhere((value) => value.id == proposal.id);
        if (index < 0 || totalScore <= 0) return 0;
        final weighted = riskLimit * positiveScores[index] / totalScore;
        return math.min(proposal.requestedRisk, weighted);
      }
      return proposal.requestedRisk;
    }

    for (final proposal in candidates) {
      if (selected.length >= availableSlots ||
          selectedSymbols.contains(proposal.symbol)) {
        continue;
      }
      final allocatedRisk = requestedRiskFor(proposal);
      if (!allocatedRisk.isFinite || allocatedRisk <= 0) continue;
      final riskScale = allocatedRisk / proposal.requestedRisk;
      final allocatedMargin = proposal.requestedMargin * riskScale;
      final allocatedQuantity = proposal.requestedQuantity * riskScale;
      if (riskUsed + allocatedRisk > riskLimit + 1e-9 ||
          marginUsed + allocatedMargin > marginLimit + 1e-9) {
        continue;
      }
      final bucket = configuration.correlationPolicy.bucketFor(
        symbol: proposal.candidate.symbol,
        assetGroup: proposal.candidate.assetGroup,
      );
      final bucketBefore = workingBucketRisk[bucket] ?? 0;
      final bucketLimit =
          configuration.totalRiskBudget *
          configuration.correlationPolicy.maximumBucketRiskFraction;
      if (bucketBefore + allocatedRisk > bucketLimit + 1e-9) {
        continue;
      }
      final outcome = outcomes[proposal.id]!;
      final selection = PortfolioAllocationReplaySelection(
        proposalId: proposal.id,
        symbol: proposal.symbol,
        utilityScore: proposal.utility.score,
        allocatedRisk: allocatedRisk,
        allocatedMargin: allocatedMargin,
        allocatedQuantity: allocatedQuantity,
        correlationBucket: bucket,
        releaseFrameIndex: frameIndex + outcome.holdingFrames,
      );
      selected.add(selection);
      riskUsed += allocatedRisk;
      marginUsed += allocatedMargin;
      selectedSymbols.add(proposal.symbol);
      workingBucketRisk[bucket] = bucketBefore + allocatedRisk;
    }
    return selected;
  }

  static int _compareProposals(
    PortfolioAllocationProposal left,
    PortfolioAllocationProposal right,
  ) {
    final scoreOrder = right.utility.score.compareTo(left.utility.score);
    if (scoreOrder != 0) return scoreOrder;
    final setupOrder = left.utility.setupId.compareTo(right.utility.setupId);
    if (setupOrder != 0) return setupOrder;
    return left.id.compareTo(right.id);
  }

  static String _fingerprint({
    required PortfolioAllocationReplayPolicy policy,
    required PortfolioAllocationReplayConfiguration configuration,
    required List<PortfolioAllocationReplayFrameResult> frames,
    required PortfolioAllocationReplayMetrics metrics,
    required List<double> realizedPath,
  }) {
    final canonical = jsonEncode({
      'version': configuration.version,
      'policy': policy.name,
      'riskBudget': configuration.totalRiskBudget.toStringAsPrecision(16),
      'marginBudget': configuration.totalMarginBudget.toStringAsPrecision(16),
      'maximumSelections': configuration.maximumSelections,
      'reserveRiskFraction': configuration.reserveRiskFraction
          .toStringAsPrecision(16),
      'reserveMarginFraction': configuration.reserveMarginFraction
          .toStringAsPrecision(16),
      'correlationFraction': configuration
          .correlationPolicy
          .maximumBucketRiskFraction
          .toStringAsPrecision(16),
      'frames': frames.map((value) => value.toJson()).toList(growable: false),
      'metrics': metrics.toJson(),
      'realizedPath': realizedPath
          .map((value) => value.toStringAsPrecision(16))
          .toList(growable: false),
    });
    return sha256.convert(utf8.encode(canonical)).toString();
  }
}

final class _ActiveReplayAllocation {
  const _ActiveReplayAllocation({
    required this.selection,
    required this.outcome,
  });

  final PortfolioAllocationReplaySelection selection;
  final PortfolioAllocationReplayOutcome outcome;
}
