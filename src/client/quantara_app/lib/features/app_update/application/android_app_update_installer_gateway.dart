import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

import '../data/app_update_download_verifier.dart';
import '../domain/app_update_models.dart';
import 'app_update_install_coordinator.dart';

typedef AndroidAppUpdateTemporaryDirectoryProvider =
    Future<Directory> Function();
typedef AndroidAppUpdateHandoffInvoker = Future<void> Function(String path);

/// Android package-installer handoff for an already verified Quantara APK.
///
/// This gateway does not install packages itself. It persists the verified APK
/// into Quantara's private cache, re-verifies SHA-256, then asks the Android
/// host to open the normal user-confirmed package installer flow.
final class AndroidAppUpdateInstallerGateway
    implements AppUpdateInstallerGateway {
  AndroidAppUpdateInstallerGateway({
    AndroidAppUpdateTemporaryDirectoryProvider? temporaryDirectoryProvider,
    AndroidAppUpdateHandoffInvoker? handoffInvoker,
    bool? isAndroid,
  }) : _temporaryDirectoryProvider =
           temporaryDirectoryProvider ?? getTemporaryDirectory,
       _handoffInvoker = handoffInvoker ?? _invokePlatformInstaller,
       _isAndroid = isAndroid ?? Platform.isAndroid;

  static const _channel = MethodChannel('quantara/app_updates');

  final AndroidAppUpdateTemporaryDirectoryProvider _temporaryDirectoryProvider;
  final AndroidAppUpdateHandoffInvoker _handoffInvoker;
  final bool _isAndroid;

  @override
  Future<void> handoff(VerifiedAppUpdateDownload download) async {
    final artifact = download.artifact;
    if (!_isAndroid || artifact.platform != AppReleasePlatform.android) {
      throw const AppUpdateInstallException(
        'Android installer handoff is unavailable on this platform.',
      );
    }
    if (!artifact.downloadUri.path.toLowerCase().endsWith('.apk')) {
      throw const AppUpdateInstallException(
        'Android update artifact type is not approved for installer handoff.',
      );
    }
    if (artifact.packageId?.trim().isEmpty ?? true) {
      throw const AppUpdateInstallException(
        'Android package identity is unavailable. Installer handoff is blocked.',
      );
    }
    if (artifact.signingIdentity?.trim().isEmpty ?? true) {
      throw const AppUpdateInstallException(
        'Android signing identity is unavailable. Installer handoff is blocked.',
      );
    }

    final root = await _temporaryDirectoryProvider();
    final updateDirectory = Directory(
      '${root.path}${Platform.pathSeparator}quantara-updates',
    );
    await updateDirectory.create(recursive: true);
    await _deleteStaleApks(updateDirectory);

    final apk = File(
      '${updateDirectory.path}${Platform.pathSeparator}'
      'quantara-${artifact.buildNumber}.apk',
    );
    await apk.writeAsBytes(download.bytes, flush: true);

    final persistedSha256 = sha256.convert(await apk.readAsBytes()).toString();
    if (persistedSha256.toLowerCase() != artifact.sha256.trim().toLowerCase()) {
      await _deleteQuietly(apk);
      throw const AppUpdateInstallException(
        'Persisted Android update checksum verification failed. Installer handoff is blocked.',
      );
    }

    try {
      await _handoffInvoker(apk.path);
    } on PlatformException catch (error) {
      await _deleteQuietly(apk);
      throw AppUpdateInstallException(_safePlatformDiagnostic(error.code));
    } on Object catch (error) {
      await _deleteQuietly(apk);
      throw AppUpdateInstallException(
        'Android installer handoff failed safely (${error.runtimeType}).',
      );
    }
  }

  static Future<void> _invokePlatformInstaller(String path) async {
    await _channel.invokeMethod<void>('installVerifiedApk', {'path': path});
  }

  static String _safePlatformDiagnostic(String code) {
    switch (code) {
      case 'install_permission_required':
        return 'Android installer policy requires permission before package handoff.';
      case 'installer_unavailable':
        return 'Android package installer is unavailable.';
      case 'installer_blocked':
        return 'Android installer policy blocked the package handoff.';
      case 'invalid_apk_path':
        return 'Verified Android update cache integrity check failed. Installer handoff is blocked.';
      default:
        return 'Android package installer handoff failed safely with an unknown platform diagnostic.';
    }
  }

  static Future<void> _deleteStaleApks(Directory directory) async {
    try {
      await for (final entity in directory.list(followLinks: false)) {
        if (entity is File && entity.path.toLowerCase().endsWith('.apk')) {
          await _deleteQuietly(entity);
        }
      }
    } on FileSystemException {
      // Cache cleanup is best effort. Integrity is checked on the new APK below.
    }
  }

  static Future<void> _deleteQuietly(File file) async {
    try {
      if (await file.exists()) await file.delete();
    } on FileSystemException {
      // Cleanup failure must never turn a blocked install into an allowed one.
    }
  }
}
