import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:quantara_app/features/app_update/application/app_update_controller.dart';
import 'package:quantara_app/features/app_update/data/app_update_manifest_client.dart';
import 'package:quantara_app/features/app_update/domain/app_update_models.dart';

String checksum(String character) => List.filled(64, character).join();

http.Response manifestResponse(Map<String, Object?> body) {
  return http.Response.bytes(
    utf8.encode(jsonEncode(body)),
    200,
    headers: const {'content-type': 'application/json; charset=utf-8'},
  );
}

Map<String, Object?> manifestJson({
  String channel = 'canary',
  String version = '0.14.0',
  int buildNumber = 17,
  bool mandatory = false,
  List<int> revokedBuilds = const [],
}) => {
  'schemaVersion': 1,
  'channel': channel,
  'publishedAt': '2026-08-01T00:00:00Z',
  'minimumSupportedVersion': '0.13.0',
  'mandatory': mandatory,
  'releaseNotes': {
    'fa': 'مدیریت ریسک داینامیک',
    'en': 'Dynamic risk management',
  },
  'rolloutPercent': 100,
  'revokedBuilds': revokedBuilds,
  'artifacts': {
    'android': {
      'version': version,
      'buildNumber': buildNumber,
      'url': 'https://updates.quantara.app/releases/$version/quantara.apk',
      'sha256': checksum('a'),
      'packageId': 'app.quantara.canary',
      'signingIdentity': 'sha256/example',
      'architecture': 'arm64-v8a',
    },
    'windows': {
      'version': version,
      'buildNumber': buildNumber,
      'url': 'https://updates.quantara.app/releases/$version/QuantaraSetup.exe',
      'sha256': checksum('b'),
      'signingIdentity': 'Quantara',
      'architecture': 'x64',
    },
  },
};

void main() {
  test('parses a valid multi-platform manifest', () {
    final manifest = AppUpdateManifest.fromJson(manifestJson());

    expect(manifest.channel, AppReleaseChannel.canary);
    expect(manifest.artifactFor(AppReleasePlatform.android)?.buildNumber, 17);
    expect(
      manifest.artifactFor(AppReleasePlatform.windows)?.downloadUri.scheme,
      'https',
    );
  });

  test('rejects non-HTTPS artifacts and malformed checksums', () {
    final json = manifestJson();
    final artifacts = json['artifacts']! as Map<String, Object?>;
    final android = artifacts['android']! as Map<String, Object?>;
    android['url'] = 'http://updates.quantara.app/quantara.apk';
    android['sha256'] = 'bad';

    expect(() => AppUpdateManifest.fromJson(json), throwsFormatException);
  });

  test('rejects a 64-character checksum that is not hexadecimal', () {
    final json = manifestJson();
    final artifacts = json['artifacts']! as Map<String, Object?>;
    final android = artifacts['android']! as Map<String, Object?>;
    android['sha256'] = checksum('z');

    expect(() => AppUpdateManifest.fromJson(json), throwsFormatException);
  });

  test('rejects missing required manifest fields instead of defaulting', () {
    final json = manifestJson();
    json.remove('mandatory');

    expect(() => AppUpdateManifest.fromJson(json), throwsFormatException);
  });

  test(
    'rejects malformed revoked builds instead of silently dropping them',
    () {
      final json = manifestJson();
      json['revokedBuilds'] = <Object?>[16, '17'];

      expect(() => AppUpdateManifest.fromJson(json), throwsFormatException);
    },
  );

  test('rejects credential-bearing HTTPS artifact URLs', () {
    final json = manifestJson();
    final artifacts = json['artifacts']! as Map<String, Object?>;
    final android = artifacts['android']! as Map<String, Object?>;
    android['url'] = 'https://token@updates.quantara.app/quantara.apk';

    expect(() => AppUpdateManifest.fromJson(json), throwsFormatException);
  });

  test('client rejects a channel mismatch', () async {
    final client = MockClient(
      (_) async => manifestResponse(manifestJson(channel: 'stable')),
    );
    final manifestClient = AppUpdateManifestClient(
      client: client,
      stableManifestUri: Uri.parse('https://updates.quantara.app/stable.json'),
      canaryManifestUri: Uri.parse('https://updates.quantara.app/canary.json'),
    );

    expect(
      () => manifestClient.fetch(AppReleaseChannel.canary),
      throwsFormatException,
    );
  });

  test('controller reports an available Android update', () async {
    final client = MockClient((_) async => manifestResponse(manifestJson()));
    final controller = AppUpdateController(
      manifestClient: AppUpdateManifestClient(
        client: client,
        stableManifestUri: Uri.parse(
          'https://updates.quantara.app/stable.json',
        ),
        canaryManifestUri: Uri.parse(
          'https://updates.quantara.app/canary.json',
        ),
      ),
      currentVersion: '0.13.0',
      currentBuildNumber: 16,
      platform: AppReleasePlatform.android,
      initialChannel: AppReleaseChannel.canary,
      languageCode: 'fa',
    );

    expect(await controller.check(), isTrue);
    expect(controller.result?.updateAvailable, isTrue);
    expect(controller.result?.mandatory, isFalse);
    expect(controller.result?.releaseNotes, 'مدیریت ریسک داینامیک');
  });

  test('revoked current build becomes a mandatory recovery update', () async {
    final client = MockClient(
      (_) async => manifestResponse(
        manifestJson(
          version: '0.13.0',
          buildNumber: 16,
          revokedBuilds: const [16],
        ),
      ),
    );
    final controller = AppUpdateController(
      manifestClient: AppUpdateManifestClient(
        client: client,
        stableManifestUri: Uri.parse(
          'https://updates.quantara.app/stable.json',
        ),
        canaryManifestUri: Uri.parse(
          'https://updates.quantara.app/canary.json',
        ),
      ),
      currentVersion: '0.13.0',
      currentBuildNumber: 16,
      platform: AppReleasePlatform.android,
      initialChannel: AppReleaseChannel.canary,
      languageCode: 'en',
    );

    expect(await controller.check(), isTrue);
    expect(controller.result?.revoked, isTrue);
    expect(controller.result?.mandatory, isTrue);
    expect(controller.result?.updateAvailable, isTrue);
  });
}
