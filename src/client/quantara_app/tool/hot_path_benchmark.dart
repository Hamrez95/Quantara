import 'dart:convert';
import 'dart:io';

import 'package:quantara_app/features/hot_path_performance/application/hot_path_benchmark.dart';

void main(List<String> arguments) {
  final outputIndex = arguments.indexOf('--output');
  final outputPath = outputIndex >= 0 && outputIndex + 1 < arguments.length
      ? arguments[outputIndex + 1]
      : 'hot-path-performance.json';
  final buildCommitIndex = arguments.indexOf('--build-commit');
  final buildCommit =
      buildCommitIndex >= 0 && buildCommitIndex + 1 < arguments.length
      ? arguments[buildCommitIndex + 1].trim()
      : (Platform.environment['QUANTARA_BUILD_COMMIT'] ??
                Platform.environment['GITHUB_SHA'] ??
                'local')
            .trim();
  if (buildCommit.isEmpty) {
    stderr.writeln('Hot-path evidence requires a non-empty build commit.');
    exitCode = 2;
    return;
  }

  final rssBefore = ProcessInfo.currentRss;
  final target = HotPathBenchmark.run();
  final stress = HotPathBenchmark.run(
    config: const HotPathBenchmarkConfig(
      symbols: 150,
      timeframes: 5,
      strategies: 4,
      bootstrapCandles: 210,
      updatesPerStream: 20,
      seed: 199,
    ),
  );
  final rssAfter = ProcessInfo.currentRss;
  const combinedSoftwareGateLimit = Duration(seconds: 60);
  final combinedElapsed = target.elapsed + stress.elapsed;
  final softwareGatePassed = combinedElapsed <= combinedSoftwareGateLimit;
  final runnerOs = Platform.environment['RUNNER_OS']?.trim();
  final runnerArch = Platform.environment['RUNNER_ARCH']?.trim();
  final report = {
    'schemaVersion': 'hot-path-certification/1.1',
    'evidenceClass': 'software-ci-synthetic-market-load',
    'buildCommit': buildCommit,
    'physicalAndroidEvidence': false,
    'platform': {
      'operatingSystem': Platform.operatingSystem,
      'operatingSystemVersion': Platform.operatingSystemVersion,
      'numberOfProcessors': Platform.numberOfProcessors,
      'dartVersion': Platform.version,
      'runnerOs': runnerOs,
      'runnerArch': runnerArch,
    },
    'profiles': [target.toJson(), stress.toJson()],
    'processRssBytesBefore': rssBefore,
    'processRssBytesAfter': rssAfter,
    'combinedElapsedMicros': combinedElapsed.inMicroseconds,
    'combinedSoftwareGateLimitMicros': combinedSoftwareGateLimit.inMicroseconds,
    'softwareGatePassed': softwareGatePassed,
  };
  final output = const JsonEncoder.withIndent('  ').convert(report);
  File(outputPath).writeAsStringSync('$output\n');
  stdout.writeln(output);
  if (!softwareGatePassed) {
    stderr.writeln('Combined software stress gate exceeded 60 seconds.');
    exitCode = 1;
  }
}
