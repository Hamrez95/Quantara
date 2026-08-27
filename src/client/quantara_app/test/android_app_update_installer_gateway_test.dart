import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quantara_app/features/app_update/application/android_app_update_installer_gateway.dart';
import 'package:quantara_app/features/app_update/application/app_update_install_coordinator.dart';
import 'package:quantara_app/features/app_update/data/app_update_download_verifier.dart';
import 'package:quantara_app/features/app_update/domain/app_update_models.dart';

void main() {
  late Directory tempDirectory;

  setUp(() async {
    tempDirectory = await Directory.systemTemp.createTemp(
      'quantara-android-update-gateway-test-',
    );
  });

  tearDown(() async {
    if (await tempDirectory.exists()) {
      await tempDirectory.delete(recursive: true);
    }
  });

  test('re-verifies persisted APK before explicit platform handoff', () async {
    final download = _download();
    String? handedOffPath;
    final gateway = AndroidAppUpdateInstallerGateway(
      isAndroid: true,
      temporaryDirectoryProvider: () async => tempDirectory,
      handoffInvoker: (path) async {
        handedOffPath = path;
      },
    );

    await gateway.handoff(download);

    expect(handedOffPath, isNotNull);
    final persisted = File(handedOffPath!);
    expect(await persisted.exists(), isTrue);
    expect(await persisted.readAsBytes(), download.bytes);
  });

  test('rejects non-APK artifacts before platform handoff', () async {
    var handoffs = 0;
    final gateway = AndroidAppUpdateInstallerGateway(
      isAndroid: true,
      temporaryDirectoryProvider: () async => tempDirectory,
      handoffInvoker: (path) async {
        handoffs += 1;
      },
    );

    await expectLater(
      gateway.handoff(_download(path: '/quantara.zip')),
      throwsA(isA<AppUpdateInstallException>()),
    );

    expect(handoffs, 0);
  });

  test('rejects Android gateway use on other runtime platforms', () async {
    var handoffs = 0;
    final gateway = AndroidAppUpdateInstallerGateway(
      isAndroid: false,
      temporaryDirectoryProvider: () async => tempDirectory,
      handoffInvoker: (path) async {
        handoffs += 1;
      },
    );

    await expectLater(
      gateway.handoff(_download()),
      throwsA(isA<AppUpdateInstallException>()),
    );

    expect(handoffs, 0);
  });

  test('blocks and deletes APK when persisted checksum is invalid', () async {
    var handoffs = 0;
    final download = _download(sha256Override: '0' * 64);
    final gateway = AndroidAppUpdateInstallerGateway(
      isAndroid: true,
      temporaryDirectoryProvider: () async => tempDirectory,
      handoffInvoker: (path) async {
        handoffs += 1;
      },
    );

    await expectLater(
      gateway.handoff(download),
      throwsA(
        isA<AppUpdateInstallException>().having(
          (error) => error.message,
          'message',
          contains('checksum verification failed'),
        ),
      ),
    );

    expect(handoffs, 0);
    final updateDirectory = Directory(
      '${tempDirectory.path}${Platform.pathSeparator}quantara-updates',
    );
    final remaining = await updateDirectory.exists()
        ? await updateDirectory.list().toList()
        : <FileSystemEntity>[];
    expect(remaining.whereType<File>(), isEmpty);
  });

  test('deletes APK when native package-installer handoff fails', () async {
    String? persistedPath;
    final gateway = AndroidAppUpdateInstallerGateway(
      isAndroid: true,
      temporaryDirectoryProvider: () async => tempDirectory,
      handoffInvoker: (path) async {
        persistedPath = path;
        throw const FileSystemException('Package installer unavailable');
      },
    );

    await expectLater(
      gateway.handoff(_download()),
      throwsA(
        isA<AppUpdateInstallException>().having(
          (error) => error.message,
          'message',
          contains('handoff failed safely'),
        ),
      ),
    );

    expect(persistedPath, isNotNull);
    expect(await File(persistedPath!).exists(), isFalse);
  });

  test('preserves safe Android installer policy diagnostic', () async {
    String? persistedPath;
    final gateway = AndroidAppUpdateInstallerGateway(
      isAndroid: true,
      temporaryDirectoryProvider: () async => tempDirectory,
      handoffInvoker: (path) async {
        persistedPath = path;
        throw PlatformException(
          code: 'install_permission_required',
          message: 'native detail that must not leak',
          details: 'private native detail',
        );
      },
    );

    await expectLater(
      gateway.handoff(_download()),
      throwsA(
        isA<AppUpdateInstallException>()
            .having(
              (error) => error.message,
              'category',
              contains('installer policy requires permission'),
            )
            .having(
              (error) => error.message,
              'native message',
              isNot(contains('native detail')),
            )
            .having(
              (error) => error.message,
              'native details',
              isNot(contains('private native detail')),
            ),
      ),
    );

    expect(persistedPath, isNotNull);
    expect(await File(persistedPath!).exists(), isFalse);
  });

  test('maps blocked installer handoff to a safe policy category', () async {
    final gateway = AndroidAppUpdateInstallerGateway(
      isAndroid: true,
      temporaryDirectoryProvider: () async => tempDirectory,
      handoffInvoker: (path) async {
        throw PlatformException(code: 'installer_blocked');
      },
    );

    await expectLater(
      gateway.handoff(_download()),
      throwsA(
        isA<AppUpdateInstallException>().having(
          (error) => error.message,
          'category',
          contains('installer policy blocked'),
        ),
      ),
    );
  });

  test('unknown platform diagnostics stay fail-closed and sanitized', () async {
    final gateway = AndroidAppUpdateInstallerGateway(
      isAndroid: true,
      temporaryDirectoryProvider: () async => tempDirectory,
      handoffInvoker: (path) async {
        throw PlatformException(
          code: 'vendor_sensitive_code',
          message: 'secret native message',
          details: {'token': 'do-not-log'},
        );
      },
    );

    await expectLater(
      gateway.handoff(_download()),
      throwsA(
        isA<AppUpdateInstallException>()
            .having(
              (error) => error.message,
              'category',
              contains('unknown platform diagnostic'),
            )
            .having(
              (error) => error.message,
              'code',
              isNot(contains('vendor_sensitive_code')),
            )
            .having(
              (error) => error.message,
              'message',
              isNot(contains('secret native message')),
            )
            .having(
              (error) => error.message,
              'details',
              isNot(contains('do-not-log')),
            ),
      ),
    );
  });

  test('removes stale cached APKs before persisting the next build', () async {
    final updateDirectory = Directory(
      '${tempDirectory.path}${Platform.pathSeparator}quantara-updates',
    );
    await updateDirectory.create(recursive: true);
    final stale = File(
      '${updateDirectory.path}${Platform.pathSeparator}quantara-120.apk',
    );
    await stale.writeAsBytes([9, 9, 9]);

    final gateway = AndroidAppUpdateInstallerGateway(
      isAndroid: true,
      temporaryDirectoryProvider: () async => tempDirectory,
      handoffInvoker: (path) async {},
    );

    await gateway.handoff(_download());

    expect(await stale.exists(), isFalse);
    expect(
      await File(
        '${updateDirectory.path}${Platform.pathSeparator}quantara-127.apk',
      ).exists(),
      isTrue,
    );
  });
}

VerifiedAppUpdateDownload _download({
  String path = '/quantara.apk',
  String? sha256Override,
}) {
  final bytes = Uint8List.fromList([1, 7, 9, 2, 6]);
  return VerifiedAppUpdateDownload(
    artifact: AppReleaseArtifact(
      platform: AppReleasePlatform.android,
      version: '1.2.1',
      buildNumber: 127,
      downloadUri: Uri.parse('https://updates.example.test$path'),
      sha256: sha256Override ?? sha256.convert(bytes).toString(),
      packageId: 'com.quantara.quantara_app',
      signingIdentity: 'AA-BB-CC',
    ),
    bytes: bytes,
  );
}
