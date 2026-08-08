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

  test('Flutter CI pins preview signer and publishes signing evidence', () {
    final workflow = File(
      '../../../.github/workflows/flutter-ci.yml',
    ).readAsStringSync();

    expect(workflow, contains(fingerprint));
    expect(workflow, contains('QUANTARA_PREVIEW_ANDROID_KEYSTORE_BASE64'));
    expect(workflow, contains('QUANTARA_PREVIEW_RELEASE=true'));
    expect(workflow, contains('apksigner'));
    expect(workflow, contains('preview-signing.txt'));
    expect(workflow, contains('SHA256SUMS.txt'));
    expect(workflow, contains('Resolve Android release candidate path'));
    expect(workflow, contains('ANDROID_RC_APK_PATH'));
  });

  test('alpha preview workflow uses the same persistent signer', () {
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
}
