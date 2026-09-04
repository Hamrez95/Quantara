import 'dart:collection';
import 'dart:convert';

import '../domain/strategy_evaluation_run.dart';

abstract interface class StrategyEvaluationArchiveKeyValueStore {
  Future<String?> read(String key);

  Future<void> write(String key, String value);

  Future<void> delete(String key);
}

/// Immutable archived evidence for one deterministic strategy evaluation run.
///
/// The payload is the exact serialized run produced by [StrategyEvaluationRun].
/// Corrupt or incomplete records are rejected rather than reconstructed from
/// guesses. Archived evidence is informational and carries no execution
/// authority.
final class ArchivedStrategyEvaluationRun {
  ArchivedStrategyEvaluationRun._({
    required this.runId,
    required this.setupId,
    required this.strategyId,
    required this.strategyVersion,
    required this.symbol,
    required this.timeframe,
    required this.createdAtUtc,
    required Map<String, Object?> payload,
  }) : payload = UnmodifiableMapView<String, Object?>(payload);

  final String runId;
  final String setupId;
  final String strategyId;
  final String strategyVersion;
  final String symbol;
  final String timeframe;
  final DateTime createdAtUtc;
  final Map<String, Object?> payload;

  bool get grantsLocalLiveAuthority => false;

  factory ArchivedStrategyEvaluationRun.fromRun(StrategyEvaluationRun run) {
    return ArchivedStrategyEvaluationRun._(
      runId: run.runId,
      setupId: run.setupId,
      strategyId: run.identity.strategyId,
      strategyVersion: run.identity.strategyVersion,
      symbol: run.symbol,
      timeframe: run.timeframe,
      createdAtUtc: run.createdAtUtc.toUtc(),
      payload: Map<String, Object?>.from(run.toJson()),
    );
  }

  static ArchivedStrategyEvaluationRun? tryFromJson(Map<String, Object?> json) {
    try {
      final payloadValue = json['payload'];
      if (payloadValue is! Map<Object?, Object?>) return null;
      final payload = _stringMap(payloadValue);
      if (payload == null) return null;

      final runId = json['runId'];
      final setupId = json['setupId'];
      final strategyId = json['strategyId'];
      final strategyVersion = json['strategyVersion'];
      final symbol = json['symbol'];
      final timeframe = json['timeframe'];
      final createdAtUtc = json['createdAtUtc'];
      if (runId is! String ||
          setupId is! String ||
          strategyId is! String ||
          strategyVersion is! String ||
          symbol is! String ||
          timeframe is! String ||
          createdAtUtc is! String) {
        return null;
      }
      final parsedCreatedAt = DateTime.tryParse(createdAtUtc)?.toUtc();
      if (parsedCreatedAt == null ||
          runId.trim().isEmpty ||
          setupId.trim().isEmpty ||
          strategyId.trim().isEmpty ||
          strategyVersion.trim().isEmpty ||
          symbol.trim().isEmpty ||
          timeframe.trim().isEmpty) {
        return null;
      }

      // Fail closed when metadata and immutable payload provenance disagree.
      final identityValue = payload['identity'];
      final identity = identityValue is Map<Object?, Object?>
          ? _stringMap(identityValue)
          : null;
      if (payload['runId'] != runId ||
          payload['setupId'] != setupId ||
          payload['symbol'] != symbol ||
          payload['timeframe'] != timeframe ||
          identity == null ||
          identity['strategyId'] != strategyId ||
          identity['strategyVersion'] != strategyVersion) {
        return null;
      }

      return ArchivedStrategyEvaluationRun._(
        runId: runId,
        setupId: setupId,
        strategyId: strategyId,
        strategyVersion: strategyVersion,
        symbol: symbol,
        timeframe: timeframe,
        createdAtUtc: parsedCreatedAt,
        payload: payload,
      );
    } on Object {
      return null;
    }
  }

  Map<String, Object?> toJson() => <String, Object?>{
    'runId': runId,
    'setupId': setupId,
    'strategyId': strategyId,
    'strategyVersion': strategyVersion,
    'symbol': symbol,
    'timeframe': timeframe,
    'createdAtUtc': createdAtUtc.toIso8601String(),
    'payload': payload,
  };
}

