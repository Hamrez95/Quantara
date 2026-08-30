import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;

import '../../ai_supervisor/application/supervisor_diagnostic_evidence_adapter.dart';
import '../../ai_supervisor/domain/supervisor_system_evidence.dart';
import '../domain/unattended_auto_trade_models.dart';
import 'support_session_diagnostic_snapshot.dart';

final class ReadOnlySupportSessionGrant {
  const ReadOnlySupportSessionGrant({
    required this.token,
    required this.expiresAt,
    required this.scope,
  });

  final String token;
  final DateTime expiresAt;
  final String scope;
}

final class ReadOnlySupportSessionSnapshot {
  const ReadOnlySupportSessionSnapshot({
    required this.createdAt,
    required this.expiresAt,
    required this.scope,
    required this.tokenFingerprint,
  });

  final DateTime createdAt;
  final DateTime expiresAt;
  final String scope;
  final String tokenFingerprint;

  Map<String, Object?> toDiagnosticJson(DateTime now) => {
    'active': now.toUtc().isBefore(expiresAt),
    'scope': scope,
    'createdAt': createdAt.toUtc().toIso8601String(),
    'expiresAt': expiresAt.toUtc().toIso8601String(),
    'tokenFingerprint': tokenFingerprint,
    'transportImplemented': true,
    'exchangeCredentialsExposed': false,
    'tradingPermission': false,
  };
}

final class ReadOnlySupportSessionManager {
  ReadOnlySupportSessionManager({DateTime Function()? clock, Random? random})
    : _clock = clock ?? (() => DateTime.now().toUtc()),
      _random = random ?? Random.secure();

  static const scope = 'diagnostics.read';
  final DateTime Function() _clock;
  final Random _random;
  ReadOnlySupportSessionSnapshot? _snapshot;

  ReadOnlySupportSessionSnapshot? get current {
    final snapshot = _snapshot;
    if (snapshot == null) return null;
    if (!_clock().toUtc().isBefore(snapshot.expiresAt)) {
      _snapshot = null;
      return null;
    }
    return snapshot;
  }

  bool get isActive => current != null;

  ReadOnlySupportSessionGrant enable({
    Duration ttl = const Duration(minutes: 45),
  }) {
    if (ttl < const Duration(minutes: 30) ||
        ttl > const Duration(minutes: 60)) {
      throw ArgumentError.value(
        ttl,
        'ttl',
        'must be between 30 and 60 minutes',
      );
    }
    final now = _clock().toUtc();
    final bytes = List<int>.generate(32, (_) => _random.nextInt(256));
    final token = base64UrlEncode(bytes).replaceAll('=', '');
    final fingerprint = sha256
        .convert(utf8.encode(token))
        .toString()
        .substring(0, 16);
    final expiresAt = now.add(ttl);
    _snapshot = ReadOnlySupportSessionSnapshot(
      createdAt: now,
      expiresAt: expiresAt,
      scope: scope,
      tokenFingerprint: fingerprint,
    );
    return ReadOnlySupportSessionGrant(
      token: token,
      expiresAt: expiresAt,
      scope: scope,
    );
  }

  void revoke() => _snapshot = null;

  static Map<String, Object?> architectureDescriptor() => const {
    'defaultEnabled': false,
    'scope': scope,
    'readOnly': true,
    'sanitizedDiagnosticsOnly': true,
    'revocable': true,
    'ttlMinutes': {'minimum': 30, 'default': 45, 'maximum': 60},
    'backendTransportImplemented': true,
    'mcpTransport': 'remote-http',
    'exchangeCredentialsAllowed': false,
    'tradingWritesAllowed': false,
  };
}

abstract final class ReadOnlySupportSessionEvidence {
  static List<SupervisorSystemEvidence> fromDiagnosticSections({
    required String bundleId,
    required DateTime observedAtUtc,
    required Map<String, Object?> sections,
  }) {
    final correlated = _correlatedSections(
      bundleId: bundleId,
      observedAtUtc: observedAtUtc,
      sections: sections,
    );
    return SupervisorDiagnosticEvidenceAdapter.fromDiagnosticBundle(
      bundleId: bundleId,
      observedAtUtc: observedAtUtc,
      diagnosticBundle: <String, Object?>{
        'sections': <String, Object?>{...sections, ...correlated},
      },
      correlationId: bundleId,
    );
  }

