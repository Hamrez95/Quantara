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
    final notifications = File(
      'lib/features/owner_alpha/data/platform_opportunity_services.dart',
    ).readAsStringSync();
    final page = File(
      'lib/features/owner_alpha/presentation/owner_alpha_page.dart',
    ).readAsStringSync();

    expect(controller, contains('outcomeCatchUpBatchSize = 2'));
    expect(controller, contains('_collectOutcomeCandles'));
    expect(controller, contains('selectChartContext'));
    expect(signals, contains('filtered[index].timeframe'));
    expect(signals, contains('filtered[index].setupId'));
    expect(analysis, contains('frozenSignal: controller.selectedChartSignal'));
    expect(notifications, contains('onDidReceiveNotificationResponse'));
    expect(notifications, contains('getNotificationAppLaunchDetails'));
    expect(notifications, contains("'view_analysis'"));
    expect(page, contains('_openNotificationSetup'));
    expect(page, contains('signal.timeframe'));
    expect(page, contains('signal.setupId'));
  });
}