/// Durable archive for completed deterministic evaluation evidence.
///
/// Archive mutation is serialized. Reset operations require an explicit token;
/// there is deliberately no implicit cleanup path that can silently erase
/// evidence used to explain a strategy decision.
final class DurableStrategyEvaluationArchive {
  DurableStrategyEvaluationArchive({
    required this.keyValueStore,
    this.storageKey = 'quantara.strategy-evaluation-archive-v1',
  }) {
    if (storageKey.trim().isEmpty) {
      throw ArgumentError.value(storageKey, 'storageKey');
    }
  }

  static const resetConfirmation = 'RESET EVALUATION ARCHIVE';

  final StrategyEvaluationArchiveKeyValueStore keyValueStore;
  final String storageKey;
  Future<void> _writeTail = Future<void>.value();

  Future<List<ArchivedStrategyEvaluationRun>> list() async {
    final decoded = await _loadDecoded();
    if (decoded == null) return const <ArchivedStrategyEvaluationRun>[];
    final recordsValue = decoded['records'];
    if (recordsValue is! List<Object?>) {
      return const <ArchivedStrategyEvaluationRun>[];
    }
    final records = <ArchivedStrategyEvaluationRun>[];
    for (final value in recordsValue) {
      if (value is! Map<Object?, Object?>) {
        return const <ArchivedStrategyEvaluationRun>[];
      }
      final json = _stringMap(value);
      final record = json == null
          ? null
          : ArchivedStrategyEvaluationRun.tryFromJson(json);
      if (record == null) {
        return const <ArchivedStrategyEvaluationRun>[];
      }
      records.add(record);
    }
    records.sort((a, b) => b.createdAtUtc.compareTo(a.createdAtUtc));
    return List<ArchivedStrategyEvaluationRun>.unmodifiable(records);
  }

  Future<ArchivedStrategyEvaluationRun?> find(String runId) async {
    if (runId.trim().isEmpty) return null;
    final records = await list();
    for (final record in records) {
      if (record.runId == runId) return record;
    }
    return null;
  }

  Future<void> archive(StrategyEvaluationRun run) {
    return _enqueue(() async {
      final current = await list();
      final replacement = ArchivedStrategyEvaluationRun.fromRun(run);
      final next = <ArchivedStrategyEvaluationRun>[
        replacement,
        ...current.where((record) => record.runId != replacement.runId),
      ];
      await _persist(next);
    });
  }

  Future<bool> deleteRun({
    required String runId,
    required String confirmation,
  }) async {
    if (runId.trim().isEmpty || confirmation != runId) return false;
    var removed = false;
    await _enqueue(() async {
      final current = await list();
      final next = current.where((record) => record.runId != runId).toList();
      removed = next.length != current.length;
      if (removed) await _persist(next);
    });
    return removed;
  }

  Future<bool> reset({required String confirmation}) async {
    if (confirmation != resetConfirmation) return false;
    await _enqueue(() => keyValueStore.delete(storageKey));
    return true;
  }

  Future<Map<String, Object?>?> _loadDecoded() async {
    final raw = await keyValueStore.read(storageKey);
    if (raw == null || raw.trim().isEmpty)
      return <String, Object?>{'schemaVersion': 1, 'records': <Object?>[]};
    try {
      final value = jsonDecode(raw);
      if (value is! Map<Object?, Object?>) return null;
      final decoded = _stringMap(value);
      if (decoded == null || decoded['schemaVersion'] != 1) return null;
      return decoded;
    } on Object {
      return null;
    }
  }

  Future<void> _persist(List<ArchivedStrategyEvaluationRun> records) {
    return keyValueStore.write(
      storageKey,
      jsonEncode(<String, Object?>{
        'schemaVersion': 1,
        'records': records.map((record) => record.toJson()).toList(),
      }),
    );
  }

  Future<void> _enqueue(Future<void> Function() operation) {
    final result = _writeTail.then((_) => operation());
    _writeTail = result.then<void>(
      (_) {},
      onError: (Object _, StackTrace _) {},
    );
    return result;
  }
}

Map<String, Object?>? _stringMap(Map<Object?, Object?> source) {
  final result = <String, Object?>{};
  for (final entry in source.entries) {
    if (entry.key is! String) return null;
    result[entry.key! as String] = entry.value;
  }
  return result;
}
