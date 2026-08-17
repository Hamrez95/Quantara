import 'package:flutter/foundation.dart';

import 'capital_guardian.dart';
import 'portfolio_correlation_policy.dart';
import 'portfolio_liquidation_policy.dart';
import 'portfolio_risk_models.dart';

enum PortfolioAdmissionStatus { approved, rejected, deferred }

enum PortfolioAdmissionStage {
  baseRisk,
  capitalGuardian,
  correlation,
  liquidation,
  liveExecution,
  complete,
}

@immutable
final class PortfolioAdmissionDecision {
  PortfolioAdmissionDecision({
    required this.status,
    required this.blockingStage,
    required Iterable<String> reasonCodes,
    required this.baseRisk,
    required this.guardian,
    required this.correlation,
    required this.liquidation,
  }) : reasonCodes = List.unmodifiable(reasonCodes);

  final PortfolioAdmissionStatus status;
  final PortfolioAdmissionStage blockingStage;
  final List<String> reasonCodes;
  final PortfolioEntryDecision baseRisk;
  final CapitalGuardianDecision guardian;
  final PortfolioCorrelationDecision correlation;
  final PortfolioLiquidationDecision liquidation;

  bool get approved => status == PortfolioAdmissionStatus.approved;

  Map<String, Object?> toJson() => {
    'status': status.name,
    'blockingStage': blockingStage.name,
    'reasonCodes': reasonCodes,
    'proposedMaximumLoss': baseRisk.maximumLoss,
    'requiredMargin': baseRisk.requiredMargin,
    'availableRiskBefore': baseRisk.availableRiskBefore,
    'availableRiskAfter': baseRisk.availableRiskAfter,
    'availableMarginAfter': baseRisk.availableMarginAfter,
    'guardian': {
      'reason': guardian.reason.name,
      'drawdownTier': guardian.drawdownTier.name,
      'riskMultiplier': guardian.riskMultiplier,
      'weeklyLossLimit': guardian.weeklyLossLimit,
      'weeklyLossRemaining': guardian.weeklyLossRemaining,
      'maximumAllowedEntryRisk': guardian.maximumAllowedEntryRisk,
    },
    'correlation': {
      'reason': correlation.reason.name,
      'bucket': correlation.bucket,
      'bucketRiskLimit': correlation.bucketRiskLimit,
      'bucketRiskBefore': correlation.bucketRiskBefore,
      'bucketRiskAfter': correlation.bucketRiskAfter,
    },
    'liquidation': {
      'reason': liquidation.reason.name,
      'cushionFraction': liquidation.liquidationCushionFraction,
      'minimumCushionFraction': liquidation.minimumLiquidationCushionFraction,
      'marginHeadroomAfterEntry': liquidation.marginHeadroomAfterEntry,
      'minimumMarginHeadroom': liquidation.minimumMarginHeadroom,
    },
  };
}

abstract final class PortfolioAdmissionSafetyChain {
  static PortfolioAdmissionDecision compose({
    required PortfolioEntryDecision baseRisk,
    required CapitalGuardianDecision guardian,
    required PortfolioCorrelationDecision correlation,
    required PortfolioLiquidationDecision liquidation,
  }) {
    if (!baseRisk.allowed) {
      return _decision(
        status: _baseRiskDeferred(baseRisk.reason)
            ? PortfolioAdmissionStatus.deferred
            : PortfolioAdmissionStatus.rejected,
        blockingStage: PortfolioAdmissionStage.baseRisk,
        reasonCode: 'base:${baseRisk.reason.name}',
        baseRisk: baseRisk,
        guardian: guardian,
        correlation: correlation,
        liquidation: liquidation,
      );
    }
    if (!guardian.allowed) {
      return _decision(
        status: _guardianDeferred(guardian.reason)
            ? PortfolioAdmissionStatus.deferred
            : PortfolioAdmissionStatus.rejected,
        blockingStage: PortfolioAdmissionStage.capitalGuardian,
        reasonCode: 'guardian:${guardian.reason.name}',
        baseRisk: baseRisk,
        guardian: guardian,
        correlation: correlation,
        liquidation: liquidation,
      );
    }
    if (!correlation.allowed) {
      return _decision(
        status: PortfolioAdmissionStatus.rejected,
        blockingStage: PortfolioAdmissionStage.correlation,
        reasonCode: 'correlation:${correlation.reason.name}',
        baseRisk: baseRisk,
        guardian: guardian,
        correlation: correlation,
        liquidation: liquidation,
      );
    }
    if (!liquidation.allowed) {
      return _decision(
        status: _liquidationDeferred(liquidation.reason)
            ? PortfolioAdmissionStatus.deferred
            : PortfolioAdmissionStatus.rejected,
        blockingStage: PortfolioAdmissionStage.liquidation,
        reasonCode: 'liquidation:${liquidation.reason.name}',
        baseRisk: baseRisk,
        guardian: guardian,
        correlation: correlation,
        liquidation: liquidation,
      );
    }
    if (!baseRisk.liveExecutionAllowed) {
      return _decision(
        status: PortfolioAdmissionStatus.deferred,
        blockingStage: PortfolioAdmissionStage.liveExecution,
        reasonCode: 'live:execution-not-allowed',
        baseRisk: baseRisk,
        guardian: guardian,
        correlation: correlation,
        liquidation: liquidation,
      );
    }
    return _decision(
      status: PortfolioAdmissionStatus.approved,
      blockingStage: PortfolioAdmissionStage.complete,
      reasonCode: 'admission:approved',
      baseRisk: baseRisk,
      guardian: guardian,
      correlation: correlation,
      liquidation: liquidation,
    );
  }

  static PortfolioAdmissionDecision _decision({
    required PortfolioAdmissionStatus status,
    required PortfolioAdmissionStage blockingStage,
    required String reasonCode,
    required PortfolioEntryDecision baseRisk,
    required CapitalGuardianDecision guardian,
    required PortfolioCorrelationDecision correlation,
    required PortfolioLiquidationDecision liquidation,
  }) => PortfolioAdmissionDecision(
    status: status,
    blockingStage: blockingStage,
    reasonCodes: [reasonCode],
    baseRisk: baseRisk,
    guardian: guardian,
    correlation: correlation,
    liquidation: liquidation,
  );

  static bool _baseRiskDeferred(PortfolioEntryBlockReason reason) => switch (
    reason
  ) {
    PortfolioEntryBlockReason.staleAccount ||
    PortfolioEntryBlockReason.incompleteProtection ||
    PortfolioEntryBlockReason.ambiguousReservation => true,
    _ => false,
  };

  static bool _guardianDeferred(CapitalGuardianBreakerReason reason) => switch (
    reason
  ) {
    CapitalGuardianBreakerReason.lossStreakCooldown ||
    CapitalGuardianBreakerReason.abnormalVolatility => true,
    _ => false,
  };

  static bool _liquidationDeferred(PortfolioLiquidationReason reason) => switch (
    reason
  ) {
    PortfolioLiquidationReason.invalidEvidence ||
    PortfolioLiquidationReason.staleEvidence => true,
    _ => false,
  };
}
