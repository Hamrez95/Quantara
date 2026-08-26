import '../data/app_update_download_verifier.dart';
import '../domain/app_update_models.dart';

typedef AppUpdateVerifiedDownloader =
    Future<VerifiedAppUpdateDownload> Function(AppReleaseArtifact artifact);
typedef AppUpdateInstallerHandoff =
    Future<void> Function(VerifiedAppUpdateDownload download);

final class AppUpdateInstallException implements Exception {
  const AppUpdateInstallException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Coordinates the native update boundary without gaining silent-install
/// authority.
///
/// The caller must present an explicit user confirmation for every handoff.
/// Only a checksum- and identity-verified download may reach the platform
/// installer adapter. PWA activation remains a separate service-worker flow.
final class AppUpdateInstallCoordinator {
  const AppUpdateInstallCoordinator({
    required this._downloadAndVerify,
    required this._installerHandoff,
  });

  final AppUpdateVerifiedDownloader _downloadAndVerify;
  final AppUpdateInstallerHandoff _installerHandoff;

  Future<VerifiedAppUpdateDownload> downloadVerifyAndRequestInstall({
    required AppReleaseArtifact artifact,
    required bool userConfirmedInstall,
  }) async {
    if (!userConfirmedInstall) {
      throw const AppUpdateInstallException(
        'Explicit user confirmation is required before installer handoff.',
      );
    }
    if (artifact.platform == AppReleasePlatform.pwa) {
      throw const AppUpdateInstallException(
        'PWA updates must use the service-worker refresh flow.',
      );
    }

    final verified = await _downloadAndVerify(artifact);
    if (!identical(verified.artifact, artifact) &&
        !_sameArtifactIdentity(verified.artifact, artifact)) {
      throw const AppUpdateInstallException(
        'Verified artifact identity changed before installer handoff.',
      );
    }

    await _installerHandoff(verified);
    return verified;
  }

  static bool _sameArtifactIdentity(
    AppReleaseArtifact left,
    AppReleaseArtifact right,
  ) {
    return left.platform == right.platform &&
        left.version == right.version &&
        left.buildNumber == right.buildNumber &&
        left.downloadUri == right.downloadUri &&
        left.sha256.toLowerCase() == right.sha256.toLowerCase() &&
        left.packageId == right.packageId &&
        left.signingIdentity == right.signingIdentity &&
        left.architecture == right.architecture;
  }
}
