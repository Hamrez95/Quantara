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
/// This component deliberately does not install, launch, or execute the
/// artifact. Platform-specific install flows must consume only a
/// [VerifiedAppUpdateDownload].
final class AppUpdateDownloadVerifier {
  AppUpdateDownloadVerifier({
    http.Client? client,
    this.maxBytes = 256 * 1024 * 1024,
  }) : _client = client ?? http.Client();

  final http.Client _client;
  final int maxBytes;

  Future<VerifiedAppUpdateDownload> downloadAndVerify(
    AppReleaseArtifact artifact,
  ) async {
    if (maxBytes < 1) {
      throw const AppUpdateDownloadException(
        'Update download size policy is invalid.',
      );
    }
    final uri = artifact.downloadUri;
    if (uri.scheme != 'https' || uri.host.isEmpty || uri.userInfo.isNotEmpty) {
      throw const AppUpdateDownloadException(
        'Update artifact URL is not an approved HTTPS URL.',
      );
    }

    late http.Response response;
    try {
      response = await _client.get(
        uri,
        headers: const {'Accept': 'application/octet-stream'},
      );
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

    final bytes = response.bodyBytes;
    if (bytes.isEmpty) {
      throw const AppUpdateDownloadException('Update artifact is empty.');
    }
    if (bytes.length > maxBytes) {
      throw const AppUpdateDownloadException(
        'Update artifact exceeds the allowed download size.',
      );
    }

    final actualSha256 = sha256.convert(bytes).toString().toLowerCase();
    final expectedSha256 = artifact.sha256.trim().toLowerCase();
    if (actualSha256 != expectedSha256) {
      throw const AppUpdateDownloadException(
        'Update checksum verification failed. Installation is blocked.',
      );
    }

    return VerifiedAppUpdateDownload(
      artifact: artifact,
      bytes: Uint8List.fromList(bytes),
    );
  }

  void close() => _client.close();
}
