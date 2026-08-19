import '../../hot_path_performance/domain/hot_path_latency.dart';
import 'release_certification.dart';

abstract final class PerformanceReleaseEvidenceGate {
  static ReleaseGateEvidence evaluate({
    required String expectedBuildCommit,
    required Map<String, Object?> serverReport,
    required Map<String, Object?> windowsReport,
  }) {
    final commit = expectedBuildCommit.trim();
    if (commit.isEmpty) {
      throw const FormatException(
        'Performance release evidence requires a build commit.',
      );
    }

    final server = _validateReport(
      report: serverReport,
      expectedBuildCommit: commit,
      expectedOperatingSystem: 'linux',
    );
    final windows = _validateReport(
      report: windowsReport,
      expectedBuildCommit: commit,
      expectedOperatingSystem: 'windows',
    );

    return ReleaseGateEvidence(
      code: ReleaseGateCode.performanceSlo,
      status: ReleaseGateStatus.passed,
      evidenceIds: [server.evidenceId, windows.evidenceId],
    );
  }

  static _ValidatedPerformanceReport _validateReport({
    required Map<String, Object?> report,
    required String expectedBuildCommit,
    required String expectedOperatingSystem,
  }) {
    if (report['schemaVersion'] != 'hot-path-certification/1.1' ||
        report['evidenceClass'] != 'software-ci-synthetic-market-load' ||
        report['physicalAndroidEvidence'] != false ||
        report['softwareGatePassed'] != true ||
        report['buildCommit']?.toString().trim() != expectedBuildCommit) {
      throw const FormatException(
        'Performance report identity or software gate evidence is invalid.',
      );
    }

    final platform = _stringObjectMap(report['platform']);
    final operatingSystem = platform['operatingSystem']?.toString().trim();
    final processorCount = _integer(platform['numberOfProcessors']);
    if (operatingSystem != expectedOperatingSystem || processorCount < 1) {
      throw const FormatException(
        'Performance report platform evidence is invalid.',
      );
    }

    final rssBefore = _integer(report['processRssBytesBefore']);
    final rssAfter = _integer(report['processRssBytesAfter']);
    final elapsed = _integer(report['combinedElapsedMicros']);
    final limit = _integer(report['combinedSoftwareGateLimitMicros']);
    if (rssBefore <= 0 || rssAfter <= 0 || elapsed <= 0 || limit <= 0 || elapsed > limit) {
      throw const FormatException(
        'Performance report RSS or elapsed-budget evidence is invalid.',
      );
    }

    final profiles = report['profiles'];
    if (profiles is! List<Object?> || profiles.length != 2) {
      throw const FormatException(
        'Performance report must contain target and stress profiles.',
      );
    }
    final parsed = profiles.map(_stringObjectMap).toList(growable: false);
    final target = parsed.firstWhere(
      (profile) => _config(profile)['symbols'] == 100,
      orElse: () => const <String, Object?>{},
    );
    final stress = parsed.firstWhere(
      (profile) => _integer(_config(profile)['symbols']) >= 150,
      orElse: () => const <String, Object?>{},
    );
    if (target.isEmpty || stress.isEmpty) {
      throw const FormatException(
        'Performance target and stress profiles are missing.',
      );
    }
    _validateProfile(target, targetProfile: true);
    _validateProfile(stress, targetProfile: false);

    final targetChecksum = _integer(target['deterministicChecksum']);
    final stressChecksum = _integer(stress['deterministicChecksum']);
    return _ValidatedPerformanceReport(
      evidenceId:
          'hot-path:$expectedOperatingSystem:$expectedBuildCommit:$targetChecksum:$stressChecksum',
    );
  }

  static void _validateProfile(
    Map<String, Object?> profile, {
    required bool targetProfile,
  }) {
    if (profile['schemaVersion'] != 'hot-path-benchmark/1.0' ||
        profile['physicalAndroidEvidence'] != false ||
        _integer(profile['elapsedMicros']) <= 0 ||
        _integer(profile['deterministicChecksum']) <= 0) {
      throw const FormatException('Performance profile identity is invalid.');
    }

    final config = _config(profile);
    final symbols = _integer(config['symbols']);
    final timeframes = _integer(config['timeframes']);
    final strategies = _integer(config['strategies']);
    if (targetProfile) {
      if (symbols != 100 || timeframes < 5 || strategies < 3) {
        throw const FormatException(
          'Target performance profile does not cover the required universe.',
        );
      }
    } else if (symbols < 150 || timeframes < 5 || strategies < 4) {
      throw const FormatException(
        'Stress performance profile does not cover the required envelope.',
      );
    }

    final latency = _stringObjectMap(profile['latency']);
    final stages = _stringObjectMap(latency['stages']);
    for (final stage in HotPathStage.values) {
      final values = _stringObjectMap(stages[stage.name]);
      final count = _integer(values['count']);
      final p50 = _integer(values['p50Micros']);
      final p95 = _integer(values['p95Micros']);
      final p99 = _integer(values['p99Micros']);
      if (count <= 0 || p50 < 0 || p95 < p50 || p99 < p95) {
        throw FormatException(
          'Performance latency evidence is invalid for ${stage.name}.',
        );
      }
    }
  }

  static Map<String, Object?> _config(Map<String, Object?> profile) =>
      _stringObjectMap(profile['config']);

  static Map<String, Object?> _stringObjectMap(Object? value) {
    if (value is Map<String, Object?>) return value;
    if (value is Map<Object?, Object?>) {
      return value.map((key, item) => MapEntry(key.toString(), item));
    }
    return const {};
  }

  static int _integer(Object? value) => value is num ? value.toInt() : -1;
}

final class _ValidatedPerformanceReport {
  const _ValidatedPerformanceReport({required this.evidenceId});

  final String evidenceId;
}
