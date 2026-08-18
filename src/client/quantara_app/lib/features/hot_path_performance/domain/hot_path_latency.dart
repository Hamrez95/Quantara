import 'dart:collection';

enum HotPathStage {
  ingestValidation,
  featureUpdate,
  playbookFanout,
  candidateEvaluation,
  ranking,
  riskAllocation,
  durableReservationAudit,
  tradeIntent,
}

final class HotPathStageSample {
  const HotPathStageSample({
    required this.correlationId,
    required this.stage,
    required this.startedAtUtc,
    required this.completedAtUtc,
  });

  final String correlationId;
  final HotPathStage stage;
  final DateTime startedAtUtc;
  final DateTime completedAtUtc;

  Duration get latency => completedAtUtc.difference(startedAtUtc);
}

final class HotPathStagePercentiles {
  const HotPathStagePercentiles({
    required this.count,
    required this.p50,
    required this.p95,
    required this.p99,
  });

  final int count;
  final Duration p50;
  final Duration p95;
  final Duration p99;

  Map<String, Object> toJson() => {
    'count': count,
    'p50Micros': p50.inMicroseconds,
    'p95Micros': p95.inMicroseconds,
    'p99Micros': p99.inMicroseconds,
  };
}

/// Bounded in-memory latency evidence. It never performs I/O on the hot path.
final class HotPathLatencyRecorder {
  HotPathLatencyRecorder({this.maximumSamplesPerStage = 512}) {
    if (maximumSamplesPerStage < 20 || maximumSamplesPerStage > 8192) {
      throw ArgumentError.value(
        maximumSamplesPerStage,
        'maximumSamplesPerStage',
      );
    }
  }

  final int maximumSamplesPerStage;
  final Map<HotPathStage, Queue<HotPathStageSample>> _samples = {};

  void record(HotPathStageSample sample) {
    if (sample.correlationId.trim().isEmpty ||
        !sample.startedAtUtc.isUtc ||
        !sample.completedAtUtc.isUtc ||
        sample.completedAtUtc.isBefore(sample.startedAtUtc)) {
      throw const FormatException('Hot-path latency evidence is invalid.');
    }
    final values = _samples.putIfAbsent(sample.stage, Queue.new);
    values.addLast(sample);
    while (values.length > maximumSamplesPerStage) {
      values.removeFirst();
    }
  }

  int sampleCount(HotPathStage stage) => _samples[stage]?.length ?? 0;

  HotPathStagePercentiles percentiles(HotPathStage stage) {
    final values = _samples[stage];
    if (values == null || values.isEmpty) {
      return const HotPathStagePercentiles(
        count: 0,
        p50: Duration.zero,
        p95: Duration.zero,
        p99: Duration.zero,
      );
    }
    final micros =
        values
            .map((sample) => sample.latency.inMicroseconds)
            .toList(growable: false)
          ..sort();
    Duration at(double percentile) {
      final index = ((micros.length - 1) * percentile).ceil();
      return Duration(microseconds: micros[index]);
    }

    return HotPathStagePercentiles(
      count: micros.length,
      p50: at(0.50),
      p95: at(0.95),
      p99: at(0.99),
    );
  }

  Map<String, Object> toJson() => {
    'sampleCapacityPerStage': maximumSamplesPerStage,
    'stages': {
      for (final stage in HotPathStage.values)
        stage.name: percentiles(stage).toJson(),
    },
  };
}
