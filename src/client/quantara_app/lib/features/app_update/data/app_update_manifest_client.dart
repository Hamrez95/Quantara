import 'dart:convert';

import 'package:http/http.dart' as http;

import '../domain/app_update_models.dart';

final class AppUpdateManifestClient {
  AppUpdateManifestClient({
    required http.Client client,
    required Uri stableManifestUri,
    required Uri canaryManifestUri,
    Uri? internalManifestUri,
  }) : _client = client,
       _stableManifestUri = stableManifestUri,
       _canaryManifestUri = canaryManifestUri,
       _internalManifestUri = internalManifestUri;

  final http.Client _client;
  final Uri _stableManifestUri;
  final Uri _canaryManifestUri;
  final Uri? _internalManifestUri;

  Future<AppUpdateManifest> fetch(AppReleaseChannel channel) async {
    final uri = switch (channel) {
      AppReleaseChannel.stable => _stableManifestUri,
      AppReleaseChannel.canary => _canaryManifestUri,
      AppReleaseChannel.internal =>
        _internalManifestUri ??
            (throw StateError('Internal update channel is not configured.')),
    };
    if (uri.scheme != 'https') {
      throw const FormatException('Update manifests must use HTTPS.');
    }

    final response = await _client
        .get(
          uri,
          headers: const {
            'Accept': 'application/json',
            'Cache-Control': 'no-cache',
          },
        )
        .timeout(const Duration(seconds: 12));
    if (response.statusCode != 200) {
      throw AppUpdateManifestException(
        'Update manifest request failed.',
        statusCode: response.statusCode,
      );
    }
    final decoded = jsonDecode(utf8.decode(response.bodyBytes));
    if (decoded is! Map<String, Object?>) {
      throw const FormatException('Update manifest root must be an object.');
    }
    final manifest = AppUpdateManifest.fromJson(decoded);
    if (manifest.channel != channel) {
      throw const FormatException('Update manifest channel mismatch.');
    }
    return manifest;
  }
}

final class AppUpdateManifestException implements Exception {
  const AppUpdateManifestException(this.message, {this.statusCode});

  final String message;
  final int? statusCode;

  @override
  String toString() => message;
}
