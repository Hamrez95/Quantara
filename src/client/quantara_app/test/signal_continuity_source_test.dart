import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('signal continuity stays bounded and opens exact chart context', () {
    final controller = File(
      'lib/features/owner_alpha/application/owner_alpha_controller.dart',
    ).readAsStringSync();
    final signals = File(
      'lib/features/owner_alpha/presentation/owner_alpha_signals.dart',
    ).readAsStringSync();
    final analysis = File(
      'lib/features/owner_alpha/presentation/owner_alpha_analysis.dart',
    ).readAsStringSync();

    expect(controller, contains('outcomeCatchUpBatchSize = 2'));
    expect(controller, contains('_collectOutcomeCandles'));
    expect(controller, contains('selectChartContext'));
    expect(signals, contains('filtered[index].timeframe'));
    expect(signals, contains('filtered[index].setupId'));
    expect(analysis, contains('frozenSignal: controller.selectedChartSignal'));
  });
}
