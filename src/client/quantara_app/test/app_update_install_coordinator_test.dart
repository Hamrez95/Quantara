import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:quantara_app/features/app_update/application/app_update_install_coordinator.dart';
import 'package:quantara_app/features/app_update/data/app_update_download_verifier.dart';
import 'package:quantara_app/features/app_update/domain/app_update_models.dart';

void main() {
  AppReleaseArtifact artifact(AppReleasePlatform platform) {
    return AppReleaseArtifact(
      platform: platform,
      version: '1.2.0',
      buildNumber: 120,
      downloadUri: Uri.parse('https://releases.example.com/quantara.bin'),
      sha256: List.filled(64, 'a').join(),
      packageId: platform == AppReleasePlatform.android
          ? 'com.quantara.quantara_app'
          : null,
      signingIdentity: platform == AppReleasePlatform.pwa ? null : 'AA:BB',
      architecture: platform == AppReleasePlatform.windows ? 'x64' : null,
    );
  }

  test('requires confirmation before native handoff', () async {
    var downloads = 0;
    var handoffs = 0;
    final coordinator = AppUpdateInstallCoordinator(
      downloadAndVerify: (value) async {
        downloads++;
        return VerifiedAppUpdateDownload(
          artifact: value,
          bytes: Uint8List.fromList([1]),
        );
      },
      installerHandoff: (_) async => handoffs++,
    );

    await expectLater(
      coordinator.downloadVerifyAndRequestInstall(
        artifact: artifact(AppReleasePlatform.android),
        userConfirmedInstall: false,
      ),
      throwsA(isA<AppUpdateInstallException>()),
    );
    expect(downloads, 0);
    expect(handoffs, 0);
  });

  test('hands verified native artifact to installer', () async {
    final requested = artifact(AppReleasePlatform.android);
    VerifiedAppUpdateDownload? handedOff;
    final coordinator = AppUpdateInstallCoordinator(
      downloadAndVerify: (value) async {
        return VerifiedAppUpdateDownload(
          artifact: value,
          bytes: Uint8List.fromList([1, 2, 3]),
        );
      },
      installerHandoff: (download) async {
        handedOff = download;
      },
    );

    final result = await coordinator.downloadVerifyAndRequestInstall(
      artifact: requested,
      userConfirmedInstall: true,
    );

    expect(result, same(handedOff));
    expect(result.artifact, same(requested));
  });

  test('rejects changed verified artifact identity', () async {
    var handoffs = 0;
    final requested = artifact(AppReleasePlatform.android);
    final coordinator = AppUpdateInstallCoordinator(
      downloadAndVerify: (_) async {
        return VerifiedAppUpdateDownload(
          artifact: AppReleaseArtifact(
            platform: AppReleasePlatform.android,
            version: '1.2.1',
            buildNumber: 121,
            downloadUri: requested.downloadUri,
            sha256: requested.sha256,
            packageId: requested.packageId,
            signingIdentity: requested.signingIdentity,
          ),
          bytes: Uint8List.fromList([1]),
        );
      },
      installerHandoff: (_) async => handoffs++,
    );

    await expectLater(
      coordinator.downloadVerifyAndRequestInstall(
        artifact: requested,
        userConfirmedInstall: true,
      ),
      throwsA(isA<AppUpdateInstallException>()),
    );
    expect(handoffs, 0);
  });

  test('keeps PWA on service-worker update flow', () async {
    var downloads = 0;
    var handoffs = 0;
    final coordinator = AppUpdateInstallCoordinator(
      downloadAndVerify: (value) async {
        downloads++;
        return VerifiedAppUpdateDownload(
          artifact: value,
          bytes: Uint8List.fromList([1]),
        );
      },
      installerHandoff: (_) async => handoffs++,
    );

    await expectLater(
      coordinator.downloadVerifyAndRequestInstall(
        artifact: artifact(AppReleasePlatform.pwa),
        userConfirmedInstall: true,
      ),
      throwsA(isA<AppUpdateInstallException>()),
    );
    expect(downloads, 0);
    expect(handoffs, 0);
  });
}
