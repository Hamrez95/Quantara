import 'package:flutter_test/flutter_test.dart';
import 'package:quantara_app/features/hot_path_performance/domain/hot_path_latency.dart';
import 'package:quantara_app/features/release_acceptance/domain/performance_release_evidence.dart';
import 'package:quantara_app/features/release_acceptance/domain/release_certification.dart';

void main() {
  const commit = 'abc123';

  test('Linux and Windows reports for one build pass performanceSlo', () {
    final evidence = PerformanceReleaseEvidenceGate.evaluate(
      expectedBuildCommit: commit,
      serverReport: report(os: 'linux', buildCommit: commit),
      windowsReport: report(os: 'windows', buildCommit: commit),
    );

    expect(evidence.code, ReleaseGateCode.performanceSlo);
    expect(evidence.status, ReleaseGateStatus.passed);
    expect(evidence.evidenceIds, hasLength(2));
    expect(evidence.evidenceIds.first, startsWith('hot-path:linux:$commit:'));
    expect(evidence.evidenceIds.last, startsWith('hot-path:windows:$commit:'));
  });

  test('cross-build performance evidence fails closed', () {
    expect(
      () => PerformanceReleaseEvidenceGate.evaluate(
        expectedBuildCommit: commit,
        serverReport: report(os: 'linux', buildCommit: commit),
        windowsReport: report(os: 'windows', buildCommit: 'other'),
      ),
      throwsFormatException,
    );
  });

  test('physical Android claim cannot be smuggled into software evidence', () {
    final windows = report(os: 'windows', buildCommit: commit);
    windows['physicalAndroidEvidence'] = true;

    expect(
      () => PerformanceReleaseEvidenceGate.evaluate(
        expectedBuildCommit: commit,
        serverReport: report(os: 'linux', buildCommit: commit),
        windowsReport: windows,
      ),
      throwsFormatException,
    );
  });

  test('missing critical-stage percentile evidence fails closed', () {
    final server = report(os: 'linux', buildCommit: commit);
    final profiles = server['profiles']! as List<Object?>;
    final target = profiles.first as Map<String, Object?>;
    final latency = target['latency']! as Map<String, Object?>;
    final stages = latency['stages']! as Map<String, Object?>;
    stages.remove(HotPathStage.riskAllocation.name);

    expect(
      () => PerformanceReleaseEvidenceGate.evaluate(
        expectedBuildCommit: commit,
        serverReport: server,
        windowsReport: report(os: 'windows', buildCommit: commit),
      ),
      throwsFormatException,
    );
  });

  test('benchmark below required target universe cannot pass release evidence', () {
    final server = report(os: 'linux', buildCommit: commit);
    final profiles = server['profiles']! as List<Object?>;
    final target = profiles.first as Map<String, Object?>;
    final config = target['config']! as Map<String, Object?>;
    config['symbols'] = 99;

    expect(
      () => PerformanceReleaseEvidenceGate.evaluate(
        expectedBuildCommit: commit,
        serverReport: server,
        windowsReport: report(os: 'windows', buildCommit: commit),
      ),
      throwsFormatException,
    );
  });
}

Map<String, Object?> report({
  required String os,
  required String buildCommit,
}) => {
  'schemaVersion': 'hot-path-certification/1.1',
  'evidenceClass': 'software-ci-synthetic-market-load',
  'buildCommit': buildCommit,
  'physicalAndroidEvidence': false,
  'platform': {
    'operatingSystem': os,
    'operatingSystemVersion': '$os-test',
    'numberOfProcessors': 8,
    'dartVersion': 'test',
    'runnerOs': os,
    'runnerArch': 'X64',
  },
  'profiles': [
    profile(symbols: 100, timeframes: 5, strategies: 3, checksum: 101),
    profile(symbols: 150, timeframes: 5, strategies: 4, checksum: 202),
  ],
  'processRssBytesBefore': 100000,
  'processRssBytesAfter': 120000,
  'combinedElapsedMicros': 500000,
  'combinedSoftwareGateLimitMicros': 60000000,
  'softwareGatePassed': true,
};

Map<String, Object?> profile({
  required int symbols,
  required int timeframes,
  required int strategies,
  required int checksum,
}) => {
  'schemaVersion': 'hot-path-benchmark/1.0',
  'evidenceClass': 'software-ci-synthetic-market-load',
  'physicalAndroidEvidence': false,
  'config': {
    'symbols': symbols,
    'timeframes': timeframes,
    'strategies': strategies,
    'bootstrapCandles': 210,
    'updatesPerStream': 20,
    'seed': 198,
  },
  'elapsedMicros': 250000,
  'deterministicChecksum': checksum,
  'latency': {
    'sampleCapacityPerStage': 1024,
    'stages': {
      for (final stage in HotPathStage.values)
        stage.name: {
          'count': 100,
          'p50Micros': 1,
          'p95Micros': 2,
          'p99Micros': 3,
        },
    },
  },
};
