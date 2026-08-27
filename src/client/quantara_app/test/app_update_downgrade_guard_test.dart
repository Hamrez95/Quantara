import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:quantara_app/features/app_update/application/app_update_controller.dart';
import 'package:quantara_app/features/app_update/data/app_update_manifest_client.dart';
import 'package:quantara_app/features/app_update/domain/app_update_models.dart';

void main() {
  const checksum =
      'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';

  AppUpdateController makeController({
    required String currentVersion,
    required int currentBuild,
    required String publishedVersion,
    required int publishedBuild,
  }) {
    final client = MockClient((request) async {
      final manifest = <String, Object?>{
        'schemaVersion': 1,
        'channel': 'stable',
        'publishedAt': '2026-08-27T00:00:00Z',
        'minimumSupportedVersion': '1.0.0',
        'mandatory': false,
        'releaseNotes': <String, String>{'en': 'Release notes'},
        'artifacts': <String, Object?>{
          'android': <String, Object?>{
            'version': publishedVersion,
            'buildNumber': publishedBuild,
            'url': 'https://releases.example.test/Quantara.apk',
            'sha256': checksum,
            'packageId': 'com.quantara.quantara_app',
            'signingIdentity': 'AA11',
          },
        },
        'rolloutPercent': 100,
        'revokedBuilds': <int>[],
      };
      return http.Response(jsonEncode(manifest), 200);
    });

    final manifestClient = AppUpdateManifestClient(
      client: client,
      stableManifestUri: Uri.parse('https://updates.example.test/stable.json'),
      canaryManifestUri: Uri.parse('https://updates.example.test/canary.json'),
    );
    return AppUpdateController(
      manifestClient: manifestClient,
      currentVersion: currentVersion,
      currentBuildNumber: currentBuild,
      platform: AppReleasePlatform.android,
      initialChannel: AppReleaseChannel.stable,
      languageCode: 'en',
    );
  }

  test('rejects semantic downgrade', () async {
    final controller = makeController(
      currentVersion: '1.2.0',
      currentBuild: 126,
      publishedVersion: '1.1.9',
      publishedBuild: 999,
    );
    addTearDown(controller.dispose);

    expect(await controller.check(), isFalse);
    expect(controller.result, isNull);
    expect(controller.error, contains('explicit recovery is required'));
  });

  test('rejects same-version build downgrade', () async {
    final controller = makeController(
      currentVersion: '1.2.0',
      currentBuild: 126,
      publishedVersion: '1.2.0',
      publishedBuild: 125,
    );
    addTearDown(controller.dispose);

    expect(await controller.check(), isFalse);
    expect(controller.result, isNull);
    expect(controller.error, contains('current build'));
  });

  test('rejects lower build for newer version', () async {
    final controller = makeController(
      currentVersion: '1.2.0',
      currentBuild: 126,
      publishedVersion: '1.3.0',
      publishedBuild: 125,
    );
    addTearDown(controller.dispose);

    expect(await controller.check(), isFalse);
    expect(controller.result, isNull);
    expect(controller.error, contains('current build'));
  });

  test('allows newer version with monotonic build', () async {
    final controller = makeController(
      currentVersion: '1.2.0',
      currentBuild: 126,
      publishedVersion: '1.2.1',
      publishedBuild: 127,
    );
    addTearDown(controller.dispose);

    expect(await controller.check(), isTrue);
    expect(controller.error, isNull);
    expect(controller.result?.updateAvailable, isTrue);
  });
}
