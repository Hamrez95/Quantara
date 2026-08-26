import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path_provider/path_provider.dart';

import '../data/app_update_download_verifier.dart';
import '../domain/app_update_models.dart';
import 'app_update_install_coordinator.dart';

typedef AppUpdateProcessRunner =
    Future<ProcessResult> Function(
      String executable,
      List<String> arguments, {
      Map<String, String>? environment,
    });

typedef AppUpdateProcessStarter =
    Future<void> Function(
      String executable,
      List<String> arguments, {
      ProcessStartMode mode,
    });

typedef AppUpdateTemporaryDirectoryProvider = Future<Directory> Function();

/// Windows installer handoff for an already verified Quantara artifact.
///
/// The gateway persists the verified bytes into a private temporary directory,
/// re-verifies the persisted SHA-256, validates the file's real Authenticode
/// signer thumbprint, and only then opens the file through Windows Explorer.
/// Explorer keeps installation under the operating system's normal interactive
/// installer/UAC flow; this gateway never performs a silent install.
final class WindowsAppUpdateInstallerGateway
    implements AppUpdateInstallerGateway {
  WindowsAppUpdateInstallerGateway({
    AppUpdateTemporaryDirectoryProvider? temporaryDirectoryProvider,
    AppUpdateProcessRunner? processRunner,
    AppUpdateProcessStarter? processStarter,
    bool? isWindows,
  }) : _temporaryDirectoryProvider =
           temporaryDirectoryProvider ?? getTemporaryDirectory,
       _processRunner = processRunner ?? _runProcess,
       _processStarter = processStarter ?? _startProcess,
       _isWindows = isWindows ?? Platform.isWindows;

  final AppUpdateTemporaryDirectoryProvider _temporaryDirectoryProvider;
  final AppUpdateProcessRunner _processRunner;
  final AppUpdateProcessStarter _processStarter;
  final bool _isWindows;

  static const _authenticodeCommand =
      r"$signature = Get-AuthenticodeSignature -LiteralPath $env:QUANTARA_UPDATE_PATH; "
      r"if ($signature.Status -ne 'Valid' -or $null -eq $signature.SignerCertificate) { exit 2 }; "
      r"Write-Output $signature.SignerCertificate.Thumbprint";

  @override
  Future<void> handoff(VerifiedAppUpdateDownload download) async {
    if (!_isWindows ||
        download.artifact.platform != AppReleasePlatform.windows) {
      throw const AppUpdateInstallException(
        'Windows installer handoff is unavailable on this platform.',
      );
    }

    final signingIdentity = _normalizeIdentity(
      download.artifact.signingIdentity,
    );
    if (signingIdentity == null) {
      throw const AppUpdateInstallException(
        'Windows signing identity is unavailable. Installer handoff is blocked.',
      );
    }

    final extension = _approvedInstallerExtension(
      download.artifact.downloadUri.path,
    );
    if (extension == null) {
      throw const AppUpdateInstallException(
        'Windows update artifact type is not approved for installer handoff.',
      );
    }

    final root = await _temporaryDirectoryProvider();
    final updateDirectory = Directory(
      '${root.path}${Platform.pathSeparator}quantara-updates',
    );
    await updateDirectory.create(recursive: true);
    final installer = File(
      '${updateDirectory.path}${Platform.pathSeparator}'
      'quantara-${download.artifact.buildNumber}$extension',
    );
    await installer.writeAsBytes(download.bytes, flush: true);

    final persistedSha256 = sha256
        .convert(await installer.readAsBytes())
        .toString();
    if (persistedSha256.toLowerCase() !=
        download.artifact.sha256.trim().toLowerCase()) {
      await _deleteQuietly(installer);
      throw const AppUpdateInstallException(
        'Persisted update checksum verification failed. Installer handoff is blocked.',
      );
    }

    final signatureResult = await _processRunner(
      'powershell.exe',
      const [
        '-NoLogo',
        '-NoProfile',
        '-NonInteractive',
        '-Command',
        _authenticodeCommand,
      ],
      environment: {'QUANTARA_UPDATE_PATH': installer.path},
    );
    final actualIdentity = _normalizeIdentity(
      signatureResult.stdout.toString(),
    );
    if (signatureResult.exitCode != 0 || actualIdentity != signingIdentity) {
      await _deleteQuietly(installer);
      throw const AppUpdateInstallException(
        'Windows Authenticode verification failed. Installer handoff is blocked.',
      );
    }

    try {
      await _processStarter('explorer.exe', [
        installer.path,
      ], mode: ProcessStartMode.detached);
    } on Object catch (error) {
      await _deleteQuietly(installer);
      throw AppUpdateInstallException(
        'Windows installer handoff failed safely (${error.runtimeType}).',
      );
    }
  }

  static Future<ProcessResult> _runProcess(
    String executable,
    List<String> arguments, {
    Map<String, String>? environment,
  }) => Process.run(executable, arguments, environment: environment);

  static Future<void> _startProcess(
    String executable,
    List<String> arguments, {
    ProcessStartMode mode = ProcessStartMode.normal,
  }) async {
    await Process.start(executable, arguments, mode: mode);
  }

  static String? _approvedInstallerExtension(String path) {
    final normalized = path.toLowerCase();
    for (final extension in const ['.exe', '.msix', '.msixbundle']) {
      if (normalized.endsWith(extension)) return extension;
    }
    return null;
  }

  static String? _normalizeIdentity(String? value) {
    if (value == null) return null;
    final normalized = value
        .trim()
        .replaceAll(RegExp(r'[\s:-]'), '')
        .toUpperCase();
    return normalized.isEmpty ? null : normalized;
  }

  static Future<void> _deleteQuietly(File file) async {
    try {
      if (await file.exists()) await file.delete();
    } on FileSystemException {
      // A failed cleanup must never turn a blocked install into an allowed one.
    }
  }
}