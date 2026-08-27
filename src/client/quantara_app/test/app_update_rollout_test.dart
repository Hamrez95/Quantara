import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:quantara_app/features/app_update/application/app_update_controller.dart';
import 'package:quantara_app/features/app_update/data/app_update_manifest_client.dart';
import 'package:quantara_app/features/app_update/data/app_update_rollout_store.dart';
import 'package:quantara_app/features/app_update/domain/app_update_models.dart';

void main() {
  AppUpdateController makeController({
    required int rolloutPercent,
    required AppUpdateRolloutStore rolloutStore,
    bool mandatory = false,
    List<int> revokedBuilds = const <int>[],
  }) {
    final client = MockClient((request) async {
      return http.Response(
        jsonEncode({
          'schemaVersion': 1,
          'channel': 'stable',
          'publishedAt': '2026-08-27T00:00:00Z',
          'minimumSupportedVersion': '1.0.0',
          'mandatory': mandatory,
          'releaseNotes': {'en': 'Staged release'},
          'rolloutPercent': rolloutPercent,
          'revokedBuilds': revokedBuilds,
          'artifacts': {
            'android': {
              'version': '1.2.1',
              'buildNumber': 127,
              'url': 'https://releases.example.test/Quantara.apk',
              'sha256':
                  'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
              'packageId': 'com.quantara.quantara_app',
              'signingIdentity': 'AA11',
            },
          },
        }),
        200,
      );
    });

    return AppUpdateController(
      manifestClient: AppUpdateManifestClient(
        client: client,
        stableManifestUri: Uri.parse(
          'https://updates.example.test/stable.json',
        ),
        canaryManifestUri: Uri.parse(
          'https://updates.example.test/canary.json',
        ),
      ),
      currentVersion: '1.2.0',
      currentBuildNumber: 126,
      platform: AppReleasePlatform.android,
      initialChannel: AppReleaseChannel.stable,
      languageCode: 'en',
      rolloutStore: rolloutStore,
    );
  }

  test('optional update is available inside staged rollout cohort', () async {
    final controller = makeController(
      rolloutPercent: 25,
      rolloutStore: const _FixedRolloutStore(24),
    );
    addTearDown(controller.dispose);

    expect(await controller.check(), isTrue);
    expect(controller.result?.updateAvailable, isTrue);
    expect(controller.result?.stagedRolloutDeferred, isFalse);
  });

  test('optional update is deferred outside staged rollout cohort', () async {
    final controller = makeController(
      rolloutPercent: 25,
      rolloutStore: const _FixedRolloutStore(25),
    );
    addTearDown(controller.dispose);

    expect(await controller.check(), isTrue);
    expect(controller.result?.updateAvailable, isFalse);
    expect(controller.result?.stagedRolloutDeferred, isTrue);
    expect(controller.result?.artifact?.version, '1.2.1');
  });

  test('zero-percent rollout still exposes mandatory update', () async {
    final controller = makeController(
      rolloutPercent: 0,
      rolloutStore: const _ThrowingRolloutStore(),
      mandatory: true,
    );
    addTearDown(controller.dispose);

    expect(await controller.check(), isTrue);
    expect(controller.result?.updateAvailable, isTrue);
    expect(controller.result?.mandatory, isTrue);
    expect(controller.result?.stagedRolloutDeferred, isFalse);
  });

  test('zero-percent rollout still exposes revoked build recovery', () async {
    final controller = makeController(
      rolloutPercent: 0,
      rolloutStore: const _ThrowingRolloutStore(),
      revokedBuilds: const [126],
    );
    addTearDown(controller.dispose);

    expect(await controller.check(), isTrue);
    expect(controller.result?.updateAvailable, isTrue);
    expect(controller.result?.revoked, isTrue);
    expect(controller.result?.mandatory, isTrue);
  });

  test('rollout-store failure blocks optional update fail-closed', () async {
    final controller = makeController(
      rolloutPercent: 50,
      rolloutStore: const _ThrowingRolloutStore(),
    );
    addTearDown(controller.dispose);

    expect(await controller.check(), isFalse);
    expect(controller.result, isNull);
    expect(controller.error, contains('StateError'));
  });
}

final class _FixedRolloutStore implements AppUpdateRolloutStore {
  const _FixedRolloutStore(this.bucket);

  final int bucket;

  @override
  Future<int> loadOrCreateBucket() async => bucket;
}

final class _ThrowingRolloutStore implements AppUpdateRolloutStore {
  const _ThrowingRolloutStore();

  @override
  Future<int> loadOrCreateBucket() async => throw StateError('unavailable');
}
