import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:quantara_app/features/app_update/application/app_update_install_coordinator.dart';
import 'package:quantara_app/features/app_update/application/windows_service_update_preflight.dart';
import 'package:quantara_app/features/app_update/data/app_update_download_verifier.dart';
import 'package:quantara_app/features/app_update/domain/app_update_models.dart';
import 'package:quantara_app/features/windows_desktop/application/windows_service_status_reader.dart';

void main() {
  const packageId = 'com.quantara.quantara_app';
  const signingIdentity = 'AA:BB:CC:DD:EE:FF:00:11:22:33:44:55:66:77:88:99';
  const windowsSigningIdentity = '11:22:33:44:55:66:77:88';

  AppReleaseArtifact androidArtifact(List<int> bytes) => AppReleaseArtifact(
    platform: AppReleasePlatform.android,
    version: '1.3.0',
    buildNumber: 130,
    downloadUri: Uri.parse('https://downloads.example/quantara.apk'),
    sha256: sha256.convert(bytes).toString(),
    packageId: packageId,
    signingIdentity: signingIdentity,
  );

  AppReleaseArtifact windowsArtifact(List<int> bytes) => AppReleaseArtifact(
    platform: AppReleasePlatform.windows,
    version: '1.3.0',
    buildNumber: 130,
    downloadUri: Uri.parse('https://downloads.example/QuantaraSetup.exe'),
    sha256: sha256.convert(bytes).toString(),
    signingIdentity: windowsSigningIdentity,
    architecture: 'x64',
  );

  AppUpdateArtifactIdentityPolicy identityPolicy() =>
      const AppUpdateArtifactIdentityPolicy(
        androidPackageId: packageId,
        androidSigningIdentity: signingIdentity,
        windowsSigningIdentity: windowsSigningIdentity,
      );

  WindowsServiceUpdatePreflight windowsPreflight({
    int exitCode = 0,
    String state = 'disarmed',
  }) {
    return WindowsServiceUpdatePreflight(
      reader: WindowsServiceStatusReader(
        command: () async => WindowsServiceStatusCommandResult(
          exitCode: exitCode,
          stdout: exitCode == 0
              ? '{"protocolVersion":1,"requestId":"update.1","kind":"statusSnapshot","payload":{"serviceState":"$state","entryAuthority":false}}'
              : '',
          stderr: '',
        ),
      ),
    );
  }

  test('does not download or hand off without explicit confirmation', () async {
    var requests = 0;
    final client = MockClient((request) async {
      requests += 1;
      return http.Response.bytes([1, 2, 3], 200);
    });
    final gateway = _RecordingInstallerGateway();
    final verifier = AppUpdateDownloadVerifier(
      client: client,
      identityPolicy: identityPolicy(),
    );
    final coordinator = AppUpdateInstallCoordinator(
      verifier: verifier,
      installerGateway: gateway,
    );
    addTearDown(client.close);

    await expectLater(
      coordinator.downloadVerifyAndHandoff(
        artifact: androidArtifact([1, 2, 3]),
        userConfirmedInstall: false,
      ),
      throwsA(isA<AppUpdateInstallException>()),
    );

    expect(requests, 0);
    expect(gateway.handoffs, isEmpty);
  });

  test('PWA artifacts never enter the native installer path', () async {
    var requests = 0;
    final client = MockClient((request) async {
      requests += 1;
      return http.Response.bytes([1, 2, 3], 200);
    });
    final gateway = _RecordingInstallerGateway();
    final verifier = AppUpdateDownloadVerifier(client: client);
    final coordinator = AppUpdateInstallCoordinator(
      verifier: verifier,
      installerGateway: gateway,
    );
    addTearDown(client.close);

    final artifact = AppReleaseArtifact(
      platform: AppReleasePlatform.pwa,
      version: '1.3.0',
      buildNumber: 130,
      downloadUri: Uri.parse('https://downloads.example/quantara-pwa.zip'),
      sha256: sha256.convert([1, 2, 3]).toString(),
    );

    await expectLater(
      coordinator.downloadVerifyAndHandoff(
        artifact: artifact,
        userConfirmedInstall: true,
      ),
      throwsA(isA<AppUpdateInstallException>()),
    );

    expect(requests, 0);
    expect(gateway.handoffs, isEmpty);
  });

  test('hands off only the checksum-verified native payload', () async {
    final bytes = Uint8List.fromList([7, 8, 9, 10]);
    var requests = 0;
    final client = MockClient((request) async {
      requests += 1;
      expect(request.url, Uri.parse('https://downloads.example/quantara.apk'));
      return http.Response.bytes(bytes, 200);
    });
    final gateway = _RecordingInstallerGateway();
    final verifier = AppUpdateDownloadVerifier(
      client: client,
      identityPolicy: identityPolicy(),
    );
    final coordinator = AppUpdateInstallCoordinator(
      verifier: verifier,
      installerGateway: gateway,
    );
    addTearDown(client.close);

    final artifact = androidArtifact(bytes);
    await coordinator.downloadVerifyAndHandoff(
      artifact: artifact,
      userConfirmedInstall: true,
    );

    expect(requests, 1);
    expect(gateway.handoffs, hasLength(1));
    expect(gateway.handoffs.single.artifact, same(artifact));
    expect(gateway.handoffs.single.bytes, orderedEquals(bytes));
  });

  test('checksum failure blocks installer handoff', () async {
    final client = MockClient((request) async {
      return http.Response.bytes([99, 98, 97], 200);
    });
    final gateway = _RecordingInstallerGateway();
    final verifier = AppUpdateDownloadVerifier(
      client: client,
      identityPolicy: identityPolicy(),
    );
    final coordinator = AppUpdateInstallCoordinator(
      verifier: verifier,
      installerGateway: gateway,
    );
    addTearDown(client.close);

    await expectLater(
      coordinator.downloadVerifyAndHandoff(
        artifact: androidArtifact([1, 2, 3]),
        userConfirmedInstall: true,
      ),
      throwsA(isA<AppUpdateDownloadException>()),
    );

    expect(gateway.handoffs, isEmpty);
  });

  test('Windows handoff requires authenticated disarmed service', () async {
    final bytes = Uint8List.fromList([4, 5, 6]);
    var requests = 0;
    final client = MockClient((request) async {
      requests += 1;
      return http.Response.bytes(bytes, 200);
    });
    final gateway = _RecordingInstallerGateway();
    final coordinator = AppUpdateInstallCoordinator(
      verifier: AppUpdateDownloadVerifier(
        client: client,
        identityPolicy: identityPolicy(),
      ),
      installerGateway: gateway,
      windowsServicePreflight: windowsPreflight(),
    );
    addTearDown(client.close);

    await coordinator.downloadVerifyAndHandoff(
      artifact: windowsArtifact(bytes),
      userConfirmedInstall: true,
    );

    expect(requests, 1);
    expect(gateway.handoffs, hasLength(1));
  });

  test('Windows reconciliation state blocks before download', () async {
    var requests = 0;
    final client = MockClient((request) async {
      requests += 1;
      return http.Response.bytes([4, 5, 6], 200);
    });
    final gateway = _RecordingInstallerGateway();
    final coordinator = AppUpdateInstallCoordinator(
      verifier: AppUpdateDownloadVerifier(
        client: client,
        identityPolicy: identityPolicy(),
      ),
      installerGateway: gateway,
      windowsServicePreflight: windowsPreflight(
        state: 'reconciliationRequired',
      ),
    );
    addTearDown(client.close);

    await expectLater(
      coordinator.downloadVerifyAndHandoff(
        artifact: windowsArtifact([4, 5, 6]),
        userConfirmedInstall: true,
      ),
      throwsA(isA<AppUpdateInstallException>()),
    );

    expect(requests, 0);
    expect(gateway.handoffs, isEmpty);
  });

  test('unverified Windows service status blocks before download', () async {
    var requests = 0;
    final client = MockClient((request) async {
      requests += 1;
      return http.Response.bytes([4, 5, 6], 200);
    });
    final gateway = _RecordingInstallerGateway();
    final coordinator = AppUpdateInstallCoordinator(
      verifier: AppUpdateDownloadVerifier(
        client: client,
        identityPolicy: identityPolicy(),
      ),
      installerGateway: gateway,
      windowsServicePreflight: windowsPreflight(exitCode: 5),
    );
    addTearDown(client.close);

    await expectLater(
      coordinator.downloadVerifyAndHandoff(
        artifact: windowsArtifact([4, 5, 6]),
        userConfirmedInstall: true,
      ),
      throwsA(isA<AppUpdateInstallException>()),
    );

    expect(requests, 0);
    expect(gateway.handoffs, isEmpty);
  });
}

final class _RecordingInstallerGateway implements AppUpdateInstallerGateway {
  final List<VerifiedAppUpdateDownload> handoffs = [];

  @override
  Future<void> handoff(VerifiedAppUpdateDownload download) async {
    handoffs.add(download);
  }
}
