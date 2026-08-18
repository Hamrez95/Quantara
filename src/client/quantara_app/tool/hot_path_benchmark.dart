import 'dart:convert';
import 'dart:io';

import 'package:quantara_app/features/hot_path_performance/application/hot_path_benchmark.dart';

void main(List<String> arguments) {
  final outputIndex = arguments.indexOf('--output');
  final outputPath = outputIndex >= 0 && outputIndex + 1 < arguments.length
      ? arguments[outputIndex + 1]
      : 'hot-path-performance.json';
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
  final report = {
    'schemaVersion': 'hot-path-certification/1.0',
    'physicalAndroidEvidence': false,
    'profiles': [target.toJson(), stress.toJson()],
    'processRssBytesBefore': rssBefore,
    'processRssBytesAfter': rssAfter,
  };
  final output = const JsonEncoder.withIndent('  ').convert(report);
  File(outputPath).writeAsStringSync('$output\n');
  stdout.writeln(output);
  if (target.elapsed + stress.elapsed > const Duration(seconds: 60)) {
    stderr.writeln('Combined software stress gate exceeded 60 seconds.');
    exitCode = 1;
  }
}
