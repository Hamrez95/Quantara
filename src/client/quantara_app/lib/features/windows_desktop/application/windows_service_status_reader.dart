import 'dart:convert';

import '../domain/windows_service_protocol.dart';

final class WindowsServiceStatusCommandResult {
  const WindowsServiceStatusCommandResult({
    required this.exitCode,
    required this.stdout,
    required this.stderr,
  });

  final int exitCode;
  final String stdout;
  final String stderr;
}

typedef WindowsServiceStatusCommand =
    Future<WindowsServiceStatusCommandResult> Function();

final class WindowsServiceStatusReadException implements Exception {
  const WindowsServiceStatusReadException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Converts the packaged native status helper result into the canonical,
/// fail-closed Flutter status snapshot.
///
/// Peer identity is authenticated by the native helper before it emits stdout.
/// This reader intentionally accepts only that helper boundary, validates the
/// bounded protocol again in Dart, and never exposes mutation authority.
final class WindowsServiceStatusReader {
  factory WindowsServiceStatusReader({
    required WindowsServiceStatusCommand command,
  }) => WindowsServiceStatusReader._(command);

  const WindowsServiceStatusReader._(this._command);

  final WindowsServiceStatusCommand _command;

  Future<WindowsServiceStatusSnapshot> read() async {
    late WindowsServiceStatusCommandResult result;
    try {
      result = await _command();
    } on WindowsServiceStatusReadException {
      rethrow;
    } on Object catch (error) {
      throw WindowsServiceStatusReadException(
        'Windows service status query failed safely (${error.runtimeType}).',
      );
    }

    if (result.exitCode != 0) {
      throw WindowsServiceStatusReadException(
        'Windows service status query failed with exit code ${result.exitCode}.',
      );
    }

    final stdout = result.stdout.trim();
    if (stdout.isEmpty ||
        utf8.encode(stdout).length > WindowsServiceProtocol.maxFrameBytes) {
      throw const WindowsServiceStatusReadException(
        'Windows service status response is empty or oversized.',
      );
    }

    try {
      final decoded = jsonDecode(stdout);
      if (decoded is! Map) {
        throw const WindowsServiceProtocolException(
          'Windows service status response is not a JSON object.',
        );
      }
      final normalized = <String, Object?>{};
      for (final entry in decoded.entries) {
        if (entry.key is! String) {
          throw const WindowsServiceProtocolException(
            'Windows service status response keys must be strings.',
          );
        }
        normalized[entry.key as String] = entry.value;
      }
      final frame = WindowsServiceProtocol.decodeAuthenticated(
        normalized,
        peerAuthenticated: true,
      );
      return WindowsServiceStatusSnapshot.fromFrame(frame);
    } on WindowsServiceProtocolException catch (error) {
      throw WindowsServiceStatusReadException(error.message);
    } on FormatException {
      throw const WindowsServiceStatusReadException(
        'Windows service status response is malformed JSON.',
      );
    } on Object catch (error) {
      throw WindowsServiceStatusReadException(
        'Windows service status response failed safely (${error.runtimeType}).',
      );
    }
  }
}
