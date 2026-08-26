import '../data/app_update_download_verifier.dart';
import '../domain/app_update_models.dart';

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
/// PWA artifacts never enter the native installer path. The gateway receives
/// bytes only after package/signing preflight and SHA-256 verification have
/// succeeded in [AppUpdateDownloadVerifier].
final class AppUpdateInstallCoordinator {
  AppUpdateInstallCoordinator({
    required AppUpdateDownloadVerifier verifier,
    required AppUpdateInstallerGateway installerGateway,
  }) : _verifier = verifier,
       _installerGateway = installerGateway;

  final AppUpdateDownloadVerifier _verifier;
  final AppUpdateInstallerGateway _installerGateway;

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
