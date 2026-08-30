import 'package:flutter_test/flutter_test.dart';
import 'package:quantara_app/features/hot_path_performance/domain/hot_path_latency.dart';

void main() {
  test('keeps bounded samples and reports deterministic percentiles', () {
    final recorder = HotPathLatencyRecorder(maximumSamplesPerStage: 20);
    final base = DateTime.utc(2026, 1, 1);
    for (var index = 1; index <= 30; index++) {
      recorder.record(
        HotPathStageSample(
          correlationId: 'trace-$index',
          stage: HotPathStage.featureUpdate,
          startedAtUtc: base,
          completedAtUtc: base.add(Duration(microseconds: index)),
        ),
      );
    }

    final result = recorder.percentiles(HotPathStage.featureUpdate);
    expect(result.count, 20);
    expect(result.p50.inMicroseconds, 21);
    expect(result.p95.inMicroseconds, 30);
    expect(result.p99.inMicroseconds, 30);
    expect(recorder.sampleCount(HotPathStage.ingestValidation), 0);
  });

  test('rejects malformed correlation and non-UTC or negative samples', () {
    final recorder = HotPathLatencyRecorder(maximumSamplesPerStage: 20);
    final utc = DateTime.utc(2026, 1, 1);

    expect(
      () => recorder.record(
        HotPathStageSample(
          correlationId: ' ',
          stage: HotPathStage.ranking,
          startedAtUtc: utc,
          completedAtUtc: utc,
        ),
      ),
      throwsFormatException,
    );
    expect(
      () => recorder.record(
        HotPathStageSample(
          correlationId: 'trace',
          stage: HotPathStage.ranking,
          startedAtUtc: utc,
          completedAtUtc: utc.subtract(const Duration(microseconds: 1)),
        ),
      ),
      throwsFormatException,
    );
  });
}
