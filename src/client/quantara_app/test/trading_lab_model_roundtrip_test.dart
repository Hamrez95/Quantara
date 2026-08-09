import 'package:flutter_test/flutter_test.dart';
import 'package:quantara_app/features/trading_lab/domain/trading_lab_models.dart';

void main() {
  test('Trading Lab run manifest and state survive JSON round trip', () {
    final startedAt = DateTime.utc(2026, 8, 10, 0, 30);
    final run = TradingLabRun(
      manifest: TradingLabRunManifest(
        runId: 'lab-roundtrip',
        startedAtUtc: startedAt,
        startingEquity: 500,
        riskPercent: 1,
        maximumConcurrentPositions: 3,
        leverage: 5,
        symbols: const ['BTCUSDT', 'ETHUSDT'],
        timeframes: const ['15m', '1h'],
        strategies: const ['trendPullback@v1'],
        feeRateBps: 6,
        slippageBps: 2,
        notes: 'persist me',
      ),
      balance: 497.5,
      currentEquity: 503.25,
      peakEquity: 510,
      maximumDrawdownPercent: 2.4,
      cycleId: 42,
      lastSnapshotAtUtc: startedAt.add(const Duration(hours: 2)),
      lastWhyNoTrade: 'Scanner active; candidate threshold not met.',
      processedDecisionKeys: const ['decision-1', 'decision-2'],
    );

    final restored = TradingLabRun.fromJson(run.toJson());

    expect(restored.manifest.runId, 'lab-roundtrip');
    expect(restored.manifest.startingEquity, 500);
    expect(restored.manifest.maximumConcurrentPositions, 3);
    expect(restored.manifest.symbols, ['BTCUSDT', 'ETHUSDT']);
    expect(restored.balance, 497.5);
    expect(restored.currentEquity, 503.25);
    expect(restored.peakEquity, 510);
    expect(restored.maximumDrawdownPercent, 2.4);
    expect(restored.cycleId, 42);
    expect(restored.processedDecisionKeys, containsAll(['decision-1', 'decision-2']));
    expect(restored.lastWhyNoTrade, contains('Scanner active'));
  });

  test('Trading Lab rejects unsafe run configuration', () {
    expect(
      () => TradingLabRunManifest(
        runId: 'unsafe',
        startedAtUtc: DateTime.utc(2026, 8, 10),
        startingEquity: 500,
        riskPercent: 5,
        maximumConcurrentPositions: 3,
        leverage: 5,
        symbols: const ['BTCUSDT'],
        timeframes: const ['1h'],
        strategies: const ['trendPullback@v1'],
      ),
      throwsFormatException,
    );
  });
}
