import 'dart:math' as math;

import '../../market_analysis/domain/market_chart_models.dart';
import '../domain/hot_path_latency.dart';
import '../domain/rolling_market_features.dart';

final class HotPathBenchmarkConfig {
  const HotPathBenchmarkConfig({
    this.symbols = 100,
    this.timeframes = 5,
    this.strategies = 3,
    this.bootstrapCandles = 210,
    this.updatesPerStream = 20,
    this.seed = 198,
  });

  final int symbols;
  final int timeframes;
  final int strategies;
  final int bootstrapCandles;
  final int updatesPerStream;
  final int seed;

  int get streams => symbols * timeframes;
  int get candidateEvaluations => streams * updatesPerStream * strategies;
}

final class HotPathBenchmarkResult {
  const HotPathBenchmarkResult({
    required this.config,
    required this.elapsed,
    required this.checksum,
    required this.latency,
  });

  final HotPathBenchmarkConfig config;
  final Duration elapsed;
  final int checksum;
  final HotPathLatencyRecorder latency;

  Map<String, Object> toJson() => {
    'schemaVersion': 'hot-path-benchmark/1.0',
    'evidenceClass': 'software-ci-synthetic-market-load',
    'physicalAndroidEvidence': false,
    'config': {
      'symbols': config.symbols,
      'timeframes': config.timeframes,
      'strategies': config.strategies,
      'bootstrapCandles': config.bootstrapCandles,
      'updatesPerStream': config.updatesPerStream,
      'seed': config.seed,
      'streams': config.streams,
      'candidateEvaluations': config.candidateEvaluations,
    },
    'elapsedMicros': elapsed.inMicroseconds,
    'deterministicChecksum': checksum,
    'latency': latency.toJson(),
  };
}

/// Reproducible software stress harness; it does not certify physical devices.
abstract final class HotPathBenchmark {
  static HotPathBenchmarkResult run({
    HotPathBenchmarkConfig config = const HotPathBenchmarkConfig(),
  }) {
    if (config.symbols < 1 ||
        config.timeframes < 1 ||
        config.strategies < 1 ||
        config.bootstrapCandles < 200 ||
        config.updatesPerStream < 1) {
      throw ArgumentError('The hot-path benchmark configuration is invalid.');
    }
    final random = math.Random(config.seed);
    final recorder = HotPathLatencyRecorder(maximumSamplesPerStage: 1024);
    final clock = Stopwatch()..start();
    final evidenceEpoch = DateTime.utc(2026, 1, 1);
    var checksum = 17;

    for (var stream = 0; stream < config.streams; stream++) {
      final state = RollingMarketFeatureState();
      var price = 100 + stream * 0.01;
      final total = config.bootstrapCandles + config.updatesPerStream;
      for (var index = 0; index < total; index++) {
        final correlationId = 's$stream-u$index';
        final move = random.nextDouble() * 2 - 1;
        final close = math.max(1, price + move).toDouble();
        final candle = ChartCandle(
          openTime: evidenceEpoch.add(Duration(minutes: index * 5)),
          open: price,
          high: math.max(price, close) + random.nextDouble(),
          low: math.max(0.000001, math.min(price, close) - random.nextDouble()),
          close: close,
          volume: 100 + random.nextDouble() * 900,
        );
        _measure(
          recorder,
          clock,
          evidenceEpoch,
          correlationId,
          HotPathStage.ingestValidation,
          () {
            if (!candle.isValid) throw StateError('Invalid benchmark candle.');
          },
        );
        RollingMarketFeatureSnapshot? features;
        _measure(
          recorder,
          clock,
          evidenceEpoch,
          correlationId,
          HotPathStage.featureUpdate,
          () => features = state.append(candle),
        );
        price = close;
        if (index < config.bootstrapCandles || features == null) continue;

        late List<double> scores;
        _measure(
          recorder,
          clock,
          evidenceEpoch,
          correlationId,
          HotPathStage.playbookFanout,
          () => scores = List<double>.generate(
            config.strategies,
            (strategy) =>
                features!.ema20 -
                features!.ema50 +
                features!.relativeVolume20 * (strategy + 1),
            growable: false,
          ),
        );
        _measure(
          recorder,
          clock,
          evidenceEpoch,
          correlationId,
          HotPathStage.candidateEvaluation,
          () => scores = scores.where((score) => score.isFinite).toList(),
        );
        _measure(
          recorder,
          clock,
          evidenceEpoch,
          correlationId,
          HotPathStage.ranking,
          () => scores.sort((left, right) => right.compareTo(left)),
        );
        var capacity = 0.0;
        _measure(
          recorder,
          clock,
          evidenceEpoch,
          correlationId,
          HotPathStage.riskAllocation,
          () => capacity = scores.isEmpty
              ? 0.0
              : math.min(scores.first.abs(), 1).toDouble(),
        );
        _measure(
          recorder,
          clock,
          evidenceEpoch,
          correlationId,
          HotPathStage.durableReservationAudit,
          () => checksum = _mix(checksum, (capacity * 1000000).round()),
        );
        _measure(
          recorder,
          clock,
          evidenceEpoch,
          correlationId,
          HotPathStage.tradeIntent,
          () {
            for (final codeUnit in correlationId.codeUnits) {
              checksum = _mix(checksum, codeUnit);
            }
          },
        );
      }
    }
    clock.stop();
    return HotPathBenchmarkResult(
      config: config,
      elapsed: clock.elapsed,
      checksum: checksum,
      latency: recorder,
    );
  }

  static void _measure(
    HotPathLatencyRecorder recorder,
    Stopwatch clock,
    DateTime epoch,
    String correlationId,
    HotPathStage stage,
    void Function() operation,
  ) {
    final started = clock.elapsedMicroseconds;
    operation();
    final completed = clock.elapsedMicroseconds;
    recorder.record(
      HotPathStageSample(
        correlationId: correlationId,
        stage: stage,
        startedAtUtc: epoch.add(Duration(microseconds: started)),
        completedAtUtc: epoch.add(Duration(microseconds: completed)),
      ),
    );
  }

  static int _mix(int current, int value) =>
      ((current * 16777619) ^ value) & 0x7fffffff;
}
