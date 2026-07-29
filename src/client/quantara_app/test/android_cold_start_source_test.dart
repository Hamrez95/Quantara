import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Android cold start stays free of optional background plugins', () {
    final mainSource = File('lib/main.dart').readAsStringSync();
    final manifest = File(
      'android/app/src/main/AndroidManifest.xml',
    ).readAsStringSync();
    final activity = File(
      'android/app/src/main/kotlin/com/quantara/quantara_app/SafeMainActivity.kt',
    ).readAsStringSync();
    final pubspec = File('pubspec.yaml').readAsStringSync();

    expect(mainSource, contains('runApp(const QuantaraApp())'));
    expect(mainSource, isNot(contains('BackgroundOpportunityScanner')));
    expect(mainSource, isNot(contains('await ')));

    expect(manifest, contains('android:name=".SafeMainActivity"'));
    expect(activity, contains('class SafeMainActivity : FlutterActivity()'));
    expect(activity, isNot(contains('configureFlutterEngine')));
    expect(activity, isNot(contains('WebView')));

    expect(pubspec, isNot(contains('\n  workmanager:')));
    expect(pubspec, isNot(contains('\n  flutter_local_notifications:')));
  });
}
