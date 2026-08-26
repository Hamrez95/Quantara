import 'dart:convert';

/// Versioned, read-only IPC framing contract for the future Windows service.
///
/// This file intentionally does not implement a named-pipe transport or peer
/// authentication. A transport must verify the peer first and pass that result
/// to [decodeAuthenticated]. Until then, application frames fail closed.
final class WindowsServiceProtocol {
  const WindowsServiceProtocol._();

  static const int currentVersion = 1;
  static const int maxFrameBytes = 64 * 1024;

  static WindowsServiceFrame decodeAuthenticated(
    Map<String, Object?> json, {
    required bool peerAuthenticated,
  }) {
    if (!peerAuthenticated) {
      throw const WindowsServiceProtocolException(
        'Unauthenticated Windows service peer.',
      );
    }
    return WindowsServiceFrame.fromJson(json);
  }
}

enum WindowsServiceMessageKind {
  handshake,
  statusRequest,
  statusSnapshot;

  static WindowsServiceMessageKind parse(String value) {
    for (final kind in values) {
      if (kind.name == value) return kind;
    }
    throw const WindowsServiceProtocolException(
      'Unknown Windows service message kind.',
    );
  }
}

final class WindowsServiceFrame {
  WindowsServiceFrame({
    required this.requestId,
    required this.kind,
    required Map<String, Object?> payload,
    this.protocolVersion = WindowsServiceProtocol.currentVersion,
  }) : payload = Map.unmodifiable(payload) {
    _validate();
  }

  factory WindowsServiceFrame.fromJson(Map<String, Object?> json) {
    _validateFrameSize(json);

    final protocolVersion = json['protocolVersion'];
    final requestId = json['requestId'];
    final kind = json['kind'];
    final payload = json['payload'];

    if (protocolVersion is! int ||
        requestId is! String ||
        kind is! String ||
        payload is! Map) {
      throw const WindowsServiceProtocolException(
        'Malformed Windows service frame.',
      );
    }

    final normalizedPayload = <String, Object?>{};
    for (final entry in payload.entries) {
      if (entry.key is! String) {
        throw const WindowsServiceProtocolException(
          'Windows service payload keys must be strings.',
        );
      }
      normalizedPayload[entry.key as String] = entry.value;
    }

    return WindowsServiceFrame(
      protocolVersion: protocolVersion,
      requestId: requestId,
      kind: WindowsServiceMessageKind.parse(kind),
      payload: normalizedPayload,
    );
  }

  final int protocolVersion;
  final String requestId;
  final WindowsServiceMessageKind kind;
  final Map<String, Object?> payload;

  Map<String, Object?> toJson() => <String, Object?>{
    'protocolVersion': protocolVersion,
    'requestId': requestId,
    'kind': kind.name,
    'payload': payload,
  };

  void _validate() {
    if (protocolVersion != WindowsServiceProtocol.currentVersion) {
      throw const WindowsServiceProtocolException(
        'Incompatible Windows service protocol version.',
      );
    }
    if (!_requestIdPattern.hasMatch(requestId)) {
      throw const WindowsServiceProtocolException(
        'Invalid Windows service request id.',
      );
    }
    _validateFrameSize(toJson());
  }

  static final RegExp _requestIdPattern = RegExp(r'^[A-Za-z0-9._-]{1,64}$');

  static void _validateFrameSize(Map<String, Object?> frame) {
    final encodedBytes = utf8.encode(jsonEncode(frame));
    if (encodedBytes.length > WindowsServiceProtocol.maxFrameBytes) {
      throw const WindowsServiceProtocolException(
        'Windows service frame exceeds the size limit.',
      );
    }
  }
}

final class WindowsServiceProtocolException implements Exception {
  const WindowsServiceProtocolException(this.message);

  final String message;

  @override
  String toString() => 'WindowsServiceProtocolException: $message';
}
