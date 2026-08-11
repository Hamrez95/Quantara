import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  const fingerprint =
      'c1f8cbedb45a35f62e2065d74a1041477d811efa374128c0af4c493628dad984';

  test('release Gradle is fail-closed without persistent signing', () {
    final gradle = File('android/app/build.gradle.kts').readAsStringSync();

    expect(gradle, contains('QUANTARA_PREVIEW_RELEASE'));
    expect(gradle, contains('quantaraPreview'));
    expect(gradle, contains('Runner-local debug signing is forbidden'));
    expect(gradle, contains('gradle.taskGraph.whenReady'));
    expect(gradle, contains('releaseTaskSelected'));
    expect(
      gradle,
      contains(
        'releaseTaskSelected && !quantaraStableRelease && !quantaraPreviewRelease',
      ),
    );
    expect(gradle, contains('else -> Unit'));
    expect(gradle, isNot(contains('QUANTARA_UNSIGNED_CANDIDATE')));
    expect(gradle, isNot(contains('signingConfig = null')));
    expect(gradle, isNot(contains('signingConfigs.getByName("debug")')));
  });

  test('debug cleartext override cannot weaken main release manifest', () {
    final debugManifest = File(
      'android/app/src/debug/AndroidManifest.xml',
    ).readAsStringSync();
    final mainManifest = File(
      'android/app/src/main/AndroidManifest.xml',
    ).readAsStringSync();

    expect(debugManifest, contains('android:usesCleartextTraffic="true"'));
    expect(
      debugManifest,
      contains('tools:replace="android:usesCleartextTraffic"'),
    );
    expect(mainManifest, contains('android:usesCleartextTraffic="false"'));
  });

  test('generic Flutter CI is secret-free and uses an unsigned QA build', () {
    final workflow = File(
      '../../../.github/workflows/flutter-ci.yml',
    ).readAsStringSync();

    expect(workflow, contains('flutter analyze --fatal-infos'));
    expect(workflow, contains('flutter test --reporter expanded'));
    expect(workflow, contains('flutter build apk --debug'));
    expect(workflow, contains('app-debug.apk'));
    expect(workflow, contains('cold-start smoke'));
    expect(workflow, isNot(contains('environment: Preview')));
    expect(workflow, isNot(contains('KEYSTORE_BASE64:')));
    expect(workflow, isNot(contains('QUANTARA_PREVIEW_RELEASE=true')));
  });

  test('alpha preview workflow uses the persistent preview signer', () {
    final workflow = File(
      '../../../.github/workflows/android-alpha.yml',
    ).readAsStringSync();

    expect(workflow, contains('environment: Preview'));
    expect(workflow, contains(fingerprint));
    expect(workflow, contains('QUANTARA_PREVIEW_ANDROID_KEYSTORE_BASE64'));
    expect(workflow, contains('QUANTARA_PREVIEW_RELEASE=true'));
    expect(workflow, contains('apksigner'));
    expect(workflow, contains('SHA256SUMS.txt'));
  });

  test('stable release workflow pins the permanent signer', () {
    final workflow = File(
      '../../../.github/workflows/android-stable-release.yml',
    ).readAsStringSync();

    expect(workflow, contains('environment: production'));
    expect(workflow, contains('QUANTARA_ANDROID_KEYSTORE_BASE64'));
    expect(workflow, contains('QUANTARA_STABLE_CERT_SHA256'));
    expect(workflow, contains("QUANTARA_STABLE_RELEASE: 'true'"));
    expect(workflow, contains('apksigner'));
    expect(workflow, isNot(contains('QUANTARA_PREVIEW_RELEASE=true')));
  });
}
