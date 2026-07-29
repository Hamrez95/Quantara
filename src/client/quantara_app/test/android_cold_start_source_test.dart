import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Android cold start defers background work until after first frame', () {
    final mainSource = File('lib/main.dart').readAsStringSync();
    final scanner = File(
      'lib/features/owner_alpha/data/background_opportunity_scanner.dart',
    ).readAsStringSync();
    final manifest = File(
      'android/app/src/main/AndroidManifest.xml',
    ).readAsStringSync();
    final activity = File(
      'android/app/src/main/kotlin/com/quantara/quantara_app/'
      'SafeMainActivity.kt',
    ).readAsStringSync();
    final application = File(
      'android/app/src/main/kotlin/com/quantara/quantara_app/'
      'QuantaraApplication.kt',
    ).readAsStringSync();
    final pubspec = File('pubspec.yaml').readAsStringSync();

    final runAppIndex = mainSource.indexOf('runApp(const QuantaraApp())');
    final postFrameIndex = mainSource.indexOf('addPostFrameCallback');
    final backgroundIndex = mainSource.indexOf(
      'BackgroundOpportunityScanner.initialize()',
    );
    expect(runAppIndex, greaterThanOrEqualTo(0));
    expect(postFrameIndex, greaterThan(runAppIndex));
    expect(backgroundIndex, greaterThan(postFrameIndex));
    expect(mainSource.substring(0, runAppIndex), isNot(contains('await ')));

    expect(manifest, contains('android:name=".SafeMainActivity"'));
    expect(manifest, contains('android:name=".QuantaraApplication"'));
    expect(manifest, contains('androidx.work.WorkManagerInitializer'));
    expect(manifest, contains('tools:node="remove"'));
    expect(application, contains('Configuration.Provider'));
    expect(activity, isNot(contains('WebView')));
    expect(activity, isNot(contains('QuantaraChartFactory')));

    expect(pubspec, contains('\n  workmanager: ^0.9.0+3'));
    expect(pubspec, contains('\n  flutter_local_notifications: ^22.2.0'));
    expect(scanner, contains('registerPeriodicTask'));
    expect(scanner, contains('Duration(minutes: 15)'));
  });
}
