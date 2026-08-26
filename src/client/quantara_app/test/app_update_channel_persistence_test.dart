import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:quantara_app/features/app_update/application/app_update_controller.dart';
import 'package:quantara_app/features/app_update/data/app_update_channel_store.dart';
import 'package:quantara_app/features/app_update/data/app_update_manifest_client.dart';
import 'package:quantara_app/features/app_update/domain/app_update_models.dart';

final class _MemoryChannelStore implements AppUpdateChannelStore {
  _MemoryChannelStore({this.value, this.failLoad = false, this.failSave = false});

  AppReleaseChannel? value;
  final bool failLoad;
  final bool failSave;

  @override
  Future<AppReleaseChannel?> load() async {
    if (failLoad) throw StateError('load failed');
    return value;
  }

  @override
  Future<void> save(AppReleaseChannel channel) async {
    if (failSave) throw StateError('save failed');
    value = channel;
  }
}

AppUpdateManifestClient _manifestClient() => AppUpdateManifestClient(
  client: MockClient(
    (_) async => http.Response(
      jsonEncode({
        'schemaVersion': 1,
        'channel': 'stable',
        'publishedAt': '2026-08-26T00:00:00Z',
        'minimumSupportedVersion': '1.0.0',
        'mandatory': false,
        'releaseNotes': {'en': 'fixture'},
        'rolloutPercent': 100,
        'revokedBuilds': <int>[],
        'artifacts': {
          'android': {
            'version': '1.1.0',
            'buildNumber': 2,
            'url': 'https://updates.quantara.app/quantara.apk',
            'sha256': List.filled(64, 'a').join(),
          },
        },
      }),
      200,
    ),
  ),
  stableManifestUri: Uri.parse('https://updates.quantara.app/stable.json'),
  canaryManifestUri: Uri.parse('https://updates.quantara.app/canary.json'),
);

AppUpdateController _controller(
  AppUpdateChannelStore store, {
  AppReleaseChannel initial = AppReleaseChannel.stable,
}) => AppUpdateController(
  manifestClient: _manifestClient(),
  currentVersion: '1.0.0',
  currentBuildNumber: 1,
  platform: AppReleasePlatform.android,
  initialChannel: initial,
  languageCode: 'en',
  channelStore: store,
);

void main() {
  test('restores a previously selected update channel after restart', () async {
    final store = _MemoryChannelStore(value: AppReleaseChannel.canary);
    final controller = _controller(store);

    await controller.restoreChannel();

    expect(controller.channel, AppReleaseChannel.canary);
    expect(controller.error, isNull);
  });

  test('persists channel changes before the next app restart', () async {
    final store = _MemoryChannelStore();
    final controller = _controller(store);

    await controller.setChannel(AppReleaseChannel.canary);

    expect(controller.channel, AppReleaseChannel.canary);
    expect(store.value, AppReleaseChannel.canary);
    expect(controller.error, isNull);
  });

  test('failed channel persistence rolls back instead of lying to UI', () async {
    final store = _MemoryChannelStore(failSave: true);
    final controller = _controller(store);

    await controller.setChannel(AppReleaseChannel.canary);

    expect(controller.channel, AppReleaseChannel.stable);
    expect(controller.error, contains('could not be saved safely'));
  });

  test('corrupt persistence failure keeps configured default fail-closed', () async {
    final store = _MemoryChannelStore(failLoad: true);
    final controller = _controller(store);

    await controller.restoreChannel();

    expect(controller.channel, AppReleaseChannel.stable);
    expect(controller.error, contains('could not be restored safely'));
  });
}
