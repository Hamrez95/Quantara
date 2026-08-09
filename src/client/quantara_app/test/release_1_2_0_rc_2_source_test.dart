import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('RC2 source and artifacts are version-locked to physical fixes', () {
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

    expect(pubspec, contains('version: 1.2.0-rc.2+123'));
    expect(flutterWorkflow, contains('RC_VERSION: 1.2.0-rc.2'));
    expect(
      flutterWorkflow,
      contains('ANDROID_RC_ARTIFACT: quantara-android-1.2.0-rc.2'),
    );
    expect(windowsWorkflow, contains('RC_VERSION: 1.2.0-rc.2'));
    expect(application, contains('_quarantinedStreamFaults'));
    expect(autoTrade, contains('Resume entries'));
  });
}
