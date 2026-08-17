import 'package:flutter/foundation.dart';

import 'portfolio_risk_models.dart';

enum PortfolioCorrelationReason {
  allowed,
  baseDecisionRejected,
  correlationBucketLimit,
}

@immutable
final class PortfolioCorrelationDecision {
  const PortfolioCorrelationDecision({
    required this.allowed,
    required this.reason,
    required this.bucket,
    required this.bucketRiskLimit,
    required this.bucketRiskBefore,
    required this.bucketRiskAfter,
  });

  final bool allowed;
  final PortfolioCorrelationReason reason;
  final String bucket;
  final double bucketRiskLimit;
  final double bucketRiskBefore;
  final double bucketRiskAfter;
}

@immutable
final class PortfolioCorrelationPolicy {
  const PortfolioCorrelationPolicy({
    this.maximumBucketRiskFraction = 0.6,
    this.bucketBySymbol = const {},
  }) : assert(maximumBucketRiskFraction > 0),
       assert(maximumBucketRiskFraction <= 1);

  final double maximumBucketRiskFraction;
  final Map<String, String> bucketBySymbol;

  PortfolioCorrelationDecision evaluate({
    required PortfolioRiskLedger ledger,
    required PortfolioEntryCandidate candidate,
    required PortfolioEntryDecision baseDecision,
  }) {
    final bucket = bucketFor(
      symbol: candidate.symbol,
      assetGroup: candidate.assetGroup,
    );
    final limit = ledger.dailyRisk.limit * maximumBucketRiskFraction;
    final before = ledger.activeReservations
        .where(
          (item) =>
              bucketFor(symbol: item.symbol, assetGroup: item.assetGroup) ==
              bucket,
        )
        .fold<double>(0, (sum, item) => sum + item.maximumLoss);
    final after =
        before + (baseDecision.allowed ? baseDecision.maximumLoss : 0);

    if (!baseDecision.allowed) {
      return PortfolioCorrelationDecision(
        allowed: false,
        reason: PortfolioCorrelationReason.baseDecisionRejected,
        bucket: bucket,
        bucketRiskLimit: limit,
        bucketRiskBefore: before,
        bucketRiskAfter: before,
      );
    }
    if (after > limit + 1e-9) {
      return PortfolioCorrelationDecision(
        allowed: false,
        reason: PortfolioCorrelationReason.correlationBucketLimit,
        bucket: bucket,
        bucketRiskLimit: limit,
        bucketRiskBefore: before,
        bucketRiskAfter: after,
      );
    }
    return PortfolioCorrelationDecision(
      allowed: true,
      reason: PortfolioCorrelationReason.allowed,
      bucket: bucket,
      bucketRiskLimit: limit,
      bucketRiskBefore: before,
      bucketRiskAfter: after,
    );
  }

  String bucketFor({required String symbol, required String assetGroup}) {
    final normalizedSymbol = symbol.trim().toUpperCase();
    final explicit = bucketBySymbol[normalizedSymbol]?.trim().toLowerCase();
    if (explicit != null && explicit.isNotEmpty) return explicit;
    final fallback = assetGroup.trim().toLowerCase();
    return fallback.isEmpty ? 'unknown' : 'asset:$fallback';
  }
}
