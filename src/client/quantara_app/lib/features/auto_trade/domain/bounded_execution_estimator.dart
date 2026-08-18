import 'dart:collection';

import 'execution_quality_models.dart';

final class ExecutionEstimatorObservation {
  const ExecutionEstimatorObservation({
    required this.outcome,
    required this.observedAtUtc,
    required this.signedSlippageBps,
    required this.ackLatency,
    required this.finalFillLatency,
    required this.finalized,
  });

  final ExecutionOutcome outcome;
  final DateTime observedAtUtc;
  final double? signedSlippageBps;
  final Duration? ackLatency;
  final Duration? finalFillLatency;

  /// True only after the order attempt can no longer accumulate more fill.
  final bool finalized;

  void validate() {
    if (!observedAtUtc.isUtc ||
        (signedSlippageBps != null && !signedSlippageBps!.isFinite) ||
        (ackLatency?.isNegative ?? false) ||
        (finalFillLatency?.isNegative ?? false)) {
      throw const FormatException(
        'Execution estimator observation is invalid.',
      );
    }
    if (!finalized ||
        outcome == ExecutionOutcome.planned ||
        outcome == ExecutionOutcome.unknown) {
      throw const FormatException(
        'Execution estimator accepts finalized outcomes only.',
      );
    }
    final hasFill =
        outcome == ExecutionOutcome.partialFill ||
        outcome == ExecutionOutcome.filled;
    if (!hasFill && signedSlippageBps != null) {
      throw const FormatException(
        'Only confirmed fill outcomes may contribute slippage evidence.',
      );
    }
  }
}

final class EmpiricalExecutionEstimate {
  const EmpiricalExecutionEstimate({
    required this.modelVersion,
    required this.asOfUtc,
    required this.evidenceQuality,
    required this.sampleCount,
    required this.fullFillProbability,
    required this.anyFillProbability,
    required this.adverseSlippageP50Bps,
    required this.adverseSlippageP95Bps,
    required this.ackLatencyP50,
    required this.finalFillLatencyP95,
  });

  final String modelVersion;
  final DateTime asOfUtc;
  final ExecutionEvidenceQuality evidenceQuality;
  final int sampleCount;
  final double? fullFillProbability;
  final double? anyFillProbability;
  final double? adverseSlippageP50Bps;
  final double? adverseSlippageP95Bps;
  final Duration? ackLatencyP50;
  final Duration? finalFillLatencyP95;

  bool get hasProbabilityEstimate =>
      fullFillProbability != null && anyFillProbability != null;
}

final class BoundedExecutionEstimator {
  BoundedExecutionEstimator({
    this.modelVersion = 'bounded-execution-estimator/1.0',
    this.capacity = 128,
    this.minimumSamples = 30,
  }) {
    if (modelVersion.trim().isEmpty ||
        capacity <= 0 ||
        minimumSamples <= 0 ||
        minimumSamples > capacity) {
      throw const FormatException(
        'Execution estimator configuration is invalid.',
      );
    }
  }

  final String modelVersion;
  final int capacity;
  final int minimumSamples;
  final Queue<ExecutionEstimatorObservation> _observations = Queue();

  int get sampleCount => _observations.length;

  void add(ExecutionEstimatorObservation observation) {
    observation.validate();
    _observations.addLast(observation);
    while (_observations.length > capacity) {
      _observations.removeFirst();
    }
  }

  EmpiricalExecutionEstimate estimate({required DateTime asOfUtc}) {
    if (!asOfUtc.isUtc) {
      throw const FormatException('Execution estimate timestamp must be UTC.');
    }
    final observations = _observations.toList(growable: false);
    final sufficient = observations.length >= minimumSamples;
    if (!sufficient) {
      return EmpiricalExecutionEstimate(
        modelVersion: modelVersion,
        asOfUtc: asOfUtc,
        evidenceQuality: ExecutionEvidenceQuality.insufficient,
        sampleCount: observations.length,
        fullFillProbability: null,
        anyFillProbability: null,
        adverseSlippageP50Bps: null,
        adverseSlippageP95Bps: null,
        ackLatencyP50: null,
        finalFillLatencyP95: null,
      );
    }

    final fullFillCount = observations
        .where((observation) => observation.outcome == ExecutionOutcome.filled)
        .length;
    final anyFillCount = observations
        .where(
          (observation) =>
              observation.outcome == ExecutionOutcome.filled ||
              observation.outcome == ExecutionOutcome.partialFill,
        )
        .length;
    final slippage =
        observations
            .map((observation) => observation.signedSlippageBps)
            .whereType<double>()
            .map((value) => value > 0 ? value : 0.0)
            .toList(growable: false)
          ..sort();
    final ackLatencies =
        observations
            .map((observation) => observation.ackLatency)
            .whereType<Duration>()
            .toList(growable: false)
          ..sort((left, right) => left.compareTo(right));
    final finalFillLatencies =
        observations
            .map((observation) => observation.finalFillLatency)
            .whereType<Duration>()
            .toList(growable: false)
          ..sort((left, right) => left.compareTo(right));

    return EmpiricalExecutionEstimate(
      modelVersion: modelVersion,
      asOfUtc: asOfUtc,
      evidenceQuality: ExecutionEvidenceQuality.observed,
      sampleCount: observations.length,
      fullFillProbability: fullFillCount / observations.length,
      anyFillProbability: anyFillCount / observations.length,
      adverseSlippageP50Bps: _doublePercentile(slippage, 0.50),
      adverseSlippageP95Bps: _doublePercentile(slippage, 0.95),
      ackLatencyP50: _durationPercentile(ackLatencies, 0.50),
      finalFillLatencyP95: _durationPercentile(finalFillLatencies, 0.95),
    );
  }

  static double? _doublePercentile(List<double> values, double percentile) {
    if (values.isEmpty) return null;
    return values[_nearestRankIndex(values.length, percentile)];
  }

  static Duration? _durationPercentile(
    List<Duration> values,
    double percentile,
  ) {
    if (values.isEmpty) return null;
    return values[_nearestRankIndex(values.length, percentile)];
  }

  static int _nearestRankIndex(int length, double percentile) {
    final rank = (percentile * length).ceil().clamp(1, length);
    return rank.toInt() - 1;
  }
}
