import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quantara_app/features/app_update/application/app_update_install_coordinator.dart';
import 'package:quantara_app/features/app_update/application/windows_app_update_installer_gateway.dart';
import 'package:quantara_app/features/app_update/data/app_update_download_verifier.dart';
import 'package:quantara_app/features/app_update/domain/app_update_models.dart';

void main() {
  late Directory tempDirectory;

  setUp(() async {
    tempDirectory = await Directory.systemTemp.createTemp(
      'quantara-update-gateway-test-',
    );
  });

  tearDown(() async {
    if (await tempDirectory.exists()) {
      await tempDirectory.delete(recursive: true);
    }
  });

  test('re-verifies persisted bytes and Authenticode before Explorer handoff', () async {
    final download = _download();
    var signatureChecks = 0;
    var launches = 0;
    String? checkedPath;
    String? launchedPath;

    final gateway = WindowsAppUpdateInstallerGateway(
      isWindows: true,
      temporaryDirectoryProvider: () async => tempDirectory,
      processRunner: (executable, arguments, {environment}) async {
        signatureChecks += 1;
        expect(executable, 'powershell.exe');
        expect(arguments, contains('Get-AuthenticodeSignature'));
        checkedPath = environment?['QUANTARA_UPDATE_PATH'];
        return ProcessResult(1, 0, 'AA:BB:CC\n', '');
      },
      processStarter: (executable, arguments, {mode = ProcessStartMode.normal}) async {
        launches += 1;
        expect(executable, 'explorer.exe');
        expect(mode, ProcessStartMode.detached);
        launchedPath = arguments.single;
      },
    );

    await gateway.handoff(download);

    expect(signatureChecks, 1);
    expect(launches, 1);
    expect(checkedPath, isNotNull);
    expect(launchedPath, checkedPath);
    expect(await File(checkedPath!).readAsBytes(), download.bytes);
  });

  test('blocks handoff and deletes installer when Authenticode does not match', () async {
    final download = _download();
    var launches = 0;
    String? checkedPath;
    final gateway = WindowsAppUpdateInstallerGateway(
      isWindows: true,
      temporaryDirectoryProvider: () async => tempDirectory,
      processRunner: (executable, arguments, {environment}) async {
        checkedPath = environment?['QUANTARA_UPDATE_PATH'];
        return ProcessResult(1, 0, 'DD-EE-FF', '');
      },
      processStarter: (executable, arguments, {mode = ProcessStartMode.normal}) async {
        launches += 1;
      },
    );

    await expectLater(
      gateway.handoff(download),
      throwsA(
        isA<AppUpdateInstallException>().having(
          (error) => error.message,
          'message',
          contains('Authenticode verification failed'),
        ),
      ),
    );

    expect(launches, 0);
    expect(checkedPath, isNotNull);
    expect(await File(checkedPath!).exists(), isFalse);
  });

  test('rejects unapproved artifact types before signature check', () async {
    var signatureChecks = 0;
    final gateway = WindowsAppUpdateInstallerGateway(
      isWindows: true,
      temporaryDirectoryProvider: () async => tempDirectory,
      processRunner: (executable, arguments, {environment}) async {
        signatureChecks += 1;
        return ProcessResult(1, 0, 'AA:BB:CC', '');
      },
      processStarter: (executable, arguments, {mode = ProcessStartMode.normal}) async {},
    );

    await expectLater(
      gateway.handoff(_download(path: '/quantara.zip')),
      throwsA(isA<AppUpdateInstallException>()),
    );

    expect(signatureChecks, 0);
  });

  test('rejects Windows gateway use on other runtime platforms', () async {
    var signatureChecks = 0;
    final gateway = WindowsAppUpdateInstallerGateway(
      isWindows: false,
      temporaryDirectoryProvider: () async => tempDirectory,
      processRunner: (executable, arguments, {environment}) async {
        signatureChecks += 1;
        return ProcessResult(1, 0, 'AA:BB:CC', '');
      },
      processStarter: (executable, arguments, {mode = ProcessStartMode.normal}) async {},
    );

    await expectLater(
      gateway.handoff(_download()),
      throwsA(isA<AppUpdateInstallException>()),
    );

    expect(signatureChecks, 0);
  });
}

VerifiedAppUpdateDownload _download({String path = '/quantara-setup.exe'}) {
  final bytes = Uint8List.fromList([1, 7, 9, 2, 6]);
  return VerifiedAppUpdateDownload(
    artifact: AppReleaseArtifact(
      platform: AppReleasePlatform.windows,
      version: '1.2.1',
      buildNumber: 127,
      downloadUri: Uri.parse('https://updates.example.test$path'),
      sha256: sha256.convert(bytes).toString(),
      signingIdentity: 'AA-BB-CC',
      architecture: 'x64',
    ),
    bytes: bytes,
  );
}
