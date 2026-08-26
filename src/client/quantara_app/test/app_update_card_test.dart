import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:quantara_app/features/app_update/application/app_update_controller.dart';
import 'package:quantara_app/features/app_update/data/app_update_manifest_client.dart';
import 'package:quantara_app/features/app_update/domain/app_update_models.dart';
import 'package:quantara_app/features/app_update/presentation/app_update_card.dart';

void main() {
  testWidgets('fails closed when update runtime is not configured', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: AppUpdateCard(controller: null, locale: Locale('en')),
        ),
      ),
    );

    expect(
      find.byKey(const ValueKey('app-update-unconfigured')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('app-update-check')), findsNothing);
    expect(find.byKey(const ValueKey('app-update-download')), findsNothing);
  });

  testWidgets('shows release status and requires explicit download action', (
    tester,
  ) async {
    var requests = 0;
    var explicitDownloads = 0;
    final client = MockClient((request) async {
      requests += 1;
      expect(request.url, Uri.parse('https://updates.example/stable.json'));
      return http.Response(
        jsonEncode({
          'schemaVersion': 1,
          'channel': 'stable',
          'publishedAt': '2026-08-26T00:00:00Z',
          'minimumSupportedVersion': '1.0.0',
          'mandatory': false,
          'releaseNotes': {'en': 'Safer update flow.'},
          'rolloutPercent': 100,
          'revokedBuilds': <int>[],
          'artifacts': {
            'android': {
              'version': '1.3.0',
              'buildNumber': 130,
              'url': 'https://downloads.example/quantara.apk',
              'sha256':
                  'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
              'packageId': 'com.quantara.quantara_app',
              'signingIdentity': 'release-cert',
            },
          },
        }),
        200,
        headers: {'content-type': 'application/json'},
      );
    });
    final controller = AppUpdateController(
      manifestClient: AppUpdateManifestClient(
        client: client,
        stableManifestUri: Uri.parse('https://updates.example/stable.json'),
        canaryManifestUri: Uri.parse('https://updates.example/canary.json'),
      ),
      currentVersion: '1.2.0',
      currentBuildNumber: 126,
      platform: AppReleasePlatform.android,
      initialChannel: AppReleaseChannel.stable,
      languageCode: 'en',
    );
    addTearDown(controller.dispose);
    addTearDown(client.close);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AppUpdateCard(
            controller: controller,
            locale: const Locale('en'),
            onDownloadVerifiedArtifact: (_) async {
              explicitDownloads += 1;
            },
          ),
        ),
      ),
    );

    expect(requests, 0);
    expect(explicitDownloads, 0);
    expect(find.byKey(const ValueKey('app-update-download')), findsNothing);

    await tester.tap(find.byKey(const ValueKey('app-update-check')));
    await tester.pumpAndSettle();

    expect(requests, 1);
    expect(find.text('A new version is available.'), findsOneWidget);
    expect(find.text('Safer update flow.'), findsOneWidget);
    expect(find.byKey(const ValueKey('app-update-download')), findsOneWidget);
    expect(explicitDownloads, 0);

    await tester.tap(find.byKey(const ValueKey('app-update-download')));
    await tester.pumpAndSettle();

    expect(explicitDownloads, 1);
  });
}
