import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:quantara_app/features/owner_alpha/data/durable_strategy_evaluation_archive.dart';
import 'package:quantara_app/features/owner_alpha/domain/strategy_evaluation_run.dart';

void main() {
  StrategyEvaluationRun run(String runId, {int day = 1}) {
    return StrategyEvaluationRun(
      runId: runId,
      setupId: 'setup-$runId',
      identity: StrategyEvaluationIdentity(
        strategyId: 'structure_zones',
        strategyVersion: '1.2.3',
        implementationVersion: 'engine/7',
        managementPolicyVersion: 'management/2',
        parameterSchemaVersion: 3,
        normalizedParameters: const <String, Object?>{'cadence': 'balanced'},
        snapshotHash: 'sha256-$runId',
      ),
      symbol: 'BTCUSDT',
      market: 'linear-perpetual',
      timeframe: '15m',
      rangeStartUtc: DateTime.utc(2026, 8, day),
      rangeEndUtc: DateTime.utc(2026, 8, day + 1),
      createdAtUtc: DateTime.utc(2026, 9, day),
      costModel: const StrategyEvaluationCostModel(
        version: 'bitunix-taker/1',
        takerFeeBps: 6,
        slippageBps: 2,
      ),
      trades: <StrategyEvaluationTrade>[
        StrategyEvaluationTrade(
          tradeId: 'trade-$runId',
          openedAtUtc: DateTime.utc(2026, 8, day, 1),
          closedAtUtc: DateTime.utc(2026, 8, day, 2),
          grossPnl: 4,
          cost: 0.2,
          maximumFavorableExcursion: 5,
          maximumAdverseExcursion: 1,
        ),
      ],
      deterministicSeed: 42,
    );
  }

  test('archives exact immutable evidence and restores it after restart', () async {
    final memory = _MemoryStore();
    final archive = DurableStrategyEvaluationArchive(keyValueStore: memory);
    final original = run('run-1');

    await archive.archive(original);
    final restarted = DurableStrategyEvaluationArchive(keyValueStore: memory);
    final restored = await restarted.find('run-1');

    expect(restored, isNotNull);
    expect(restored!.strategyId, 'structure_zones');
    expect(restored.strategyVersion, '1.2.3');
    expect(restored.payload, original.toJson());
    expect(restored.grantsLocalLiveAuthority, isFalse);
  });

  test('newest evidence is listed first without fabricating missing runs', () async {
    final archive = DurableStrategyEvaluationArchive(
      keyValueStore: _MemoryStore(),
    );
    await archive.archive(run('older', day: 1));
    await archive.archive(run('newer', day: 2));

    final records = await archive.list();

    expect(records.map((record) => record.runId), <String>['newer', 'older']);
    expect(await archive.find('missing'), isNull);
  });

  test('delete and reset require explicit confirmations', () async {
    final memory = _MemoryStore();
    final archive = DurableStrategyEvaluationArchive(keyValueStore: memory);
    await archive.archive(run('run-1'));

    expect(
      await archive.deleteRun(runId: 'run-1', confirmation: 'yes'),
      isFalse,
    );
    expect(await archive.find('run-1'), isNotNull);
    expect(await archive.reset(confirmation: 'RESET'), isFalse);
    expect(await archive.find('run-1'), isNotNull);

    expect(
      await archive.deleteRun(runId: 'run-1', confirmation: 'run-1'),
      isTrue,
    );
    expect(await archive.find('run-1'), isNull);

    await archive.archive(run('run-2'));
    expect(
      await archive.reset(
        confirmation: DurableStrategyEvaluationArchive.resetConfirmation,
      ),
      isTrue,
    );
    expect(await archive.list(), isEmpty);
  });

  test('corrupt or provenance-mismatched evidence fails closed', () async {
    final memory = _MemoryStore();
    final archive = DurableStrategyEvaluationArchive(keyValueStore: memory);
    await archive.archive(run('run-1'));
    final decoded = jsonDecode(memory.values.values.single) as Map<String, dynamic>;
    final records = decoded['records'] as List<dynamic>;
    final record = records.single as Map<String, dynamic>;
    record['strategyVersion'] = 'latest';
    memory.values[memory.values.keys.single] = jsonEncode(decoded);

    expect(await archive.list(), isEmpty);
    expect(await archive.find('run-1'), isNull);
  });
}

final class _MemoryStore implements StrategyEvaluationArchiveKeyValueStore {
  final Map<String, String> values = <String, String>{};

  @override
  Future<void> delete(String key) async {
    values.remove(key);
  }

  @override
  Future<String?> read(String key) async => values[key];

  @override
  Future<void> write(String key, String value) async {
    values[key] = value;
  }
}
