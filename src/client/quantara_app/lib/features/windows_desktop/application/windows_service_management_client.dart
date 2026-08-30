import 'dart:convert';

import '../domain/windows_service_protocol.dart';

final class WindowsServiceManagementCommandResult {
  const WindowsServiceManagementCommandResult({
    required this.exitCode,
    required this.stdout,
    required this.stderr,
  });

  final int exitCode;
  final String stdout;
  final String stderr;
}

typedef WindowsServiceCloseExistingPositionCommand =
    Future<WindowsServiceManagementCommandResult> Function(String positionId);

final class WindowsServiceManagementException implements Exception {
  const WindowsServiceManagementException(this.message);

  final String message;

  @override
  String toString() => message;
}

final class WindowsServiceManagementResult {
  const WindowsServiceManagementResult({
    required this.completed,
    required this.submissionAttempted,
    required this.exchangeTruthReconciled,
  });

  final bool completed;
  final bool submissionAttempted;
  final bool exchangeTruthReconciled;
}

/// Narrow Flutter boundary for the Windows management-only worker.
///
/// This client can express exactly one mutation: closing one verified existing
/// position by canonical exchange position id. The packaged native helper
/// authenticates the service process before it emits a response. This layer
/// validates input and the canonical management result again and deliberately
/// exposes no entry, leverage, margin, transfer, generic-order, or stop-widening
/// surface.
final class WindowsServiceManagementClient {
  factory WindowsServiceManagementClient({
    required WindowsServiceCloseExistingPositionCommand closeCommand,
  }) => WindowsServiceManagementClient._(closeCommand);

  const WindowsServiceManagementClient._(this._closeCommand);

  final WindowsServiceCloseExistingPositionCommand _closeCommand;

  static final RegExp _positionIdPattern = RegExp(r'^[0-9]{1,64}$');

  Future<WindowsServiceManagementResult> closeExistingPosition(
    String positionId,
  ) async {
    if (!_positionIdPattern.hasMatch(positionId) || positionId == '0') {
      throw const WindowsServiceManagementException(
        'Windows position id must contain 1-64 decimal digits and must not be zero.',
      );
    }

    late WindowsServiceManagementCommandResult result;
    try {
      result = await _closeCommand(positionId);
    } on WindowsServiceManagementException {
      rethrow;
    } on Object catch (error) {
      throw WindowsServiceManagementException(
        'Windows management command failed safely (${error.runtimeType}).',
      );
    }

    // The native helper returns 8 only for a canonical, validated management
    // result whose completed flag is false. Any other non-zero exit code means
    // no response is trusted by Flutter.
    if (result.exitCode != 0 && result.exitCode != 8) {
      throw WindowsServiceManagementException(
        'Windows management command failed with exit code ${result.exitCode}.',
      );
    }

    final stdout = result.stdout.trim();
    if (stdout.isEmpty ||
        utf8.encode(stdout).length > WindowsServiceProtocol.maxFrameBytes) {
      throw const WindowsServiceManagementException(
        'Windows management response is empty or oversized.',
      );
    }

    try {
      final decoded = jsonDecode(stdout);
      if (decoded is! Map) {
        throw const WindowsServiceManagementException(
          'Windows management response is not a JSON object.',
        );
      }

      if (decoded.length != 4 ||
          decoded['protocolVersion'] != WindowsServiceProtocol.currentVersion ||
          decoded['requestId'] is! String ||
          decoded['kind'] != 'managementResult' ||
          decoded['payload'] is! Map) {
        throw const WindowsServiceManagementException(
          'Malformed Windows management response.',
        );
      }

      final requestId = decoded['requestId'] as String;
      if (!RegExp(r'^[A-Za-z0-9._-]{1,64}$').hasMatch(requestId)) {
        throw const WindowsServiceManagementException(
          'Invalid Windows management request id.',
        );
      }

      final payload = decoded['payload'] as Map;
      if (payload.length != 3 ||
          !payload.containsKey('completed') ||
          !payload.containsKey('submissionAttempted') ||
          !payload.containsKey('exchangeTruthReconciled')) {
        throw const WindowsServiceManagementException(
          'Malformed Windows management result payload.',
        );
      }

      final completed = payload['completed'];
      final submissionAttempted = payload['submissionAttempted'];
      final exchangeTruthReconciled = payload['exchangeTruthReconciled'];
      if (completed is! bool ||
          submissionAttempted is! bool ||
          exchangeTruthReconciled is! bool ||
          (completed && (!submissionAttempted || !exchangeTruthReconciled)) ||
          (exchangeTruthReconciled && !submissionAttempted)) {
        throw const WindowsServiceManagementException(
          'Windows management result failed closed validation.',
        );
      }

      if ((result.exitCode == 0) != completed) {
        throw const WindowsServiceManagementException(
          'Windows management helper exit code contradicts its result.',
        );
      }

      return WindowsServiceManagementResult(
        completed: completed,
        submissionAttempted: submissionAttempted,
        exchangeTruthReconciled: exchangeTruthReconciled,
      );
    } on WindowsServiceManagementException {
      rethrow;
    } on FormatException {
      throw const WindowsServiceManagementException(
        'Windows management response is malformed JSON.',
      );
    } on Object catch (error) {
      throw WindowsServiceManagementException(
        'Windows management response failed safely (${error.runtimeType}).',
      );
    }
  }
}
