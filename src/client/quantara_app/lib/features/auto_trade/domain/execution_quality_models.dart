enum ExecutionSide { long, short }

enum ExecutionEvidenceQuality { insufficient, conservative, observed }

enum ExecutionOutcome {
  planned,
  partialFill,
  filled,
  rejected,
  expired,
  noFill,
  unknown,
}

enum NoChaseDecisionReason { allowed, staleIntent, priceBeyondBoundary }

final class PlannedExecutionCosts {
  const PlannedExecutionCosts({
    required this.fees,
    required this.funding,
    required this.spread,
    required this.slippage,
    required this.latency,
  });

  final double fees;
  final double funding;
  final double spread;
  final double slippage;
  final double latency;

  double get total => fees + funding + spread + slippage + latency;

  void validate() => _validateNonNegativeFinite(
    [fees, funding, spread, slippage, latency],
    'Planned execution costs are invalid.',
  );
}

final class EstimatedExecutionCosts {
  const EstimatedExecutionCosts({
    required this.modelVersion,
    required this.asOfUtc,
    required this.evidenceQuality,
    required this.fees,
    required this.funding,
    required this.spread,
    required this.slippage,
    required this.latency,
  });

  final String modelVersion;
  final DateTime asOfUtc;
  final ExecutionEvidenceQuality evidenceQuality;
  final double fees;
  final double funding;
  final double spread;
  final double slippage;
  final double latency;

  double get total => fees + funding + spread + slippage + latency;

  void validate() {
    if (modelVersion.trim().isEmpty || !asOfUtc.isUtc) {
      throw const FormatException('Execution estimate identity is invalid.');
    }
    _validateNonNegativeFinite(
      [fees, funding, spread, slippage, latency],
      'Estimated execution costs are invalid.',
    );
  }
}

final class ConfirmedExecutionCosts {
  const ConfirmedExecutionCosts({
    required this.entryFees,
    required this.exitFees,
    required this.funding,
    required this.spread,
    required this.slippage,
  });

  final double entryFees;
  final double exitFees;
  final double funding;
  final double spread;
  final double slippage;

  double get total => entryFees + exitFees + funding + spread + slippage;

  void validate() => _validateNonNegativeFinite(
    [entryFees, exitFees, funding, spread, slippage],
    'Confirmed execution costs are invalid.',
  );
}

final class ExecutionLifecycleTiming {
  const ExecutionLifecycleTiming({
    required this.correlationId,
    required this.decisionAtUtc,
    this.submitAtUtc,
    this.acknowledgedAtUtc,
    this.firstFillAtUtc,
    this.finalFillAtUtc,
  });

  final String correlationId;
  final DateTime decisionAtUtc;
  final DateTime? submitAtUtc;
  final DateTime? acknowledgedAtUtc;
  final DateTime? firstFillAtUtc;
  final DateTime? finalFillAtUtc;

  void validate() {
    if (correlationId.trim().isEmpty || !decisionAtUtc.isUtc) {
      throw const FormatException('Execution lifecycle identity is invalid.');
    }
    final timestamps = [
      submitAtUtc,
      acknowledgedAtUtc,
      firstFillAtUtc,
      finalFillAtUtc,
    ];
    if (timestamps.whereType<DateTime>().any((value) => !value.isUtc)) {
      throw const FormatException('Execution lifecycle timestamps must be UTC.');
    }
    var previous = decisionAtUtc;
    for (final value in timestamps) {
      if (value == null) continue;
      if (value.isBefore(previous)) {
        throw const FormatException('Execution lifecycle timestamps are out of order.');
      }
      previous = value;
    }
  }
}

final class NoChaseDecision {
  const NoChaseDecision({required this.allowed, required this.reason});

  final bool allowed;
  final NoChaseDecisionReason reason;
}

final class NoChasePolicy {
  const NoChasePolicy();

  NoChaseDecision evaluate({
    required ExecutionSide side,
    required double executablePrice,
    required double worstAcceptablePrice,
    required DateTime evaluatedAtUtc,
    required DateTime validUntilUtc,
  }) {
    if (!evaluatedAtUtc.isUtc ||
        !validUntilUtc.isUtc ||
        !executablePrice.isFinite ||
        !worstAcceptablePrice.isFinite ||
        executablePrice <= 0 ||
        worstAcceptablePrice <= 0) {
      throw const FormatException('No-chase policy input is invalid.');
    }
    if (evaluatedAtUtc.isAfter(validUntilUtc)) {
      return const NoChaseDecision(
        allowed: false,
        reason: NoChaseDecisionReason.staleIntent,
      );
    }
    final beyondBoundary = switch (side) {
      ExecutionSide.long => executablePrice > worstAcceptablePrice,
      ExecutionSide.short => executablePrice < worstAcceptablePrice,
    };
    if (beyondBoundary) {
      return const NoChaseDecision(
        allowed: false,
        reason: NoChaseDecisionReason.priceBeyondBoundary,
      );
    }
    return const NoChaseDecision(
      allowed: true,
      reason: NoChaseDecisionReason.allowed,
    );
  }
}

abstract final class ExecutionQualityMath {
  static double signedSlippageBps({
    required ExecutionSide side,
    required double referencePrice,
    required double fillPrice,
  }) {
    if (!referencePrice.isFinite ||
        !fillPrice.isFinite ||
        referencePrice <= 0 ||
        fillPrice <= 0) {
      throw const FormatException('Slippage prices are invalid.');
    }
    final signedPriceDelta = switch (side) {
      ExecutionSide.long => fillPrice - referencePrice,
      ExecutionSide.short => referencePrice - fillPrice,
    };
    return signedPriceDelta / referencePrice * 10000;
  }

  static double fillRatio({
    required double plannedQuantity,
    required double filledQuantity,
  }) {
    if (!plannedQuantity.isFinite ||
        !filledQuantity.isFinite ||
        plannedQuantity <= 0 ||
        filledQuantity < 0 ||
        filledQuantity > plannedQuantity + 1e-9) {
      throw const FormatException('Execution fill quantities are invalid.');
    }
    return (filledQuantity / plannedQuantity).clamp(0.0, 1.0);
  }
}

void _validateNonNegativeFinite(List<double> values, String message) {
  if (values.any((value) => !value.isFinite || value < 0)) {
    throw FormatException(message);
  }
}
