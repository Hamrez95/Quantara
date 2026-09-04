import 'package:flutter_test/flutter_test.dart';
import 'package:quantara_app/features/owner_alpha/domain/owner_alpha_models.dart';
import 'package:quantara_app/features/trading_lab/application/trading_lab_strategy_identity.dart';
import 'package:quantara_app/features/trading_lab/domain/trading_lab_models.dart';

void main() {
  test('exact evaluation identity changes when snapshot hash changes', () {
    final first = _idea(snapshotHash: 'snapshot-a');
    final second = _idea(snapshotHash: 'snapshot-b');

    expect(
      tradingLabStrategyIdentityKey(first),
      isNot(tradingLabStrategyIdentityKey(second)),
    );
  });

  test('new manifest accepts only its exact immutable strategy snapshot', () {
    final accepted = _idea(snapshotHash: 'snapshot-a');
    final rejected = _idea(snapshotHash: 'snapshot-b');
    final manifest = _manifest(strategies: [tradingLabStrategyIdentityKey(accepted)]);

    expect(tradingLabManifestAcceptsIdea(manifest, accepted), isTrue);
    expect(tradingLabManifestAcceptsIdea(manifest, rejected), isFalse);
  });

  test('legacy manifest remains readable without inventing registry identity', () {
    final idea = _idea(snapshotHash: 'snapshot-a');
    final manifest = _manifest(
      strategies: [tradingLabLegacyStrategyIdentityKey(idea)],
    );

    expect(tradingLabManifestAcceptsIdea(manifest, idea), isTrue);
  });
}

TradeIdea _idea({required String snapshotHash}) => TradeIdea(
  symbol: 'BTCUSDT',
  timeframe: '15m',
  direction: TradeDirection.long,
  confidencePercent: 80,
  entryLower: 100,
  entryUpper: 101,
  stopLoss: 98,
  targets: const [103, 105, 108],
  riskReward: 2,
  maximumLoss: 10,
  positionSize: 1,
  notionalValue: 100,
  recommendedLeverage: 2,
  maximumSafeLeverage: 4,
  requiredMargin: 50,
  estimatedRoundTripCosts: 0.2,
  setupId: 'setup-1',
  candleClosedAt: DateTime.utc(2026, 9, 4),
  summary: 'test',
  invalidation: 'below stop',
  reasons: const ['test'],
  strategy: AnalysisStrategy.structureZones,
  strategyVersion: '1.0',
  registryStrategyId: 'structure_zones',
  registryStrategyVersion: '2.0.0',
  strategyParameterSchemaVersion: 3,
  normalizedStrategyParameters: const {'alpha': 1},
  strategySnapshotHash: snapshotHash,
  managementPolicyVersion: 'management-v2',
  strategyImplementationVersion: 'engine-v3',
  strategyLifecycle: 'active',
);

TradingLabRunManifest _manifest({required List<String> strategies}) =>
    TradingLabRunManifest(
      runId: 'run-1',
      startedAtUtc: DateTime.utc(2026, 9, 4),
      startingEquity: 500,
      riskPercent: 1,
      maximumConcurrentPositions: 1,
      leverage: 2,
      symbols: const ['BTCUSDT'],
      timeframes: const ['15m'],
      strategies: strategies,
    );
