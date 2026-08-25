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
    final version = json['version']?.toString().trim() ?? '';
    final buildNumber = (json['buildNumber'] as num?)?.toInt() ?? 0;
    final downloadUri = Uri.tryParse(json['url']?.toString() ?? '');
    final sha256 = json['sha256']?.toString().trim().toLowerCase() ?? '';
    final validSha256 = RegExp(r'^[a-f0-9]{64}$').hasMatch(sha256);
    if (version.isEmpty ||
        buildNumber < 1 ||
        downloadUri == null ||
        downloadUri.scheme != 'https' ||
        !validSha256) {
      throw const FormatException('Release artifact metadata is invalid.');
    }
    return AppReleaseArtifact(
      platform: platform,
      version: version,
      buildNumber: buildNumber,
      downloadUri: downloadUri,
      sha256: sha256,
      packageId: json['packageId']?.toString(),
      signingIdentity: json['signingIdentity']?.toString(),
      architecture: json['architecture']?.toString(),
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
    final schemaVersion = (json['schemaVersion'] as num?)?.toInt() ?? 0;
    if (schemaVersion != 1) {
      throw const FormatException('Unsupported update manifest schema.');
    }
    final channel = AppReleaseChannel.values.firstWhere(
      (item) => item.name == json['channel'],
      orElse: () => throw const FormatException('Unknown release channel.'),
    );
    final publishedAt = DateTime.tryParse(json['publishedAt']?.toString() ?? '')
        ?.toUtc();
    if (publishedAt == null) {
      throw const FormatException('Manifest publication time is invalid.');
    }
    final rolloutPercent = (json['rolloutPercent'] as num?)?.toInt() ?? 100;
    if (rolloutPercent < 0 || rolloutPercent > 100) {
      throw const FormatException('Rollout percent must be between 0 and 100.');
    }

    final artifactJson = json['artifacts'];
    if (artifactJson is! Map<Object?, Object?>) {
      throw const FormatException('Release artifacts are missing.');
    }
    final artifacts = <AppReleasePlatform, AppReleaseArtifact>{};
    for (final platform in AppReleasePlatform.values) {
      final raw = artifactJson[platform.name];
      if (raw is Map<Object?, Object?>) {
        artifacts[platform] = AppReleaseArtifact.fromJson(
          platform,
          raw.map((key, value) => MapEntry(key.toString(), value)),
        );
      }
    }
    if (artifacts.isEmpty) {
      throw const FormatException('Manifest has no supported artifacts.');
    }

    final notes = (json['releaseNotes'] as Map<Object?, Object?>? ?? const {})
        .map((key, value) => MapEntry(key.toString(), value.toString()));
    final revokedBuilds = (json['revokedBuilds'] as List<Object?>? ?? const [])
        .whereType<num>()
        .map((value) => value.toInt())
        .toSet();

    return AppUpdateManifest(
      schemaVersion: schemaVersion,
      channel: channel,
      publishedAt: publishedAt,
      minimumSupportedVersion:
          json['minimumSupportedVersion']?.toString() ?? '0.0.0',
      mandatory: json['mandatory'] == true,
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
