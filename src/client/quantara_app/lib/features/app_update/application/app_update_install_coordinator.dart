// Keep stable public named constructor parameters while storing dependencies privately.
// ignore_for_file: prefer_initializing_formals

import '../../windows_desktop/data/platform_windows_service_status_command.dart';
import '../data/app_update_download_verifier.dart';
import '../domain/app_update_models.dart';
import 'windows_service_update_preflight.dart';

final class AppUpdateInstallException implements Exception {
  const AppUpdateInstallException(this.message);

  final String message;

  @override
  String toString() => message;
}

abstract interface class AppUpdateInstallerGateway {
  Future<void> handoff(VerifiedAppUpdateDownload download);
}

/// Coordinates the only allowed path from a published update artifact to a
/// native installer handoff.
///
/// The caller must provide an explicit user confirmation for each attempt.
/// PWA artifacts never enter the native installer path. Windows additionally
/// requires an authenticated, explicitly disarmed service before any artifact
/// download begins. The gateway receives bytes only after package/signing
/// preflight and SHA-256 verification have succeeded in
/// [AppUpdateDownloadVerifier].
final class AppUpdateInstallCoordinator {
  AppUpdateInstallCoordinator({
    required AppUpdateDownloadVerifier verifier,
    required AppUpdateInstallerGateway installerGateway,
    WindowsServiceUpdatePreflight? windowsServicePreflight,
  }) : _verifier = verifier,
       _installerGateway = installerGateway,
       _windowsServicePreflight = windowsServicePreflight;

  final AppUpdateDownloadVerifier _verifier;
  final AppUpdateInstallerGateway _installerGateway;
  final WindowsServiceUpdatePreflight? _windowsServicePreflight;

  Future<void> downloadVerifyAndHandoff({
    required AppReleaseArtifact artifact,
    required bool userConfirmedInstall,
  }) async {
    if (!userConfirmedInstall) {
      throw const AppUpdateInstallException(
        'Installer handoff requires explicit user confirmation.',
      );
    }
    if (artifact.platform == AppReleasePlatform.pwa) {
      throw const AppUpdateInstallException(
        'PWA updates must use the service-worker update flow.',
      );
    }
    if (artifact.platform == AppReleasePlatform.windows) {
      final preflight =
          _windowsServicePreflight ??
          WindowsServiceUpdatePreflight(
            reader: createPlatformWindowsServiceStatusReader(),
          );
      try {
        await preflight.assertSafeForInstallerHandoff();
      } on WindowsServiceUpdatePreflightException catch (error) {
        throw AppUpdateInstallException(error.message);
      }
    }

    final verified = await _verifier.downloadAndVerify(artifact);
    if (verified.artifact.platform != artifact.platform ||
        verified.artifact.version != artifact.version ||
        verified.artifact.buildNumber != artifact.buildNumber ||
        verified.artifact.sha256.trim().toLowerCase() !=
            artifact.sha256.trim().toLowerCase()) {
      throw const AppUpdateInstallException(
        'Verified update identity changed before installer handoff.',
      );
    }

    await _installerGateway.handoff(verified);
  }
}