  static Map<String, Object?> _correlatedSections({
    required String bundleId,
    required DateTime observedAtUtc,
    required Map<String, Object?> sections,
  }) {
    Map<String, Object?> map(String key) {
      final value = sections[key];
      if (value is Map<String, Object?>) return value;
      if (value is Map<Object?, Object?>) {
        return value.map((key, value) => MapEntry(key.toString(), value));
      }
      return const {};
    }

    final status = map('localLiveStatus');
    final analysis = map('analysisRuntime');
    final configuration = map('configuration');
    final reconciliation = map('privateAccountReconciliation');
    final portfolioRaw = status['portfolioBudget'];
    final portfolio = portfolioRaw is Map<Object?, Object?>
        ? portfolioRaw.map((key, value) => MapEntry(key.toString(), value))
        : const <String, Object?>{};
    final managed = (status['managedPositionCount'] as num?)?.toInt() ?? 0;
    final totalSlots =
        (configuration['maximumConcurrentPositions'] as num?)?.toInt() ?? 0;
    final availableSlots = max(0, totalSlots - managed);
    final heartbeat =
        DateTime.tryParse(status['lastScanAt']?.toString() ?? '')?.toUtc() ??
        observedAtUtc.toUtc();
    final blockReason = status['entryBlockReason']?.toString().trim();
    final blocked = blockReason != null && blockReason.isNotEmpty;
    final reconciliationHealth = reconciliation['health']?.toString() ?? '';
    final journalAvailable = sections['tradingJournal'] != null;

    final snapshot = SupportSessionDiagnosticSnapshot(
      correlationId: bundleId,
      observedAtUtc: observedAtUtc,
      route: '/owner-alpha/auto-trade',
      selectedTab: 'auto-trade',
      symbol: analysis['selectedSymbol']?.toString() ?? '',
      timeframe: analysis['selectedTimeframe']?.toString() ?? '',
      strategyId: analysis['primaryStrategy']?.toString() ?? '',
      mode: status['entriesEnabled'] == true ? 'local-live' : 'read-only',
      autoTradeState: reconciliationHealth.isEmpty
          ? 'unknown'
          : reconciliationHealth,
      localLiveState: status['state']?.toString() ?? 'unknown',
      uiState: status['message']?.toString() ?? 'unknown',
      appBuild: 'runtime-current',
      configVersion: 'local-live-v1',
      visibleValues: [
        SupportVisibleValue(
          key: 'localLiveState',
          value: status['state']?.toString() ?? 'unknown',
          sourceType: 'localLiveStatus',
          sourceEvidenceId: 'diagnostic:$bundleId:localLiveStatus',
        ),
        SupportVisibleValue(
          key: 'reconciliationHealth',
          value: reconciliationHealth.isEmpty
              ? 'unknown'
              : reconciliationHealth,
          sourceType: 'privateAccountReconciliation',
          sourceEvidenceId: 'diagnostic:$bundleId:privateAccountReconciliation',
        ),
        SupportVisibleValue(
          key: 'managedPositions',
          value: managed.toString(),
          sourceType: 'localLiveStatus',
          sourceEvidenceId: 'diagnostic:$bundleId:localLiveStatus',
        ),
      ],
      decisionTrace: [
        if (reconciliation.isNotEmpty)
          SupportDecisionTraceStage(
            stage: SupportDecisionStage.reconciliation,
            status: reconciliationHealth == 'fresh' ? 'accepted' : 'observed',
            reasonCode: reconciliationHealth.isEmpty
                ? 'reconciliation.status_unknown'
                : 'reconciliation.$reconciliationHealth',
            evidenceIds: ['diagnostic:$bundleId:privateAccountReconciliation'],
          ),
        if (journalAvailable)
          SupportDecisionTraceStage(
            stage: SupportDecisionStage.journal,
            status: 'observed',
            reasonCode: 'journal.snapshot_available',
            evidenceIds: ['diagnostic:$bundleId:tradingJournal'],
          ),
      ],
      capacity: SupportCapacityExplanation(
        scannerHeartbeatAtUtc: heartbeat,
        managedPositionCount: managed,
        totalSlots: totalSlots,
        availableSlots: availableSlots,
        riskCapacity: portfolio['riskAvailable']?.toString() ?? 'unknown',
        marginCapacity: portfolio['spendableMargin']?.toString() ?? 'unknown',
        correlationCapacity: blocked ? 'blocked' : 'unknown',
        reservedCapacity: portfolio['reservedMargin']?.toString() ?? 'unknown',
        disposition: blocked ? 'blocked' : 'observable',
        reasonCode: blocked
            ? blockReason
            : 'support.capacity.no_block_reported',
        evidenceIds: [
          'diagnostic:$bundleId:localLiveStatus',
          if (portfolio.isNotEmpty) 'diagnostic:$bundleId:accountSnapshot',
        ],
      ),
    );
    return snapshot.toDiagnosticSections();
  }

