import 'dart:collection';

import '../../decision_core/domain/economic_opportunity_models.dart';
import '../../portfolio_risk/domain/portfolio_correlation_policy.dart';
import '../../portfolio_risk/domain/portfolio_risk_models.dart';

enum PortfolioAllocationReason {
  selected,
  hardRiskRejected,
  invalidProposal,
  utilityBelowThreshold,
  duplicateSymbol,
  slotCeiling,
  riskReserveProtected,
  marginReserveProtected,
  correlationBucketLimit,
}

final class PortfolioAllocationConfiguration {
  const PortfolioAllocationConfiguration({
    this.version = 'portfolio-allocator/1.1',
    this.maximumSelections = 3,
    this.minimumUtilityScore = 0,
    this.riskReserveFraction = 0.2,
    this.marginReserveFraction = 0.2,
  });

  final String version;
  final int maximumSelections;
  final double minimumUtilityScore;
  final double riskReserveFraction;
  final double marginReserveFraction;

  bool get valid =>
      version.trim().isNotEmpty &&
      maximumSelections > 0 &&
      minimumUtilityScore.isFinite &&
      riskReserveFraction.isFinite &&
      riskReserveFraction >= 0 &&
      riskReserveFraction < 1 &&
      marginReserveFraction.isFinite &&
      marginReserveFraction >= 0 &&
      marginReserveFraction < 1;
}

final class PortfolioAllocationBudget {
  const PortfolioAllocationBudget({
    required this.availableRisk,
    required this.availableMargin,
  });

  final double availableRisk;
  final double availableMargin;

  bool get valid =>
      availableRisk.isFinite &&
      availableRisk >= 0 &&
      availableMargin.isFinite &&
      availableMargin >= 0;
}

final class PortfolioAllocationProposal {
  const PortfolioAllocationProposal({
    required this.utility,
    required this.candidate,
    required this.riskDecision,
    required this.evidenceAsOfUtc,
  });

  final OpportunityUtility utility;
  final PortfolioEntryCandidate candidate;
  final PortfolioEntryDecision riskDecision;
  final DateTime evidenceAsOfUtc;

  String get id => candidate.candidateId;
  String get symbol => candidate.symbol.trim().toUpperCase();
  double get requestedRisk => riskDecision.maximumLoss;
  double get requestedMargin => riskDecision.requiredMargin;
  double get requestedQuantity => candidate.plannedQuantity;

  bool get valid =>
      id.trim().isNotEmpty &&
      symbol.isNotEmpty &&
      evidenceAsOfUtc.isUtc &&
      utility.version.trim().isNotEmpty &&
      utility.fingerprint.trim().isNotEmpty &&
      utility.score.isFinite &&
      requestedRisk.isFinite &&
      requestedRisk >= 0 &&
      requestedMargin.isFinite &&
      requestedMargin >= 0 &&
      requestedQuantity.isFinite &&
      requestedQuantity > 0;
}

final class PortfolioAllocationCorrelationContext {
  const PortfolioAllocationCorrelationContext({
    required this.ledger,
    required this.policy,
  });

  final PortfolioRiskLedger ledger;
  final PortfolioCorrelationPolicy policy;
}

final class PortfolioAllocationItemDecision {
  const PortfolioAllocationItemDecision({
    required this.proposalId,
    required this.symbol,
    required this.utilityScore,
    required this.reason,
    required this.requestedRisk,
    required this.allocatedRisk,
    required this.requestedMargin,
    required this.allocatedMargin,
    required this.requestedQuantity,
    required this.allocatedQuantity,
    this.correlationBucket,
    this.correlationRiskBefore,
    this.correlationRiskAfter,
    this.correlationRiskLimit,
  });

  final String proposalId;
  final String symbol;
  final double utilityScore;
  final PortfolioAllocationReason reason;
  final double requestedRisk;
  final double allocatedRisk;
  final double requestedMargin;
  final double allocatedMargin;
  final double requestedQuantity;
  final double allocatedQuantity;
  final String? correlationBucket;
  final double? correlationRiskBefore;
  final double? correlationRiskAfter;
  final double? correlationRiskLimit;

  bool get selected => reason == PortfolioAllocationReason.selected;

