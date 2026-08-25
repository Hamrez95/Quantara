import 'package:flutter/foundation.dart';

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
  }) : _manifestClient = manifestClient,
       _channel = initialChannel;

  final AppUpdateManifestClient _manifestClient;
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

  Future<void> setChannel(AppReleaseChannel channel) async {
    if (_busy || channel == _channel || _disposed) return;
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
      final revoked = manifest.revokedBuilds.contains(currentBuildNumber);
      final newerBuild = artifact.buildNumber > currentBuildNumber;
      final newerVersion =
          _compareVersions(artifact.version, currentVersion) > 0;
      _result = AppUpdateCheckResult(
        currentVersion: currentVersion,
        currentBuildNumber: currentBuildNumber,
        channel: _channel,
        updateAvailable: revoked || newerBuild || newerVersion,
        mandatory: manifest.mandatory || revoked,
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

  static int _compareVersions(String left, String right) {
    List<int> parse(String value) {
      final core = value.trim().split('-').first;
      final parts = core.split('.');
      return List<int>.generate(
        3,
        (index) => index < parts.length ? int.tryParse(parts[index]) ?? 0 : 0,
      );
    }

    final leftParts = parse(left);
    final rightParts = parse(right);
    for (var index = 0; index < 3; index++) {
      final compared = leftParts[index].compareTo(rightParts[index]);
      if (compared != 0) return compared;
    }
    return 0;
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
