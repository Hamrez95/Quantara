import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:quantara_app/features/app_update/data/app_update_download_verifier.dart';
import 'package:quantara_app/features/app_update/domain/app_update_models.dart';

void main() {
  test(
    'native download fails closed when identity policy is unavailable',
    () async {
      final payload = utf8.encode('native-artifact');
      var requested = false;
      final verifier = AppUpdateDownloadVerifier(
        client: MockClient((request) async {
          requested = true;
          return http.Response.bytes(payload, 200);
        }),
      );
      addTearDown(verifier.close);
      final artifact = AppReleaseArtifact(
        platform: AppReleasePlatform.android,
        version: '1.2.1',
        buildNumber: 127,
        downloadUri: Uri.parse('https://releases.example.com/quantara.apk'),
        sha256: sha256.convert(payload).toString(),
        packageId: 'com.quantara.quantara_app',
        signingIdentity: 'AA:BB',
      );

      await expectLater(
        verifier.downloadAndVerify(artifact),
        throwsA(
          isA<AppUpdateDownloadException>().having(
            (error) => error.message,
            'message',
            contains('identity policy is unavailable'),
          ),
        ),
      );
      expect(requested, isFalse);
    },
  );

  test('Windows signing policy is required before native download', () async {
    final payload = utf8.encode('windows-artifact');
    var requested = false;
    final verifier = AppUpdateDownloadVerifier(
      identityPolicy: const AppUpdateArtifactIdentityPolicy(
        androidPackageId: 'com.quantara.quantara_app',
        androidSigningIdentity: 'AA:BB',
      ),
      client: MockClient((request) async {
        requested = true;
        return http.Response.bytes(payload, 200);
      }),
    );
    addTearDown(verifier.close);
    final artifact = AppReleaseArtifact(
      platform: AppReleasePlatform.windows,
      version: '1.2.1',
      buildNumber: 127,
      downloadUri: Uri.parse('https://releases.example.com/QuantaraSetup.exe'),
      sha256: sha256.convert(payload).toString(),
      signingIdentity: 'Quantara Publisher',
      architecture: 'x64',
    );

    await expectLater(
      verifier.downloadAndVerify(artifact),
      throwsA(
        isA<AppUpdateDownloadException>().having(
          (error) => error.message,
          'message',
          contains('Windows update signing identity policy is unavailable'),
        ),
      ),
    );
    expect(requested, isFalse);
  });
}
