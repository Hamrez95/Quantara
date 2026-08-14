import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../auto_trade/application/read_only_support_session.dart';
import '../../auto_trade/domain/unattended_auto_trade_models.dart';
import '../domain/supervisor_system_evidence.dart';

final class SupervisorSupportSessionRemoteSnapshot {
  const SupervisorSupportSessionRemoteSnapshot({
    required this.sessionId,
    required this.tokenFingerprint,
    required this.expiresAtUtc,
    required this.scope,
    required this.evidenceCount,
    required this.lastUpdatedAtUtc,
  });

  final String sessionId;
  final String tokenFingerprint;
  final DateTime expiresAtUtc;
  final String scope;
  final int evidenceCount;
  final DateTime lastUpdatedAtUtc;

  factory SupervisorSupportSessionRemoteSnapshot.fromJson(
    Map<String, Object?> json,
  ) => SupervisorSupportSessionRemoteSnapshot(
    sessionId: json['sessionId']?.toString() ?? '',
    tokenFingerprint: json['tokenFingerprint']?.toString() ?? '',
    expiresAtUtc: DateTime.parse(json['expiresAtUtc']!.toString()).toUtc(),
    scope: json['scope']?.toString() ?? '',
    evidenceCount: (json['evidenceCount'] as num?)?.toInt() ?? 0,
    lastUpdatedAtUtc: DateTime.parse(
      json['lastUpdatedAtUtc']!.toString(),
    ).toUtc(),
  );
}

final class SupervisorSupportSessionException implements Exception {
  const SupervisorSupportSessionException(this.message, {this.statusCode});

  final String message;
  final int? statusCode;

  @override
  String toString() => message;
}

final class SupervisorSupportSessionApiClient {
  const SupervisorSupportSessionApiClient({required http.Client client})
    : _client = client;

  final http.Client _client;

  Future<SupervisorSupportSessionRemoteSnapshot> register({
    required AutoTradeServerConfig serverConfig,
    required ReadOnlySupportSessionGrant grant,
    required List<SupervisorSystemEvidence> evidence,
  }) => _requestSnapshot(
    uri: serverConfig.baseUrl.resolve(
      '/api/v1/supervisor/support-session/register',
    ),
    method: 'POST',
    headers: <String, String>{
      'Accept': 'application/json',
      'Content-Type': 'application/json',
      'X-Quantara-Control-Token': serverConfig.controlToken,
    },
    body: <String, Object?>{
      'token': grant.token,
      'expiresAtUtc': grant.expiresAt.toUtc().toIso8601String(),
      'scope': grant.scope,
      'evidence': evidence.map((item) => item.toJson()).toList(growable: false),
    },
  );

  Future<SupervisorSupportSessionRemoteSnapshot> refreshEvidence({
    required Uri baseUrl,
    required String supportToken,
    required List<SupervisorSystemEvidence> evidence,
  }) => _requestSnapshot(
    uri: baseUrl.resolve('/api/v1/supervisor/support-session/evidence'),
    method: 'POST',
    headers: _sessionHeaders(supportToken, json: true),
    body: <String, Object?>{
      'evidence': evidence.map((item) => item.toJson()).toList(growable: false),
    },
  );

  Future<SupervisorSupportSessionRemoteSnapshot> fetchStatus({
    required Uri baseUrl,
    required String supportToken,
  }) => _requestSnapshot(
    uri: baseUrl.resolve('/api/v1/supervisor/support-session'),
    method: 'GET',
    headers: _sessionHeaders(supportToken),
  );

  Future<void> revoke({
    required Uri baseUrl,
    required String supportToken,
  }) async {
    final response = await _client
        .delete(
          baseUrl.resolve('/api/v1/supervisor/support-session'),
          headers: _sessionHeaders(supportToken),
        )
        .timeout(const Duration(seconds: 12));
    if (response.statusCode != 204) {
      throw SupervisorSupportSessionException(
        'The remote support session could not be revoked safely.',
        statusCode: response.statusCode,
      );
    }
  }

  static Map<String, String> _sessionHeaders(
    String token, {
    bool json = false,
  }) => <String, String>{
    'Accept': 'application/json',
    'Authorization': 'Bearer $token',
    if (json) 'Content-Type': 'application/json',
  };

  Future<SupervisorSupportSessionRemoteSnapshot> _requestSnapshot({
    required Uri uri,
    required String method,
    required Map<String, String> headers,
    Map<String, Object?>? body,
  }) async {
    late final http.Response response;
    try {
      response = switch (method) {
        'GET' => await _client
            .get(uri, headers: headers)
            .timeout(const Duration(seconds: 12)),
        _ => await _client
            .post(uri, headers: headers, body: jsonEncode(body))
            .timeout(const Duration(seconds: 15)),
      };
    } on Object {
      throw const SupervisorSupportSessionException(
        'The Quantara Supervisor server could not be reached.',
      );
    }

    if (response.bodyBytes.length > 1000000) {
      throw const SupervisorSupportSessionException(
        'The Supervisor server returned an oversized response.',
      );
    }
    Object? decoded;
    try {
      decoded = jsonDecode(utf8.decode(response.bodyBytes));
    } on Object {
      throw SupervisorSupportSessionException(
        'The Supervisor server returned an unreadable response.',
        statusCode: response.statusCode,
      );
    }
    if (decoded is! Map<String, Object?>) {
      throw SupervisorSupportSessionException(
        'The Supervisor server returned an unexpected response.',
        statusCode: response.statusCode,
      );
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw SupervisorSupportSessionException(
        decoded['error']?.toString() ??
            'The Supervisor server rejected the support-session request.',
        statusCode: response.statusCode,
      );
    }
    return SupervisorSupportSessionRemoteSnapshot.fromJson(decoded);
  }
}
