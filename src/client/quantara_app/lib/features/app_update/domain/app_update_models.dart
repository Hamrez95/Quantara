enum AppReleaseChannel { stable, canary, internal }

enum AppReleasePlatform { android, windows, pwa }

final class AppReleaseArtifact {
  const AppReleaseArtifact({
    required this.platform,
    required this.version,
    required this.buildNumber,
    required this.downloadUri,
    required this.sha256,
    this.packageId,
    this.signingIdentity,
    this.architecture,
  });

  final AppReleasePlatform platform;
  final String version;
  final int buildNumber;
  final Uri downloadUri;
  final String sha256;
  final String? packageId;
  final String? signingIdentity;
  final String? architecture;

  factory AppReleaseArtifact.fromJson(
    AppReleasePlatform platform,
    Map<String, Object?> json,
  ) {
    final rawVersion = json['version'];
    final rawBuildNumber = json['buildNumber'];
    final rawUrl = json['url'];
    final rawSha256 = json['sha256'];
    if (rawVersion is! String ||
        rawBuildNumber is! int ||
        rawUrl is! String ||
        rawSha256 is! String) {
      throw const FormatException('Release artifact metadata is invalid.');
    }

    final version = rawVersion.trim();
    final downloadUri = Uri.tryParse(rawUrl);
    final sha256 = rawSha256.trim().toLowerCase();
    final validSha256 = RegExp(r'^[a-f0-9]{64}$').hasMatch(sha256);
    if (version.isEmpty ||
        rawBuildNumber < 1 ||
        downloadUri == null ||
        downloadUri.scheme != 'https' ||
        downloadUri.hasUserInfo ||
        downloadUri.host.isEmpty ||
        !validSha256) {
      throw const FormatException('Release artifact metadata is invalid.');
    }

    String? optionalString(String key) {
      final value = json[key];
      if (value == null) return null;
      if (value is! String || value.trim().isEmpty) {
        throw const FormatException('Release artifact metadata is invalid.');
      }
      return value.trim();
    }

    return AppReleaseArtifact(
      platform: platform,
      version: version,
      buildNumber: rawBuildNumber,
      downloadUri: downloadUri,
      sha256: sha256,
      packageId: optionalString('packageId'),
      signingIdentity: optionalString('signingIdentity'),
      architecture: optionalString('architecture'),
    );
  }
}

final class AppUpdateManifest {
  const AppUpdateManifest({
    required this.schemaVersion,
    required this.channel,
    required this.publishedAt,
    required this.minimumSupportedVersion,
    required this.mandatory,
    required this.releaseNotes,
    required this.artifacts,
    required this.rolloutPercent,
    required this.revokedBuilds,
  });

  final int schemaVersion;
  final AppReleaseChannel channel;
  final DateTime publishedAt;
  final String minimumSupportedVersion;
  final bool mandatory;
  final Map<String, String> releaseNotes;
  final Map<AppReleasePlatform, AppReleaseArtifact> artifacts;
  final int rolloutPercent;
  final Set<int> revokedBuilds;

  factory AppUpdateManifest.fromJson(Map<String, Object?> json) {
    final schemaVersion = json['schemaVersion'];
    if (schemaVersion != 1) {
      throw const FormatException('Unsupported update manifest schema.');
    }

    final rawChannel = json['channel'];
    if (rawChannel is! String) {
      throw const FormatException('Unknown release channel.');
    }
    final channel = AppReleaseChannel.values.firstWhere(
      (item) => item.name == rawChannel,
      orElse: () => throw const FormatException('Unknown release channel.'),
    );

    final rawPublishedAt = json['publishedAt'];
    final publishedAt = rawPublishedAt is String
        ? DateTime.tryParse(rawPublishedAt)?.toUtc()
        : null;
    if (publishedAt == null) {
      throw const FormatException('Manifest publication time is invalid.');
    }

    final minimumSupportedVersion = json['minimumSupportedVersion'];
    final mandatory = json['mandatory'];
    final rolloutPercent = json['rolloutPercent'];
    if (minimumSupportedVersion is! String ||
        minimumSupportedVersion.trim().isEmpty ||
        mandatory is! bool ||
        rolloutPercent is! int ||
        rolloutPercent < 0 ||
        rolloutPercent > 100) {
      throw const FormatException('Release manifest metadata is invalid.');
    }

    final artifactJson = json['artifacts'];
    if (artifactJson is! Map<Object?, Object?>) {
      throw const FormatException('Release artifacts are missing.');
    }
    final supportedArtifactKeys = AppReleasePlatform.values
        .map((platform) => platform.name)
        .toSet();
    if (artifactJson.keys.any(
      (key) => key is! String || !supportedArtifactKeys.contains(key),
    )) {
      throw const FormatException('Release artifacts contain an unknown platform.');
    }
    final artifacts = <AppReleasePlatform, AppReleaseArtifact>{};
    for (final platform in AppReleasePlatform.values) {
      final raw = artifactJson[platform.name];
      if (raw == null) continue;
      if (raw is! Map<Object?, Object?>) {
        throw const FormatException('Release artifact metadata is invalid.');
      }
      artifacts[platform] = AppReleaseArtifact.fromJson(
        platform,
        raw.map((key, value) => MapEntry(key.toString(), value)),
      );
    }
    if (artifacts.isEmpty) {
      throw const FormatException('Manifest has no supported artifacts.');
    }

    final rawNotes = json['releaseNotes'];
    if (rawNotes is! Map<Object?, Object?> || rawNotes.isEmpty) {
      throw const FormatException('Release notes are missing.');
    }
    final notes = <String, String>{};
    for (final entry in rawNotes.entries) {
      if (entry.key is! String || entry.value is! String) {
        throw const FormatException('Release notes are invalid.');
      }
      notes[(entry.key! as String)] = entry.value! as String;
    }

    final rawRevokedBuilds = json['revokedBuilds'];
    if (rawRevokedBuilds is! List<Object?> ||
        rawRevokedBuilds.any((value) => value is! int || value < 1)) {
      throw const FormatException('Revoked build metadata is invalid.');
    }
    final revokedBuilds = rawRevokedBuilds.cast<int>().toSet();
    if (revokedBuilds.length != rawRevokedBuilds.length) {
      throw const FormatException('Revoked build metadata contains duplicates.');
    }

    return AppUpdateManifest(
      schemaVersion: schemaVersion,
      channel: channel,
      publishedAt: publishedAt,
      minimumSupportedVersion: minimumSupportedVersion.trim(),
      mandatory: mandatory,
      releaseNotes: Map.unmodifiable(notes),
      artifacts: Map.unmodifiable(artifacts),
      rolloutPercent: rolloutPercent,
      revokedBuilds: Set.unmodifiable(revokedBuilds),
    );
  }

  AppReleaseArtifact? artifactFor(AppReleasePlatform platform) =>
      artifacts[platform];
}

final class AppUpdateCheckResult {
  const AppUpdateCheckResult({
    required this.currentVersion,
    required this.currentBuildNumber,
    required this.channel,
    required this.updateAvailable,
    required this.mandatory,
    required this.revoked,
    this.artifact,
    this.releaseNotes = '',
  });

  final String currentVersion;
  final int currentBuildNumber;
  final AppReleaseChannel channel;
  final bool updateAvailable;
  final bool mandatory;
  final bool revoked;
  final AppReleaseArtifact? artifact;
  final String releaseNotes;
}
