import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:quantara_app/features/trading_lab/application/trading_lab_zip_bundle.dart';
import 'package:quantara_app/features/trading_lab/domain/trading_lab_account_context.dart';
import 'package:quantara_app/features/trading_lab/domain/trading_lab_models.dart';
import 'package:quantara_app/features/trading_lab/domain/trading_lab_real_account_evidence.dart';

void main() {
  TradingLabRun buildRun() => TradingLabRun(
    manifest: TradingLabRunManifest(
      runId: 'lab-zip-roundtrip',
      startedAtUtc: DateTime.utc(2026, 8, 10, 3),
      startingEquity: 500,
      riskPercent: 1,
      maximumConcurrentPositions: 3,
      leverage: 5,
      symbols: const ['BTCUSDT', 'ETHUSDT'],
      timeframes: const ['15m', '1h'],
      strategies: const ['trendPullback@v1'],
      feeRateBps: 6,
      slippageBps: 2,
      notes: 'portable evidence',
    ),
    balance: 505,
    currentEquity: 508,
    peakEquity: 510,
    maximumDrawdownPercent: 1.2,
    cycleId: 7,
    lastSnapshotAtUtc: DateTime.utc(2026, 8, 10, 4),
    lastWhyNoTrade: 'Scanner active; no candidate met admission.',
    processedDecisionKeys: const ['decision-a'],
  );

  const accountContext = TradingLabAccountContext(
    connected: true,
    reconciliationHealth: 'healthy',
    refreshing: false,
    blocksNewEntries: false,
    canManageExistingPositions: true,
    marginCoin: 'USDT',
    available: 420,
    estimatedEquity: 510,
    openPositionCount: 1,
    pendingOrderCount: 0,
    allOpenPositionsFullyProtected: true,
  );

  final realAccountEvidence = TradingLabRealAccountEvidence(
    currency: 'USDT',
    asOfUtc: DateTime.utc(2026, 8, 10, 4),
    verified: true,
    fillsAvailable: true,
    settlementsAvailable: true,
    accountUnrealizedPnl: 0.4,
    accountRealizedGrossPnl: 1.2,
    accountFees: 0.1,
    accountFunding: 0.02,
    accountNetRealizedPnl: 1.08,
    sourceWarningPresent: false,
    trades: [
      TradingLabRealAccountTradeEvidence(
        symbol: 'BTCUSDT',
        side: 'long',
        state: 'closed',
        quantity: 0.01,
        averageEntryPrice: 100,
        averageExitPrice: 102,
        realizedGrossPnl: 1.2,
        fees: 0.1,
        funding: 0.02,
        netRealizedPnl: 1.08,
        unrealizedPnl: 0,
        openedAtUtc: DateTime.utc(2026, 8, 10, 3),
        closedAtUtc: DateTime.utc(2026, 8, 10, 4),
        asOfUtc: DateTime.utc(2026, 8, 10, 4),
        verified: true,
      ),
    ],
  );

  const benchmarkMatrix = <String, Object?>{
    'schema': 'quantara.trading_lab.benchmark.v1',
    'targetTimeframes': ['5m', '15m', '30m', '1h'],
  };

  test('full Lab evidence is a standard ZIP and round-trips safely', () {
    final run = buildRun();
    final aiReview = jsonEncode({
      'schemaVersion': 1,
      'runId': run.manifest.runId,
      'scorecards': const [],
    });
    final shadow = <String, Object?>{
      'summary': const {'signalsTracked': 3},
      'scorecards': const <Object?>[],
      'signals': const <Object?>[],
    };

    final bundle = const TradingLabZipBundleCodec().encode(
      run: run,
      aiReviewJson: aiReview,
      shadowEvidence: shadow,
      accountContext: accountContext,
      realAccountEvidence: realAccountEvidence,
      benchmarkMatrix: benchmarkMatrix,
    );

    expect(bundle.fileName, 'quantara-lab-lab-zip-roundtrip.zip');
    expect(bundle.bytes.take(4), [0x50, 0x4b, 0x03, 0x04]);

    final restored = const TradingLabZipBundleCodec().decode(bundle.bytes);
    expect(restored.run.manifest.runId, run.manifest.runId);
    expect(restored.run.currentEquity, 508);
    expect(restored.aiReviewJson, contains('lab-zip-roundtrip'));
    expect(restored.shadowEvidenceJson, contains('signalsTracked'));
    expect(restored.accountContextJson, contains('read_only_context'));
    expect(
      restored.fileNames,
      containsAll(TradingLabZipBundleCodec.requiredEvidenceFiles),
    );
    expect(restored.fileNames, contains('summary.json'));
    expect(restored.fileNames, contains('trades.jsonl'));
    expect(restored.fileNames, contains('decisions.jsonl'));
    expect(restored.fileNames, contains('management_events.jsonl'));
    expect(restored.fileNames, contains('equity_curve.jsonl'));
    expect(restored.fileNames, contains('market_feature_snapshots.jsonl'));
    expect(restored.fileNames, contains('real_account_summary.json'));
    expect(restored.fileNames, contains('real_account_trades.jsonl'));
    expect(restored.fileNames, contains('real_account_snapshots.jsonl'));
    expect(restored.fileNames, contains('benchmark_matrix.json'));
  });

  test('ZIP corruption is rejected instead of silently importing evidence', () {
    final run = buildRun();
    final bundle = const TradingLabZipBundleCodec().encode(
      run: run,
      aiReviewJson: jsonEncode({'runId': run.manifest.runId}),
      shadowEvidence: const {'signals': <Object?>[]},
      accountContext: accountContext,
      realAccountEvidence: realAccountEvidence,
      benchmarkMatrix: benchmarkMatrix,
    );
    final corrupted = Uint8List.fromList(bundle.bytes);
    final readme = utf8.encode('Quantara Bot Trading Lab evidence bundle');
    final offset = _indexOf(corrupted, readme);
    expect(offset, greaterThanOrEqualTo(0));
    corrupted[offset] ^= 0x01;

    expect(
      () => const TradingLabZipBundleCodec().decode(corrupted),
      throwsFormatException,
    );
  });

  test('sensitive credential-shaped keys fail closed before export', () {
    final run = buildRun();
    expect(
      () => const TradingLabZipBundleCodec().encode(
        run: run,
        aiReviewJson: jsonEncode({
          'runId': run.manifest.runId,
          'apiSecret': 'must-never-export',
        }),
        shadowEvidence: const {'signals': <Object?>[]},
        accountContext: accountContext,
        realAccountEvidence: realAccountEvidence,
        benchmarkMatrix: benchmarkMatrix,
      ),
      throwsFormatException,
    );
  });
}

int _indexOf(Uint8List haystack, List<int> needle) {
  if (needle.isEmpty) return 0;
  for (var start = 0; start <= haystack.length - needle.length; start += 1) {
    var matches = true;
    for (var index = 0; index < needle.length; index += 1) {
      if (haystack[start + index] != needle[index]) {
        matches = false;
        break;
      }
    }
    if (matches) return start;
  }
  return -1;
}
