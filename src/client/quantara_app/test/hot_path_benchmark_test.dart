import 'package:flutter_test/flutter_test.dart';
import 'package:quantara_app/features/hot_path_performance/application/hot_path_benchmark.dart';
import 'package:quantara_app/features/hot_path_performance/domain/hot_path_latency.dart';

void main() {
  test('stress harness covers every stage with deterministic work', () {
    const config = HotPathBenchmarkConfig(
      symbols: 3,
      timeframes: 2,
      strategies: 3,
      bootstrapCandles: 200,
      updatesPerStream: 2,
      seed: 198,
    );
    final first = HotPathBenchmark.run(config: config);
    final second = HotPathBenchmark.run(config: config);

    expect(first.checksum, second.checksum);
    expect(first.config.candidateEvaluations, 36);
    for (final stage in HotPathStage.values) {
      expect(
        first.latency.sampleCount(stage),
        greaterThan(0),
        reason: stage.name,
      );
    }
    expect(first.toJson()['physicalAndroidEvidence'], isFalse);
  });
}
