import '../domain/execution_quality_models.dart';
import 'private_order_execution_tracker.dart';

final class PrivateExecutionQualitySnapshot {
  const PrivateExecutionQualitySnapshot({
    required this.correlationId,
    required this.orderId,
    required this.symbol,
    required this.outcome,
    required this.evidenceQuality,
    required this.lifecycle,
    required this.fillRatio,
    required this.weightedAverageFillPrice,
    required this.signedSlippageBps,
    required this.ambiguous,
  });

  final String correlationId;
  final String orderId;
  final String symbol;
  final ExecutionOutcome outcome;
  final ExecutionEvidenceQuality evidenceQuality;
  final ExecutionLifecycleTiming? lifecycle;
  final double? fillRatio;
  final double? weightedAverageFillPrice;
  final double? signedSlippageBps;
  final bool ambiguous;

  bool get isTrusted =>
      !ambiguous && evidenceQuality == ExecutionEvidenceQuality.observed;
}

abstract final class PrivateExecutionQualityAdapter {
  static PrivateExecutionQualitySnapshot fromObservation({
    required PrivateOrderExecutionObservation observation,
    required String expectedCorrelationId,
    required String expectedSymbol,
    required ExecutionSide side,
    required DateTime decisionAtUtc,
    required double referencePrice,
  }) {
    final correlationId = expectedCorrelationId.trim();
    final symbol = expectedSymbol.trim().toUpperCase();
    if (correlationId.isEmpty ||
        symbol.isEmpty ||
        !decisionAtUtc.isUtc ||
        !referencePrice.isFinite ||
        referencePrice <= 0) {
      throw const FormatException(
        'Private execution-quality adapter input is invalid.',
      );
    }

    final orderId = observation.orderId.trim();
    final identityMatches =
        orderId.isNotEmpty &&
        observation.correlationId.trim() == correlationId &&
        observation.symbol.trim().toUpperCase() == symbol;
    final quantitiesValid =
        observation.orderQuantity.isFinite &&
        observation.orderQuantity > 0 &&
        observation.filledQuantity.isFinite &&
        observation.filledQuantity >= 0 &&
        observation.filledQuantity <= observation.orderQuantity + 1e-9;

    double? fillRatio;
    if (quantitiesValid) {
      fillRatio = ExecutionQualityMath.fillRatio(
        plannedQuantity: observation.orderQuantity,
        filledQuantity: observation.filledQuantity,
      );
    }

    final mapped = _mapOutcome(
      status: observation.orderStatus,
      fillRatio: fillRatio,
    );
    final hasFill = (fillRatio ?? 0) > 0;
    final fillPrice = observation.weightedAverageFillPrice;
    final trustedFillPrice =
        fillPrice != null && fillPrice.isFinite && fillPrice > 0;
    final statusConsistent = _isStatusConsistent(
      status: observation.orderStatus,
      outcome: mapped.outcome,
      fillRatio: fillRatio,
      hasTrustedFillPrice: trustedFillPrice,
    );

    final lifecycle = _validatedLifecycle(
      correlationId: correlationId,
      decisionAtUtc: decisionAtUtc,
      acknowledgedAtUtc: observation.acknowledgedAtUtc,
      firstFillAtUtc: observation.firstFillAtUtc,
      finalFillAtUtc: observation.finalFillAtUtc,
    );
    final lifecycleRequired = mapped.outcome != ExecutionOutcome.unknown;
    final lifecycleConsistent = !lifecycleRequired || lifecycle != null;

    final ambiguous =
        observation.ambiguous ||
        !identityMatches ||
        !quantitiesValid ||
        !mapped.knownStatus ||
        !statusConsistent ||
        !lifecycleConsistent;
    final evidenceQuality = _evidenceQuality(ambiguous);

    double? signedSlippageBps;
    if (!ambiguous && hasFill && trustedFillPrice) {
      signedSlippageBps = ExecutionQualityMath.signedSlippageBps(
        side: side,
        referencePrice: referencePrice,
        fillPrice: fillPrice,
      );
    }

    double? trustedWeightedAverageFillPrice;
    if (trustedFillPrice) {
      trustedWeightedAverageFillPrice = fillPrice;
    }

    return PrivateExecutionQualitySnapshot(
      correlationId: correlationId,
      orderId: orderId,
      symbol: symbol,
      outcome: mapped.outcome,
      evidenceQuality: evidenceQuality,
      lifecycle: lifecycle,
      fillRatio: fillRatio,
      weightedAverageFillPrice: trustedWeightedAverageFillPrice,
      signedSlippageBps: signedSlippageBps,
      ambiguous: ambiguous,
    );
  }