  Map<String, Object?> toJson() => {
    'proposalId': proposalId,
    'symbol': symbol,
    'utilityScore': utilityScore,
    'reason': reason.name,
    'requestedRisk': requestedRisk,
    'allocatedRisk': allocatedRisk,
    'requestedMargin': requestedMargin,
    'allocatedMargin': allocatedMargin,
    'requestedQuantity': requestedQuantity,
    'allocatedQuantity': allocatedQuantity,
    if (correlationBucket != null) 'correlationBucket': correlationBucket,
    if (correlationRiskBefore != null)
      'correlationRiskBefore': correlationRiskBefore,
    if (correlationRiskAfter != null)
      'correlationRiskAfter': correlationRiskAfter,
    if (correlationRiskLimit != null)
      'correlationRiskLimit': correlationRiskLimit,
  };
}

final class PortfolioAllocationDecision {
  PortfolioAllocationDecision({
    required this.version,
    required this.generatedAtUtc,
    required Iterable<PortfolioAllocationItemDecision> items,
    required this.riskConsumed,
    required this.marginConsumed,
    required this.riskHeldInReserve,
    required this.marginHeldInReserve,
    required this.riskRemainingOutsideReserve,
    required this.marginRemainingOutsideReserve,
  }) : items = UnmodifiableListView(items.toList(growable: false));

  final String version;
  final DateTime generatedAtUtc;
  final UnmodifiableListView<PortfolioAllocationItemDecision> items;
  final double riskConsumed;
  final double marginConsumed;
  final double riskHeldInReserve;
  final double marginHeldInReserve;
  final double riskRemainingOutsideReserve;
  final double marginRemainingOutsideReserve;

  List<PortfolioAllocationItemDecision> get selected =>
      List.unmodifiable(items.where((item) => item.selected));

  Map<String, Object?> toJson() => {
    'version': version,
    'generatedAtUtc': generatedAtUtc.toIso8601String(),
    'items': items.map((item) => item.toJson()).toList(growable: false),
    'riskConsumed': riskConsumed,
    'marginConsumed': marginConsumed,
    'riskHeldInReserve': riskHeldInReserve,
    'marginHeldInReserve': marginHeldInReserve,
    'riskRemainingOutsideReserve': riskRemainingOutsideReserve,
    'marginRemainingOutsideReserve': marginRemainingOutsideReserve,
  };
}

final class PortfolioCapitalAllocator {
  const PortfolioCapitalAllocator({
    this.configuration = const PortfolioAllocationConfiguration(),
  });

  final PortfolioAllocationConfiguration configuration;

