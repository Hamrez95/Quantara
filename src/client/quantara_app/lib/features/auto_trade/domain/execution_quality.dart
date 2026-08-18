enum ExecutionSide { long, short }

enum ExecutionFillOutcome { pending, partial, filled, rejected, expired, noFill }

final class ExecutionPlan {
  const ExecutionPlan({
    required this.correlationId,
    required this.side,
    required this.decisionAtUtc,
    required this.referencePrice,
    required this.noChaseBoundPrice,
    required this.requestedQuantity,
  });

  final String correlationId;
  final ExecutionSide side;
  final DateTime decisionAtUtc;
  final double referencePrice;
  final double noChaseBoundPrice;
  final double requestedQuantity;

  bool get isValid =>
      correlationId.trim().isNotEmpty &&
      _isPositiveFinite(referencePrice) &&
      _isPositiveFinite(noChaseBoundPrice) &&
      _isPositiveFinite(requestedQuantity);

  bool isExecutablePriceWithinNoChase(double executablePrice) {
    if (!isValid || !_isPositiveFinite(executablePrice)) return false;

    return switch (side) {
      ExecutionSide.long => executablePrice <= noChaseBoundPrice,
      ExecutionSide.short => executablePrice >= noChaseBoundPrice,
    };
  }
}

final class EstimatedExecutionCost {
  const EstimatedExecutionCost({
    required this.modelVersion,
    required this.estimatedAtUtc,
    required this.spreadBps,
    required this.slippageBps,
    required this.feeBps,
    required this.fundingBps,
    required this.fillProbability,
    required this.insufficientEvidence,
  });

  final String modelVersion;
  final DateTime estimatedAtUtc;
  final double? spreadBps;
  final double? slippageBps;
  final double? feeBps;
  final double? fundingBps;
  final double? fillProbability;
  final bool insufficientEvidence;

  double? get totalEstimatedDragBps {
    final components = <double?>[
      spreadBps,
      slippageBps,
      feeBps,
      fundingBps,
    ];
    if (components.any((value) => value == null || !value!.isFinite)) {
      return null;
    }
    return components.fold<double>(0, (sum, value) => sum + value!);
  }

  bool get hasUsableFillProbability =>
      !insufficientEvidence &&
      fillProbability != null &&
      fillProbability!.isFinite &&
      fillProbability! >= 0 &&
      fillProbability! <= 1;
}

final class ConfirmedExecutionCost {
  const ConfirmedExecutionCost({
    required this.correlationId,
    required this.outcome,
    required this.acknowledgedAtUtc,
    required this.firstFillAtUtc,
    required this.finalFillAtUtc,
    required this.filledQuantity,
    required this.orderQuantity,
    required this.weightedAverageFillPrice,
    required this.feesUsdt,
    required this.fundingUsdt,
    required this.ambiguous,
  });

  final String correlationId;
  final ExecutionFillOutcome outcome;
  final DateTime? acknowledgedAtUtc;
  final DateTime? firstFillAtUtc;
  final DateTime? finalFillAtUtc;
  final double filledQuantity;
  final double orderQuantity;
  final double? weightedAverageFillPrice;
  final double feesUsdt;
  final double fundingUsdt;
  final bool ambiguous;

  double? get fillRatio {
    if (!_isPositiveFinite(orderQuantity) ||
        !filledQuantity.isFinite ||
        filledQuantity < 0) {
      return null;
    }
    return (filledQuantity / orderQuantity).clamp(0.0, 1.0).toDouble();
  }
}

final class ExecutionQualityMeasurement {
  const ExecutionQualityMeasurement({
    required this.correlationId,
    required this.outcome,
    required this.signedSlippagePrice,
    required this.signedSlippageBps,
    required this.slippageUsdt,
    required this.slippageR,
    required this.fillRatio,
    required this.decisionToAckLatency,
    required this.decisionToFirstFillLatency,
    required this.decisionToFinalFillLatency,
    required this.totalConfirmedDragUsdt,
    required this.ambiguous,
  });

  final String correlationId;
  final ExecutionFillOutcome outcome;

  /// Positive means adverse execution; negative means price improvement.
  final double? signedSlippagePrice;

  /// Positive means adverse execution; negative means price improvement.
  final double? signedSlippageBps;

  /// Signed economic slippage on the confirmed filled quantity.
  final double? slippageUsdt;

  /// Signed slippage normalized by planned risk-per-unit when available.
  final double? slippageR;
  final double? fillRatio;
  final Duration? decisionToAckLatency;
  final Duration? decisionToFirstFillLatency;
  final Duration? decisionToFinalFillLatency;
  final double? totalConfirmedDragUsdt;
  final bool ambiguous;
}

ExecutionQualityMeasurement measureExecutionQuality({
  required ExecutionPlan plan,
  required ConfirmedExecutionCost confirmed,
  double? plannedRiskPerUnit,
}) {
  final sameCorrelation =
      plan.correlationId.trim().isNotEmpty &&
      plan.correlationId.trim() == confirmed.correlationId.trim();
  final fillPrice = confirmed.weightedAverageFillPrice;
  final hasTrustedFill =
      sameCorrelation &&
      plan.isValid &&
      !confirmed.ambiguous &&
      confirmed.filledQuantity > 0 &&
      confirmed.filledQuantity.isFinite &&
      fillPrice != null &&
      _isPositiveFinite(fillPrice);

  double? signedSlippagePrice;
  double? signedSlippageBps;
  double? slippageUsdt;
  double? slippageR;
  if (hasTrustedFill) {
    signedSlippagePrice = switch (plan.side) {
      ExecutionSide.long => fillPrice - plan.referencePrice,
      ExecutionSide.short => plan.referencePrice - fillPrice,
    };
    signedSlippageBps =
        signedSlippagePrice / plan.referencePrice * 10000;
    slippageUsdt = signedSlippagePrice * confirmed.filledQuantity;
    if (plannedRiskPerUnit != null && _isPositiveFinite(plannedRiskPerUnit)) {
      slippageR = signedSlippagePrice / plannedRiskPerUnit;
    }
  }

  final feesAndFundingAreTrusted =
      confirmed.feesUsdt.isFinite && confirmed.fundingUsdt.isFinite;
  final totalConfirmedDragUsdt =
      slippageUsdt != null && feesAndFundingAreTrusted
      ? slippageUsdt + confirmed.feesUsdt + confirmed.fundingUsdt
      : null;

  return ExecutionQualityMeasurement(
    correlationId: plan.correlationId.trim(),
    outcome: confirmed.outcome,
    signedSlippagePrice: signedSlippagePrice,
    signedSlippageBps: signedSlippageBps,
    slippageUsdt: slippageUsdt,
    slippageR: slippageR,
    fillRatio: confirmed.fillRatio,
    decisionToAckLatency: _nonNegativeLatency(
      plan.decisionAtUtc,
      confirmed.acknowledgedAtUtc,
    ),
    decisionToFirstFillLatency: _nonNegativeLatency(
      plan.decisionAtUtc,
      confirmed.firstFillAtUtc,
    ),
    decisionToFinalFillLatency: _nonNegativeLatency(
      plan.decisionAtUtc,
      confirmed.finalFillAtUtc,
    ),
    totalConfirmedDragUsdt: totalConfirmedDragUsdt,
    ambiguous: confirmed.ambiguous || !sameCorrelation,
  );
}

Duration? _nonNegativeLatency(DateTime start, DateTime? end) {
  if (end == null) return null;
  final latency = end.toUtc().difference(start.toUtc());
  return latency.isNegative ? null : latency;
}

bool _isPositiveFinite(double value) => value.isFinite && value > 0;
