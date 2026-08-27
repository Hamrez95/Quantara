// Keep stable public named constructor parameters while storing dependencies privately.
// ignore_for_file: prefer_initializing_formals

import 'package:flutter/foundation.dart';

import '../data/app_update_channel_store.dart';
import '../data/app_update_manifest_client.dart';
import '../domain/app_update_models.dart';

final class AppUpdateController extends ChangeNotifier {
  AppUpdateController({
    required AppUpdateManifestClient manifestClient,
    required this.currentVersion,
    required this.currentBuildNumber,
    required this.platform,
    required AppReleaseChannel initialChannel,
    required this.languageCode,
    AppUpdateChannelStore? channelStore,
  }) : _manifestClient = manifestClient,
       _channelStore = channelStore,
       _channel = initialChannel;

  final AppUpdateManifestClient _manifestClient;
  final AppUpdateChannelStore? _channelStore;
  final String currentVersion;
  final int currentBuildNumber;
  final AppReleasePlatform platform;
  final String languageCode;

  AppReleaseChannel _channel;
  AppUpdateCheckResult? _result;
  String? _error;
  bool _busy = false;
  bool _disposed = false;

  AppReleaseChannel get channel => _channel;
  AppUpdateCheckResult? get result => _result;
  String? get error => _error;
  bool get isBusy => _busy;

  Future<void> restoreChannel() async {
    if (_busy || _disposed || _channelStore == null) return;
    try {
      final restored = await _channelStore.load();
      if (_disposed || restored == null || restored == _channel) return;
      _channel = restored;
      _result = null;
      _error = null;
      notifyListeners();
    } on Object catch (error) {
      if (_disposed) return;
      _error =
          'Saved update channel could not be restored safely (${error.runtimeType}).';
      _result = null;
      notifyListeners();
    }
  }

  Future<void> setChannel(AppReleaseChannel channel) async {
    if (_busy || channel == _channel || _disposed) return;
    try {
      await _channelStore?.save(channel);
    } on Object catch (error) {
      if (_disposed) return;
      _result = null;
      _error =
          'Update channel could not be saved safely (${error.runtimeType}).';
      notifyListeners();
      return;
    }
    if (_disposed) return;
    _channel = channel;
    _result = null;
    _error = null;
    notifyListeners();
  }

  Future<bool> check() async {
    if (_busy || _disposed) return false;
    _busy = true;
    _error = null;
    notifyListeners();
    try {
      final manifest = await _manifestClient.fetch(_channel);
      final artifact = manifest.artifactFor(platform);
      if (artifact == null) {
        throw const FormatException(
          'No update artifact is published for this platform.',
        );
      }
      if (_compareVersions(artifact.version, manifest.minimumSupportedVersion) <
          0) {
        throw const FormatException(
          'Published update is below the minimum supported version.',
        );
      }

      final versionComparison = _compareVersions(
        artifact.version,
        currentVersion,
      );
      if (versionComparison < 0) {
        throw const FormatException(
          'Published update would downgrade the current app; explicit recovery is required.',
        );
      }
      if (artifact.buildNumber < currentBuildNumber) {
        throw const FormatException(
          'Published update would downgrade the current build; explicit recovery is required.',
        );
      }

      final revoked = manifest.revokedBuilds.contains(currentBuildNumber);
      final newerBuild = artifact.buildNumber > currentBuildNumber;
      final newerVersion = versionComparison > 0;
      final belowMinimumSupported =
          _compareVersions(currentVersion, manifest.minimumSupportedVersion) <
          0;
      _result = AppUpdateCheckResult(
        currentVersion: currentVersion,
        currentBuildNumber: currentBuildNumber,
        channel: _channel,
        updateAvailable:
            revoked || belowMinimumSupported || newerBuild || newerVersion,
        mandatory: manifest.mandatory || revoked || belowMinimumSupported,
        revoked: revoked,
        artifact: artifact,
        releaseNotes:
            manifest.releaseNotes[languageCode] ??
            manifest.releaseNotes['en'] ??
            '',
      );
      return true;
    } on Object catch (error) {
      _error = error is AppUpdateManifestException || error is FormatException
          ? error.toString()
          : 'Update check failed safely (${error.runtimeType}).';
      _result = null;
      return false;
    } finally {
      if (!_disposed) {
        _busy = false;
        notifyListeners();
      }
    }
  }

  static int _compareVersions(String left, String right) =>
      _SemanticVersion.parse(left).compareTo(_SemanticVersion.parse(right));

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}

final class _SemanticVersion implements Comparable<_SemanticVersion> {
  const _SemanticVersion(this.major, this.minor, this.patch, this.preRelease);

  final int major;
  final int minor;
  final int patch;
  final List<String> preRelease;

  static final RegExp _pattern = RegExp(
    r'^(\d+)\.(\d+)\.(\d+)(?:-([0-9A-Za-z.-]+))?(?:\+([0-9A-Za-z.-]+))?$',
  );

  factory _SemanticVersion.parse(String raw) {
    final value = raw.trim();
    final match = _pattern.firstMatch(value);
    if (match == null) {
      throw const FormatException('Release version is not valid SemVer.');
    }

    int parseCore(int group) {
      final segment = match.group(group)!;
      if (segment.length > 1 && segment.startsWith('0')) {
        throw const FormatException('Release version is not valid SemVer.');
      }
      return int.parse(segment);
    }

    final rawPreRelease = match.group(4);
    final preRelease = rawPreRelease == null
        ? const <String>[]
        : rawPreRelease.split('.');
    for (final identifier in preRelease) {
      if (identifier.isEmpty ||
          (_isNumeric(identifier) &&
              identifier.length > 1 &&
              identifier.startsWith('0'))) {
        throw const FormatException('Release version is not valid SemVer.');
      }
    }

    final rawBuildMetadata = match.group(5);
    if (rawBuildMetadata != null &&
        rawBuildMetadata.split('.').any((identifier) => identifier.isEmpty)) {
      throw const FormatException('Release version is not valid SemVer.');
    }

    return _SemanticVersion(
      parseCore(1),
      parseCore(2),
      parseCore(3),
      List.unmodifiable(preRelease),
    );
  }

  static bool _isNumeric(String value) => RegExp(r'^\d+$').hasMatch(value);

  @override
  int compareTo(_SemanticVersion other) {
    final core = <int>[
      major.compareTo(other.major),
      minor.compareTo(other.minor),
      patch.compareTo(other.patch),
    ];
    for (final compared in core) {
      if (compared != 0) return compared;
    }

    if (preRelease.isEmpty && other.preRelease.isEmpty) return 0;
    if (preRelease.isEmpty) return 1;
    if (other.preRelease.isEmpty) return -1;

    final commonLength = preRelease.length < other.preRelease.length
        ? preRelease.length
        : other.preRelease.length;
    for (var index = 0; index < commonLength; index++) {
      final left = preRelease[index];
      final right = other.preRelease[index];
      if (left == right) continue;
      final leftNumeric = _isNumeric(left);
      final rightNumeric = _isNumeric(right);
      if (leftNumeric && rightNumeric) {
        return int.parse(left).compareTo(int.parse(right));
      }
      if (leftNumeric) return -1;
      if (rightNumeric) return 1;
      return left.compareTo(right);
    }
    return preRelease.length.compareTo(other.preRelease.length);
  }
}
