import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('RC2 source and release artifacts retain physical-fix contracts', () {
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

    expect(pubspec, contains('version: 1.2.0-rc.2+124'));
    expect(
      flutterWorkflow,
      contains('Flutter format, analyze, test, and unsigned QA build'),
    );
    expect(flutterWorkflow, contains('flutter build apk --debug'));
    expect(
      flutterWorkflow,
      contains('ANDROID_DEBUG_ARTIFACT: quantara-android-debug-'),
    );
    expect(flutterWorkflow, isNot(contains('RC_VERSION:')));
    expect(windowsWorkflow, contains('RC_VERSION: 1.2.0-rc.2'));
    expect(application, contains('_quarantinedStreamFaults'));
    expect(autoTrade, contains('Resume entries'));
  });
}
