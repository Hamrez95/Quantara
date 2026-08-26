import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;

import '../domain/app_update_models.dart';

final class AppUpdateDownloadException implements Exception {
  const AppUpdateDownloadException(this.message);

  final String message;

  @override
  String toString() => message;
}

final class AppUpdateArtifactIdentityPolicy {
  const AppUpdateArtifactIdentityPolicy({
    required this.androidPackageId,
    required this.androidSigningIdentity,
    this.windowsSigningIdentity,
  });

  final String androidPackageId;
  final String androidSigningIdentity;
  final String? windowsSigningIdentity;

  void validate(AppReleaseArtifact artifact) {
    switch (artifact.platform) {
      case AppReleasePlatform.android:
        final expectedPackageId = androidPackageId.trim();
        final expectedSigningIdentity = _normalizeSigningIdentity(
          androidSigningIdentity,
        );
        final artifactPackageId = artifact.packageId?.trim();
        final artifactSigningIdentity = _normalizeSigningIdentity(
          artifact.signingIdentity,
        );
        if (expectedPackageId.isEmpty ||
            expectedSigningIdentity == null ||
            artifactPackageId != expectedPackageId ||
            artifactSigningIdentity != expectedSigningIdentity) {
          throw const AppUpdateDownloadException(
            'Android update package or signing identity mismatch. Download is blocked.',
          );
        }
      case AppReleasePlatform.windows:
        final expected = _normalizeSigningIdentity(windowsSigningIdentity);
        if (expected == null) return;
        final actual = _normalizeSigningIdentity(artifact.signingIdentity);
        if (actual != expected) {
          throw const AppUpdateDownloadException(
            'Windows update signing identity mismatch. Download is blocked.',
          );
        }
      case AppReleasePlatform.pwa:
        return;
    }
  }

  static String? _normalizeSigningIdentity(String? value) {
    if (value == null) return null;
    final normalized = value
        .trim()
        .replaceAll(RegExp(r'[\s:-]'), '')
        .toUpperCase();
    return normalized.isEmpty ? null : normalized;
  }
}

final class VerifiedAppUpdateDownload {
  const VerifiedAppUpdateDownload({
    required this.artifact,
    required this.bytes,
  });

  final AppReleaseArtifact artifact;
  final Uint8List bytes;
}

/// Downloads an immutable release artifact and verifies its manifest SHA-256
/// before any installer handoff can occur.
///
/// When an [identityPolicy] is supplied, package/signing metadata is checked
/// before any network request. This component deliberately does not install,
/// launch, or execute the artifact. Platform-specific install flows must
/// consume only a [VerifiedAppUpdateDownload].
final class AppUpdateDownloadVerifier {
  AppUpdateDownloadVerifier({
    http.Client? client,
    this.maxBytes = 256 * 1024 * 1024,
    AppUpdateArtifactIdentityPolicy? identityPolicy,
  }) : _client = client ?? http.Client(),
       _identityPolicy = identityPolicy;

  final http.Client _client;
  final int maxBytes;
  final AppUpdateArtifactIdentityPolicy? _identityPolicy;

  Future<VerifiedAppUpdateDownload> downloadAndVerify(
    AppReleaseArtifact artifact,
  ) async {
    if (maxBytes < 1) {
      throw const AppUpdateDownloadException(
        'Update download size policy is invalid.',
      );
    }
    _identityPolicy?.validate(artifact);

    final uri = artifact.downloadUri;
    if (uri.scheme != 'https' || uri.host.isEmpty || uri.userInfo.isNotEmpty) {
      throw const AppUpdateDownloadException(
        'Update artifact URL is not an approved HTTPS URL.',
      );
    }

    late http.StreamedResponse response;
    try {
      final request = http.Request('GET', uri)
        ..headers['Accept'] = 'application/octet-stream';
      response = await _client.send(request);
    } on Object catch (error) {
      throw AppUpdateDownloadException(
        'Update download failed safely (${error.runtimeType}).',
      );
    }

    if (response.statusCode != 200) {
      throw AppUpdateDownloadException(
        'Update download failed with HTTP ${response.statusCode}.',
      );
    }
    final contentLength = response.contentLength;
    if (contentLength != null && contentLength > maxBytes) {
      throw const AppUpdateDownloadException(
        'Update artifact exceeds the allowed download size.',
      );
    }

    final builder = BytesBuilder(copy: false);
    var receivedBytes = 0;
    try {
      await for (final chunk in response.stream) {
        receivedBytes += chunk.length;
        if (receivedBytes > maxBytes) {
          throw const AppUpdateDownloadException(
            'Update artifact exceeds the allowed download size.',
          );
        }
        builder.add(chunk);
      }
    } on AppUpdateDownloadException {
      rethrow;
    } on Object catch (error) {
      throw AppUpdateDownloadException(
        'Update download failed safely (${error.runtimeType}).',
      );
    }

    final bytes = builder.takeBytes();
    if (bytes.isEmpty) {
      throw const AppUpdateDownloadException('Update artifact is empty.');
    }

    final actualSha256 = sha256.convert(bytes).toString().toLowerCase();
    final expectedSha256 = artifact.sha256.trim().toLowerCase();
    if (actualSha256 != expectedSha256) {
      throw const AppUpdateDownloadException(
        'Update checksum verification failed. Installation is blocked.',
      );
    }

    return VerifiedAppUpdateDownload(artifact: artifact, bytes: bytes);
  }

  void close() => _client.close();
}