  static ExecutionEvidenceQuality _evidenceQuality(bool ambiguous) {
    if (ambiguous) return ExecutionEvidenceQuality.insufficient;
    return ExecutionEvidenceQuality.observed;
  }

  static ExecutionLifecycleTiming? _validatedLifecycle({
    required String correlationId,
    required DateTime decisionAtUtc,
    required DateTime acknowledgedAtUtc,
    required DateTime? firstFillAtUtc,
    required DateTime? finalFillAtUtc,
  }) {
    final lifecycle = ExecutionLifecycleTiming(
      correlationId: correlationId,
      decisionAtUtc: decisionAtUtc,
      acknowledgedAtUtc: acknowledgedAtUtc,
      firstFillAtUtc: firstFillAtUtc,
      finalFillAtUtc: finalFillAtUtc,
    );
    try {
      lifecycle.validate();
      return lifecycle;
    } on FormatException {
      return null;
    }
  }

  static _MappedOutcome _mapOutcome({
    required String status,
    required double? fillRatio,
  }) {
    final normalized = status.trim().toUpperCase();
    return switch (normalized) {
      'NEW' || 'OPEN' || 'PENDING' => const _MappedOutcome(
        outcome: ExecutionOutcome.planned,
        knownStatus: true,
      ),
      'PARTIALLY_FILLED' || 'PARTIAL_FILLED' => const _MappedOutcome(
        outcome: ExecutionOutcome.partialFill,
        knownStatus: true,
      ),
      'FILLED' => const _MappedOutcome(
        outcome: ExecutionOutcome.filled,
        knownStatus: true,
      ),
      'REJECTED' => const _MappedOutcome(
        outcome: ExecutionOutcome.rejected,
        knownStatus: true,
      ),
      'EXPIRED' => _terminalOutcome(
        fillRatio: fillRatio,
        emptyOutcome: ExecutionOutcome.expired,
      ),
      'CANCELED' || 'CANCELLED' => _terminalOutcome(
        fillRatio: fillRatio,
        emptyOutcome: ExecutionOutcome.noFill,
      ),
      _ => const _MappedOutcome(
        outcome: ExecutionOutcome.unknown,
        knownStatus: false,
      ),
    };
  }

  static _MappedOutcome _terminalOutcome({
    required double? fillRatio,
    required ExecutionOutcome emptyOutcome,
  }) {
    if ((fillRatio ?? 0) > 0) {
      return const _MappedOutcome(
        outcome: ExecutionOutcome.partialFill,
        knownStatus: true,
      );
    }
    return _MappedOutcome(outcome: emptyOutcome, knownStatus: true);
  }

  static bool _isStatusConsistent({
    required String status,
    required ExecutionOutcome outcome,
    required double? fillRatio,
    required bool hasTrustedFillPrice,
  }) {
    if (fillRatio == null) return false;
    final normalized = status.trim().toUpperCase();
    final hasFill = fillRatio > 0;
    final isFullFill = (fillRatio - 1).abs() <= 1e-9;

    if (hasFill && !hasTrustedFillPrice) return false;

    return switch (normalized) {
      'NEW' || 'OPEN' || 'PENDING' => fillRatio == 0,
      'PARTIALLY_FILLED' || 'PARTIAL_FILLED' =>
        hasFill && !isFullFill && outcome == ExecutionOutcome.partialFill,
      'FILLED' => isFullFill && outcome == ExecutionOutcome.filled,
      'REJECTED' => fillRatio == 0 && outcome == ExecutionOutcome.rejected,
      'EXPIRED' => !isFullFill,
      'CANCELED' || 'CANCELLED' => !isFullFill,
      _ => false,
    };
  }
}

final class _MappedOutcome {
  const _MappedOutcome({required this.outcome, required this.knownStatus});

  final ExecutionOutcome outcome;
  final bool knownStatus;
}
