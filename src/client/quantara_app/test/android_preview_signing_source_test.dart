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
    expect(gradle, isNot(contains('QUANTARA_UNSIGNED_CANDIDATE')));
    expect(gradle, isNot(contains('signingConfig = null')));
    expect(gradle, isNot(contains('signingConfigs.getByName("debug")')));
  });

  test('generic Flutter CI needs no release signing secrets', () {
    final workflow = File(
      '../../../.github/workflows/flutter-ci.yml',
    ).readAsStringSync();

    expect(workflow, contains('flutter analyze --fatal-infos'));
    expect(workflow, contains('flutter test --reporter expanded'));
    expect(workflow, contains('--debug --flavor alpha'));
    expect(workflow, contains('app-alpha-debug.apk'));
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

  test('stable release workflow keeps stable signing isolated', () {
    final workflow = File(
      '../../../.github/workflows/android-stable-release.yml',
    ).readAsStringSync();

    expect(workflow, contains('environment: production'));
    expect(workflow, contains('QUANTARA_ANDROID_KEYSTORE_BASE64'));
    expect(workflow, contains("QUANTARA_STABLE_RELEASE: 'true'"));
    expect(workflow, contains('apksigner'));
    expect(workflow, isNot(contains('QUANTARA_PREVIEW_RELEASE=true')));
  });
}
