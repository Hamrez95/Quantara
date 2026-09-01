import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../application/windows_service_management_client.dart';
import '../domain/windows_service_protocol.dart';

const _commandTimeout = Duration(seconds: 8);
const _shutdownTimeout = Duration(seconds: 1);
const _maxDiagnosticBytes = 8 * 1024;

WindowsServiceCloseExistingPositionCommand
createWindowsServiceCloseExistingPositionCommand() {
  return (positionId) => _runWindowsServiceManagementCommand([
    '--close-existing-position',
    positionId,
  ]);
}

WindowsServiceTightenExistingStopCommand
createWindowsServiceTightenExistingStopCommand() {
  return (positionId, newStopPrice) => _runWindowsServiceManagementCommand([
    '--tighten-existing-stop',
    positionId,
    newStopPrice,
  ]);
}

Future<WindowsServiceManagementCommandResult>
_runWindowsServiceManagementCommand(List<String> arguments) async {
  if (!Platform.isWindows) {
    throw const WindowsServiceManagementException(
      'Windows service management is unavailable on this platform.',
    );
  }

  final appDirectory = File(Platform.resolvedExecutable).parent.path;
  final executable = [
    appDirectory,
    'service',
    'quantara_windows_service_client.exe',
  ].join(Platform.pathSeparator);
  if (!await File(executable).exists()) {
    throw const WindowsServiceManagementException(
      'Windows service management helper is unavailable.',
    );
  }

  late Process process;
  try {
    process = await Process.start(
      executable,
      arguments,
      runInShell: false,
      mode: ProcessStartMode.normal,
    );
  } on Object catch (error) {
    throw WindowsServiceManagementException(
      'Windows service management helper could not start (${error.runtimeType}).',
    );
  }

  final stdoutFuture = _readBounded(
    process.stdout,
    WindowsServiceProtocol.maxFrameBytes,
    process,
  );
  final stderrFuture = _readBounded(
    process.stderr,
    _maxDiagnosticBytes,
    process,
  );

  try {
    final completed = await Future.wait<Object>([
      process.exitCode,
      stdoutFuture,
      stderrFuture,
    ]).timeout(_commandTimeout);
    return WindowsServiceManagementCommandResult(
      exitCode: completed[0] as int,
      stdout: utf8.decode(completed[1] as List<int>, allowMalformed: false),
      stderr: utf8.decode(completed[2] as List<int>, allowMalformed: true),
    );
  } on TimeoutException {
    process.kill();
    try {
      await process.exitCode.timeout(_shutdownTimeout);
    } on Object {
      // The helper and service are fail-closed. No output is trusted after a
      // timeout and Flutter never retries a mutation automatically.
    }
    throw const WindowsServiceManagementException(
      'Windows service management helper timed out; exchange outcome must be reconciled before retrying.',
    );
  } on WindowsServiceManagementException {
    process.kill();
    rethrow;
  } on FormatException {
    throw const WindowsServiceManagementException(
      'Windows service management helper returned invalid UTF-8.',
    );
  }
}

Future<List<int>> _readBounded(
  Stream<List<int>> stream,
  int maxBytes,
  Process process,
) async {
  final bytes = <int>[];
  await for (final chunk in stream) {
    if (bytes.length + chunk.length > maxBytes) {
      process.kill();
      throw const WindowsServiceManagementException(
        'Windows service management helper output exceeded its safety limit.',
      );
    }
    bytes.addAll(chunk);
  }
  return bytes;
}