  PortfolioAllocationDecision allocate({
    required Iterable<PortfolioAllocationProposal> proposals,
    required PortfolioAllocationBudget budget,
    required DateTime nowUtc,
    PortfolioAllocationCorrelationContext? correlation,
  }) {
    if (!configuration.valid || !budget.valid || !nowUtc.isUtc) {
      throw const FormatException('Portfolio allocation input is invalid.');
    }

    final ranked = proposals.toList(growable: false)
      ..sort((left, right) {
        final scoreOrder = right.utility.score.compareTo(left.utility.score);
        if (scoreOrder != 0) return scoreOrder;
        final setupOrder = left.utility.setupId.compareTo(
          right.utility.setupId,
        );
        if (setupOrder != 0) return setupOrder;
        return left.id.compareTo(right.id);
      });

    final riskHeldInReserve =
        budget.availableRisk * configuration.riskReserveFraction;
    final marginHeldInReserve =
        budget.availableMargin * configuration.marginReserveFraction;
    final allocatableRisk = budget.availableRisk - riskHeldInReserve;
    final allocatableMargin = budget.availableMargin - marginHeldInReserve;
    final selectedSymbols = <String>{};
    final decisions = <PortfolioAllocationItemDecision>[];
    final correlationRiskByBucket = _initialCorrelationExposure(correlation);
    final correlationRiskLimit = correlation == null
        ? null
        : correlation.ledger.dailyRisk.limit *
              correlation.policy.maximumBucketRiskFraction;
    var riskConsumed = 0.0;
    var marginConsumed = 0.0;
    var selectionCount = 0;

    for (final proposal in ranked) {
      PortfolioAllocationReason reason;
      _PortfolioAllocationCorrelationImpact? correlationImpact;
      if (correlation != null && proposal.valid) {
        final bucket = correlation.policy.bucketFor(
          symbol: proposal.candidate.symbol,
          assetGroup: proposal.candidate.assetGroup,
        );
        final before = correlationRiskByBucket[bucket] ?? 0;
        correlationImpact = _PortfolioAllocationCorrelationImpact(
          bucket: bucket,
          riskBefore: before,
          riskAfter: before + proposal.requestedRisk,
          riskLimit: correlationRiskLimit!,
        );
      }

      if (!proposal.valid) {
        reason = PortfolioAllocationReason.invalidProposal;
      } else if (!proposal.riskDecision.allowed) {
        reason = PortfolioAllocationReason.hardRiskRejected;
      } else if (proposal.utility.score < configuration.minimumUtilityScore) {
        reason = PortfolioAllocationReason.utilityBelowThreshold;
      } else if (selectedSymbols.contains(proposal.symbol)) {
        reason = PortfolioAllocationReason.duplicateSymbol;
      } else if (selectionCount >= configuration.maximumSelections) {
        reason = PortfolioAllocationReason.slotCeiling;
      } else if (riskConsumed + proposal.requestedRisk >
          allocatableRisk + 1e-9) {
        reason = PortfolioAllocationReason.riskReserveProtected;
      } else if (marginConsumed + proposal.requestedMargin >
          allocatableMargin + 1e-9) {
        reason = PortfolioAllocationReason.marginReserveProtected;
      } else if (correlationImpact != null &&
          correlationImpact.riskAfter > correlationImpact.riskLimit + 1e-9) {
        reason = PortfolioAllocationReason.correlationBucketLimit;
      } else {
        reason = PortfolioAllocationReason.selected;
        riskConsumed += proposal.requestedRisk;
        marginConsumed += proposal.requestedMargin;
        selectionCount += 1;
        selectedSymbols.add(proposal.symbol);
        if (correlationImpact != null) {
          correlationRiskByBucket[correlationImpact.bucket] =
              correlationImpact.riskAfter;
        }
      }

      final selected = reason == PortfolioAllocationReason.selected;
      decisions.add(
        PortfolioAllocationItemDecision(
          proposalId: proposal.id,
          symbol: proposal.symbol,
          utilityScore: proposal.utility.score,
          reason: reason,
          requestedRisk: proposal.requestedRisk,
          allocatedRisk: selected ? proposal.requestedRisk : 0,
          requestedMargin: proposal.requestedMargin,
          allocatedMargin: selected ? proposal.requestedMargin : 0,
          requestedQuantity: proposal.requestedQuantity,
          allocatedQuantity: selected ? proposal.requestedQuantity : 0,
          correlationBucket: correlationImpact?.bucket,
          correlationRiskBefore: correlationImpact?.riskBefore,
          correlationRiskAfter: correlationImpact?.riskAfter,
          correlationRiskLimit: correlationImpact?.riskLimit,
        ),
      );
    }

    return PortfolioAllocationDecision(
      version: configuration.version,
      generatedAtUtc: nowUtc,
      items: decisions,
      riskConsumed: riskConsumed,
      marginConsumed: marginConsumed,
      riskHeldInReserve: riskHeldInReserve,
      marginHeldInReserve: marginHeldInReserve,
      riskRemainingOutsideReserve: (allocatableRisk - riskConsumed)
          .clamp(0.0, double.infinity)
          .toDouble(),
      marginRemainingOutsideReserve: (allocatableMargin - marginConsumed)
          .clamp(0.0, double.infinity)
          .toDouble(),
    );
  }

  Map<String, double> _initialCorrelationExposure(
    PortfolioAllocationCorrelationContext? correlation,
  ) {
    if (correlation == null) return <String, double>{};
    final exposure = <String, double>{};
    for (final reservation in correlation.ledger.activeReservations) {
      final bucket = correlation.policy.bucketFor(
        symbol: reservation.symbol,
        assetGroup: reservation.assetGroup,
      );
      exposure.update(
        bucket,
        (current) => current + reservation.maximumLoss,
        ifAbsent: () => reservation.maximumLoss,
      );
    }
    return exposure;
  }
}

final class _PortfolioAllocationCorrelationImpact {
  const _PortfolioAllocationCorrelationImpact({
    required this.bucket,
    required this.riskBefore,
    required this.riskAfter,
    required this.riskLimit,
  });

  final String bucket;
  final double riskBefore;
  final double riskAfter;
  final double riskLimit;
}
