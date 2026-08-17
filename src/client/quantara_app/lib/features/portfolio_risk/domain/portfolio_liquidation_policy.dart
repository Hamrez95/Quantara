import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import 'portfolio_risk_models.dart';

enum PortfolioLiquidationReason {
  allowed,
  baseDecisionRejected,
  invalidPolicy,
  invalidCandidateInputs,
  invalidAccountInputs,
  invalidEvidence,
  staleEvidence,
  invalidLiquidationGeometry,
  insufficientLiquidationCushion,
  insufficientMarginHeadroom,
}

@immutable
final class PortfolioLiquidationEvidence {
  const PortfolioLiquidationEvidence({
    required this.asOfUtc,
    required this.estimatedLiquidationPrice,
    required this.source,
  });

  final DateTime asOfUtc;
  final double estimatedLiquidationPrice;
  final String source;
}

@immutable
final class PortfolioLiquidationDecision {
  const PortfolioLiquidationDecision({
    required this.allowed,
    required this.reason,
    required this.liquidationCushionFraction,
    required this.minimumLiquidationCushionFraction,
    required this.marginHeadroomAfterEntry,
    required this.minimumMarginHeadroom,
  });

  final bool allowed;
  final PortfolioLiquidationReason reason;
  final double liquidationCushionFraction;
  final double minimumLiquidationCushionFraction;
  final double marginHeadroomAfterEntry;
  final double minimumMarginHeadroom;
}

@immutable
final class PortfolioLiquidationPolicy {
  const PortfolioLiquidationPolicy({
    this.maximumEvidenceAge = const Duration(seconds: 5),
    this.minimumLiquidationCushionFraction = 0.015,
    this.minimumPostEntryMarginHeadroomFraction = 0.25,
  });

  final Duration maximumEvidenceAge;
  final double minimumLiquidationCushionFraction;
  final double minimumPostEntryMarginHeadroomFraction;

  PortfolioLiquidationDecision evaluate({
    required PortfolioEntryCandidate candidate,
    required PortfolioAccountTruth account,
    required PortfolioEntryDecision baseDecision,
    required PortfolioLiquidationEvidence evidence,
    required DateTime nowUtc,
  }) {
    if (!baseDecision.allowed) {
      return _blocked(reason: PortfolioLiquidationReason.baseDecisionRejected);
    }
    if (maximumEvidenceAge <= Duration.zero ||
        !minimumLiquidationCushionFraction.isFinite ||
        minimumLiquidationCushionFraction <= 0 ||
        minimumLiquidationCushionFraction > 1 ||
        !minimumPostEntryMarginHeadroomFraction.isFinite ||
        minimumPostEntryMarginHeadroomFraction < 0) {
      return _blocked(reason: PortfolioLiquidationReason.invalidPolicy);
    }
    if (!candidate.entryPrice.isFinite ||
        !candidate.stopPrice.isFinite ||
        candidate.entryPrice <= 0 ||
        candidate.stopPrice <= 0) {
      return _blocked(
        reason: PortfolioLiquidationReason.invalidCandidateInputs,
      );
    }

    final spendable = account.marginBudget.spendable;
    if (!spendable.isFinite ||
        !baseDecision.requiredMargin.isFinite ||
        baseDecision.requiredMargin < 0) {
      return _blocked(reason: PortfolioLiquidationReason.invalidAccountInputs);
    }
    final postEntryHeadroom = math
        .max(0, spendable - baseDecision.requiredMargin)
        .toDouble();
    final minimumHeadroom =
        baseDecision.requiredMargin * minimumPostEntryMarginHeadroomFraction;

    PortfolioLiquidationDecision blocked(
      PortfolioLiquidationReason reason, {
      double cushionFraction = 0,
    }) => PortfolioLiquidationDecision(
      allowed: false,
      reason: reason,
      liquidationCushionFraction: cushionFraction,
      minimumLiquidationCushionFraction: minimumLiquidationCushionFraction,
      marginHeadroomAfterEntry: postEntryHeadroom,
      minimumMarginHeadroom: minimumHeadroom,
    );

    if (!nowUtc.isUtc ||
        !evidence.asOfUtc.isUtc ||
        evidence.source.trim().isEmpty ||
        !evidence.estimatedLiquidationPrice.isFinite ||
        evidence.estimatedLiquidationPrice <= 0) {
      return blocked(PortfolioLiquidationReason.invalidEvidence);
    }
    final age = nowUtc.difference(evidence.asOfUtc);
    if (age.isNegative) {
      return blocked(PortfolioLiquidationReason.invalidEvidence);
    }
    if (age > maximumEvidenceAge) {
      return blocked(PortfolioLiquidationReason.staleEvidence);
    }

    final liquidationPrice = evidence.estimatedLiquidationPrice;
    final validGeometry = switch (candidate.side) {
      PortfolioSide.long =>
        liquidationPrice < candidate.stopPrice &&
            candidate.stopPrice < candidate.entryPrice,
      PortfolioSide.short =>
        liquidationPrice > candidate.stopPrice &&
            candidate.stopPrice > candidate.entryPrice,
    };
    if (!validGeometry) {
      return blocked(PortfolioLiquidationReason.invalidLiquidationGeometry);
    }

    final cushionDistance = switch (candidate.side) {
      PortfolioSide.long => candidate.stopPrice - liquidationPrice,
      PortfolioSide.short => liquidationPrice - candidate.stopPrice,
    };
    final cushionFraction = cushionDistance / candidate.entryPrice;
    if (!cushionFraction.isFinite || cushionFraction < 0) {
      return blocked(PortfolioLiquidationReason.invalidLiquidationGeometry);
    }
    if (cushionFraction + 1e-12 < minimumLiquidationCushionFraction) {
      return blocked(
        PortfolioLiquidationReason.insufficientLiquidationCushion,
        cushionFraction: cushionFraction,
      );
    }
    if (postEntryHeadroom + 1e-9 < minimumHeadroom) {
      return blocked(
        PortfolioLiquidationReason.insufficientMarginHeadroom,
        cushionFraction: cushionFraction,
      );
    }
    return PortfolioLiquidationDecision(
      allowed: true,
      reason: PortfolioLiquidationReason.allowed,
      liquidationCushionFraction: cushionFraction,
      minimumLiquidationCushionFraction: minimumLiquidationCushionFraction,
      marginHeadroomAfterEntry: postEntryHeadroom,
      minimumMarginHeadroom: minimumHeadroom,
    );
  }

  PortfolioLiquidationDecision _blocked({
    required PortfolioLiquidationReason reason,
  }) => PortfolioLiquidationDecision(
    allowed: false,
    reason: reason,
    liquidationCushionFraction: 0,
    minimumLiquidationCushionFraction:
        minimumLiquidationCushionFraction.isFinite &&
            minimumLiquidationCushionFraction > 0
        ? minimumLiquidationCushionFraction
        : 0,
    marginHeadroomAfterEntry: 0,
    minimumMarginHeadroom: 0,
  );
}
