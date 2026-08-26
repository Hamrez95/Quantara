import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:quantara_app/features/app_update/data/app_update_download_verifier.dart';
import 'package:quantara_app/features/app_update/domain/app_update_models.dart';

void main() {
  AppReleaseArtifact artifactFor(List<int> bytes) => AppReleaseArtifact(
    platform: AppReleasePlatform.android,
    version: '1.2.1',
    buildNumber: 127,
    downloadUri: Uri.parse('https://releases.example.com/quantara.apk'),
    sha256: sha256.convert(bytes).toString(),
    packageId: 'com.quantara.quantara_app',
    signingIdentity: 'AA:BB',
  );

  test('returns verified bytes only when SHA-256 matches the manifest', () async {
    final payload = utf8.encode('signed-release-artifact');
    final verifier = AppUpdateDownloadVerifier(
      client: MockClient((request) async {
        expect(request.url.scheme, 'https');
        return http.Response.bytes(payload, 200);
      }),
    );
    addTearDown(verifier.close);

    final verified = await verifier.downloadAndVerify(artifactFor(payload));

    expect(verified.bytes, payload);
    expect(verified.artifact.buildNumber, 127);
  });

  test('blocks a tampered artifact before installer handoff', () async {
    final expected = utf8.encode('expected-release-artifact');
    final tampered = utf8.encode('tampered-release-artifact');
    final verifier = AppUpdateDownloadVerifier(
      client: MockClient((request) async => http.Response.bytes(tampered, 200)),
    );
    addTearDown(verifier.close);

    await expectLater(
      verifier.downloadAndVerify(artifactFor(expected)),
      throwsA(
        isA<AppUpdateDownloadException>().having(
          (error) => error.message,
          'message',
          contains('checksum verification failed'),
        ),
      ),
    );
  });

  test('fails closed for non-success HTTP responses', () async {
    final payload = utf8.encode('artifact');
    final verifier = AppUpdateDownloadVerifier(
      client: MockClient((request) async => http.Response('unavailable', 503)),
    );
    addTearDown(verifier.close);

    await expectLater(
      verifier.downloadAndVerify(artifactFor(payload)),
      throwsA(
        isA<AppUpdateDownloadException>().having(
          (error) => error.message,
          'message',
          contains('HTTP 503'),
        ),
      ),
    );
  });

  test('blocks artifacts larger than the configured safety bound', () async {
    final payload = utf8.encode('artifact-too-large');
    final verifier = AppUpdateDownloadVerifier(
      maxBytes: 4,
      client: MockClient((request) async => http.Response.bytes(payload, 200)),
    );
    addTearDown(verifier.close);

    await expectLater(
      verifier.downloadAndVerify(artifactFor(payload)),
      throwsA(
        isA<AppUpdateDownloadException>().having(
          (error) => error.message,
          'message',
          contains('allowed download size'),
        ),
      ),
    );
  });
}
