import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../application/windows_service_status_reader.dart';
import '../domain/windows_service_protocol.dart';

const _commandTimeout = Duration(seconds: 6);
const _shutdownTimeout = Duration(seconds: 1);
const _maxDiagnosticBytes = 8 * 1024;

WindowsServiceStatusCommand createWindowsServiceStatusCommand() {
  return _runWindowsServiceStatusCommand;
}

Future<WindowsServiceStatusCommandResult>
_runWindowsServiceStatusCommand() async {
  if (!Platform.isWindows) {
    throw const WindowsServiceStatusReadException(
      'Windows service status is unavailable on this platform.',
    );
  }

  final appDirectory = File(Platform.resolvedExecutable).parent.path;
  final executable = [
    appDirectory,
    'service',
    'quantara_windows_service_client.exe',
  ].join(Platform.pathSeparator);
  if (!await File(executable).exists()) {
    throw const WindowsServiceStatusReadException(
      'Windows service status helper is unavailable.',
    );
  }

  late Process process;
  try {
    process = await Process.start(
      executable,
      const ['--status'],
      runInShell: false,
      mode: ProcessStartMode.normal,
    );
  } on Object catch (error) {
    throw WindowsServiceStatusReadException(
      'Windows service status helper could not start (${error.runtimeType}).',
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
    final exitCode = completed[0] as int;
    final stdoutBytes = completed[1] as List<int>;
    final stderrBytes = completed[2] as List<int>;
    return WindowsServiceStatusCommandResult(
      exitCode: exitCode,
      stdout: utf8.decode(stdoutBytes, allowMalformed: false),
      stderr: utf8.decode(stderrBytes, allowMalformed: true),
    );
  } on TimeoutException {
    process.kill();
    try {
      await process.exitCode.timeout(_shutdownTimeout);
    } on Object {
      // The helper is already fail-closed and no output is trusted after a
      // timeout. Do not block application shutdown waiting on a broken child.
    }
    throw const WindowsServiceStatusReadException(
      'Windows service status helper timed out.',
    );
  } on WindowsServiceStatusReadException {
    process.kill();
    rethrow;
  } on FormatException {
    throw const WindowsServiceStatusReadException(
      'Windows service status helper returned invalid UTF-8.',
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
      throw const WindowsServiceStatusReadException(
        'Windows service status helper output exceeded its safety limit.',
      );
    }
    bytes.addAll(chunk);
  }
  return bytes;
}
