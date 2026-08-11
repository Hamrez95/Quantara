import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('RC3 source and artifacts are version-locked to post-run fixes', () {
    final pubspec = File('pubspec.yaml').readAsStringSync();
    final flutterWorkflow = File(
      '../../../.github/workflows/flutter-ci.yml',
    ).readAsStringSync();
    final windowsWorkflow = File(
      '../../../.github/workflows/windows-desktop-ci.yml',
    ).readAsStringSync();
    final application = File(
      'lib/features/owner_alpha/data/realtime_market_application.dart',
    ).readAsStringSync();
    final autoTrade = File(
      'lib/features/owner_alpha/presentation/owner_alpha_auto_trade.dart',
    ).readAsStringSync();
    final labBroker = File(
      'lib/features/trading_lab/application/trading_lab_paper_broker.dart',
    ).readAsStringSync();
    final labZip = File(
      'lib/features/trading_lab/application/trading_lab_zip_bundle.dart',
    ).readAsStringSync();

    expect(pubspec, contains('version: 1.2.0-rc.3+125'));
    expect(flutterWorkflow, contains('RC_VERSION: 1.2.0-rc.3'));
    expect(
      flutterWorkflow,
      contains('ANDROID_RC_ARTIFACT: quantara-android-1.2.0-rc.3'),
    );
    expect(windowsWorkflow, contains('RC_VERSION: 1.2.0-rc.3'));
    expect(application, contains('_quarantinedStreamFaults'));
    expect(autoTrade, contains('Resume entries'));
    expect(labBroker, contains('execution_cost_to_risk_too_high'));
    expect(labBroker, contains("'anomalyCode': 'scanner_gap'"));
    expect(labZip, contains("'real_account_trades.jsonl'"));
    expect(labZip, contains("'benchmark_matrix.json'"));
  });
}