  static List<SupervisorSystemEvidence> fromCorrelatedSnapshot(
    SupportSessionDiagnosticSnapshot snapshot,
  ) => SupervisorDiagnosticEvidenceAdapter.fromDiagnosticBundle(
    bundleId: snapshot.correlationId,
    observedAtUtc: snapshot.observedAtUtc,
    diagnosticBundle: <String, Object?>{
      'sections': snapshot.toDiagnosticSections(),
    },
    correlationId: snapshot.correlationId,
  );
}

final class ReadOnlySupportRemoteSnapshot {
  const ReadOnlySupportRemoteSnapshot({
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

  factory ReadOnlySupportRemoteSnapshot.fromJson(Map<String, Object?> json) =>
      ReadOnlySupportRemoteSnapshot(
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

final class ReadOnlySupportTransportException implements Exception {
  const ReadOnlySupportTransportException(this.message, {this.statusCode});

  final String message;
  final int? statusCode;

  @override
  String toString() => message;
}

final class ReadOnlySupportSessionTransport {
  const ReadOnlySupportSessionTransport();

  Future<ReadOnlySupportRemoteSnapshot> register({
    required AutoTradeServerConfig serverConfig,
    required ReadOnlySupportSessionGrant grant,
    required List<SupervisorSystemEvidence> evidence,
  }) => _withClient(
    (client) => _requestSnapshot(
      client: client,
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
        'evidence': evidence
            .map((item) => item.toJson())
            .toList(growable: false),
      },
    ),
  );

  Future<ReadOnlySupportRemoteSnapshot> refreshEvidence({
    required Uri baseUrl,
    required String supportToken,
    required List<SupervisorSystemEvidence> evidence,
  }) => _withClient(
    (client) => _requestSnapshot(
      client: client,
      uri: baseUrl.resolve('/api/v1/supervisor/support-session/evidence'),
      method: 'POST',
      headers: _sessionHeaders(supportToken, json: true),
      body: <String, Object?>{
        'evidence': evidence
            .map((item) => item.toJson())
            .toList(growable: false),
      },
    ),
  );

  Future<void> revoke({required Uri baseUrl, required String supportToken}) =>
      _withClient((client) async {
        final response = await client
            .delete(
              baseUrl.resolve('/api/v1/supervisor/support-session'),
              headers: _sessionHeaders(supportToken),
            )
            .timeout(const Duration(seconds: 12));
        if (response.statusCode != 204) {
          throw ReadOnlySupportTransportException(
            'The remote support session could not be revoked safely.',
            statusCode: response.statusCode,
          );
        }
      });

  static Map<String, String> _sessionHeaders(
    String token, {
    bool json = false,
  }) => <String, String>{
    'Accept': 'application/json',
    'Authorization': 'Bearer $token',
    if (json) 'Content-Type': 'application/json',
  };

  static Future<T> _withClient<T>(
    Future<T> Function(http.Client client) operation,
  ) async {
    final client = http.Client();
    try {
      return await operation(client);
    } finally {
      client.close();
    }
  }

  static Future<ReadOnlySupportRemoteSnapshot> _requestSnapshot({
    required http.Client client,
    required Uri uri,
    required String method,
    required Map<String, String> headers,
    Map<String, Object?>? body,
  }) async {
    late final http.Response response;
    try {
      response = switch (method) {
        'GET' =>
          await client
              .get(uri, headers: headers)
              .timeout(const Duration(seconds: 12)),
        _ =>
          await client
              .post(uri, headers: headers, body: jsonEncode(body))
              .timeout(const Duration(seconds: 15)),
      };
    } on Object {
      throw const ReadOnlySupportTransportException(
        'The Quantara Supervisor server could not be reached.',
      );
    }

    if (response.bodyBytes.length > 1000000) {
      throw const ReadOnlySupportTransportException(
        'The Supervisor server returned an oversized response.',
      );
    }
    Object? decoded;
    try {
      decoded = jsonDecode(utf8.decode(response.bodyBytes));
    } on Object {
      throw ReadOnlySupportTransportException(
        'The Supervisor server returned an unreadable response.',
        statusCode: response.statusCode,
      );
    }
    if (decoded is! Map<String, Object?>) {
      throw ReadOnlySupportTransportException(
        'The Supervisor server returned an unexpected response.',
        statusCode: response.statusCode,
      );
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw ReadOnlySupportTransportException(
        decoded['error']?.toString() ??
            'The Supervisor server rejected the support-session request.',
        statusCode: response.statusCode,
      );
    }
    return ReadOnlySupportRemoteSnapshot.fromJson(decoded);
  }
}
